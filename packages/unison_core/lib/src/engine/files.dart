/// File-level operations for sync propagation.
///
/// Mirrors OCaml Unison's `files.ml`. Handles copying, deleting,
/// setting properties, and moving files with atomic write safety.
library;

import 'dart:io';
import 'dart:typed_data';

import '../fs/os.dart';
import '../model/fspath.dart';
import '../model/props.dart';
import '../model/sync_path.dart';
import '../util/trace.dart';

/// Progress callback: (bytesTransferred, totalBytes).
typedef ProgressCallback = void Function(int transferred, int total);

/// File-level sync operations with atomic write safety.
class FileOps {
  final OsFs _os;

  FileOps({OsFs? os}) : _os = os ?? const OsFs();

  /// Copy a file from source to destination using atomic temp+rename.
  ///
  /// 1. Ensure parent directory exists
  /// 2. Copy to temp file
  /// 3. Set properties on temp file
  /// 4. Atomic rename to final path
  void copyFile(
    Fspath srcRoot,
    SyncPath srcPath,
    Fspath dstRoot,
    SyncPath dstPath, {
    Props? props,
    ProgressCallback? onProgress,
  }) {
    final srcFull = srcRoot.concat(srcPath).toLocal();
    final dstFull = dstRoot.concat(dstPath).toLocal();

    // Ensure parent directory exists
    final dstParent = File(dstFull).parent;
    if (!dstParent.existsSync()) {
      dstParent.createSync(recursive: true);
    }

    // Generate temp path
    final tempPath = _os.tempPath(dstRoot, dstPath);

    try {
      // Copy content to temp file
      _copyContent(srcFull, tempPath, onProgress: onProgress);

      // Set properties if provided
      if (props != null) {
        _setProps(tempPath, props);
      }

      // Atomic rename to final destination
      // Delete existing target first if it exists
      if (File(dstFull).existsSync()) {
        File(dstFull).deleteSync();
      }
      File(tempPath).renameSync(dstFull);

      Trace.debug(
        TraceCategory.transport,
        'Copied $srcPath → $dstPath',
      );
    } catch (e) {
      // Clean up temp file on failure
      try {
        File(tempPath).deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  /// Copy a directory recursively from source to destination.
  void copyDir(
    Fspath srcRoot,
    SyncPath srcPath,
    Fspath dstRoot,
    SyncPath dstPath, {
    Props? props,
  }) {
    final dstFull = dstRoot.concat(dstPath).toLocal();
    Directory(dstFull).createSync(recursive: true);

    if (props != null) {
      _setProps(dstFull, props);
    }

    // Copy children
    final children = _os.childrenOf(srcRoot, srcPath);
    for (final child in children) {
      final childSrcPath = srcPath.child(child);
      final childDstPath = dstPath.child(child);
      final srcFull = srcRoot.concat(childSrcPath).toLocal();
      final type = FileSystemEntity.typeSync(srcFull, followLinks: false);

      switch (type) {
        case FileSystemEntityType.file:
          copyFile(srcRoot, childSrcPath, dstRoot, childDstPath);
        case FileSystemEntityType.directory:
          copyDir(srcRoot, childSrcPath, dstRoot, childDstPath);
        case FileSystemEntityType.link:
          copySymlink(srcRoot, childSrcPath, dstRoot, childDstPath);
        default:
          break;
      }
    }
  }

  /// Copy a symbolic link.
  void copySymlink(
    Fspath srcRoot,
    SyncPath srcPath,
    Fspath dstRoot,
    SyncPath dstPath,
  ) {
    final target = _os.readLink(srcRoot, srcPath);
    final dstFull = dstRoot.concat(dstPath).toLocal();

    // Ensure parent exists
    final parent = Link(dstFull).parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    // Remove existing if present
    if (Link(dstFull).existsSync()) {
      Link(dstFull).deleteSync();
    }

    Link(dstFull).createSync(target);
  }

  /// Delete a file, directory, or symlink.
  void delete(Fspath root, SyncPath path) {
    _os.delete(root, path, recursive: true);
    Trace.debug(TraceCategory.transport, 'Deleted $path');
  }

  /// Set file properties (modification time, permissions).
  void setProps(Fspath root, SyncPath path, Props props) {
    final fullPath = root.concat(path).toLocal();
    _setProps(fullPath, props);
  }

  /// Move/rename a file within the same root.
  ///
  /// Falls back to copy+delete if rename fails (e.g. cross-device).
  void move(
    Fspath root,
    SyncPath fromPath,
    SyncPath toPath,
  ) {
    try {
      _os.rename(root, fromPath, toPath);
      Trace.debug(
        TraceCategory.transport,
        'Moved $fromPath → $toPath',
      );
    } on FileSystemException {
      // Cross-device: copy then delete
      final type = _os.typeOf(root, fromPath);
      if (type == FileSystemEntityType.directory) {
        copyDir(root, fromPath, root, toPath);
      } else {
        copyFile(root, fromPath, root, toPath);
      }
      delete(root, fromPath);
      Trace.debug(
        TraceCategory.transport,
        'Moved (copy+delete) $fromPath → $toPath',
      );
    }
  }

  void _copyContent(
    String srcPath,
    String dstPath, {
    ProgressCallback? onProgress,
  }) {
    final src = File(srcPath);
    final totalSize = src.lengthSync();

    final srcRaf = src.openSync(mode: FileMode.read);
    final dstRaf = File(dstPath).openSync(mode: FileMode.write);
    try {
      final buffer = Uint8List(65536); // 64KB chunks
      var transferred = 0;
      while (true) {
        final bytesRead = srcRaf.readIntoSync(buffer);
        if (bytesRead <= 0) break;
        if (bytesRead == buffer.length) {
          dstRaf.writeFromSync(buffer);
        } else {
          dstRaf.writeFromSync(buffer, 0, bytesRead);
        }
        transferred += bytesRead;
        onProgress?.call(transferred, totalSize);
      }
    } finally {
      srcRaf.closeSync();
      dstRaf.closeSync();
    }
  }

  void _setProps(String path, Props props) {
    // Set modification time
    _os.setModTime(path, props.modTime);

    // Set permissions (Unix only)
    if (!Platform.isWindows) {
      _os.setPermissions(path, props.permissions);
    }
  }
}
