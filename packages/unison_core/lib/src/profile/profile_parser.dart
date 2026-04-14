/// Profile (.prf) file parser.
///
/// Mirrors OCaml Unison's profile file format:
/// - `key = value` lines
/// - `#` comment lines
/// - `include filename` directives
/// - `include? filename` (optional, no error if missing)
/// - Blank lines ignored
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'prefs.dart';

/// A parsed preference entry with source location.
class PrefEntry {
  final String name;
  final String value;
  final String file;
  final int line;

  const PrefEntry(this.name, this.value, this.file, this.line);

  @override
  String toString() => '$name = $value ($file:$line)';
}

/// Parse error with location.
class ProfileParseError {
  final String message;
  final String file;
  final int line;

  const ProfileParseError(this.message, this.file, this.line);

  @override
  String toString() => '$file:$line: $message';
}

/// Parses .prf profile files and applies them to a [PrefsRegistry].
class ProfileParser {
  /// Base directory for resolving include paths and finding profiles.
  final String profileDir;

  const ProfileParser(this.profileDir);

  /// Get the default profile directory.
  static String defaultProfileDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.unison';
  }

  /// List all available profile names (without .prf extension).
  List<String> listProfiles() {
    final dir = Directory(profileDir);
    if (!dir.existsSync()) return [];

    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.prf'))
        .map((f) {
          final basename = p.basename(f.path);
          return basename.substring(0, basename.length - 4);
        })
        .toList()
      ..sort();
  }

  /// Parse a profile file and return raw entries.
  ///
  /// Follows `include` directives recursively.
  (List<PrefEntry>, List<ProfileParseError>) parseFile(String name) {
    final filePath = _resolveProfilePath(name);
    return _parseFileImpl(filePath, {});
  }

  /// Parse a profile file and apply to a [PrefsRegistry].
  List<ProfileParseError> loadProfile(String name, PrefsRegistry registry) {
    final (entries, errors) = parseFile(name);
    for (final entry in entries) {
      registry.setFromString(entry.name, entry.value);
    }
    return errors;
  }

  /// Write a profile file from a [PrefsRegistry].
  void saveProfile(String name, PrefsRegistry registry) {
    final filePath = _resolveProfilePath(name);
    Directory(profileDir).createSync(recursive: true);
    File(filePath).writeAsStringSync(registry.serialize());
  }

  /// Parse a profile file at an absolute path.
  (List<PrefEntry>, List<ProfileParseError>) _parseFileImpl(
    String filePath,
    Set<String> visited,
  ) {
    // Prevent circular includes
    final canonical = p.canonicalize(filePath);
    if (visited.contains(canonical)) {
      return ([], [ProfileParseError('Circular include detected', filePath, 0)]);
    }
    visited.add(canonical);

    final file = File(filePath);
    if (!file.existsSync()) {
      return ([], [ProfileParseError('File not found', filePath, 0)]);
    }

    final entries = <PrefEntry>[];
    final errors = <ProfileParseError>[];
    final lines = file.readAsLinesSync();

    for (var lineNum = 0; lineNum < lines.length; lineNum++) {
      var line = lines[lineNum].trim();

      // Skip empty lines and comments
      if (line.isEmpty || line.startsWith('#')) continue;

      // Handle include directives
      if (line.startsWith('include')) {
        _handleInclude(line, filePath, lineNum + 1, entries, errors, visited);
        continue;
      }

      // Parse key = value
      final eqIdx = line.indexOf('=');
      if (eqIdx == -1) {
        errors.add(ProfileParseError(
          "Invalid line (no '='): $line",
          filePath,
          lineNum + 1,
        ));
        continue;
      }

      final key = line.substring(0, eqIdx).trim();
      final value = line.substring(eqIdx + 1).trim();

      if (key.isEmpty) {
        errors.add(ProfileParseError(
          'Empty preference name',
          filePath,
          lineNum + 1,
        ));
        continue;
      }

      entries.add(PrefEntry(key, value, filePath, lineNum + 1));
    }

    return (entries, errors);
  }

  void _handleInclude(
    String line,
    String currentFile,
    int lineNum,
    List<PrefEntry> entries,
    List<ProfileParseError> errors,
    Set<String> visited,
  ) {
    final optional = line.startsWith('include?');
    final directive = optional ? 'include?' : 'include';
    final rest = line.substring(directive.length).trim();

    if (rest.isEmpty) {
      errors.add(ProfileParseError(
        'Missing filename after $directive',
        currentFile,
        lineNum,
      ));
      return;
    }

    // Resolve relative to profile directory
    final includePath = _resolveProfilePath(rest);
    final includeFile = File(includePath);

    if (!includeFile.existsSync()) {
      if (optional) return; // include? silently skips missing files
      errors.add(ProfileParseError(
        'Included file not found: $rest',
        currentFile,
        lineNum,
      ));
      return;
    }

    final (subEntries, subErrors) = _parseFileImpl(includePath, visited);
    entries.addAll(subEntries);
    errors.addAll(subErrors);
  }

  String _resolveProfilePath(String name) {
    // If name already has .prf extension or is an absolute path, use as-is
    if (p.isAbsolute(name)) return name;
    if (name.endsWith('.prf')) return p.join(profileDir, name);
    return p.join(profileDir, '$name.prf');
  }
}

/// Metadata about a profile for UI display.
class ProfileInfo {
  final String name;
  final List<String> roots;
  final String? label;
  final String? key;

  const ProfileInfo({
    required this.name,
    required this.roots,
    this.label,
    this.key,
  });
}

/// Scan a profile file for quick metadata (roots, label, key) without
/// fully loading all preferences.
ProfileInfo? scanProfile(String profileDir, String name) {
  final filePath = '$profileDir/$name.prf';
  final file = File(filePath);
  if (!file.existsSync()) return null;

  final roots = <String>[];
  String? label;
  String? key;

  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final eqIdx = trimmed.indexOf('=');
    if (eqIdx == -1) continue;

    final k = trimmed.substring(0, eqIdx).trim();
    final v = trimmed.substring(eqIdx + 1).trim();

    switch (k) {
      case 'root':
        roots.add(v);
      case 'label':
        label = v;
      case 'key':
        key = v;
    }
  }

  return ProfileInfo(name: name, roots: roots, label: label, key: key);
}
