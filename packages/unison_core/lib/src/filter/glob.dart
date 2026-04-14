/// Glob pattern to regex conversion.
///
/// Mirrors OCaml Unison's glob syntax:
/// - `*` matches any chars except `/` (and not leading `.`)
/// - `?` matches any single char except `/` (and not leading `.`)
/// - `[abc]` / `[a-z]` character classes
/// - `{a,bb,ccc}` alternation
/// - `\` escapes the next character
library;

/// Convert a Unison glob pattern to a [RegExp] pattern string.
///
/// The result can be used with `RegExp(result)` for matching.
String globToRegex(String glob) {
  final buf = StringBuffer();
  var i = 0;

  while (i < glob.length) {
    final c = glob[i];
    switch (c) {
      case '*':
        // Match any chars except /
        buf.write('[^/]*');
        i++;

      case '?':
        // Match single char except /
        buf.write('[^/]');
        i++;

      case '[':
        // Character class — pass through mostly as-is
        buf.write('[');
        i++;
        // Handle negation
        if (i < glob.length && glob[i] == '!') {
          buf.write('^');
          i++;
        }
        while (i < glob.length && glob[i] != ']') {
          if (glob[i] == '\\' && i + 1 < glob.length) {
            buf.write(RegExp.escape(glob[i + 1]));
            i += 2;
          } else {
            // Pass through range chars like a-z
            buf.write(
                _isRegexMetaInClass(glob[i]) ? '\\${glob[i]}' : glob[i]);
            i++;
          }
        }
        if (i < glob.length) {
          buf.write(']');
          i++; // skip ]
        }

      case '{':
        // Alternation: {a,b,c} → (?:a|b|c)
        // Extract the full {...} content first, then convert each alternative
        i++;
        final altStart = i;
        var depth = 1;
        while (i < glob.length && depth > 0) {
          if (glob[i] == '{') depth++;
          if (glob[i] == '}') depth--;
          if (depth > 0) i++;
        }
        final altContent = glob.substring(altStart, i);
        if (i < glob.length) i++; // skip }

        // Split on top-level commas
        final alternatives = _splitAlternation(altContent);
        buf.write('(?:');
        for (var ai = 0; ai < alternatives.length; ai++) {
          if (ai > 0) buf.write('|');
          buf.write(globToRegex(alternatives[ai]));
        }
        buf.write(')');

      case '\\':
        // Escape next char
        if (i + 1 < glob.length) {
          buf.write(RegExp.escape(glob[i + 1]));
          i += 2;
        } else {
          buf.write('\\\\');
          i++;
        }

      default:
        // Literal character — escape if regex-special
        buf.write(RegExp.escape(c));
        i++;
    }
  }

  return buf.toString();
}

/// Split alternation content on top-level commas (respecting nested {}).
List<String> _splitAlternation(String content) {
  final parts = <String>[];
  var start = 0;
  var depth = 0;
  for (var i = 0; i < content.length; i++) {
    if (content[i] == '{') depth++;
    if (content[i] == '}') depth--;
    if (content[i] == ',' && depth == 0) {
      parts.add(content.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(content.substring(start));
  return parts;
}

bool _isRegexMetaInClass(String c) {
  // Inside [], these need escaping
  return c == '\\' || c == ']' || c == '^';
}

String _escapeIfMeta(String c) {
  const metas = r'\.^$|+()[]{}*?';
  if (metas.contains(c)) return '\\$c';
  return c;
}
