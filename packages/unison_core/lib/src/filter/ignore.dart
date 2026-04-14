/// Ignore/filter system for excluding paths from synchronization.
///
/// Mirrors OCaml Unison's ignore system:
/// - `ignore` patterns exclude matching paths
/// - `ignorenot` patterns override ignore (whitelist exceptions)
/// - Ignored directories exclude all descendants
library;

import '../model/sync_path.dart';
import 'pred.dart';

/// Manages ignore and ignorenot predicates for path filtering.
class IgnoreFilter {
  /// Patterns for paths to ignore.
  final Pred ignore;

  /// Exception patterns that override ignore.
  final Pred ignoreNot;

  /// Built-in patterns always ignored (temp files, etc.).
  final Pred _builtIn;

  IgnoreFilter({
    List<String> ignorePatterns = const [],
    List<String> ignoreNotPatterns = const [],
  })  : ignore = Pred.fromStrings(ignorePatterns),
        ignoreNot = Pred.fromStrings(ignoreNotPatterns),
        _builtIn = Pred.fromStrings(const [
          'Name .unison.*',
          'Name *.unison.tmp',
        ]);

  /// Test whether a path should be ignored.
  ///
  /// Logic: if `ignorenot` matches, do NOT ignore (even if `ignore` matches).
  /// Otherwise, ignore if `ignore` or built-in patterns match.
  bool shouldIgnore(SyncPath path) {
    final pathStr = path.toString();
    if (pathStr.isEmpty) return false; // never ignore root

    // ignorenot takes precedence
    if (ignoreNot.test(pathStr)) return false;

    // Check built-in patterns
    if (_builtIn.test(pathStr)) return true;

    // Check user ignore patterns
    return ignore.test(pathStr);
  }

  /// Test using a raw path string.
  bool shouldIgnoreString(String path) {
    if (path.isEmpty) return false;
    if (ignoreNot.test(path)) return false;
    if (_builtIn.test(path)) return true;
    return ignore.test(path);
  }

  /// Add an ignore pattern.
  void addIgnore(String spec) => ignore.addSpec(spec);

  /// Add an ignorenot pattern.
  void addIgnoreNot(String spec) => ignoreNot.addSpec(spec);

  /// Create from [UnisonPrefs]-style preference lists.
  factory IgnoreFilter.fromPrefs(
    List<String> ignorePatterns,
    List<String> ignoreNotPatterns,
  ) {
    return IgnoreFilter(
      ignorePatterns: ignorePatterns,
      ignoreNotPatterns: ignoreNotPatterns,
    );
  }
}
