/// Sync engine — orchestrates all phases of synchronization.
///
/// Ties together: Archive → Update Detection → Reconciliation →
/// Propagation → Archive Update.
library;

import 'dart:async';

import '../archive/archive_store.dart';
import '../filter/ignore.dart';
import '../fingerprint/fpcache.dart';
import '../fs/watcher.dart';
import '../model/archive.dart';
import '../model/fspath.dart';
import '../model/recon_item.dart';
import '../model/sync_path.dart';
import '../model/update_item.dart';
import '../util/trace.dart';
import 'recon.dart';
import 'transport.dart';
import 'update.dart';

/// Result of a complete sync operation.
class SyncResult {
  /// Items that were propagated, skipped, or failed.
  final List<TransportResult> transportResults;

  /// Reconciliation items (for UI display).
  final List<ReconItem> reconItems;

  /// Number of items equal on both sides.
  final int equalCount;

  /// Errors during scanning.
  final List<(SyncPath, String)> scanErrors;

  /// Whether all propagations succeeded.
  bool get allSucceeded =>
      transportResults.every((r) => r is TransportSuccess || r is TransportSkipped);

  int get propagated =>
      transportResults.whereType<TransportSuccess>().length;
  int get skipped =>
      transportResults.whereType<TransportSkipped>().length;
  int get failed =>
      transportResults.whereType<TransportError>().length;

  const SyncResult({
    required this.transportResults,
    required this.reconItems,
    required this.equalCount,
    required this.scanErrors,
  });
}

/// Callback phases for progress reporting.
enum SyncPhase { scanning, reconciling, propagating, updatingArchive, done }

/// Progress callback.
typedef SyncProgressCallback = void Function(SyncPhase phase, String message);

/// End-to-end local file synchronizer.
class SyncEngine {
  final ArchiveStore _archiveStore;
  final UpdateDetector _updateDetector;
  final Reconciler _reconciler;
  final TransportOrchestrator _transport;
  final FpCache _fpCache1;
  final FpCache _fpCache2;

  SyncEngine({
    ArchiveStore? archiveStore,
    UpdateDetector? updateDetector,
    Reconciler? reconciler,
    TransportOrchestrator? transport,
    FpCache? fpCache1,
    FpCache? fpCache2,
  })  : _archiveStore = archiveStore ?? ArchiveStore(ArchiveStore.defaultArchiveDir()),
        _updateDetector = updateDetector ?? UpdateDetector(),
        _reconciler = reconciler ?? const Reconciler(),
        _transport = transport ?? TransportOrchestrator(),
        _fpCache1 = fpCache1 ?? FpCache(),
        _fpCache2 = fpCache2 ?? FpCache();

  /// Run a complete sync between two local roots.
  ///
  /// Phases:
  /// 1. Load archives for both roots
  /// 2. Scan both roots for changes (Update Detection)
  /// 3. Reconcile changes
  /// 4. Propagate non-conflicting changes
  /// 5. Save updated archives
  SyncResult sync(
    Fspath root1,
    Fspath root2, {
    UpdateConfig? updateConfig,
    ReconConfig? reconConfig,
    List<SyncPath>? paths,
    SyncProgressCallback? onProgress,
  }) {
    final uConfig = updateConfig ?? const UpdateConfig();
    final rConfig = reconConfig ?? const ReconConfig();
    final syncPaths = paths ?? [SyncPath.empty];

    // Phase 1: Load archives
    onProgress?.call(SyncPhase.scanning, 'Loading archives...');
    final archive = _archiveStore.load(root1, root2);

    // Split archive for each root (both use the same archive)
    var archive1 = archive;
    var archive2 = archive;

    // Phase 2: Scan both roots
    onProgress?.call(SyncPhase.scanning, 'Scanning replica 1...');
    final updates = <(SyncPath, UpdateItem, UpdateItem)>[];

    for (final syncPath in syncPaths) {
      // Detect changes on replica 1
      final detector1 = UpdateDetector(fpCache: _fpCache1);
      final (ui1, _) = detector1.findUpdates(root1, syncPath, archive1, uConfig);

      // Detect changes on replica 2
      onProgress?.call(SyncPhase.scanning, 'Scanning replica 2...');
      final detector2 = UpdateDetector(fpCache: _fpCache2);
      final (ui2, _) = detector2.findUpdates(root2, syncPath, archive2, uConfig);

      updates.add((syncPath, ui1, ui2));
    }

    // Phase 3: Reconcile
    onProgress?.call(SyncPhase.reconciling, 'Reconciling changes...');
    ReconResult reconResult;

    if (updates.length == 1) {
      final (syncPath, ui1, ui2) = updates[0];
      reconResult = _reconciler.reconcileUpdates(syncPath, ui1, ui2, rConfig);
    } else {
      // For multiple paths, flatten UpdateItems
      final flatUpdates = <(SyncPath, UpdateItem, UpdateItem)>[];
      for (final (syncPath, ui1, ui2) in updates) {
        _flattenUpdates(syncPath, ui1, ui2, flatUpdates);
      }
      reconResult = _reconciler.reconcileAll(flatUpdates, rConfig);
    }

    Trace.info(
      TraceCategory.general,
      'Reconciliation: ${reconResult.items.length} items to sync, '
      '${reconResult.equalCount} equal',
    );

    // Phase 4: Propagate
    onProgress?.call(SyncPhase.propagating, 'Propagating changes...');
    final transportResults = _transport.propagateAll(
      root1,
      root2,
      reconResult.items,
    );

    // Phase 5: Update and save archives
    onProgress?.call(SyncPhase.updatingArchive, 'Updating archives...');
    _updateAndSaveArchive(root1, root2, uConfig);

    onProgress?.call(SyncPhase.done, 'Sync complete');

    return SyncResult(
      transportResults: transportResults,
      reconItems: reconResult.items,
      equalCount: reconResult.equalCount,
      scanErrors: reconResult.errors,
    );
  }

