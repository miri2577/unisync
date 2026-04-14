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

/// A detected case conflict between two names.
class CaseConflict {
  final String name1;
  final String name2;
  final String directory;

  const CaseConflict(this.name1, this.name2, this.directory);

  @override
  String toString() => '"$name1" vs "$name2" in $directory';
}

/// Scan a directory for case conflicts.
///
/// On case-insensitive filesystems (Windows, macOS), two files like
/// `File.txt` and `file.txt` cannot coexist — the OS treats them as
/// the same. This detects such conflicts BEFORE sync to warn the user.
List<CaseConflict> detectCaseConflicts(String dirPath, {bool recursive = true}) {
  final conflicts = <CaseConflict>[];
  _scanDir(dirPath, conflicts, recursive);
  return conflicts;
}

void _scanDir(String dirPath, List<CaseConflict> conflicts, bool recursive) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return;

  try {
    final entries = dir.listSync(followLinks: false);
    final nameMap = <String, String>{}; // lowercase → original

    for (final entry in entries) {
      final basename = entry.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      final lower = basename.toLowerCase();

      if (nameMap.containsKey(lower)) {
        conflicts.add(CaseConflict(nameMap[lower]!, basename, dirPath));
      } else {
        nameMap[lower] = basename;
      }

      if (recursive && entry is Directory) {
        _scanDir(entry.path, conflicts, recursive);
      }
    }
  } catch (_) {}
}
