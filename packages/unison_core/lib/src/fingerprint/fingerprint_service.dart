/// Fingerprint computation service.
///
/// Computes MD5 content fingerprints for files via streaming I/O.
/// Mirrors OCaml Unison's `fingerprint.ml`.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../model/fingerprint.dart';
import '../model/fspath.dart';
import '../model/sync_path.dart';

/// Compute MD5 of a file synchronously, reading in chunks.
Fingerprint _md5File(RandomAccessFile raf, int? maxBytes) {
  final chunks = <int>[];
  final buffer = Uint8List(65536); // 64KB
  var remaining = maxBytes;

  while (true) {
    final toRead =
        (remaining != null && remaining < buffer.length)
            ? remaining
            : buffer.length;
    final bytesRead = raf.readIntoSync(
      toRead == buffer.length ? buffer : Uint8List.sublistView(buffer, 0, toRead),
    );
    if (bytesRead <= 0) break;
    chunks.addAll(Uint8List.sublistView(buffer, 0, bytesRead));
    if (remaining != null) {
      remaining -= bytesRead;
      if (remaining <= 0) break;
    }
  }

  final digest = md5.convert(chunks);
  return Fingerprint(Uint8List.fromList(digest.bytes));
}

/// Service for computing file content fingerprints.
class FingerprintService {
  const FingerprintService();

  /// Compute MD5 fingerprint of an entire file (synchronous).
  Fingerprint file(Fspath fspath, SyncPath path) {
    final fullPath = fspath.concat(path).toLocal();
    return fileAbsolute(fullPath);
  }

  /// Compute MD5 fingerprint from an absolute path string.
  Fingerprint fileAbsolute(String path) {
    final f = File(path);
    if (!f.existsSync()) {
      throw FileSystemException('File not found', path);
    }
    final raf = f.openSync(mode: FileMode.read);
    try {
      return _md5File(raf, null);
    } finally {
      raf.closeSync();
    }
  }

  /// Compute MD5 fingerprint of a file sub-range.
  Fingerprint subfile(String path, int offset, int length) {
    final f = File(path);
    final raf = f.openSync(mode: FileMode.read);
    try {
      raf.setPositionSync(offset);
      return _md5File(raf, length);
    } finally {
      raf.closeSync();
    }
  }

  /// Compute fingerprint asynchronously in a separate isolate.
  Future<Fingerprint> fileAsync(Fspath fspath, SyncPath path) async {
    final fullPath = fspath.concat(path).toLocal();
    return fileAbsoluteAsync(fullPath);
  }

  /// Compute fingerprint asynchronously from absolute path.
  Future<Fingerprint> fileAbsoluteAsync(String path) async {
    final bytes = await Isolate.run(() {
      final f = File(path);
      final data = f.readAsBytesSync();
      return Uint8List.fromList(md5.convert(data).bytes);
    });
    return Fingerprint(bytes);
  }

  /// Compute MD5 using async streaming I/O (no isolate, but non-blocking).
  Future<Fingerprint> fileStream(String path) async {
    final f = File(path);
    final digest = await md5.bind(f.openRead()).first;
    return Fingerprint(Uint8List.fromList(digest.bytes));
  }

  /// Create a [FullFingerprint] (data fork only, no resource fork).
  FullFingerprint fullFile(Fspath fspath, SyncPath path) {
    return FullFingerprint(file(fspath, path));
  }

  /// Create a [FullFingerprint] async.
  Future<FullFingerprint> fullFileAsync(Fspath fspath, SyncPath path) async {
    final fp = await fileAsync(fspath, path);
    return FullFingerprint(fp);
  }
}
