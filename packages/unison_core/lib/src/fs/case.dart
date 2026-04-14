/// Case sensitivity detection for filesystems.
///
/// Mirrors OCaml Unison's `case.ml`. Auto-detects whether a filesystem
/// is case-sensitive by creating a temporary probe file.
library;

import 'dart:io';

import '../model/name.dart';

/// Detect the case sensitivity of a filesystem at [path].
///
/// Creates a temp file and checks if a different-cased variant refers
/// to the same file. Returns [CaseMode.insensitive] on Windows/macOS
/// by default (optimistic), [CaseMode.sensitive] on Linux.
CaseMode detectCaseMode(String path) {
  // Quick platform heuristic first
  if (Platform.isWindows) return CaseMode.insensitive;
  if (Platform.isMacOS) return CaseMode.insensitive;

  // On Linux, actually probe the filesystem
  try {
    final dir = Directory(path);
    if (!dir.existsSync()) return CaseMode.sensitive;

    final probe = File('$path/.unison_case_probe_XyZ');
    probe.writeAsStringSync('');
    try {
      final upper = File('$path/.unison_case_probe_XYZ');
      if (upper.existsSync()) {
        return CaseMode.insensitive;
      }
      return CaseMode.sensitive;
    } finally {
      probe.deleteSync();
    }
  } catch (_) {
    return CaseMode.sensitive;
  }
}

/// Initialize the global case mode based on both roots.
///
/// If either root is case-insensitive, use insensitive mode globally
/// (matching Unison's `someHostIsInsensitive` behavior).
void initCaseMode(List<String> rootPaths) {
  for (final path in rootPaths) {
    final mode = detectCaseMode(path);
    if (mode == CaseMode.insensitive) {
      currentCaseMode = CaseMode.insensitive;
      return;
    }
  }
  currentCaseMode = CaseMode.sensitive;
}
