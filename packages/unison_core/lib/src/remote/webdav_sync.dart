/// WebDAV sync adapter — bridges WebDAV client to the sync engine.
///
/// Provides update detection and file propagation over WebDAV,
/// enabling sync with Nextcloud, Synology, HiDrive, and any
/// WebDAV-compatible server without needing a remote binary.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../archive/archive_store.dart';
import '../engine/recon.dart';
import '../engine/sync_engine.dart';
import '../engine/transport.dart';
import '../fingerprint/fpcache.dart';
import '../model/archive.dart';
import '../model/fileinfo.dart';
import '../model/fingerprint.dart';
import '../model/fspath.dart';
import '../model/name.dart';
import '../model/props.dart';
import '../model/recon_item.dart';
import '../model/sync_path.dart';
import '../model/update_item.dart';
import '../engine/history.dart';
import '../engine/update.dart';
import '../transfer/rsync.dart';
import '../util/trace.dart';
import 'webdav.dart';

/// Sync engine that works with one local root and one WebDAV root.
class WebDavSyncEngine {
  final Fspath _localRoot;
  final WebDavClient _webdav;
  final ArchiveStore _archiveStore;
  final FpCache _fpCache;

  /// Fake Fspath for the WebDAV root (used as archive key).
  final Fspath _webdavRootKey;

  /// Remote base path prefix (e.g. "UniSync/my-profile/").
  final String _remotePrefix;

  /// Sync history recorder.
  final SyncHistory _history;

  /// Profile name for history recording.
  final String _profileName;

  WebDavSyncEngine({
    required Fspath localRoot,
    required WebDavClient webdav,
    String? profileName,
    ArchiveStore? archiveStore,
  })  : _localRoot = localRoot,
        _profileName = profileName ?? 'default',
        _webdav = webdav,
        _archiveStore = archiveStore ?? ArchiveStore(ArchiveStore.defaultArchiveDir()),
        _fpCache = FpCache(),
        _history = SyncHistory(
            archiveStore?.archiveDir ?? ArchiveStore.defaultArchiveDir()),
        _remotePrefix = 'UniSync/${profileName ?? "default"}/',
        _webdavRootKey = Fspath.fromLocal(
          Platform.isWindows ? 'C:/webdav/${webdav.config.baseUrl.hashCode}' : '/webdav/${webdav.config.baseUrl.hashCode}',
        );

  /// Convert a sync path to the remote WebDAV path with prefix.
  String _remotePath(SyncPath path) {
    final rel = path.toString();
    if (rel.isEmpty) return _remotePrefix;
    return '$_remotePrefix$rel';
  }

  /// Optional cancellation check — called between operations.
  bool Function()? cancelCheck;

