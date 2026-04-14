/// Absolute filesystem path representation.
///
/// Mirrors OCaml Unison's `fspath.ml`. Enforces:
/// - Always absolute
/// - Forward slashes internally
/// - Root dirs end with `/`, non-root dirs don't
/// - Windows drive letters and UNC paths handled
library;

import 'dart:io' show Platform;

import 'name.dart';
import 'sync_path.dart';

/// An absolute filesystem path.
///
/// Internal representation always uses forward slashes.
class Fspath {
  /// The canonical internal path string (forward slashes).
  final String _path;

  Fspath._(this._path) {
    assert(_path.isNotEmpty, 'Fspath must not be empty');
  }

  /// Create from a local OS path string.
  ///
  /// Converts backslashes to forward slashes and ensures the path is absolute.
  factory Fspath.fromLocal(String localPath) {
    if (localPath.isEmpty) {
      throw ArgumentError('Path must not be empty');
    }

    var p = localPath.replaceAll('\\', '/');

    // Ensure absolute
    if (Platform.isWindows) {
      // Drive letter: C:/ or UNC: //server/share
      if (!(p.length >= 3 && p[1] == ':' && p[2] == '/') &&
          !p.startsWith('//')) {
        throw ArgumentError("Path must be absolute, got: '$localPath'");
      }
    } else {
      if (!p.startsWith('/')) {
        throw ArgumentError("Path must be absolute, got: '$localPath'");
      }
    }

    // Normalize: remove trailing slash unless root
    if (_isRoot(p)) {
      // Ensure root ends with /
      if (!p.endsWith('/')) p = '$p/';
    } else {
      while (p.length > 1 && p.endsWith('/')) {
        p = p.substring(0, p.length - 1);
      }
    }

    return Fspath._(p);
  }

  /// Whether a path string represents a root directory.
  static bool _isRoot(String p) {
    // Unix root
    if (p == '/' || p == '/.') return true;
    // Windows drive root: C:/ or C:
    if (p.length <= 3 && p.length >= 2 && p[1] == ':') return true;
    // UNC root: //server/share
    if (p.startsWith('//')) {
      final afterPrefix = p.substring(2);
      final slashIdx = afterPrefix.indexOf('/');
      if (slashIdx == -1) return true; // //server
      final afterShare = afterPrefix.substring(slashIdx + 1);
      final nextSlash = afterShare.indexOf('/');
      if (nextSlash == -1) return true; // //server/share
      // Check if only trailing slashes remain
      return afterShare.substring(nextSlash).replaceAll('/', '').isEmpty;
    }
    return false;
  }

  /// Append a child name to this path.
  Fspath child(Name name) {
    if (_path.endsWith('/')) {
      return Fspath._('$_path${name.raw}');
    }
    return Fspath._('$_path/${name.raw}');
  }

  /// Concatenate a relative [SyncPath] onto this absolute path.
  Fspath concat(SyncPath relPath) {
    if (relPath.isEmpty) return this;
    var result = this;
    for (final segment in relPath.segments) {
      result = result.child(segment);
    }
    return result;
  }

  /// The final component of this path, or `null` for root.
  String? get finalName {
    if (_isRoot(_path)) return null;
    final idx = _path.lastIndexOf('/');
    if (idx == -1) return _path;
    return _path.substring(idx + 1);
  }

  /// Parent directory, or `null` for root.
  Fspath? get parent {
    if (_isRoot(_path)) return null;
    final idx = _path.lastIndexOf('/');
    if (idx <= 0) return Fspath._('/');
    final parentPath = _path.substring(0, idx);
    // If parent is root, ensure trailing slash
    if (_isRoot(parentPath)) {
      return Fspath._(parentPath.endsWith('/') ? parentPath : '$parentPath/');
    }
    return Fspath._(parentPath);
  }

  /// Convert to OS-native path string.
  String toLocal() {
    if (Platform.isWindows) {
      return _path.replaceAll('/', '\\');
    }
    return _path;
  }

  /// The internal forward-slash representation.
  @override
  String toString() => _path;

  @override
  bool operator ==(Object other) => other is Fspath && _path == other._path;

  @override
  int get hashCode => _path.hashCode;
}
