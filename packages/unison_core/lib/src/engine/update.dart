/// Update detection — compares filesystem state against archive.
///
/// Mirrors OCaml Unison's `update.ml`. The core algorithm walks the
/// filesystem and archive tree in parallel, producing an [UpdateItem]
/// tree that describes all changes since the last sync.
library;

import 'dart:collection';
import 'dart:io';

import '../fingerprint/fingerprint_service.dart';
import '../fingerprint/fpcache.dart';
import '../fs/fileinfo_service.dart';
import '../fs/os.dart';
import '../model/archive.dart';
import '../model/fileinfo.dart';
import '../model/fingerprint.dart';
import '../model/fspath.dart';
import '../model/name.dart';
import '../model/props.dart';
import '../model/sync_path.dart';
import '../model/update_item.dart';
import '../util/trace.dart';

/// Configuration for update detection.
class UpdateConfig {
  /// Use fast-check optimization (skip fingerprint if mtime+size unchanged).
  final bool useFastCheck;

  /// Use FAT filesystem time tolerance (2-second granularity).
  final bool fatTolerance;

  /// Predicate to check if a path should be ignored.
  final bool Function(SyncPath path)? shouldIgnore;

  /// Predicate for symlinks that should be followed transparently.
  final bool Function(SyncPath path)? shouldFollow;

  /// Use pseudo-fingerprints for NEW files instead of computing MD5.
  /// Massively speeds up first sync of large folders. Pseudo-fp is
  /// based on path+size, so changes only get detected later via mtime.
  final bool usePseudoFingerprintForNewFiles;

  const UpdateConfig({
    this.useFastCheck = true,
    this.fatTolerance = false,
    this.shouldIgnore,
    this.shouldFollow,
    this.usePseudoFingerprintForNewFiles = false,
  });
}

/// Detects changes between the filesystem and the stored archive.
class UpdateDetector {
  final OsFs _os;
  final FileinfoService _fileinfoService;
  final FingerprintService _fingerprintService;
  final FpCache _fpCache;

  UpdateDetector({
    OsFs? os,
    FileinfoService? fileinfoService,
    FingerprintService? fingerprintService,
    FpCache? fpCache,
  })  : _os = os ?? const OsFs(),
        _fileinfoService = fileinfoService ?? const FileinfoService(),
        _fingerprintService = fingerprintService ?? const FingerprintService(),
        _fpCache = fpCache ?? FpCache();

  /// Detect all updates for a root, comparing filesystem against [archive].
  ///
  /// Returns an [UpdateItem] tree describing what changed.
  /// Also returns the updated archive reflecting current filesystem state.
  (UpdateItem, Archive) findUpdates(
    Fspath root,
    SyncPath path,
    Archive archive,
    UpdateConfig config,
  ) {
    try {
      return _updateRec(root, path, archive, config);
    } catch (e) {
      Trace.error(
        TraceCategory.update,
        'Error scanning $root / $path: $e',
      );
      return (UpdateError('$e'), archive);
    }
  }

  /// Recursive update detection at a single path.
  (UpdateItem, Archive) _updateRec(
    Fspath root,
    SyncPath path,
    Archive archive,
    UpdateConfig config,
  ) {
    // Check ignore
    if (config.shouldIgnore != null && config.shouldIgnore!(path)) {
      return (const NoUpdates(), archive);
    }

    var info = _fileinfoService.get(root, path);

    // Symlink following: if the path is a symlink and shouldFollow matches,
    // resolve the target and treat it as the target type instead.
    if (info.typ == FileType.symlink &&
        config.shouldFollow != null &&
        config.shouldFollow!(path)) {
      info = _resolveSymlink(root, path, info);
    }

    return switch ((info.typ, archive)) {
      // Both absent — nothing to do
      (FileType.absent, NoArchive()) => (const NoUpdates(), archive),

      // File exists, was in archive as file
      (FileType.file, ArchiveFile() && var af) =>
        _updateFile(root, path, info, af, config),

      // Directory exists, was in archive as directory
      (FileType.directory, ArchiveDir() && var ad) =>
        _updateDir(root, path, info, ad, config),

      // Symlink exists, was in archive as symlink
      (FileType.symlink, ArchiveSymlink() && var as_) =>
        _updateSymlink(root, path, as_),

      // Absent on disk, was something in archive — deleted
      (FileType.absent, _) =>
        _updateDeleted(archive),

      // Exists on disk, not in archive — new entry
      (_, NoArchive()) =>
        _updateNew(root, path, info, config),

      // Type changed (e.g. file -> dir, dir -> symlink)
      (_, _) =>
        _updateTypeChanged(root, path, info, archive, config),
    };
  }

