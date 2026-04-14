/// Sync history — records every sync operation for Time Machine browsing.
///
/// Persists a log of all sync operations with changed paths, fingerprints,
/// and timestamps. Enables browsing past versions and restoring files.
library;

import 'dart:convert';
import 'dart:io';

import '../model/sync_path.dart';
import '../util/trace.dart';

/// A single changed file in a sync operation.
class HistoryEntry {
  /// Relative sync path.
  final String path;

  /// What happened: created, modified, deleted, propsChanged.
  final String action;

  /// Direction: r1to2, r2to1, conflict, skipped.
  final String direction;

  /// File size in bytes (0 for deletions).
  final int size;

  const HistoryEntry({
    required this.path,
    required this.action,
    required this.direction,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'action': action,
    'direction': direction,
    'size': size,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    path: json['path'] as String,
    action: json['action'] as String,
    direction: json['direction'] as String,
    size: json['size'] as int,
  );
}

/// A recorded sync operation.
class SyncRecord {
  /// Unique ID (timestamp-based).
  final String id;

  /// When the sync started.
  final DateTime timestamp;

  /// Root 1 path.
  final String root1;

  /// Root 2 path.
  final String root2;

  /// Profile name (if any).
  final String? profileName;

  /// All changed files in this sync.
  final List<HistoryEntry> entries;

  /// Total propagated.
  final int propagated;

  /// Total skipped.
  final int skipped;

  /// Total failed.
  final int failed;

  /// Duration in milliseconds.
  final int durationMs;

  const SyncRecord({
    required this.id,
    required this.timestamp,
    required this.root1,
    required this.root2,
    this.profileName,
    required this.entries,
    required this.propagated,
    required this.skipped,
    required this.failed,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'root1': root1,
    'root2': root2,
    if (profileName != null) 'profile': profileName,
    'entries': entries.map((e) => e.toJson()).toList(),
    'propagated': propagated,
    'skipped': skipped,
    'failed': failed,
    'durationMs': durationMs,
  };

  factory SyncRecord.fromJson(Map<String, dynamic> json) => SyncRecord(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    root1: json['root1'] as String,
    root2: json['root2'] as String,
    profileName: json['profile'] as String?,
    entries: (json['entries'] as List)
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    propagated: json['propagated'] as int,
    skipped: json['skipped'] as int,
    failed: json['failed'] as int,
    durationMs: json['durationMs'] as int,
  );
}

/// Manages sync history persistence.
class SyncHistory {
  final String _historyDir;

  SyncHistory(String profileDir)
      : _historyDir = '$profileDir/history';

  /// Record a sync operation.
  void record(SyncRecord record) {
    Directory(_historyDir).createSync(recursive: true);
    final file = File('$_historyDir/${record.id}.json');
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
    );
    Trace.debug(TraceCategory.general,
        'Recorded sync ${record.id}: ${record.propagated} propagated');

    // Prune old records (keep last 100)
    _prune(100);
  }

  /// Load all sync records, newest first.
  List<SyncRecord> loadAll() {
    final dir = Directory(_historyDir);
    if (!dir.existsSync()) return [];

    final records = <SyncRecord>[];
    for (final file in dir.listSync()) {
      if (file is File && file.path.endsWith('.json')) {
        try {
          final json = jsonDecode(file.readAsStringSync());
          records.add(SyncRecord.fromJson(json as Map<String, dynamic>));
        } catch (e) {
          Trace.debug(TraceCategory.general,
              'Failed to load history: ${file.path}: $e');
        }
      }
    }

    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return records;
  }

  /// Load the N most recent records.
  List<SyncRecord> loadRecent(int count) {
    final all = loadAll();
    return all.take(count).toList();
  }

  /// Get all versions of a specific file across all syncs.
  List<(SyncRecord, HistoryEntry)> fileHistory(String relativePath) {
    final all = loadAll();
    final result = <(SyncRecord, HistoryEntry)>[];
    for (final record in all) {
      for (final entry in record.entries) {
        if (entry.path == relativePath) {
          result.add((record, entry));
        }
      }
    }
    return result;
  }

  /// Get all unique file paths that have ever been synced.
  Set<String> allPaths() {
    final paths = <String>{};
    for (final record in loadAll()) {
      for (final entry in record.entries) {
        paths.add(entry.path);
      }
    }
    return paths;
  }

  void _prune(int maxRecords) {
    final dir = Directory(_historyDir);
    if (!dir.existsSync()) return;

    final files = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    if (files.length > maxRecords) {
      for (final file in files.skip(maxRecords)) {
        file.deleteSync();
      }
    }
  }

  /// Delete all history.
  void clear() {
    final dir = Directory(_historyDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
