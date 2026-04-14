/// Backup/stasher for preserving file versions before overwrite.
///
/// Mirrors OCaml Unison's stasher system. Creates backups of files
/// before they are overwritten or deleted during synchronization.
library;

import 'dart:io';

import '../model/fspath.dart';
import '../model/sync_path.dart';
import '../util/trace.dart';

/// Where backups are stored.
enum BackupLocation {
  /// In a central backup directory.
  central,

  /// Next to the original file.
  local,
}

/// Configuration for the backup system.
class BackupConfig {
  /// Where to store backups.
  final BackupLocation location;

  /// Central backup directory (used when location == central).
  final String? backupDir;

  /// Filename prefix for backups.
  final String prefix;

  /// Filename suffix for backups.
  final String suffix;

  /// Maximum number of backup versions to keep per file.
  final int maxBackups;

  const BackupConfig({
    this.location = BackupLocation.central,
    this.backupDir,
    this.prefix = '.bak.',
    this.suffix = '',
    this.maxBackups = 2,
  });
}

/// Manages file backups during synchronization.
class Stasher {
  final BackupConfig _config;

  Stasher({BackupConfig config = const BackupConfig()}) : _config = config;

  /// Create a backup of a file before it is overwritten.
  ///
  /// Returns the backup path, or `null` if backup was not needed/possible.
  String? backup(Fspath root, SyncPath path) {
    final srcPath = root.concat(path).toLocal();
    final srcFile = File(srcPath);

    if (!srcFile.existsSync()) return null;

    final backupPath = _computeBackupPath(root, path);
    if (backupPath == null) return null;

    try {
      // Ensure backup directory exists
      final backupDir = File(backupPath).parent;
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      // Rotate existing backups
      _rotateBackups(root, path);

      // Copy to backup
      srcFile.copySync(backupPath);

      Trace.debug(
        TraceCategory.transport,
        'Backed up $path → $backupPath',
      );
      return backupPath;
    } catch (e) {
      Trace.warning(
        TraceCategory.transport,
        'Failed to backup $path: $e',
      );
      return null;
    }
  }

  /// Create a conflict backup with timestamp.
  ///
  /// Format: `filename (conflict on YYYY-MM-DD).N.ext`
  String? backupConflict(Fspath root, SyncPath path) {
    final srcPath = root.concat(path).toLocal();
    final srcFile = File(srcPath);

    if (!srcFile.existsSync()) return null;

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final name = path.finalName?.raw ?? 'file';
    final dotIdx = name.lastIndexOf('.');
    final baseName = dotIdx > 0 ? name.substring(0, dotIdx) : name;
    final ext = dotIdx > 0 ? name.substring(dotIdx) : '';

    // Find next available number
    final dir = srcFile.parent.path;
    for (var n = 0; n < 100; n++) {
      final suffix = n == 0 ? '' : '.$n';
      final conflictName =
          '$baseName (conflict on $dateStr)$suffix$ext';
      final conflictPath = '$dir${Platform.pathSeparator}$conflictName';

      if (!File(conflictPath).existsSync()) {
        try {
          srcFile.copySync(conflictPath);
          Trace.debug(
            TraceCategory.transport,
            'Conflict backup: $path → $conflictName',
          );
          return conflictPath;
        } catch (e) {
          Trace.warning(
            TraceCategory.transport,
            'Failed to create conflict backup: $e',
          );
          return null;
        }
      }
    }

    return null;
  }

  /// Get the most recent backup for a path, if any.
  String? getLatestBackup(Fspath root, SyncPath path) {
    final backupPath = _computeBackupPath(root, path, version: 0);
    if (backupPath != null && File(backupPath).existsSync()) {
      return backupPath;
    }
    return null;
  }

  /// Compute the backup path for a given sync path.
  String? _computeBackupPath(Fspath root, SyncPath path, {int version = 0}) {
    final name = path.finalName?.raw;
    if (name == null) return null;

    final versionSuffix = version > 0 ? '.$version' : '';
    final backupName = '${_config.prefix}$name${_config.suffix}$versionSuffix';

    switch (_config.location) {
      case BackupLocation.central:
        final dir = _config.backupDir ??
            '${root.toLocal()}${Platform.pathSeparator}.unison_backups';
        // Preserve directory structure in central backup
        final parent = path.parent;
        if (parent != null && !parent.isEmpty) {
          return '$dir${Platform.pathSeparator}'
              '${parent.toString().replaceAll('/', Platform.pathSeparator)}'
              '${Platform.pathSeparator}$backupName';
        }
        return '$dir${Platform.pathSeparator}$backupName';

      case BackupLocation.local:
        final srcPath = root.concat(path).toLocal();
        final srcDir = File(srcPath).parent.path;
        return '$srcDir${Platform.pathSeparator}$backupName';
    }
  }

  /// Rotate existing backups (shift .1 → .2, etc.) and remove excess.
  void _rotateBackups(Fspath root, SyncPath path) {
    // Delete the oldest if at max
    final oldestPath =
        _computeBackupPath(root, path, version: _config.maxBackups - 1);
    if (oldestPath != null) {
      final f = File(oldestPath);
      if (f.existsSync()) f.deleteSync();
    }

    // Shift existing versions up
    for (var i = _config.maxBackups - 2; i >= 0; i--) {
      final from = i == 0
          ? _computeBackupPath(root, path, version: 0)
          : _computeBackupPath(root, path, version: i);
      final to = _computeBackupPath(root, path, version: i + 1);

      if (from != null && to != null) {
        final f = File(from);
        if (f.existsSync()) {
          f.renameSync(to);
        }
      }
    }
  }
}
