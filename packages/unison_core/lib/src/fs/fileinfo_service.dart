/// Fileinfo service — stat filesystem entries.
///
/// Wraps dart:io FileStat to produce [Fileinfo] records compatible
/// with the sync engine's data model.
library;

import 'dart:io';

import '../model/fileinfo.dart';
import '../model/fspath.dart';
import '../model/props.dart';
import '../model/sync_path.dart';

/// Service for reading filesystem entry information.
class FileinfoService {
  const FileinfoService();

  /// Get [Fileinfo] for a path. Returns [Fileinfo.absent] if not found.
  Fileinfo get(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    return getAbsolute(fullPath);
  }

  /// Get [Fileinfo] from an absolute OS path string.
  Fileinfo getAbsolute(String fullPath) {
    final type = FileSystemEntity.typeSync(fullPath, followLinks: false);

    if (type == FileSystemEntityType.notFound) {
      return Fileinfo.absent;
    }

    final stat = FileStat.statSync(fullPath);

    final fileType = _mapType(type);
    final inode = _getInode(stat);
    final stamp = _makeStamp(inode);

    final desc = Props(
      permissions: _mapPermissions(stat),
      modTime: stat.modified,
      length: fileType == FileType.file ? _getFileSize(fullPath) : 0,
      ctime: stat.changed,
    );

    return Fileinfo(
      typ: fileType,
      inode: inode,
      desc: desc,
      stamp: stamp,
    );
  }

  /// Get just the file type without full stat.
  FileType getType(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    final type = FileSystemEntity.typeSync(fullPath, followLinks: false);
    return _mapType(type);
  }

  static FileType _mapType(FileSystemEntityType type) {
    return switch (type) {
      FileSystemEntityType.file => FileType.file,
      FileSystemEntityType.directory => FileType.directory,
      FileSystemEntityType.link => FileType.symlink,
      FileSystemEntityType.notFound => FileType.absent,
      _ => FileType.absent,
    };
  }

  static int _mapPermissions(FileStat stat) {
    // FileStat.mode returns Unix permission bits on Unix,
    // and a simplified mode on Windows
    return stat.mode & 0x1FF; // mask to lower 9 bits (rwxrwxrwx)
  }

  static int _getInode(FileStat stat) {
    // dart:io FileStat doesn't expose inode directly.
    // On Windows, inodes are not reliable anyway.
    // We use 0 and rely on NoStamp / mtime+size fast-check.
    return 0;
  }

  static Stamp _makeStamp(int inode) {
    if (inode > 0) {
      return InodeStamp(inode);
    }
    return const NoStamp();
  }

  static int _getFileSize(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }
}
