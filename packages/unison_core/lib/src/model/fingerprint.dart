/// Content fingerprint (MD5 hash) for change detection.
///
/// Mirrors OCaml Unison's `fingerprint.ml`.
library;

import 'dart:typed_data';

import 'package:collection/collection.dart';

/// MD5 fingerprint of file contents.
///
/// 16 bytes (128 bits). Used to detect content changes between syncs.
class Fingerprint {
  /// Raw MD5 digest bytes (16 bytes).
  final Uint8List bytes;

  const Fingerprint(this.bytes);

  /// A dummy fingerprint (all zeros) used as placeholder.
  static final dummy = Fingerprint(Uint8List(16));

  /// Create a pseudo-fingerprint from path and file size.
  ///
  /// Used when fast-check skips actual content hashing for new files
  /// (unsafe but faster). Format: "LEN" prefix + encoded size + path hash.
  static Fingerprint pseudo(String path, int size) {
    final data = Uint8List(16);
    // Mark as pseudo with "LEN" prefix
    data[0] = 0x4C; // 'L'
    data[1] = 0x45; // 'E'
    data[2] = 0x4E; // 'N'
    // Encode size in bytes 3-10
    var s = size;
    for (var i = 3; i < 11; i++) {
      data[i] = s & 0xFF;
      s >>= 8;
    }
    // Simple hash of path in remaining bytes
    var hash = 0;
    for (var i = 0; i < path.length; i++) {
      hash = (hash * 31 + path.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    data[11] = (hash >> 24) & 0xFF;
    data[12] = (hash >> 16) & 0xFF;
    data[13] = (hash >> 8) & 0xFF;
    data[14] = hash & 0xFF;
    data[15] = 0;
    return Fingerprint(data);
  }

  /// Whether this is a pseudo-fingerprint (not a real content hash).
  bool get isPseudo =>
      bytes.length >= 3 &&
      bytes[0] == 0x4C &&
      bytes[1] == 0x45 &&
      bytes[2] == 0x4E;

  /// Hex string representation.
  String toHex() {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Integer hash from first 3 bytes (for hash table lookups).
  int get shortHash {
    if (bytes.length < 3) return 0;
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16);
  }

  @override
  bool operator ==(Object other) =>
      other is Fingerprint &&
      const ListEquality<int>().equals(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'FP(${toHex()})';
}

/// Full fingerprint including optional resource fork (macOS).
class FullFingerprint {
  /// Content (data fork) fingerprint.
  final Fingerprint dataFork;

  /// Resource fork fingerprint (macOS only, null on other platforms).
  final Fingerprint? resourceFork;

  const FullFingerprint(this.dataFork, [this.resourceFork]);

  @override
  bool operator ==(Object other) =>
      other is FullFingerprint &&
      dataFork == other.dataFork &&
      resourceFork == other.resourceFork;

  @override
  int get hashCode => Object.hash(dataFork, resourceFork);

  @override
  String toString() {
    if (resourceFork != null) {
      return 'FullFP($dataFork, ress=$resourceFork)';
    }
    return 'FullFP($dataFork)';
  }
}
