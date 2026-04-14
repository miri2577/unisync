/// Relative path used inside the sync engine.
///
/// Mirrors OCaml Unison's `path.ml`. Internally uses forward slashes as
/// separator regardless of platform. Always relative — no leading slash,
/// no `.` or `..` components.
library;

import 'name.dart';

/// A relative sync path composed of [Name] segments.
///
/// Empty path represents the sync root itself.
class SyncPath implements Comparable<SyncPath> {
  /// The ordered segments of this path.
  final List<Name> segments;

  const SyncPath(this.segments);

  /// The empty (root) path.
  static const empty = SyncPath([]);

  /// Parse a forward-slash-separated string into a [SyncPath].
  ///
  /// Rejects absolute paths, `.`, and `..` components.
  factory SyncPath.fromString(String s) {
    if (s.isEmpty) return empty;

    // Normalize backslashes to forward slashes
    s = s.replaceAll('\\', '/');

    // Reject absolute paths
    if (s.startsWith('/') || (s.length >= 2 && s[1] == ':')) {
      throw ArgumentError("Path must be relative, got: '$s'");
    }

    // Remove trailing slashes
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return empty;

    final parts = s.split('/');
    for (final part in parts) {
      if (part == '.' || part == '..') {
        throw ArgumentError("Path must not contain '.' or '..': '$s'");
      }
      if (part.isEmpty) {
        throw ArgumentError("Path must not contain empty components: '$s'");
      }
    }

    return SyncPath(parts.map((p) => Name(p)).toList(growable: false));
  }

  /// Whether this is the empty root path.
  bool get isEmpty => segments.isEmpty;

  /// Number of segments.
  int get length => segments.length;

  /// Create a child path by appending a [Name].
  SyncPath child(Name name) =>
      SyncPath([...segments, name]);

  /// Get the parent path, or `null` if this is the root.
  SyncPath? get parent {
    if (segments.isEmpty) return null;
    return SyncPath(segments.sublist(0, segments.length - 1));
  }

  /// The final name component, or `null` for the root path.
  Name? get finalName => segments.isEmpty ? null : segments.last;

  /// Split into (first component, remaining path).
  /// Returns `null` for the empty path.
  (Name, SyncPath)? deconstruct() {
    if (segments.isEmpty) return null;
    return (segments.first, SyncPath(segments.sublist(1)));
  }

  /// Split into (all but last, last component).
  /// Returns `null` for the empty path.
  (SyncPath, Name)? deconstructRight() {
    if (segments.isEmpty) return null;
    return (
      SyncPath(segments.sublist(0, segments.length - 1)),
      segments.last,
    );
  }

  /// Append a suffix to the final name component.
  SyncPath addSuffixToFinalName(String suffix) {
    if (segments.isEmpty) {
      throw StateError('Cannot add suffix to empty path');
    }
    final last = segments.last;
    return SyncPath([
      ...segments.sublist(0, segments.length - 1),
      Name('${last.raw}$suffix'),
    ]);
  }

  /// Concatenate another path onto this one.
  SyncPath concat(SyncPath other) {
    if (other.isEmpty) return this;
    if (isEmpty) return other;
    return SyncPath([...segments, ...other.segments]);
  }

  @override
  int compareTo(SyncPath other) {
    final len = segments.length < other.segments.length
        ? segments.length
        : other.segments.length;
    for (var i = 0; i < len; i++) {
      final cmp = segments[i].compareTo(other.segments[i]);
      if (cmp != 0) return cmp;
    }
    return segments.length.compareTo(other.segments.length);
  }

  @override
  bool operator ==(Object other) =>
      other is SyncPath &&
      segments.length == other.segments.length &&
      _segmentsEqual(other);

  bool _segmentsEqual(SyncPath other) {
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != other.segments[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(segments);

  /// Forward-slash-separated string representation.
  @override
  String toString() => segments.map((n) => n.raw).join('/');
}