  /// File exists and was a file in the archive.
  (UpdateItem, Archive) _updateFile(
    Fspath root,
    SyncPath path,
    Fileinfo info,
    ArchiveFile archived,
    UpdateConfig config,
  ) {
    final fullPath = root.concat(path).toLocal();

    // Fast-check: skip fingerprint if metadata unchanged
    if (config.useFastCheck) {
      final cachedFp = _fpCache.getCachedFingerprint(fullPath, info.desc);
      if (cachedFp != null && cachedFp == archived.fingerprint.dataFork) {
        // Content unchanged — check props only
        if (info.desc.similar(archived.desc, fatTolerance: config.fatTolerance)) {
          return (const NoUpdates(), archived);
        }
        // Props changed, content same
        return (
          Updates(
            FileContent(info.desc, const ContentsSame()),
            PrevFile(
              archived.desc,
              archived.fingerprint,
              archived.stamp,
              archived.ressStamp,
            ),
          ),
          archived,
        );
      }
    }

    // Compute fingerprint
    Fingerprint fp;
    try {
      fp = _fingerprintService.file(root, path);
    } catch (e) {
      return (UpdateError('Cannot fingerprint $path: $e'), archived);
    }

    // Cache it
    _fpCache.put(fullPath, info.desc, fp);

    final fullFp = FullFingerprint(fp);
    final prevState = PrevFile(
      archived.desc,
      archived.fingerprint,
      archived.stamp,
      archived.ressStamp,
    );

    if (fullFp == archived.fingerprint) {
      // Content unchanged
      if (info.desc.similar(archived.desc, fatTolerance: config.fatTolerance)) {
        return (const NoUpdates(), archived);
      }
      // Only props changed
      return (
        Updates(FileContent(info.desc, const ContentsSame()), prevState),
        archived,
      );
    }

    // Content changed
    return (
      Updates(
        FileContent(
          info.desc,
          ContentsUpdated(fullFp, info.stamp, archived.ressStamp),
        ),
        prevState,
      ),
      archived,
    );
  }

