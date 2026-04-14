/// OS filesystem abstraction layer.
///
/// Mirrors OCaml Unison's `os.ml`. Provides cross-platform filesystem
/// operations used by the sync engine.
library;

import 'dart:io';
import 'dart:math';

import '../model/fspath.dart';
import '../model/name.dart';
import '../model/sync_path.dart';
import '../util/trace.dart';

/// Filesystem operations abstraction.
class OsFs {
  const OsFs();

  /// List children of a directory, sorted by [Name].
  ///
  /// Returns an empty list if the path doesn't exist or isn't a directory.
  List<Name> childrenOf(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    final dir = Directory(fullPath);

    if (!dir.existsSync()) return const [];

    try {
      final entries = dir.listSync(followLinks: false);
      final names = <Name>[];
      for (final entry in entries) {
        final basename = _basename(entry.path);
        if (basename.isEmpty || basename == '.' || basename == '..') continue;
        names.add(Name(basename));
      }
      names.sort();
      return names;
    } on FileSystemException catch (e) {
      Trace.warning(
        TraceCategory.general,
        'Cannot list directory $fullPath: ${e.message}',
      );
      return const [];
    }
  }

  /// Check if a path exists.
  bool exists(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    return FileSystemEntity.typeSync(fullPath, followLinks: false) !=
        FileSystemEntityType.notFound;
  }

  /// Get the type of a filesystem entity without following symlinks.
  FileSystemEntityType typeOf(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    return FileSystemEntity.typeSync(fullPath, followLinks: false);
  }

  /// Delete a file or directory (recursively).
  void delete(Fspath fspath, SyncPath path, {bool recursive = true}) {
    final fullPath = fspath.concat(path).toLocal();
    final type = FileSystemEntity.typeSync(fullPath, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
      case FileSystemEntityType.link:
        File(fullPath).deleteSync();
      case FileSystemEntityType.directory:
        Directory(fullPath).deleteSync(recursive: recursive);
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        break; // nothing to delete
    }
  }

  /// Atomic rename. Throws on cross-device rename.
  void rename(Fspath fspath, SyncPath from, SyncPath to) {
    final fromPath = fspath.concat(from).toLocal();
    final toPath = fspath.concat(to).toLocal();
    File(fromPath).renameSync(toPath);
  }

  /// Rename using full absolute paths.
  void renameAbsolute(String fromPath, String toPath) {
    final type = FileSystemEntity.typeSync(fromPath, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      Directory(fromPath).renameSync(toPath);
    } else {
      File(fromPath).renameSync(toPath);
    }
  }

  /// Create a directory (and parents if needed).
  void createDir(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    Directory(fullPath).createSync(recursive: true);
  }

  /// Read a symbolic link target.
  String readLink(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    return Link(fullPath).targetSync();
  }

  /// Create a symbolic link.
  void symlink(Fspath fspath, SyncPath path, String target) {
    final fullPath = fspath.concat(path).toLocal();
    Link(fullPath).createSync(target);
  }

  /// Generate a unique temporary file path at the given location.
  ///
  /// Format: `.unison.<hash>.<random>.unison.tmp`
  /// Kept under 143 bytes for eCryptfs compatibility.
  String tempPath(Fspath fspath, SyncPath path) {
    final dir = fspath.concat(path.parent ?? SyncPath.empty).toLocal();
    final rng = Random();
    final random = rng.nextInt(0x7FFFFFFF).toRadixString(16);
    final hash = path.toString().hashCode.toUnsigned(32).toRadixString(16);
    final name = '.unison.$hash.$random.unison.tmp';
    // Truncate to 143 bytes if needed (eCryptfs limit)
    final truncated = name.length > 143 ? name.substring(0, 143) : name;
    if (dir.endsWith(Platform.pathSeparator)) {
      return '$dir$truncated';
    }
    return '$dir${Platform.pathSeparator}$truncated';
  }

  /// Get the canonical hostname.
  String get canonicalHostName {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'localhost';
    }
  }

  /// Set file modification time.
  void setModTime(String path, DateTime time) {
    // dart:io doesn't have setLastModified — use platform-specific fallback
    // On Windows: use powershell, on Unix: use touch -t
    if (Platform.isWindows) {
      final formatted = time.toIso8601String();
      Process.runSync('powershell', [
        '-NoProfile',
        '-Command',
        "(Get-Item '$path').LastWriteTime = [DateTime]::Parse('$formatted')",
      ]);
    } else {
      final epoch = time.millisecondsSinceEpoch ~/ 1000;
      Process.runSync('touch', ['-d', '@$epoch', path]);
    }
  }

  /// Set file permissions (Unix only, no-op on Windows).
  void setPermissions(String path, int permissions) {
    if (!Platform.isWindows) {
      final octal = permissions.toRadixString(8);
      Process.runSync('chmod', [octal, path]);
    }
  }

  /// Set file ownership (Unix only, requires appropriate privileges).
  /// [ownerId] and [groupId] of -1 means "don't change".
  void setOwnership(String path, int ownerId, int groupId) {
    if (Platform.isWindows) return;
    if (ownerId == -1 && groupId == -1) return;

    final ownerStr = ownerId >= 0 ? '$ownerId' : '';
    final groupStr = groupId >= 0 ? '$groupId' : '';
    if (ownerStr.isEmpty && groupStr.isEmpty) return;

    try {
      Process.runSync('chown', ['$ownerStr:$groupStr', path]);
    } catch (e) {
      Trace.debug(TraceCategory.general, 'chown failed for $path: $e');
    }
  }

  static String _basename(String path) {
    var p = path.replaceAll('\\', '/');
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);
    final idx = p.lastIndexOf('/');
    return idx == -1 ? p : p.substring(idx + 1);
  }
}
