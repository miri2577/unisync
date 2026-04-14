/// Predicate engine for path matching.
///
/// Mirrors OCaml Unison's `pred.ml`. Supports three pattern types:
/// - `Name <glob>` — match against the final path component only
/// - `Path <glob>` — match against the full relative path
/// - `Regex <regex>` — full regex match against the path
library;

import 'glob.dart';

/// A single match pattern with its type.
class Pattern {
  final PatternType type;

  /// The original pattern string (glob or regex).
  final String pattern;

  /// Compiled regex for matching.
  final RegExp _regex;

  Pattern._(this.type, this.pattern, this._regex);

  /// Parse a pattern string like "Name *.tmp" or "Regex .*\.bak$".
  factory Pattern.parse(String spec) {
    final trimmed = spec.trim();

    if (trimmed.startsWith('Name ') || trimmed.startsWith('Name\t')) {
      final glob = trimmed.substring(5).trim();
      final regex = '^${globToRegex(glob)}\$';
      return Pattern._(PatternType.name, glob, RegExp(regex));
    }

    if (trimmed.startsWith('Path ') || trimmed.startsWith('Path\t')) {
      final glob = trimmed.substring(5).trim();
      final regex = '^${globToRegex(glob)}\$';
      return Pattern._(PatternType.path, glob, RegExp(regex));
    }

    if (trimmed.startsWith('Regex ') || trimmed.startsWith('Regex\t')) {
      final regexStr = trimmed.substring(6).trim();
      return Pattern._(PatternType.regex, regexStr, RegExp(regexStr));
    }

    // Default: treat as Name pattern
    final regex = '^${globToRegex(trimmed)}\$';
    return Pattern._(PatternType.name, trimmed, RegExp(regex));
  }

  /// Test if this pattern matches a path.
  ///
  /// [fullPath] is the forward-slash-separated relative path (e.g. "a/b/c.txt").
  bool matches(String fullPath) {
    return switch (type) {
      PatternType.name => _matchName(fullPath),
      PatternType.path => _regex.hasMatch(fullPath),
      PatternType.regex => _regex.hasMatch(fullPath),
    };
  }

  /// For Name patterns, match against the final component only.
  bool _matchName(String fullPath) {
    final lastSlash = fullPath.lastIndexOf('/');
    final name = lastSlash == -1 ? fullPath : fullPath.substring(lastSlash + 1);
    return _regex.hasMatch(name);
  }

  @override
  String toString() => '${type.name} $pattern';
}

/// Type of pattern matching.
enum PatternType { name, path, regex }

/// A predicate composed of multiple patterns (OR logic).
///
/// Returns `true` if ANY pattern matches.
class Pred {
  final List<Pattern> _patterns;

  Pred(this._patterns);

  /// Create from a list of pattern specification strings.
  factory Pred.fromStrings(List<String> specs) {
    return Pred(specs.map(Pattern.parse).toList());
  }

  /// Create an empty predicate (matches nothing).
  factory Pred.empty() => Pred([]);

  /// Test if any pattern matches the given path.
  bool test(String path) {
    for (final p in _patterns) {
      if (p.matches(path)) return true;
    }
    return false;
  }

  /// Add a pattern.
  void add(Pattern pattern) => _patterns.add(pattern);

  /// Add a pattern from string spec.
  void addSpec(String spec) => _patterns.add(Pattern.parse(spec));

  /// Number of patterns.
  int get length => _patterns.length;

  /// Whether this predicate has any patterns.
  bool get isEmpty => _patterns.isEmpty;

  /// All patterns.
  List<Pattern> get patterns => List.unmodifiable(_patterns);
}
