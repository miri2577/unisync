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
  /// Compares after NFC normalization (composed form).
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
      CaseMode.unicodeSensitive => unicodeNFC(s),
      CaseMode.unicodeInsensitive => unicodeNFC(s).toLowerCase(),
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

/// NFC normalization (canonical composition).
///
/// Converts decomposed Unicode (NFD, common on macOS HFS+) to composed
/// form (NFC). Handles the most common precomposed Latin characters.
/// Example: 'a' + '\u0308' (combining diaeresis) → 'ä'
String unicodeNFC(String s) {
  if (!s.contains('\u0300') &&
      !s.contains('\u0301') &&
      !s.contains('\u0302') &&
      !s.contains('\u0303') &&
      !s.contains('\u0304') &&
      !s.contains('\u0308') &&
      !s.contains('\u030A') &&
      !s.contains('\u030C') &&
      !s.contains('\u0327')) {
    return s; // Fast path: no combining characters
  }

  final buf = StringBuffer();
  final runes = s.runes.toList();

  for (var i = 0; i < runes.length; i++) {
    if (i + 1 < runes.length) {
      final composed = _compose(runes[i], runes[i + 1]);
      if (composed != null) {
        buf.writeCharCode(composed);
        i++; // Skip combining char
        continue;
      }
    }
    buf.writeCharCode(runes[i]);
  }

  return buf.toString();
}

/// NFD decomposition (canonical decomposition).
///
/// Converts composed characters to base + combining mark form.
String unicodeNFD(String s) {
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final decomp = _decompose(rune);
    if (decomp != null) {
      buf.writeCharCode(decomp.$1);
      buf.writeCharCode(decomp.$2);
    } else {
      buf.writeCharCode(rune);
    }
  }
  return buf.toString();
}

/// Try to compose base + combining mark into a single codepoint.
int? _compose(int base, int combining) {
  final key = (base << 16) | combining;
  return _compositionTable[key];
}

/// Try to decompose a precomposed character.
(int, int)? _decompose(int codepoint) {
  return _decompositionTable[codepoint];
}

// Common Latin compositions: base + combining mark → precomposed
final _compositionTable = <int, int>{
  // a + combining marks
  (0x61 << 16) | 0x0300: 0x00E0, // à
  (0x61 << 16) | 0x0301: 0x00E1, // á
  (0x61 << 16) | 0x0302: 0x00E2, // â
  (0x61 << 16) | 0x0303: 0x00E3, // ã
  (0x61 << 16) | 0x0308: 0x00E4, // ä
  (0x61 << 16) | 0x030A: 0x00E5, // å
  // A + combining marks
  (0x41 << 16) | 0x0300: 0x00C0, // À
  (0x41 << 16) | 0x0301: 0x00C1, // Á
  (0x41 << 16) | 0x0302: 0x00C2, // Â
  (0x41 << 16) | 0x0303: 0x00C3, // Ã
  (0x41 << 16) | 0x0308: 0x00C4, // Ä
  (0x41 << 16) | 0x030A: 0x00C5, // Å
  // e + combining marks
  (0x65 << 16) | 0x0300: 0x00E8, // è
  (0x65 << 16) | 0x0301: 0x00E9, // é
  (0x65 << 16) | 0x0302: 0x00EA, // ê
  (0x65 << 16) | 0x0308: 0x00EB, // ë
  (0x45 << 16) | 0x0300: 0x00C8, // È
  (0x45 << 16) | 0x0301: 0x00C9, // É
  (0x45 << 16) | 0x0302: 0x00CA, // Ê
  (0x45 << 16) | 0x0308: 0x00CB, // Ë
  // i + combining marks
  (0x69 << 16) | 0x0300: 0x00EC, // ì
  (0x69 << 16) | 0x0301: 0x00ED, // í
  (0x69 << 16) | 0x0302: 0x00EE, // î
  (0x69 << 16) | 0x0308: 0x00EF, // ï
  (0x49 << 16) | 0x0300: 0x00CC, // Ì
  (0x49 << 16) | 0x0301: 0x00CD, // Í
  (0x49 << 16) | 0x0302: 0x00CE, // Î
  (0x49 << 16) | 0x0308: 0x00CF, // Ï
  // o + combining marks
  (0x6F << 16) | 0x0300: 0x00F2, // ò
  (0x6F << 16) | 0x0301: 0x00F3, // ó
  (0x6F << 16) | 0x0302: 0x00F4, // ô
  (0x6F << 16) | 0x0303: 0x00F5, // õ
  (0x6F << 16) | 0x0308: 0x00F6, // ö
  (0x4F << 16) | 0x0300: 0x00D2, // Ò
  (0x4F << 16) | 0x0301: 0x00D3, // Ó
  (0x4F << 16) | 0x0302: 0x00D4, // Ô
  (0x4F << 16) | 0x0303: 0x00D5, // Õ
  (0x4F << 16) | 0x0308: 0x00D6, // Ö
  // u + combining marks
  (0x75 << 16) | 0x0300: 0x00F9, // ù
  (0x75 << 16) | 0x0301: 0x00FA, // ú
  (0x75 << 16) | 0x0302: 0x00FB, // û
  (0x75 << 16) | 0x0308: 0x00FC, // ü
  (0x55 << 16) | 0x0300: 0x00D9, // Ù
  (0x55 << 16) | 0x0301: 0x00DA, // Ú
  (0x55 << 16) | 0x0302: 0x00DB, // Û
  (0x55 << 16) | 0x0308: 0x00DC, // Ü
  // n, c, y
  (0x6E << 16) | 0x0303: 0x00F1, // ñ
  (0x4E << 16) | 0x0303: 0x00D1, // Ñ
  (0x63 << 16) | 0x0327: 0x00E7, // ç
  (0x43 << 16) | 0x0327: 0x00C7, // Ç
  (0x79 << 16) | 0x0301: 0x00FD, // ý
  (0x79 << 16) | 0x0308: 0x00FF, // ÿ
  (0x59 << 16) | 0x0301: 0x00DD, // Ý
  // s, z with caron
  (0x73 << 16) | 0x030C: 0x0161, // š
  (0x53 << 16) | 0x030C: 0x0160, // Š
  (0x7A << 16) | 0x030C: 0x017E, // ž
  (0x5A << 16) | 0x030C: 0x017D, // Ž
};

// Reverse table: precomposed → (base, combining)
final _decompositionTable = <int, (int, int)>{
  for (final e in _compositionTable.entries)
    e.value: (e.key >> 16, e.key & 0xFFFF),
};