  /// Build fresh archives from both roots after propagation and save them.
  void _updateAndSaveArchive(
    Fspath root1,
    Fspath root2,
    UpdateConfig config,
  ) {
    // After propagation, both roots should be in sync.
    // Build archive from root1 (they should be identical now).
    final detector = UpdateDetector(fpCache: _fpCache1);
    final newArchive = detector.buildArchiveFromFs(root1, SyncPath.empty, config);
    _archiveStore.save(root1, root2, newArchive);
  }

  /// Flatten paired update items for multi-path sync.
  void _flattenUpdates(
    SyncPath path,
    UpdateItem ui1,
    UpdateItem ui2,
    List<(SyncPath, UpdateItem, UpdateItem)> out,
  ) {
    // If both are directory updates, flatten their children
    if (ui1 case Updates(content: DirContent(children: var ch1))) {
      if (ui2 case Updates(content: DirContent(children: var ch2))) {
        // Merge children
        var i = 0, j = 0;
        while (i < ch1.length && j < ch2.length) {
          final cmp = ch1[i].$1.compareTo(ch2[j].$1);
          if (cmp < 0) {
            out.add((path.child(ch1[i].$1), ch1[i].$2, const NoUpdates()));
            i++;
          } else if (cmp > 0) {
            out.add((path.child(ch2[j].$1), const NoUpdates(), ch2[j].$2));
            j++;
          } else {
            out.add((path.child(ch1[i].$1), ch1[i].$2, ch2[j].$2));
            i++;
            j++;
          }
        }
        while (i < ch1.length) {
          out.add((path.child(ch1[i].$1), ch1[i].$2, const NoUpdates()));
          i++;
        }
        while (j < ch2.length) {
          out.add((path.child(ch2[j].$1), const NoUpdates(), ch2[j].$2));
          j++;
        }
        return;
      }
    }
    out.add((path, ui1, ui2));
  }

  // -----------------------------------------------------------------------
  // Continuous sync modes
  // -----------------------------------------------------------------------

  /// Run sync repeatedly on a fixed interval.
  ///
  /// Returns a [StreamSubscription] that can be cancelled to stop.
  Stream<SyncResult> syncRepeat(
    Fspath root1,
    Fspath root2, {
    required Duration interval,
    UpdateConfig? updateConfig,
    ReconConfig? reconConfig,
    SyncProgressCallback? onProgress,
  }) async* {
    while (true) {
      final result = sync(
        root1,
        root2,
        updateConfig: updateConfig,
        reconConfig: reconConfig,
        onProgress: onProgress,
      );
      yield result;
      await Future.delayed(interval);
    }
  }

  /// Run sync triggered by filesystem changes (watch mode).
  ///
  /// Performs an initial sync, then watches both roots for changes.
  /// When changes are detected, automatically re-syncs.
  /// Returns a controller to stop watching.
  WatchSyncController syncWatch(
    Fspath root1,
    Fspath root2, {
    UpdateConfig? updateConfig,
    ReconConfig? reconConfig,
    IgnoreFilter? filter,
    Duration debounce = const Duration(seconds: 2),
    SyncProgressCallback? onProgress,
    void Function(SyncResult result)? onSyncComplete,
  }) {
    final controller = WatchSyncController._();

    // Initial sync
    final initialResult = sync(
      root1,
      root2,
      updateConfig: updateConfig,
      reconConfig: reconConfig,
      onProgress: onProgress,
    );
    onSyncComplete?.call(initialResult);

    // Start watching
    final watcher = DualWatcher(
      root1: root1,
      root2: root2,
      filter: filter,
      debounce: debounce,
    );

    var syncing = false;
    var pendingResync = false;

    watcher.start((batch, replicaIndex) {
      if (!controller.isRunning) return;

      Trace.info(
        TraceCategory.fswatch,
        'Changes detected on replica $replicaIndex: ${batch.size} paths',
      );

      if (syncing) {
        pendingResync = true;
        return;
      }

      syncing = true;
      try {
        final result = sync(
          root1,
          root2,
          updateConfig: updateConfig,
          reconConfig: reconConfig,
          onProgress: onProgress,
        );
        onSyncComplete?.call(result);
      } catch (e) {
        Trace.error(TraceCategory.general, 'Watch sync failed: $e');
      } finally {
        syncing = false;
        if (pendingResync && controller.isRunning) {
          pendingResync = false;
          // Trigger another sync after a short delay
          Future.delayed(const Duration(seconds: 1), () {
            if (!controller.isRunning) return;
            try {
              final result = sync(
                root1, root2,
                updateConfig: updateConfig,
                reconConfig: reconConfig,
                onProgress: onProgress,
              );
              onSyncComplete?.call(result);
            } catch (e) {
              Trace.error(TraceCategory.general, 'Pending resync failed: $e');
            }
          });
        }
      }
    });

    controller._watcher = watcher;
    return controller;
  }
}

/// Controller for stopping a watch-mode sync.
class WatchSyncController {
  DualWatcher? _watcher;
  bool _running = true;

  WatchSyncController._();

  bool get isRunning => _running;

  /// Stop watching and syncing.
  Future<void> stop() async {
    _running = false;
    await _watcher?.dispose();
    _watcher = null;
  }
}