  /// Directory exists and was a directory in the archive.
  (UpdateItem, Archive) _updateDir(
    Fspath root,
    SyncPath path,
    Fileinfo info,
    ArchiveDir archived,
    UpdateConfig config,
  ) {
    Trace.debug(TraceCategory.update,
        'Scanning dir: ${path.isEmpty ? "(root)" : path}');
    // dirStamp optimization: if directory mtime is unchanged and fast-check
    // is enabled, check if the children list matches the archive.
    // If both match, we can skip recursing into this directory entirely.
    if (config.useFastCheck &&
        info.desc.similar(archived.desc, fatTolerance: config.fatTolerance)) {
      final fsChildren = _os.childrenOf(root, path);
      final archiveNames = archived.children.keys.toList();
      if (_childrenListUnchanged(fsChildren, archiveNames)) {
        return (const NoUpdates(), archived);
      }
    }

    // Get current children from filesystem
    final fsChildren = _os.childrenOf(root, path);

    // Sorted merge of filesystem children and archive children
    final archiveNames = archived.children.keys.toList();
    final mergedChildren = _sortedMerge(fsChildren, archiveNames);

    final updatedChildren = <(Name, UpdateItem)>[];
    final newArchiveChildren = SplayTreeMap<Name, Archive>();
    var anyChanges = false;

    for (final (name, inFs, inArchive) in mergedChildren) {
      final childPath = path.child(name);
      final childArchive =
          inArchive ? (archived.children[name] ?? const NoArchive()) : const NoArchive();

      final (updateItem, newChildArchive) =
          _updateRec(root, childPath, childArchive, config);

      if (updateItem is! NoUpdates) {
        updatedChildren.add((name, updateItem));
        anyChanges = true;
      }

      // Keep archive entry for all children that exist
      if (newChildArchive is! NoArchive) {
        newArchiveChildren[name] = newChildArchive;
      }
    }

    // Check if directory props changed
    final permChange = info.desc.similar(
      archived.desc,
      fatTolerance: config.fatTolerance,
    )
        ? PermChange.propsSame
        : PermChange.propsUpdated;

    if (!anyChanges && permChange == PermChange.propsSame) {
      return (const NoUpdates(), archived);
    }

    final isEmpty = fsChildren.isEmpty && archived.children.isNotEmpty;

    final updateItem = Updates(
      DirContent(info.desc, updatedChildren, permChange, isEmpty),
      PrevDir(archived.desc),
    );

    final newArchive = ArchiveDir(info.desc, newArchiveChildren);
    return (updateItem, newArchive);
  }

  /// Symlink exists and was a symlink in the archive.
  (UpdateItem, Archive) _updateSymlink(
    Fspath root,
    SyncPath path,
    ArchiveSymlink archived,
  ) {
    String target;
    try {
      target = _os.readLink(root, path);
    } catch (e) {
      return (UpdateError('Cannot read symlink $path: $e'), archived);
    }

    if (target == archived.target) {
      return (const NoUpdates(), archived);
    }

    return (
      Updates(SymlinkContent(target), const PrevSymlink()),
      archived,
    );
  }

  /// Path was deleted (exists in archive but not on disk).
  (UpdateItem, Archive) _updateDeleted(Archive archived) {
    final prevState = switch (archived) {
      ArchiveDir(desc: var d) => PrevDir(d) as PrevState,
      ArchiveFile(desc: var d, fingerprint: var fp, stamp: var s, ressStamp: var r) =>
        PrevFile(d, fp, s, r) as PrevState,
      ArchiveSymlink() => const PrevSymlink() as PrevState,
      NoArchive() => const NewEntry() as PrevState,
    };

    return (
      Updates(const Absent(), prevState),
      const NoArchive(),
    );
  }

  /// Path is new (exists on disk but not in archive).
  (UpdateItem, Archive) _updateNew(
    Fspath root,
    SyncPath path,
    Fileinfo info,
    UpdateConfig config,
  ) {
    switch (info.typ) {
      case FileType.file:
        Trace.debug(TraceCategory.update,
            'New file: $path (${info.desc.length} B)');
        Fingerprint fp;
        try {
          if (config.usePseudoFingerprintForNewFiles) {
            // Skip MD5 — use cheap pseudo-fingerprint (path + size hash)
            fp = Fingerprint.pseudo(path.toString(), info.desc.length);
          } else {
            fp = _fingerprintService.file(root, path);
          }
        } catch (e) {
          return (UpdateError('Cannot fingerprint new file $path: $e'), const NoArchive());
        }
        final fullPath = root.concat(path).toLocal();
        if (!fp.isPseudo) {
          _fpCache.put(fullPath, info.desc, fp);
        }

        final fullFp = FullFingerprint(fp);
        return (
          Updates(
            FileContent(info.desc, ContentsUpdated(fullFp, info.stamp, RessStamp.zero)),
            const NewEntry(),
          ),
          const NoArchive(),
        );

      case FileType.directory:
        final fsChildren = _os.childrenOf(root, path);
        final childUpdates = <(Name, UpdateItem)>[];

        for (final name in fsChildren) {
          final childPath = path.child(name);
          final (childUpdate, _) =
              _updateRec(root, childPath, const NoArchive(), config);
          if (childUpdate is! NoUpdates) {
            childUpdates.add((name, childUpdate));
          }
        }

        return (
          Updates(
            DirContent(info.desc, childUpdates, PermChange.propsUpdated, false),
            const NewEntry(),
          ),
          const NoArchive(),
        );

      case FileType.symlink:
        String target;
        try {
          target = _os.readLink(root, path);
        } catch (e) {
          return (UpdateError('Cannot read new symlink $path: $e'), const NoArchive());
        }
        return (
          Updates(SymlinkContent(target), const NewEntry()),
          const NoArchive(),
        );

      case FileType.absent:
        return (const NoUpdates(), const NoArchive());
    }
  }

