/// Transport/Propagation — executes sync actions.
///
/// Mirrors OCaml Unison's `transport.ml`. Takes reconciliation results
/// and propagates changes between replicas. Supports concurrent transfers
/// via Dart isolates.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../model/fspath.dart';
import '../model/recon_item.dart';
import '../model/sync_path.dart';
import '../model/update_item.dart';
import '../util/trace.dart';
import 'files.dart';

/// Result of propagating a single item.
sealed class TransportResult {
  const TransportResult();
}

/// Successfully propagated.
class TransportSuccess extends TransportResult {
  final SyncPath path;
  const TransportSuccess(this.path);
}

/// Skipped (conflict, problem, or no action).
class TransportSkipped extends TransportResult {
  final SyncPath path;
  final String reason;
  const TransportSkipped(this.path, this.reason);
}

/// Failed to propagate.
class TransportError extends TransportResult {
  final SyncPath path;
  final String error;
  const TransportError(this.path, this.error);
}

/// Progress report for the entire propagation.
class PropagationProgress {
  final int total;
  final int completed;
  final int skipped;
  final int failed;
  final SyncPath? currentPath;
  final int activeTasks;

  const PropagationProgress({
    required this.total,
    required this.completed,
    required this.skipped,
    required this.failed,
    this.currentPath,
    this.activeTasks = 0,
  });
}

/// Callback for propagation progress.
typedef PropagationCallback = void Function(PropagationProgress progress);

/// Propagates reconciliation results between two local replicas.
///
/// Supports concurrent file transfers via a configurable thread pool.
/// Error recovery: continues past individual failures up to [maxErrors].
class TransportOrchestrator {
  final FileOps _fileOps;

  /// Maximum concurrent transfer tasks.
  final int maxThreads;

  /// Maximum errors before aborting entire propagation.
  /// 0 = abort on first error, -1 = never abort.
  final int maxErrors;

  TransportOrchestrator({
    FileOps? fileOps,
    this.maxThreads = 20,
    this.maxErrors = -1,
  }) : _fileOps = fileOps ?? FileOps();

  /// Propagate all items sequentially (simple, reliable).
  List<TransportResult> propagateAll(
    Fspath root1,
    Fspath root2,
    List<ReconItem> items, {
    PropagationCallback? onProgress,
  }) {
    final results = <TransportResult>[];
    var completed = 0;
    var skipped = 0;
    var failed = 0;

    for (final item in items) {
      onProgress?.call(PropagationProgress(
        total: items.length,
        completed: completed,
        skipped: skipped,
        failed: failed,
        currentPath: item.path1,
      ));

      final result = _propagateItem(root1, root2, item);
      results.add(result);

      switch (result) {
        case TransportSuccess():
          completed++;
        case TransportSkipped():
          skipped++;
        case TransportError():
          failed++;
          // Check error threshold
          if (maxErrors >= 0 && failed > maxErrors) {
            Trace.error(
              TraceCategory.transport,
              'Error limit reached ($failed > $maxErrors), aborting',
            );
            // Mark remaining items as skipped
            for (var j = items.indexOf(item) + 1; j < items.length; j++) {
              results.add(TransportSkipped(
                items[j].path1,
                'Aborted: error limit reached',
              ));
              skipped++;
            }
            break;
          }
      }

      if (maxErrors >= 0 && failed > maxErrors) break;
    }

    onProgress?.call(PropagationProgress(
      total: items.length,
      completed: completed,
      skipped: skipped,
      failed: failed,
    ));

    Trace.info(
      TraceCategory.transport,
      'Propagation complete: $completed OK, $skipped skipped, $failed failed',
    );

    return results;
  }

