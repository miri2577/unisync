/// WebDAV sync adapter — bridges WebDAV client to the sync engine.
///
/// Provides update detection and file propagation over WebDAV,
/// enabling sync with Nextcloud, Synology, HiDrive, and any
/// WebDAV-compatible server without needing a remote binary.
library;

import 'dart:convert';
import 'dart:io';
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
import '../engine/update.dart';
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

  WebDavSyncEngine({
    required Fspath localRoot,
    required WebDavClient webdav,
    ArchiveStore? archiveStore,
  })  : _localRoot = localRoot,
        _webdav = webdav,
        _archiveStore = archiveStore ?? ArchiveStore(ArchiveStore.defaultArchiveDir()),
        _fpCache = FpCache(),
        _webdavRootKey = Fspath.fromLocal(
          Platform.isWindows ? 'C:/webdav/${webdav.config.baseUrl.hashCode}' : '/webdav/${webdav.config.baseUrl.hashCode}',
        );

  /// Run a full sync: local <-> WebDAV.
  Future<SyncResult> sync({
    SyncProgressCallback? onProgress,
  }) async {
    // Phase 1: Load archive
    onProgress?.call(SyncPhase.scanning, 'Loading archive...');
    final archive = _archiveStore.load(_localRoot, _webdavRootKey);

    // Phase 2: Scan local
    onProgress?.call(SyncPhase.scanning, 'Scanning local files...');
    final localUpdates = _scanLocal(archive);

    // Phase 3: Scan WebDAV
    onProgress?.call(SyncPhase.scanning, 'Scanning remote (WebDAV)...');
    final webdavUpdates = await _scanWebDav(archive, SyncPath.empty);

    // Phase 4: Reconcile
    onProgress?.call(SyncPhase.reconciling, 'Reconciling...');
    const reconciler = Reconciler();
    final reconResult = reconciler.reconcileUpdates(
      SyncPath.empty,
      localUpdates,
      webdavUpdates,
      const ReconConfig(),
    );

    Trace.info(TraceCategory.general,
        'WebDAV reconciliation: ${reconResult.items.length} items');

    // Phase 5: Propagate
    onProgress?.call(SyncPhase.propagating, 'Propagating...');
    final results = <TransportResult>[];
    for (final item in reconResult.items) {
      final r = await _propagateItem(item);
      results.add(r);
    }

    // Phase 6: Rebuild and save archive from local (now in sync)
    onProgress?.call(SyncPhase.updatingArchive, 'Updating archive...');
    final detector = UpdateDetector(fpCache: _fpCache);
    final newArchive = detector.buildArchiveFromFs(
      _localRoot, SyncPath.empty, const UpdateConfig(useFastCheck: false),
    );
    _archiveStore.save(_localRoot, _webdavRootKey, newArchive);

    onProgress?.call(SyncPhase.done, 'Sync complete');

    return SyncResult(
      transportResults: results,
      reconItems: reconResult.items,
      equalCount: reconResult.equalCount,
      scanErrors: reconResult.errors,
    );
  }

  /// Scan local filesystem against archive.
  UpdateItem _scanLocal(Archive archive) {
    final detector = UpdateDetector(fpCache: _fpCache);
    final (ui, _) = detector.findUpdates(
      _localRoot, SyncPath.empty, archive,
      const UpdateConfig(useFastCheck: false),
    );
    return ui;
  }

  /// Scan WebDAV server against archive.
  Future<UpdateItem> _scanWebDav(Archive archive, SyncPath path) async {
    try {
      final entries = await _webdav.listDirectory(path.toString());

      if (archive case ArchiveDir(desc: var arDesc, children: var arChildren)) {
        // Compare WebDAV entries against archive
        final childUpdates = <(Name, UpdateItem)>[];

        // Index archive children
        final arNames = arChildren.keys.toSet();
        final remoteNames = <Name>{};

        for (final entry in entries) {
          final name = Name(entry.name);
          remoteNames.add(name);
          final childPath = path.child(name);
          final childArchive = arChildren[name] ?? const NoArchive();

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
      // Compare by size + mtime (can't fingerprint remote without downloading)
      if (entry.size == arDesc.length &&
          entry.lastModified != null &&
          entry.lastModified!.difference(arDesc.modTime).inSeconds.abs() <= 2) {
        return const NoUpdates();
      }

      // Changed
      final desc = Props(
        permissions: 0x1ED,
        modTime: entry.lastModified ?? DateTime.now(),
        length: entry.size,
      );
      // Use a pseudo-fingerprint based on etag/size
      final fp = _pseudoFp(entry);
      return Updates(
        FileContent(desc, ContentsUpdated(
          FullFingerprint(fp), const NoStamp(), RessStamp.zero,
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
    final fp = _pseudoFp(entry);
    return Updates(
      FileContent(desc, ContentsUpdated(
        FullFingerprint(fp), const NoStamp(), RessStamp.zero,
      )),
      const NewEntry(),
    );
  }

  Fingerprint _pseudoFp(WebDavEntry entry) {
    final key = '${entry.etag ?? ""}:${entry.size}:${entry.lastModified}';
    final digest = md5.convert(utf8.encode(key));
    return Fingerprint(Uint8List.fromList(digest.bytes));
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
      await _webdav.delete(path.toString());
      return;
    }

    switch (source.content) {
      case FileContent():
        final localPath = _localRoot.concat(path).toLocal();
        final data = File(localPath).readAsBytesSync();
        await _webdav.writeFileWithParents(path.toString(), data);

      case DirContent():
        await _webdav.mkdirRecursive(path.toString());

      default:
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
        final data = await _webdav.readFile(path.toString());
        final localPath = _localRoot.concat(path).toLocal();
        final parent = File(localPath).parent;
        if (!parent.existsSync()) parent.createSync(recursive: true);
        File(localPath).writeAsBytesSync(data);

      case DirContent():
        final localPath = _localRoot.concat(path).toLocal();
        Directory(localPath).createSync(recursive: true);

      default:
        break;
    }
  }
}