  /// Type changed (e.g. was file, now directory).
  (UpdateItem, Archive) _updateTypeChanged(
    Fspath root,
    SyncPath path,
    Fileinfo info,
    Archive archived,
    UpdateConfig config,
  ) {
    // Treat as deletion of old + creation of new
    final prevState = switch (archived) {
      ArchiveDir(desc: var d) => PrevDir(d) as PrevState,
      ArchiveFile(desc: var d, fingerprint: var fp, stamp: var s, ressStamp: var r) =>
        PrevFile(d, fp, s, r),
      ArchiveSymlink() => const PrevSymlink(),
      NoArchive() => const NewEntry(),
    };

    // Build update content for the new type
    final (newUpdate, _) = _updateNew(root, path, info, config);
    if (newUpdate case Updates(content: var content)) {
      return (Updates(content, prevState), const NoArchive());
    }

    return (newUpdate, const NoArchive());
  }

  /// Sorted merge of two sorted name lists.
  ///
  /// Check if a directory's children list matches the archive exactly.
  /// Resolve a symlink to its target's Fileinfo.
  /// Follows up to 100 levels deep to detect cycles.
  Fileinfo _resolveSymlink(Fspath root, SyncPath path, Fileinfo symlinkInfo) {
    final visited = <String>{};
    var currentPath = root.concat(path).toLocal();

    for (var i = 0; i < 100; i++) {
      if (visited.contains(currentPath)) {
        Trace.warning(
          TraceCategory.update,
          'Symlink cycle detected at $path',
        );
        return symlinkInfo; // Return as symlink, don't follow
      }
      visited.add(currentPath);

      try {
        final target = Link(currentPath).targetSync();
        // Resolve relative targets
        final resolvedTarget = File(target).existsSync()
            ? target
            : '${File(currentPath).parent.path}/$target';

        final type = FileSystemEntity.typeSync(resolvedTarget, followLinks: false);
        if (type == FileSystemEntityType.link) {
          currentPath = resolvedTarget;
          continue; // Follow chain
        }

        // Got the real target — stat it
        return _fileinfoService.getAbsolute(resolvedTarget);
      } catch (e) {
        Trace.warning(
          TraceCategory.update,
          'Cannot resolve symlink $path: $e',
        );
        return symlinkInfo;
      }
    }

    Trace.warning(TraceCategory.update, 'Symlink chain too deep at $path');
    return symlinkInfo;
  }

  bool _childrenListUnchanged(List<Name> fsChildren, List<Name> archiveNames) {
    if (fsChildren.length != archiveNames.length) return false;
    for (var i = 0; i < fsChildren.length; i++) {
      if (fsChildren[i] != archiveNames[i]) return false;
    }
    return true;
  }