  /// Propagate all items concurrently using an isolate pool.
  ///
  /// File operations that don't conflict (different paths) run in parallel.
  /// Directory operations and deletions that may affect children are serialized.
  Future<List<TransportResult>> propagateAllConcurrent(
    Fspath root1,
    Fspath root2,
    List<ReconItem> items, {
    PropagationCallback? onProgress,
  }) async {
    if (items.isEmpty) {
      return [];
    }

    // Separate into parallelizable and sequential items
    final parallel = <(int, ReconItem)>[];
    final sequential = <(int, ReconItem)>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (_canParallelize(item)) {
        parallel.add((i, item));
      } else {
        sequential.add((i, item));
      }
    }

    final results = List<TransportResult?>.filled(items.length, null);
    var completed = 0;
    var skipped = 0;
    var failed = 0;

    void _updateCounters(TransportResult r) {
      switch (r) {
        case TransportSuccess():
          completed++;
        case TransportSkipped():
          skipped++;
        case TransportError():
          failed++;
      }
    }

    // Run parallelizable items through a pool
    if (parallel.isNotEmpty) {
      final pool = _TaskPool(maxThreads);

      for (final (idx, item) in parallel) {
        await pool.acquire();

        // ignore: unawaited_futures
        _runInPoolAsync(root1, root2, item).then((result) {
          results[idx] = result;
          _updateCounters(result);
          pool.release();

          onProgress?.call(PropagationProgress(
            total: items.length,
            completed: completed,
            skipped: skipped,
            failed: failed,
            currentPath: item.path1,
            activeTasks: pool.active,
          ));
        });
      }

      // Wait for all pool tasks to finish
      await pool.drain();
    }

    // Run sequential items one at a time
    for (final (idx, item) in sequential) {
      onProgress?.call(PropagationProgress(
        total: items.length,
        completed: completed,
        skipped: skipped,
        failed: failed,
        currentPath: item.path1,
      ));

      final result = _propagateItem(root1, root2, item);
      results[idx] = result;
      _updateCounters(result);
    }

    onProgress?.call(PropagationProgress(
      total: items.length,
      completed: completed,
      skipped: skipped,
      failed: failed,
    ));

    Trace.info(
      TraceCategory.transport,
      'Concurrent propagation: $completed OK, $skipped skipped, $failed failed '
      '(${parallel.length} parallel, ${sequential.length} sequential)',
    );