  /// Run a full sync: local <-> WebDAV.
  ///
  /// Files are stored on the WebDAV server under `UniSync/<profileName>/`
  /// to keep them separate from other data.
  Future<SyncResult> sync({
    SyncProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    cancelCheck = isCancelled;
    // Phase 0: Ensure remote prefix directory exists
    onProgress?.call(SyncPhase.scanning, 'Preparing remote directory...');
    Trace.info(TraceCategory.remote, 'Ensuring remote prefix: $_remotePrefix');
    await _webdav.mkdirRecursive(_remotePrefix);
    Trace.info(TraceCategory.remote, 'Remote prefix ready');

    // Phase 1: Load archive
    onProgress?.call(SyncPhase.scanning, 'Loading archive...');
    final archive = _archiveStore.load(_localRoot, _webdavRootKey);
    Trace.info(TraceCategory.archive, 'Archive loaded: ${archive.runtimeType}');

    // Phase 2: Scan local
    onProgress?.call(SyncPhase.scanning, 'Scanning local files...');
    Trace.info(TraceCategory.update, 'Scanning local: $_localRoot');
    final localUpdates = await _scanLocal(archive);
    Trace.info(TraceCategory.update, 'Local scan done');

    // Phase 3: Scan WebDAV (within prefix)
    onProgress?.call(SyncPhase.scanning, 'Scanning remote (WebDAV)...');
    Trace.info(TraceCategory.remote, 'Scanning remote: $_remotePrefix');
    final webdavUpdates = await _scanWebDav(archive, SyncPath.empty);
    Trace.info(TraceCategory.remote, 'Remote scan done');

    // Phase 4: Reconcile — flatten DirContent trees into per-file items
    // so each file gets its own ReconItem with direction arrow in the UI.
    onProgress?.call(SyncPhase.reconciling, 'Reconciling...');
    const reconciler = Reconciler();

    // Flatten the two update trees into per-path triples
    final flatUpdates = <(SyncPath, UpdateItem, UpdateItem)>[];
    _flattenPair(SyncPath.empty, localUpdates, webdavUpdates, flatUpdates);
    Trace.info(TraceCategory.recon,
        'Flattened to ${flatUpdates.length} path-pairs');

    final reconResult = reconciler.reconcileAll(flatUpdates, const ReconConfig());

    Trace.info(TraceCategory.general,
        'WebDAV reconciliation: ${reconResult.items.length} items');

    // Safety: if WebDAV looks empty but archive claims it had content,
    // refuse to sync — this prevents catastrophic local deletion when
    // the remote was wiped or the archive is corrupted.
    if (archive is ArchiveDir && (archive).children.isNotEmpty) {
      // Count entries actually returned by the WebDAV scan
      var remoteHasContent = false;
      if (webdavUpdates is Updates) {
        if ((webdavUpdates).content case DirContent(children: var ch)) {
          remoteHasContent = ch.any((c) => c.$2 is! Updates ||
              ((c.$2 as Updates).content) is! Absent);
        }
      }
      if (!remoteHasContent) {
        Trace.error(TraceCategory.general,
            'ABORT: WebDAV is empty but archive expects content. '
            'This would delete local files. Delete archive to force fresh sync.');
        throw StateError(
            'Refusing to sync: remote is empty but archive expects content. '
            'This is likely caused by a previous failed sync. '
            'Delete the archive at C:/Users/mirkorichter/.unison/ar* to start fresh.');
      }
    }

    // Phase 5: Propagate
    onProgress?.call(SyncPhase.propagating, 'Propagating...');
    Trace.info(TraceCategory.transport,
        'Propagating ${reconResult.items.length} items');
    final results = <TransportResult>[];
    for (var i = 0; i < reconResult.items.length; i++) {
      if (cancelCheck?.call() == true) {
        Trace.warning(TraceCategory.transport,
            'Cancelled by user — stopping at item ${i + 1}/${reconResult.items.length}');
        // Mark remaining items as skipped
        for (var j = i; j < reconResult.items.length; j++) {
          results.add(TransportSkipped(
              reconResult.items[j].path1, 'Cancelled'));
        }
        break;
      }
      final item = reconResult.items[i];
      onProgress?.call(SyncPhase.propagating,
          'Item ${i + 1}/${reconResult.items.length}: ${item.path1}');
      Trace.info(TraceCategory.transport,
          'Propagating ${item.path1} (${item.direction})');
      final r = await _propagateItem(item);
      Trace.info(TraceCategory.transport, 'Result: ${r.runtimeType}');
      results.add(r);
    }

    // Phase 6: Rebuild and save archive ONLY if all items succeeded.
    // Saving a partial archive would falsely claim things are in sync,
    // causing future runs to "delete" missing remote files from local.
    final succeeded = results.whereType<TransportSuccess>().length;
    final failed = results.whereType<TransportError>().length;
    final skipped = results.whereType<TransportSkipped>().length;
    if (succeeded == 0 && failed > 0) {
      Trace.warning(TraceCategory.archive,
          'NOT saving archive: 0 succeeded, $failed failed');
    } else if (skipped > 0 && results.length == 1 && results.first is TransportSkipped) {
      // Only-item-was-skipped case (e.g. nothing to do, or all conflicts)
      Trace.info(TraceCategory.archive, 'No successful transfers, archive unchanged');
    } else {
      onProgress?.call(SyncPhase.updatingArchive, 'Updating archive...');
      Trace.info(TraceCategory.archive, 'Building archive (with pseudo-fp)...');
      final detector = UpdateDetector(fpCache: _fpCache);
      final newArchive = detector.buildArchiveFromFs(
        _localRoot, SyncPath.empty,
        const UpdateConfig(
          useFastCheck: true,
          usePseudoFingerprintForNewFiles: true,
        ),
      );
      Trace.info(TraceCategory.archive, 'Archive built, saving...');
      _archiveStore.save(_localRoot, _webdavRootKey, newArchive);
      Trace.info(TraceCategory.archive, 'Archive saved');
    }

    // Record in Time Machine history
    final syncResult = SyncResult(
      transportResults: results,
      reconItems: reconResult.items,
      equalCount: reconResult.equalCount,
      scanErrors: reconResult.errors,
    );
    _recordHistory(syncResult);

    onProgress?.call(SyncPhase.done, 'Sync complete');
    return syncResult;
  }

  /// Record this sync in the Time Machine history.
  void _recordHistory(SyncResult result) {
    if (result.propagated == 0 && result.failed == 0) return;

    final now = DateTime.now();
    final entries = <HistoryEntry>[];

    for (var i = 0; i < result.reconItems.length; i++) {
      final item = result.reconItems[i];
      final transport = i < result.transportResults.length
          ? result.transportResults[i]
          : null;
      if (transport is TransportSuccess) {
        if (item.replicas case Different(diff: var diff)) {
          final source = diff.direction is Replica1ToReplica2
              ? diff.rc1 : diff.rc2;
          entries.add(HistoryEntry(
            path: item.path1.toString(),
            action: source.status.name,
            direction: diff.direction is Replica1ToReplica2
                ? 'upload' : 'download',
            size: source.size.$2,
          ));
        }
      }
    }

    _history.record(SyncRecord(
      id: '${now.millisecondsSinceEpoch}',
      timestamp: now,
      root1: _localRoot.toString(),
      root2: _webdav.config.baseUrl,
      profileName: _profileName,
      entries: entries,
      propagated: result.propagated,
      skipped: result.skipped,
      failed: result.failed,
      durationMs: 0,
    ));
  }

  /// Scan local filesystem against archive.
  /// Runs in a separate isolate to avoid blocking the UI thread.
  Future<UpdateItem> _scanLocal(Archive archive) async {
    final rootPath = _localRoot.toLocal();

    // Run the entire scan in a background isolate so the UI stays responsive.
    // The scan can take 30+ seconds for large folders (stat() on every file).
    return await Isolate.run(() {
      final root = Fspath.fromLocal(rootPath);
      final detector = UpdateDetector();
      final (ui, _) = detector.findUpdates(
        root, SyncPath.empty, archive,
        const UpdateConfig(
          useFastCheck: true,
          usePseudoFingerprintForNewFiles: true,
        ),
      );
      return ui;
    });
  }

  /// Scan WebDAV server against archive.
  Future<UpdateItem> _scanWebDav(Archive archive, SyncPath path) async {
    try {
      final entries = await _webdav.listDirectory(_remotePath(path));

      if (archive case ArchiveDir(desc: var arDesc, children: var arChildren)) {
        // Compare WebDAV entries against archive
        final childUpdates = <(Name, UpdateItem)>[];

        // Index archive children
        final arNames = arChildren.keys.toSet();
        final remoteNames = <Name>{};

        Trace.info(TraceCategory.remote,
            'PROPFIND returned ${entries.length} entries for $path');
        for (final entry in entries) {
          Trace.info(TraceCategory.remote,
              '  entry: "${entry.name}" dir=${entry.isDirectory} '
              'size=${entry.size}');
          final name = Name(entry.name);
          remoteNames.add(name);
          final childPath = path.child(name);
          final childArchive = arChildren[name] ?? const NoArchive();
          Trace.info(TraceCategory.remote,
              '  archive: ${childArchive.runtimeType}');

          if (entry.isDirectory) {
            final childUi = await _scanWebDav(childArchive, childPath);
            if (childUi is! NoUpdates) {
              childUpdates.add((name, childUi));
            }
          } else {
            final ui = _compareFileEntry(entry, childArchive, childPath);
            if (ui is! NoUpdates) {
              childUpdates.add((name, ui));
            }
          }
        }

        // Deleted on remote (in archive but not in WebDAV)
        for (final arName in arNames) {
          if (!remoteNames.contains(arName)) {
            childUpdates.add((arName, Updates(
              const Absent(),
              _prevStateOf(arChildren[arName]!),
            )));
          }
        }

        if (childUpdates.isEmpty) return const NoUpdates();
        // CRITICAL: sort by Name — _mergeChildren requires sorted input.
        // Without this, duplicates appear with opposite directions.
        childUpdates.sort((a, b) => a.$1.compareTo(b.$1));
        return Updates(
          DirContent(arDesc, childUpdates, PermChange.propsSame, false),
          PrevDir(arDesc),
        );
      }

      if (archive is NoArchive) {
        // First sync: everything on WebDAV is "new"
        final childUpdates = <(Name, UpdateItem)>[];
        for (final entry in entries) {
          final name = Name(entry.name);
          if (entry.isDirectory) {
            final childUi = await _scanWebDav(const NoArchive(), path.child(name));
            if (childUi is! NoUpdates) {
              childUpdates.add((name, childUi));
            }
          } else {
            childUpdates.add((name, _newFileEntry(entry)));
          }
        }
        if (childUpdates.isEmpty) return const NoUpdates();
        // Sort — _mergeChildren requires sorted input
        childUpdates.sort((a, b) => a.$1.compareTo(b.$1));
        final desc = Props(
          permissions: 0x1FF,
          modTime: DateTime.now(),
          length: 0,
        );
        return Updates(
          DirContent(desc, childUpdates, PermChange.propsUpdated, false),
          const NewEntry(),
        );
      }

      return const NoUpdates();
    } catch (e) {
      return UpdateError('WebDAV scan error: $e');
    }
  }

  UpdateItem _compareFileEntry(WebDavEntry entry, Archive archive, SyncPath path) {
    if (archive case ArchiveFile(desc: var arDesc, fingerprint: var arFp)) {
      final currentFp = _etagFingerprint(entry);

      Trace.debug(TraceCategory.remote,
          'Compare ${entry.name}: remote=${entry.size}B etag=${entry.etag} '
          'archive=${arDesc.length}B fp=${arFp.dataFork.isPseudo ? "pseudo" : "real"}');

      // Primary check: ETag fingerprint matches archive → unchanged
      if (currentFp == arFp.dataFork) {
        Trace.debug(TraceCategory.remote, '  → ETag match, unchanged');
        return const NoUpdates();
      }

      // Size-only check: WebDAV uploads don't preserve mtime, so we
      // can't compare timestamps. If size matches, trust it.
      if (entry.size == arDesc.length) {
        Trace.debug(TraceCategory.remote, '  → Size match, unchanged');
        return const NoUpdates();
      }

      Trace.debug(TraceCategory.remote,
          '  → CHANGED (size ${entry.size} != ${arDesc.length})');
      // File changed on remote (different size)
      final desc = Props(
        permissions: 0x1ED,
        modTime: entry.lastModified ?? DateTime.now(),
        length: entry.size,
      );
      return Updates(
        FileContent(desc, ContentsUpdated(
          FullFingerprint(currentFp), const NoStamp(), RessStamp.zero,
        )),
        PrevFile(arDesc, arFp, const NoStamp(), RessStamp.zero),
      );
    }

    // New file
    return _newFileEntry(entry);
  }

  UpdateItem _newFileEntry(WebDavEntry entry) {
    final desc = Props(
      permissions: 0x1ED,
      modTime: entry.lastModified ?? DateTime.now(),
      length: entry.size,
    );
    final fp = _etagFingerprint(entry);
    return Updates(
      FileContent(desc, ContentsUpdated(
        FullFingerprint(fp), const NoStamp(), RessStamp.zero,
      )),
      const NewEntry(),
    );
  }

  /// Create a fingerprint from the WebDAV entry's ETag.
  /// ETags change when content changes — they're the server's content ID.
  /// If no ETag available, fall back to size+mtime hash (pseudo-FP).
  Fingerprint _etagFingerprint(WebDavEntry entry) {
    if (entry.etag != null && entry.etag!.isNotEmpty) {
      // ETag is a real content identifier from the server
      final digest = md5.convert(utf8.encode(entry.etag!));
      return Fingerprint(Uint8List.fromList(digest.bytes));
    }
    // Fallback: pseudo-fingerprint from size+mtime
    return Fingerprint.pseudo(
        '${entry.name}:${entry.size}:${entry.lastModified}',
        entry.size);
  }

  PrevState _prevStateOf(Archive archive) {
    return switch (archive) {
      ArchiveDir(desc: var d) => PrevDir(d),
      ArchiveFile(desc: var d, fingerprint: var fp, stamp: var s, ressStamp: var r) =>
        PrevFile(d, fp, s, r),
      ArchiveSymlink() => const PrevSymlink(),
      NoArchive() => const NewEntry(),
    };
  }

  /// Propagate a single item between local and WebDAV.
  Future<TransportResult> _propagateItem(ReconItem item) async {
    if (item.replicas case Different(diff: var diff)) {
      try {
        switch (diff.direction) {
          case Conflict():
            return TransportSkipped(item.path1, 'Conflict');
          case Merge():
            return TransportSkipped(item.path1, 'Merge not supported for WebDAV');

          case Replica1ToReplica2():
            // Local → WebDAV
            await _uploadToWebDav(item.path1, diff.rc1);
            return TransportSuccess(item.path1);

          case Replica2ToReplica1():
            // WebDAV → Local
            await _downloadFromWebDav(item.path1, diff.rc2);
            return TransportSuccess(item.path1);
        }
      } catch (e) {
        Trace.error(TraceCategory.transport, 'WebDAV propagate failed: $e');
        return TransportError(item.path1, '$e');
      }
    }
    return TransportSkipped(item.path1, 'Problem');
  }

  Future<void> _uploadToWebDav(SyncPath path, ReplicaContent source) async {
    if (source.status == ReplicaStatus.deleted) {
      await _webdav.delete(_remotePath(path));
      return;
    }

    final counter = _UploadCounter();
    _countFiles(source.content, counter);
    Trace.info(TraceCategory.transport,
        'Total files to upload: ${counter.total}');

    switch (source.content) {
      case FileContent():
        Trace.info(TraceCategory.transport,
            'Upload [1/1]: $path (${source.desc.length} B)');
        final localPath = _localRoot.concat(path).toLocal();
        final data = File(localPath).readAsBytesSync();
        await _webdav.writeFileWithParents(_remotePath(path), data);

      case DirContent(children: var children):
        await _webdav.mkdirRecursive(_remotePath(path));
        for (final (name, childUpdate) in children) {
          if (childUpdate is Updates) {
            await _uploadChildItem(path.child(name), childUpdate, counter);
          }
        }

      default:
        break;
    }
  }

  /// Flatten two paired update trees into per-file triples.
  ///
  /// Walks DirContent children recursively so that each FILE or
  /// ABSENT gets its own (path, ui1, ui2) entry for reconciliation.
  void _flattenPair(
    SyncPath path,
    UpdateItem ui1,
    UpdateItem ui2,
    List<(SyncPath, UpdateItem, UpdateItem)> out,
  ) {
    // Both are DirContent → recurse into merged children
    if (ui1 case Updates(content: DirContent(children: var ch1))) {
      if (ui2 case Updates(content: DirContent(children: var ch2))) {
        // Sorted merge
        var i = 0, j = 0;
        while (i < ch1.length && j < ch2.length) {
          final cmp = ch1[i].$1.compareTo(ch2[j].$1);
          if (cmp < 0) {
            _flattenPair(path.child(ch1[i].$1), ch1[i].$2, const NoUpdates(), out);
            i++;
          } else if (cmp > 0) {
            _flattenPair(path.child(ch2[j].$1), const NoUpdates(), ch2[j].$2, out);
            j++;
          } else {
            _flattenPair(path.child(ch1[i].$1), ch1[i].$2, ch2[j].$2, out);
            i++; j++;
          }
        }
        while (i < ch1.length) {
          _flattenPair(path.child(ch1[i].$1), ch1[i].$2, const NoUpdates(), out);
          i++;
        }
        while (j < ch2.length) {
          _flattenPair(path.child(ch2[j].$1), const NoUpdates(), ch2[j].$2, out);
          j++;
        }
        return;
      }
    }

    // One side is DirContent, other is NoUpdates → recurse into the DirContent
    if (ui1 case Updates(content: DirContent(children: var ch))) {
      if (ui2 is NoUpdates) {
        for (final (name, child) in ch) {
          _flattenPair(path.child(name), child, const NoUpdates(), out);
        }
        return;
      }
    }
    if (ui2 case Updates(content: DirContent(children: var ch))) {
      if (ui1 is NoUpdates) {
        for (final (name, child) in ch) {
          _flattenPair(path.child(name), const NoUpdates(), child, out);
        }
        return;
      }
    }

    // Leaf: both NoUpdates → skip
    if (ui1 is NoUpdates && ui2 is NoUpdates) return;

    // Leaf: at least one side has an update → add as flat item
    out.add((path, ui1, ui2));
  }

  /// Count total files in the upload tree.
  void _countFiles(UpdateContent content, _UploadCounter counter) {
    switch (content) {
      case FileContent():
        counter.total++;
      case DirContent(children: var children):
        for (final (_, child) in children) {
          if (child is Updates) _countFiles(child.content, counter);
        }
      default:
        break;
    }
  }

  /// Upload a single child item from a nested DirContent.
  Future<void> _uploadChildItem(
      SyncPath path, Updates update, _UploadCounter counter) async {
    if (cancelCheck?.call() == true) return;
    switch (update.content) {
      case FileContent(desc: var desc):
        counter.done++;
        final localPath = _localRoot.concat(path).toLocal();
        try {
          final localData = File(localPath).readAsBytesSync();
          final remotePath = _remotePath(path);

          // Rsync delta: for large files that already exist on server,
          // download the old version, compute delta, upload only changes.
          if (desc.length > 1024 * 1024 && update.prevState is! NewEntry) {
            try {
              final exists = await _webdav.exists(remotePath);
              if (exists) {
                final oldData = await _webdav.readFile(remotePath);
                const rsync = Rsync();
                final tokens = rsync.computeDelta(oldData, localData);
                final blockSize = Rsync.computeBlockSize(oldData.length);
                final result = rsync.decompress(blockSize, oldData, tokens);
                var deltaBytes = 0;
                for (final t in tokens) {
                  if (t is StringToken) deltaBytes += t.data.length;
                }
                Trace.info(TraceCategory.transport,
                    'Upload [${counter.done}/${counter.total}]: $path '
                    'rsync delta ${deltaBytes}B of ${desc.length}B');
                await _webdav.writeFileWithParents(remotePath, result);
                break;
              }
            } catch (e) {
              Trace.debug(TraceCategory.transport,
                  'Rsync delta failed for $path, using full upload: $e');
            }
          }

          // Full upload
          Trace.info(TraceCategory.transport,
              'Upload [${counter.done}/${counter.total}]: $path (${desc.length} B)');
          await _webdav.writeFileWithParents(remotePath, localData);
        } catch (e) {
          Trace.warning(TraceCategory.transport, 'Upload $path failed: $e');
        }
      case DirContent(children: var children):
        await _webdav.mkdirRecursive(_remotePath(path));
        for (final (name, child) in children) {
          if (child is Updates) {
            await _uploadChildItem(path.child(name), child, counter);
          }
        }
      case Absent():
        try {
          await _webdav.delete(_remotePath(path));
        } catch (_) {}
      case SymlinkContent():
        // WebDAV doesn't support symlinks
        break;
    }
  }

  Future<void> _downloadFromWebDav(SyncPath path, ReplicaContent source) async {
    if (source.status == ReplicaStatus.deleted) {
      final localPath = _localRoot.concat(path).toLocal();
      if (File(localPath).existsSync()) File(localPath).deleteSync();
      if (Directory(localPath).existsSync()) {
        Directory(localPath).deleteSync(recursive: true);
      }
      return;
    }

    switch (source.content) {
      case FileContent():
        final localPath = _localRoot.concat(path).toLocal();
        // Safety: if local path is a directory, skip (can't overwrite dir with file)
        if (Directory(localPath).existsSync()) {
          Trace.warning(TraceCategory.transport,
              'Skip download $path: local path is a directory');
          return;
        }
        final data = await _webdav.readFile(_remotePath(path));
        final parent = File(localPath).parent;
        if (!parent.existsSync()) parent.createSync(recursive: true);
        File(localPath).writeAsBytesSync(data);

      case DirContent(children: var children):
        final localPath = _localRoot.concat(path).toLocal();
        Directory(localPath).createSync(recursive: true);
        // Recurse into children — the reconciler returns a single DirContent
        // for the whole subtree on first sync
        for (final (name, childUpdate) in children) {
          if (childUpdate is Updates) {
            await _downloadChildItem(path.child(name), childUpdate);
          }
        }

      default:
        break;
    }
  }

  /// Download a single child item from a nested DirContent.
  Future<void> _downloadChildItem(SyncPath path, Updates update) async {
    switch (update.content) {
      case FileContent(desc: var desc):
        Trace.info(TraceCategory.transport,
            'Download: $path (${desc.length} B)');
        try {
          final localPath = _localRoot.concat(path).toLocal();
          if (Directory(localPath).existsSync()) {
            Trace.warning(TraceCategory.transport,
                'Skip download $path: local is a directory');
            return;
          }
          final data = await _webdav.readFile(_remotePath(path));
          final parent = File(localPath).parent;
          if (!parent.existsSync()) parent.createSync(recursive: true);
          File(localPath).writeAsBytesSync(data);
        } catch (e) {
          Trace.warning(TraceCategory.transport, 'Download $path failed: $e');
        }
      case DirContent(children: var children):
        final localPath = _localRoot.concat(path).toLocal();
        Directory(localPath).createSync(recursive: true);
        for (final (name, child) in children) {
          if (child is Updates) {
            await _downloadChildItem(path.child(name), child);
          }
        }
      case Absent():
        // Delete locally
        final localPath = _localRoot.concat(path).toLocal();
        try {
          if (File(localPath).existsSync()) File(localPath).deleteSync();
          if (Directory(localPath).existsSync()) {
            Directory(localPath).deleteSync(recursive: true);
          }
        } catch (_) {}
      case SymlinkContent():
        break;
    }
  }
}

class _UploadCounter {
  int total = 0;
  int done = 0;
}
