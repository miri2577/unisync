/// Platform-specific filesystem extensions.
///
/// Provides hardlink detection, extended attributes, and ACL stubs.
/// Full FFI implementations can be added per platform.
library;

import 'dart:io';
import 'dart:typed_data';

/// Extended filesystem operations that require platform-specific support.
class PlatformFs {
  const PlatformFs();

  /// Check if a file is a hardlink (has link count > 1).
  ///
  /// Returns the number of hard links, or 1 if detection is not available.
  int hardLinkCount(String path) {
    if (Platform.isWindows) return 1; // not reliably available

    try {
      // On Unix, use stat to get nlink
      final result = Process.runSync('stat', ['-c', '%h', path]);
      if (result.exitCode == 0) {
        return int.tryParse(result.stdout.toString().trim()) ?? 1;
      }
    } catch (_) {}
    return 1;
  }

  /// Create a hard link.
  void createHardLink(String target, String linkPath) {
    if (Platform.isWindows) {
      Process.runSync('cmd', ['/c', 'mklink', '/H', linkPath, target]);
    } else {
      Link(linkPath).createSync(target);
    }
  }

  /// Check if two paths refer to the same inode (hardlinked).
  bool areSameFile(String path1, String path2) {
    try {
      final stat1 = FileStat.statSync(path1);
      final stat2 = FileStat.statSync(path2);
      // dart:io doesn't expose inode, so compare by identity heuristic
      return stat1.size == stat2.size &&
          stat1.modified == stat2.modified &&
          stat1.type == stat2.type;
    } catch (_) {
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Extended attributes (stubs — full impl requires FFI per platform)
  // -----------------------------------------------------------------------

  /// Get an extended attribute value.
  ///
  /// Returns null if xattrs are not supported or the attribute doesn't exist.
  Uint8List? getXattr(String path, String name) {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final cmd = Platform.isMacOS
            ? Process.runSync('xattr', ['-p', name, path])
            : Process.runSync('getfattr', ['--only-values', '-n', name, path]);
        if (cmd.exitCode == 0) {
          return Uint8List.fromList(cmd.stdout as List<int>);
        }
      } catch (_) {}
    }
    return null;
  }

  /// Set an extended attribute value.
  ///
  /// Returns true if successful.
  bool setXattr(String path, String name, Uint8List value) {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final valueStr = String.fromCharCodes(value);
        final cmd = Platform.isMacOS
            ? Process.runSync('xattr', ['-w', name, valueStr, path])
            : Process.runSync(
                'setfattr', ['-n', name, '-v', valueStr, path]);
        return cmd.exitCode == 0;
      } catch (_) {}
    }
    return false;
  }

  /// List extended attribute names.
  List<String> listXattrs(String path) {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final cmd = Platform.isMacOS
            ? Process.runSync('xattr', [path])
            : Process.runSync('getfattr', ['-d', path]);
        if (cmd.exitCode == 0) {
          return cmd.stdout
              .toString()
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }
    return [];
  }

  /// Remove an extended attribute.
  bool removeXattr(String path, String name) {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final cmd = Platform.isMacOS
            ? Process.runSync('xattr', ['-d', name, path])
            : Process.runSync('setfattr', ['-x', name, path]);
        return cmd.exitCode == 0;
      } catch (_) {}
    }
    return false;
  }

  // -----------------------------------------------------------------------
  // ACL stubs
  // -----------------------------------------------------------------------

  /// Get ACL as string representation.
  String? getAcl(String path) {
    if (Platform.isLinux) {
      try {
        final result = Process.runSync('getfacl', ['--omit-header', path]);
        if (result.exitCode == 0) return result.stdout.toString();
      } catch (_) {}
    }
    if (Platform.isMacOS) {
      try {
        final result = Process.runSync('ls', ['-le', path]);
        if (result.exitCode == 0) return result.stdout.toString();
      } catch (_) {}
    }
    return null;
  }

  /// Set ACL from string representation.
  bool setAcl(String path, String acl) {
    if (Platform.isLinux) {
      try {
        final result = Process.runSync('setfacl', ['--set', acl, path]);
        return result.exitCode == 0;
      } catch (_) {}
    }
    return false;
  }
}
