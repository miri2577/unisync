/// Case-aware file name representation.
///
/// Mirrors OCaml Unison's `name.ml` — wraps a raw filename string and
/// delegates comparison to the current [CaseMode].
library;

/// How filenames are compared across replicas.
enum CaseMode {
  /// Byte-for-byte comparison (Linux default).
  sensitive,

  /// Latin-1 case folding (Windows/macOS default).
  insensitive,

  /// Unicode-aware, decomposition-respecting, case-sensitive.
  unicodeSensitive,

  /// Unicode NFC-normalized + case-folded.
  unicodeInsensitive,
}

/// Global case mode — set once during initialization based on the roots.
CaseMode currentCaseMode = CaseMode.sensitive;

/// A single filename component (no path separators).
///
/// Comparison and hashing respect [currentCaseMode].
class Name implements Comparable<Name> {
  final String raw;

  const Name(this.raw);

  /// Normalize according to current case mode for comparison.
  String get _normalized => _normalize(raw);

  static String _normalize(String s) {
    return switch (currentCaseMode) {
      CaseMode.sensitive => s,
      CaseMode.insensitive => s.toLowerCase(),
      CaseMode.unicodeSensitive => s, // TODO: NFD decomposition
      CaseMode.unicodeInsensitive => s.toLowerCase(), // TODO: NFC + case fold
    };
  }

  @override
  int compareTo(Name other) => _normalized.compareTo(other._normalized);

  @override
  bool operator ==(Object other) =>
      other is Name && _normalized == other._normalized;

  @override
  int get hashCode => _normalized.hashCode;

  @override
  String toString() => raw;
}