  /// Returns triples: (name, existsInFs, existsInArchive).
  List<(Name, bool, bool)> _sortedMerge(
    List<Name> fsNames,
    List<Name> archiveNames,
  ) {
    final result = <(Name, bool, bool)>[];
    var i = 0, j = 0;

    while (i < fsNames.length && j < archiveNames.length) {
      final cmp = fsNames[i].compareTo(archiveNames[j]);
      if (cmp < 0) {
        result.add((fsNames[i], true, false));
        i++;
      } else if (cmp > 0) {
        result.add((archiveNames[j], false, true));
        j++;
      } else {
        result.add((fsNames[i], true, true));
        i++;
        j++;
      }
    }
    while (i < fsNames.length) {
      result.add((fsNames[i], true, false));
      i++;
    }
    while (j < archiveNames.length) {
      result.add((archiveNames[j], false, true));
      j++;
    }

    return result;
  }

  /// Build a fresh archive from the current filesystem state.
  ///
  /// Used when no previous archive exists (first sync).
  Archive buildArchiveFromFs(
    Fspath root,
    SyncPath path,
    UpdateConfig config,
  ) {
    final info = _fileinfoService.get(root, path);

    switch (info.typ) {
      case FileType.file:
        Trace.debug(TraceCategory.archive,
            'Archive: $path (${info.desc.length} B)');
        Fingerprint fp;
        if (config.usePseudoFingerprintForNewFiles) {
          fp = Fingerprint.pseudo(path.toString(), info.desc.length);
        } else {
          fp = _fingerprintService.file(root, path);
          final fullPath = root.concat(path).toLocal();
          _fpCache.put(fullPath, info.desc, fp);
        }
        return ArchiveFile(
          info.desc,
          FullFingerprint(fp),
          info.stamp,
          RessStamp.zero,
        );

      case FileType.directory:
        final children = _os.childrenOf(root, path);
        final archiveChildren = emptyNameMap();
        for (final name in children) {
          if (config.shouldIgnore != null &&
              config.shouldIgnore!(path.child(name))) {
            continue;
          }
          archiveChildren[name] =
              buildArchiveFromFs(root, path.child(name), config);
        }
        return ArchiveDir(info.desc, archiveChildren);

      case FileType.symlink:
        final target = _os.readLink(root, path);
        return ArchiveSymlink(target);

      case FileType.absent:
        return const NoArchive();
    }
  }

  /// Update the archive after successful propagation.
  ///
  /// Incorporates the changes from an [UpdateItem] into the existing archive.
  Archive updateArchive(Archive archive, SyncPath path, UpdateItem item) {
    if (item is NoUpdates) return archive;

    if (path.isEmpty) {
      return _applyUpdate(archive, item);
    }

    final (firstName, rest) = path.deconstruct()!;

    if (archive case ArchiveDir(desc: var desc, children: var children)) {
      final childArchive = children[firstName] ?? const NoArchive();
      final updatedChild = updateArchive(childArchive, rest, item);
      final newChildren = SplayTreeMap<Name, Archive>.of(children);
      if (updatedChild is NoArchive) {
        newChildren.remove(firstName);
      } else {
        newChildren[firstName] = updatedChild;
      }
      return ArchiveDir(desc, newChildren);
    }

    return archive;
  }

  Archive _applyUpdate(Archive archive, UpdateItem item) {
    if (item case Updates(content: var content)) {
      return switch (content) {
        Absent() => const NoArchive(),
        FileContent(desc: var desc, contentsChange: var cc) => switch (cc) {
          ContentsSame() => switch (archive) {
            ArchiveFile(fingerprint: var fp, stamp: var s, ressStamp: var r) =>
              ArchiveFile(desc, fp, s, r),
            _ => archive,
          },
          ContentsUpdated(fingerprint: var fp, stamp: var s, ressStamp: var r) =>
            ArchiveFile(desc, fp, s, r),
        },
        DirContent(desc: var desc) => switch (archive) {
          ArchiveDir(children: var ch) => ArchiveDir(desc, ch),
          _ => ArchiveDir.empty(desc),
        },
        SymlinkContent(target: var t) => ArchiveSymlink(t),
      };
    }
    return archive;
  }
}
