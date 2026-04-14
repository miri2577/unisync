/// Filesystem watcher service for detecting changes between syncs.
///
/// Provides cross-platform filesystem monitoring with debouncing,
/// ignore filtering, and change batching. Uses dart:io's
/// FileSystemEntity.watch for platform-native events
/// (ReadDirectoryChangesW on Windows, inotify on Linux, FSEvents on macOS).
library;

import 'dart:async';
import 'dart:io';

import '../filter/ignore.dart';
import '../model/fspath.dart';
import '../model/sync_path.dart';
import '../util/trace.dart';

/// Type of filesystem change detected.
enum WatchEventType {
  created,
  modified,
  deleted,
  moved,
}

/// A single filesystem change event.
class WatchEvent {
  final WatchEventType type;
  final String path;
  final DateTime timestamp;

  const WatchEvent({
    required this.type,
    required this.path,
    required this.timestamp,
  });

  @override
  String toString() => 'WatchEvent($type, $path)';
}

/// A batch of changes collected over a debounce window.
class WatchBatch {
  /// Paths that were created, modified, or deleted.
  final Set<String> changedPaths;

  /// When this batch was finalized.
  final DateTime timestamp;

  const WatchBatch({required this.changedPaths, required this.timestamp});

  bool get isEmpty => changedPaths.isEmpty;
  int get size => changedPaths.length;
}

/// Watches a directory tree for changes.
///
/// Emits debounced [WatchBatch]es of changed paths, filtered
/// by an optional [IgnoreFilter].
class WatcherService {
  final Fspath _root;
  final IgnoreFilter? _filter;
  final Duration _debounce;

  StreamSubscription? _subscription;
  Timer? _debounceTimer;
  final Set<String> _pendingChanges = {};
  final StreamController<WatchBatch> _batchController =
      StreamController<WatchBatch>.broadcast();
  bool _watching = false;

  WatcherService({
    required Fspath root,
    IgnoreFilter? filter,
    Duration debounce = const Duration(milliseconds: 500),
  })  : _root = root,
        _filter = filter,
        _debounce = debounce;

  /// Stream of change batches. Subscribe before calling [start].
  Stream<WatchBatch> get batches => _batchController.stream;

  /// Whether the watcher is currently active.
  bool get isWatching => _watching;

  /// Start watching the root directory for changes.
  void start() {
    if (_watching) return;

    final dir = Directory(_root.toLocal());
    if (!dir.existsSync()) {
      Trace.warning(
        TraceCategory.fswatch,
        'Cannot watch non-existent directory: $_root',
      );
      return;
    }

    _watching = true;
    _subscription = dir
        .watch(recursive: true)
        .listen(_onRawEvent, onError: _onError, onDone: _onDone);

    Trace.info(TraceCategory.fswatch, 'Started watching $_root');
  }

  /// Stop watching.
  Future<void> stop() async {
    if (!_watching) return;
    _watching = false;

    _debounceTimer?.cancel();
    _debounceTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    // Flush any pending changes
    if (_pendingChanges.isNotEmpty) {
      _emitBatch();
    }

    Trace.info(TraceCategory.fswatch, 'Stopped watching $_root');
  }

  /// Dispose the watcher service entirely.
  Future<void> dispose() async {
    await stop();
    await _batchController.close();
  }

  void _onRawEvent(FileSystemEvent event) {
    final relativePath = _toRelativePath(event.path);
    if (relativePath == null) return;

    // Apply ignore filter
    if (_filter != null) {
      final syncPath = SyncPath.fromString(relativePath);
      if (_filter.shouldIgnore(syncPath)) return;
    }

    _pendingChanges.add(relativePath);

    // Reset debounce timer
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _emitBatch);
  }

  void _emitBatch() {
    if (_pendingChanges.isEmpty) return;

    final batch = WatchBatch(
      changedPaths: Set.of(_pendingChanges),
      timestamp: DateTime.now(),
    );
    _pendingChanges.clear();

    Trace.debug(
      TraceCategory.fswatch,
      'Change batch: ${batch.size} paths',
    );

    _batchController.add(batch);
  }

  void _onError(Object error) {
    Trace.error(TraceCategory.fswatch, 'Watch error: $error');
  }

  void _onDone() {
    Trace.info(TraceCategory.fswatch, 'Watch stream ended for $_root');
    _watching = false;
  }

  /// Convert an absolute OS path to a relative forward-slash path.
  String? _toRelativePath(String absPath) {
    final rootStr = _root.toLocal();
    var normalized = absPath.replaceAll('\\', '/');
    var rootNormalized = rootStr.replaceAll('\\', '/');

    if (!rootNormalized.endsWith('/')) rootNormalized += '/';

    if (!normalized.startsWith(rootNormalized)) return null;

    return normalized.substring(rootNormalized.length);
  }
}

/// Watches two roots and triggers a callback when changes are detected.
///
/// Used to implement `repeat = watch` mode.
class DualWatcher {
  final WatcherService _watcher1;
  final WatcherService _watcher2;
  StreamSubscription? _sub1;
  StreamSubscription? _sub2;

  DualWatcher({
    required Fspath root1,
    required Fspath root2,
    IgnoreFilter? filter,
    Duration debounce = const Duration(milliseconds: 500),
  })  : _watcher1 = WatcherService(
          root: root1,
          filter: filter,
          debounce: debounce,
        ),
        _watcher2 = WatcherService(
          root: root2,
          filter: filter,
          debounce: debounce,
        );

  /// Start watching both roots. Calls [onChanges] when either side changes.
  void start(void Function(WatchBatch batch, int replicaIndex) onChanges) {
    _watcher1.start();
    _watcher2.start();

    _sub1 = _watcher1.batches.listen((batch) => onChanges(batch, 1));
    _sub2 = _watcher2.batches.listen((batch) => onChanges(batch, 2));
  }

  /// Stop watching both roots.
  Future<void> stop() async {
    await _sub1?.cancel();
    await _sub2?.cancel();
    await _watcher1.stop();
    await _watcher2.stop();
  }

  /// Dispose both watchers.
  Future<void> dispose() async {
    await stop();
    await _watcher1.dispose();
    await _watcher2.dispose();
  }
}
