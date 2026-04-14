/// Archive store — persistent storage for sync archives.
///
/// Manages loading, saving, and locking of archive files on disk.
/// Implements two-phase commit for crash safety: writes to temp file first,
/// then atomically renames. On startup, recovers from incomplete commits.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../model/archive.dart';
import '../model/fspath.dart';
import '../util/trace.dart';
import 'archive_serial.dart';

/// Manages archive persistence on disk with crash-safe two-phase commit.
class ArchiveStore {
  /// Base directory for archive files (e.g. ~/.unison/).
  final String archiveDir;

  ArchiveStore(this.archiveDir);

  /// Get the default archive directory for the current platform.
  static String defaultArchiveDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.unison';
  }

  /// Compute the archive hash for a pair of roots.
  static String archiveHash(Fspath root1, Fspath root2) {
    final input = '${root1.toString()};${root2.toString()};$archiveFormat';
    final hash = md5.convert(utf8.encode(input));
    return hash.toString().substring(0, 12);
  }

  // File paths for a given hash
  String _archivePath(String hash) => '$archiveDir/ar$hash';
  String _tempPath(String hash) => '$archiveDir/tm$hash';
  String _oldPath(String hash) => '$archiveDir/old_ar$hash';
  String _lockPath(String hash) => '$archiveDir/lk$hash';
  String _commitLogPath(String hash) => '$archiveDir/cl$hash';

  /// FP cache file path: fp<HASH>
  String _fpCachePath(String hash) => '$archiveDir/fp$hash';

  /// Get the fingerprint cache file path for a root pair.
  String fpCachePath(Fspath root1, Fspath root2) =>
      _fpCachePath(archiveHash(root1, root2));

  /// Ensure the archive directory exists.
  void ensureDir() {
    Directory(archiveDir).createSync(recursive: true);
  }

  // -----------------------------------------------------------------------
  // Crash recovery
  // -----------------------------------------------------------------------

  /// Recover from incomplete commits on startup.
  ///
  /// Checks all archive hashes for incomplete two-phase commits and
  /// either completes or rolls them back.
  void recoverAll() {
    ensureDir();
    final dir = Directory(archiveDir);
    if (!dir.existsSync()) return;

    // Find all commit logs
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.contains('/cl') ||
          entity.path.contains('\\cl')) {
        final basename = entity.uri.pathSegments.last;
        if (basename.startsWith('cl')) {
          final hash = basename.substring(2);
          _recoverOne(hash);
        }
      }
    }

    // Clean up orphaned temp files (no commit log = interrupted before log)
    for (final entity in dir.listSync()) {
      final basename = entity.uri.pathSegments.last;
      if (entity is File && basename.startsWith('tm')) {
        final hash = basename.substring(2);
        if (!File(_commitLogPath(hash)).existsSync()) {
          // Orphaned temp — delete it
          Trace.warning(
            TraceCategory.archive,
            'Removing orphaned temp archive: $basename',
          );
          entity.deleteSync();
        }
      }
    }
  }

  /// Recover a single archive from incomplete commit.
  void _recoverOne(String hash) {
    final commitLog = File(_commitLogPath(hash));
    if (!commitLog.existsSync()) return;

    final phase = commitLog.readAsStringSync().trim();

    switch (phase) {
      case 'PHASE1':
        // Temp was written but old not yet moved.
        // Rollback: delete temp, remove commit log.
        Trace.info(
          TraceCategory.archive,
          'Recovery: rolling back incomplete commit for $hash (PHASE1)',
        );
        _safeDelete(_tempPath(hash));
        _safeDelete(_commitLogPath(hash));

      case 'PHASE2':
        // Old archive was backed up, temp exists. Complete the commit.
        Trace.info(
          TraceCategory.archive,
          'Recovery: completing interrupted commit for $hash (PHASE2)',
        );
        final tempFile = File(_tempPath(hash));
        final archivePath = _archivePath(hash);
        if (tempFile.existsSync()) {
          _safeDelete(archivePath);
          tempFile.renameSync(archivePath);
        }
        _safeDelete(_oldPath(hash));
        _safeDelete(_commitLogPath(hash));

      case 'PHASE3':
        // Rename was done, just clean up old backup and log.
        Trace.info(
          TraceCategory.archive,
          'Recovery: cleaning up after commit for $hash (PHASE3)',
        );
        _safeDelete(_oldPath(hash));
        _safeDelete(_commitLogPath(hash));

      default:
        // Unknown state — clean up everything
        Trace.warning(
          TraceCategory.archive,
          'Recovery: unknown commit phase "$phase" for $hash, cleaning up',
        );
        _safeDelete(_tempPath(hash));
        _safeDelete(_oldPath(hash));
        _safeDelete(_commitLogPath(hash));
    }
  }

  // -----------------------------------------------------------------------
  // Load / Save with two-phase commit
  // -----------------------------------------------------------------------

  /// Load an archive for a root pair. Returns [NoArchive] if none exists.
  Archive load(Fspath root1, Fspath root2) {
    final hash = archiveHash(root1, root2);

    // Recover from any incomplete commit first
    _recoverOne(hash);

    final path = _archivePath(hash);
    final file = File(path);

    if (!file.existsSync()) {
      Trace.info(
        TraceCategory.archive,
        'No archive found for $root1 <-> $root2',
      );
      return const NoArchive();
    }

    try {
      final data = file.readAsBytesSync();
      final archive = decodeArchive(data);
      Trace.info(TraceCategory.archive, 'Loaded archive from $path');
      return archive;
    } on ArchiveVersionError catch (e) {
      Trace.warning(
        TraceCategory.archive,
        'Archive version mismatch ($e), starting fresh',
      );
      return const NoArchive();
    } catch (e) {
      Trace.warning(
        TraceCategory.archive,
        'Failed to load archive from $path: $e',
      );
      return const NoArchive();
    }
  }

  /// Save an archive using two-phase commit for crash safety.
  ///
  /// Protocol:
  /// 1. Write new archive to temp file, write commit log "PHASE1"
  /// 2. Backup old archive, update commit log to "PHASE2"
  /// 3. Rename temp to final, update commit log to "PHASE3"
  /// 4. Delete old backup and commit log
  void save(Fspath root1, Fspath root2, Archive archive) {
    ensureDir();
    final hash = archiveHash(root1, root2);
    final tempPath = _tempPath(hash);
    final finalPath = _archivePath(hash);
    final oldPath = _oldPath(hash);
    final commitLogPath = _commitLogPath(hash);

    // PHASE 1: Write new data to temp
    final data = encodeArchive(archive);
    File(commitLogPath).writeAsStringSync('PHASE1');
    File(tempPath).writeAsBytesSync(data);

    // PHASE 2: Backup old archive
    File(commitLogPath).writeAsStringSync('PHASE2');
    if (File(finalPath).existsSync()) {
      try {
        File(finalPath).renameSync(oldPath);
      } catch (_) {
        // If rename fails, try copy+delete
        File(finalPath).copySync(oldPath);
        File(finalPath).deleteSync();
      }
    }

    // PHASE 3: Move temp to final
    File(commitLogPath).writeAsStringSync('PHASE3');
    try {
      File(tempPath).renameSync(finalPath);
    } catch (_) {
      File(tempPath).copySync(finalPath);
      File(tempPath).deleteSync();
    }

    // Cleanup: remove old backup and commit log
    _safeDelete(oldPath);
    _safeDelete(commitLogPath);

    Trace.info(
      TraceCategory.archive,
      'Saved archive to $finalPath (${data.length} bytes)',
    );
  }

  // -----------------------------------------------------------------------
  // Locking
  // -----------------------------------------------------------------------

  /// Acquire a lock for a root pair. Returns `true` if acquired.
  bool lock(Fspath root1, Fspath root2) {
    ensureDir();
    final hash = archiveHash(root1, root2);
    final lockFile = File(_lockPath(hash));

    if (lockFile.existsSync()) {
      try {
        final content = lockFile.readAsStringSync().trim();
        final pid = int.tryParse(content);
        if (pid != null) {
          Trace.warning(
            TraceCategory.archive,
            'Archive locked by PID $pid',
          );
          return false;
        }
      } catch (_) {}
    }

    try {
      lockFile.writeAsStringSync('$pid\n');
      return true;
    } catch (e) {
      Trace.warning(TraceCategory.archive, 'Failed to acquire lock: $e');
      return false;
    }
  }

  /// Release the lock for a root pair.
  void unlock(Fspath root1, Fspath root2) {
    final hash = archiveHash(root1, root2);
    _safeDelete(_lockPath(hash));
  }

  /// Check if an archive exists for a root pair.
  bool exists(Fspath root1, Fspath root2) {
    final hash = archiveHash(root1, root2);
    return File(_archivePath(hash)).existsSync();
  }

  /// Delete archive and related files for a root pair.
  void delete(Fspath root1, Fspath root2) {
    final hash = archiveHash(root1, root2);
    for (final path in [
      _archivePath(hash),
      _tempPath(hash),
      _oldPath(hash),
      _lockPath(hash),
      _commitLogPath(hash),
      _fpCachePath(hash),
    ]) {
      _safeDelete(path);
    }
  }

  void _safeDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
