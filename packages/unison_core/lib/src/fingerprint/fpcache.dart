/// Fingerprint cache for fast change detection.
///
/// Mirrors OCaml Unison's `fpcache.ml`. Maintains an in-memory cache of
/// file fingerprints indexed by path. Uses "fast check" to determine
/// whether a file has changed without recomputing the full MD5 hash.
library;

import 'dart:io';
import 'dart:typed_data';

import '../model/fingerprint.dart';
import '../model/props.dart';
import '../util/marshal.dart';
import '../util/trace.dart';

/// A cached fingerprint entry.
class FpCacheEntry {
  /// File properties at the time of fingerprinting.
  final Props props;

  /// The computed fingerprint.
  final Fingerprint fingerprint;

  /// Modification time when fingerprinted (for fast-check).
  final DateTime modTime;

  /// File size when fingerprinted.
  final int length;

  const FpCacheEntry({
    required this.props,
    required this.fingerprint,
    required this.modTime,
    required this.length,
  });
}

/// In-memory + disk fingerprint cache.
///
/// The "fast check" optimization: if a file's mtime and size haven't changed
/// since the last fingerprint computation, we can reuse the cached fingerprint
/// instead of re-reading the entire file.
class FpCache {
  /// In-memory cache: canonical path -> entry.
  final Map<String, FpCacheEntry> _cache = {};

  /// Entries pending disk flush.
  final List<(String, FpCacheEntry)> _pendingWrites = [];

  /// Maximum pending entries before auto-flush.
  static const _flushThreshold = 5000;

  /// Maximum pending bytes before auto-flush (~100MB).
  static const _flushBytesThreshold = 100 * 1024 * 1024;

  int _pendingBytes = 0;

  /// Check if a file appears unchanged based on metadata.
  ///
  /// Returns `true` if the file's modification time and size match the
  /// cached values, meaning the fingerprint is likely still valid.
  ///
  /// This is the "fast check" optimization from Unison — avoids reading
  /// file contents when metadata indicates no change.
  bool dataClearlyUnchanged(String path, Props currentProps) {
    final entry = _cache[path];
    if (entry == null) return false;

    // Size must match exactly
    if (currentProps.length != entry.length) return false;

    // Modification time must match exactly
    if (currentProps.modTime != entry.modTime) return false;

    return true;
  }

  /// Get the cached fingerprint for a path, or `null` if not cached
  /// or if the file appears to have changed.
  Fingerprint? getCachedFingerprint(String path, Props currentProps) {
    if (!dataClearlyUnchanged(path, currentProps)) return null;
    return _cache[path]?.fingerprint;
  }

  /// Store a freshly computed fingerprint in the cache.
  void put(String path, Props props, Fingerprint fingerprint) {
    final entry = FpCacheEntry(
      props: props,
      fingerprint: fingerprint,
      modTime: props.modTime,
      length: props.length,
    );
    _cache[path] = entry;
    _pendingWrites.add((path, entry));
    _pendingBytes += path.length + 16 + 24; // rough estimate

    if (_pendingWrites.length >= _flushThreshold ||
        _pendingBytes >= _flushBytesThreshold) {
      Trace.debug(
        TraceCategory.fingerprint,
        'FpCache auto-flush: ${_pendingWrites.length} entries',
      );
    }
  }

  /// Remove a cache entry.
  void invalidate(String path) {
    _cache.remove(path);
  }

  /// Clear the entire cache.
  void clear() {
    _cache.clear();
    _pendingWrites.clear();
    _pendingBytes = 0;
  }

  /// Number of cached entries.
  int get size => _cache.length;

  /// Save the cache to disk.
  void saveToDisk(String filePath) {
    final enc = MarshalEncoder();

    // Header
    enc.writeInt(1); // format version
    enc.writeInt(_cache.length);

    for (final MapEntry(key: path, value: entry) in _cache.entries) {
      enc.writeString(path);
      enc.writeByteArray(entry.fingerprint.bytes);
      enc.writeInt64(entry.modTime.millisecondsSinceEpoch);
      enc.writeInt64(entry.length);
      enc.writeInt(entry.props.permissions);
    }

    File(filePath).writeAsBytesSync(enc.toBytes());
    _pendingWrites.clear();
    _pendingBytes = 0;

    Trace.debug(
      TraceCategory.fingerprint,
      'FpCache saved ${_cache.length} entries to $filePath',
    );
  }

  /// Load the cache from disk.
  void loadFromDisk(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return;

    try {
      final data = file.readAsBytesSync();
      final dec = MarshalDecoder(Uint8List.fromList(data));

      final version = dec.readInt();
      if (version != 1) {
        Trace.warning(
          TraceCategory.fingerprint,
          'FpCache version mismatch ($version != 1), discarding',
        );
        return;
      }

      final count = dec.readInt();
      for (var i = 0; i < count; i++) {
        final path = dec.readString();
        final fpBytes = dec.readByteArray();
        final modTimeMs = dec.readInt64();
        final length = dec.readInt64();
        final permissions = dec.readInt();

        _cache[path] = FpCacheEntry(
          props: Props(
            permissions: permissions,
            modTime: DateTime.fromMillisecondsSinceEpoch(modTimeMs),
            length: length,
          ),
          fingerprint: Fingerprint(fpBytes),
          modTime: DateTime.fromMillisecondsSinceEpoch(modTimeMs),
          length: length,
        );
      }

      Trace.debug(
        TraceCategory.fingerprint,
        'FpCache loaded ${_cache.length} entries from $filePath',
      );
    } catch (e) {
      Trace.warning(
        TraceCategory.fingerprint,
        'Failed to load FpCache from $filePath: $e',
      );
      _cache.clear();
    }
  }
}