    return results.map((r) => r ?? const TransportSkipped(
      SyncPath([]), 'Internal error',
    )).toList();
  }

  /// Check if an item can safely run in parallel with others.
  bool _canParallelize(ReconItem item) {
    if (item.replicas case Different(diff: var diff)) {
      // Conflicts and merges are not parallelized
      if (diff.direction is Conflict || diff.direction is Merge) {
        return false;
      }
      // Deletions of directories could affect children — serialize
      if (diff.rc1.status == ReplicaStatus.deleted &&
          diff.rc1.content is DirContent) {
        return false;
      }
      if (diff.rc2.status == ReplicaStatus.deleted &&
          diff.rc2.content is DirContent) {
        return false;
      }
      // Directory creation — serialize to avoid race on parent creation
      if (diff.rc1.content is DirContent || diff.rc2.content is DirContent) {
        return false;
      }
      return true;
    }
    return false;
  }

  /// Run a single transfer task. For file copies this uses Isolate.run
  /// to avoid blocking the main thread on large files.
  Future<TransportResult> _runInPoolAsync(
    Fspath root1,
    Fspath root2,
    ReconItem item,
  ) async {
    try {
      // For file operations, use isolate for I/O parallelism
      if (item.replicas case Different(diff: var diff)) {
        if (_isLargeFileTransfer(diff)) {
          return await Isolate.run(() {
            final ops = FileOps();
            return _propagateItemWith(ops, root1, root2, item);
          });
        }
      }
      // Small files: just run in-thread (isolate overhead not worth it)
      return _propagateItem(root1, root2, item);
    } catch (e) {
      return TransportError(item.path1, '$e');
    }
  }

  bool _isLargeFileTransfer(Difference diff) {
    const threshold = 1024 * 1024; // 1MB
    final source = diff.direction is Replica1ToReplica2 ? diff.rc1 : diff.rc2;
    return source.size.$2 > threshold;
  }

  TransportResult _propagateItem(
    Fspath root1,
    Fspath root2,
    ReconItem item,
  ) {
    return _propagateItemWith(_fileOps, root1, root2, item);
  }

  static TransportResult _propagateItemWith(
    FileOps fileOps,
    Fspath root1,
    Fspath root2,
    ReconItem item,
  ) {
    switch (item.replicas) {
      case Problem(message: var msg):
        return TransportSkipped(item.path1, 'Problem: $msg');

      case Different(diff: var diff):
        return _propagateDifferenceWith(
            fileOps, root1, root2, item.path1, item.path2, diff);
    }
  }

  static TransportResult _propagateDifferenceWith(
    FileOps fileOps,
    Fspath root1,
    Fspath root2,
    SyncPath path1,
    SyncPath path2,
    Difference diff,
  ) {
    switch (diff.direction) {
      case Conflict(reason: var reason):
        return TransportSkipped(path1, 'Conflict: $reason');

      case Merge():
        return TransportSkipped(path1, 'Merge not yet implemented');

      case Replica1ToReplica2():
        return _propagateOneWayWith(
            fileOps, root1, path1, root2, path2, diff.rc1);

      case Replica2ToReplica1():
        return _propagateOneWayWith(
            fileOps, root2, path2, root1, path1, diff.rc2);
    }
  }

  static TransportResult _propagateOneWayWith(
    FileOps fileOps,
    Fspath srcRoot,
    SyncPath srcPath,
    Fspath dstRoot,
    SyncPath dstPath,
    ReplicaContent source,
  ) {
    try {
      switch (source.status) {
        case ReplicaStatus.deleted:
          fileOps.delete(dstRoot, dstPath);

        case ReplicaStatus.created:
        case ReplicaStatus.modified:
          _propagateContentWith(
              fileOps, srcRoot, srcPath, dstRoot, dstPath, source);

        case ReplicaStatus.propsChanged:
          fileOps.setProps(dstRoot, dstPath, source.desc);

        case ReplicaStatus.unchanged:
          return TransportSkipped(srcPath, 'Unchanged');
      }

      return TransportSuccess(srcPath);
    } catch (e) {
      Trace.error(
        TraceCategory.transport,
        'Failed to propagate $srcPath: $e',
      );
      return TransportError(srcPath, '$e');
    }
  }

  static void _propagateContentWith(
    FileOps fileOps,
    Fspath srcRoot,
    SyncPath srcPath,
    Fspath dstRoot,
    SyncPath dstPath,
    ReplicaContent source,
  ) {
    final dstFull = dstRoot.concat(dstPath).toLocal();
    final dstType = FileSystemEntity.typeSync(dstFull, followLinks: false);
    if (dstType != FileSystemEntityType.notFound) {
      fileOps.delete(dstRoot, dstPath);
    }

    switch (source.content) {
      case FileContent(desc: var desc):
        fileOps.copyFile(srcRoot, srcPath, dstRoot, dstPath, props: desc);

      case DirContent(desc: var desc):
        fileOps.copyDir(srcRoot, srcPath, dstRoot, dstPath, props: desc);

      case SymlinkContent():
        fileOps.copySymlink(srcRoot, srcPath, dstRoot, dstPath);

      case Absent():
        fileOps.delete(dstRoot, dstPath);
    }
  }
}

/// Simple semaphore-based task pool for controlling concurrency.
class _TaskPool {
  final int maxConcurrent;
  int _active = 0;
  final _waiters = <Completer<void>>[];

  _TaskPool(this.maxConcurrent);

  int get active => _active;

  /// Acquire a slot. Waits if pool is full.
  Future<void> acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _active++;
  }

  /// Release a slot.
  void release() {
    _active--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  /// Wait for all active tasks to complete.
  Future<void> drain() async {
    while (_active > 0) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }
}
