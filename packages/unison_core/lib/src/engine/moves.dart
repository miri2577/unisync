/// Move/rename detection for reconciliation items.
///
/// Scans for pairs of deleted+created items with identical fingerprints
/// on the same replica, converting them to move operations. This avoids
/// re-transferring file content when a file was simply renamed/moved.
library;

import '../model/fingerprint.dart';
import '../model/recon_item.dart';
import '../model/sync_path.dart';
import '../model/update_item.dart';
import '../util/trace.dart';

/// Detected move: a file was moved from [oldPath] to [newPath].
class DetectedMove {
  final SyncPath oldPath;
  final SyncPath newPath;
  final FullFingerprint fingerprint;

  /// Which replica the move happened on (1 or 2).
  final int replica;

  const DetectedMove({
    required this.oldPath,
    required this.newPath,
    required this.fingerprint,
    required this.replica,
  });

  @override
  String toString() => 'Move(r$replica: $oldPath → $newPath)';
}

/// Scan reconciliation items for move/rename patterns.
///
/// A move is detected when:
/// 1. A file was deleted at path A on one replica
/// 2. A file was created at path B on the same replica
/// 3. Both have identical fingerprints (same content)
///
/// Returns the list of detected moves and updates the ReconItems'
/// MoveStatus fields.
List<DetectedMove> detectMoves(List<ReconItem> items) {
  // Collect deleted and created items per replica
  final deleted1 = <SyncPath, _FpEntry>{}; // replica1 deletions
  final deleted2 = <SyncPath, _FpEntry>{};
  final created1 = <SyncPath, _FpEntry>{}; // replica1 creations
  final created2 = <SyncPath, _FpEntry>{};

  for (final item in items) {
    if (item.replicas case Different(diff: var diff)) {
      // Replica 1
      final fp1 = _extractFingerprint(diff.rc1);
      if (fp1 != null) {
        if (diff.rc1.status == ReplicaStatus.deleted) {
          deleted1[item.path1] = _FpEntry(fp1, item);
        } else if (diff.rc1.status == ReplicaStatus.created) {
          created1[item.path1] = _FpEntry(fp1, item);
        }
      }

      // Replica 2
      final fp2 = _extractFingerprint(diff.rc2);
      if (fp2 != null) {
        if (diff.rc2.status == ReplicaStatus.deleted) {
          deleted2[item.path2] = _FpEntry(fp2, item);
        } else if (diff.rc2.status == ReplicaStatus.created) {
          created2[item.path2] = _FpEntry(fp2, item);
        }
      }
    }
  }

  final moves = <DetectedMove>[];

  // Match replica 1: deleted + created with same fingerprint
  _matchMoves(deleted1, created1, 1, moves);
  _matchMoves(deleted2, created2, 2, moves);

  if (moves.isNotEmpty) {
    Trace.info(
      TraceCategory.recon,
      'Detected ${moves.length} move(s)',
    );
  }

  return moves;
}

void _matchMoves(
  Map<SyncPath, _FpEntry> deleted,
  Map<SyncPath, _FpEntry> created,
  int replica,
  List<DetectedMove> moves,
) {
  // Build fingerprint → created path index
  final fpIndex = <String, List<(SyncPath, _FpEntry)>>{};
  for (final entry in created.entries) {
    final key = entry.value.fingerprint.dataFork.toHex();
    fpIndex.putIfAbsent(key, () => []).add((entry.key, entry.value));
  }

  final matchedDeleted = <SyncPath>{};
  final matchedCreated = <SyncPath>{};

  for (final delEntry in deleted.entries) {
    final key = delEntry.value.fingerprint.dataFork.toHex();
    final candidates = fpIndex[key];
    if (candidates == null) continue;

    // Find first unmatched candidate
    for (final (createdPath, createdEntry) in candidates) {
      if (matchedCreated.contains(createdPath)) continue;

      // Match found
      matchedDeleted.add(delEntry.key);
      matchedCreated.add(createdPath);

      moves.add(DetectedMove(
        oldPath: delEntry.key,
        newPath: createdPath,
        fingerprint: delEntry.value.fingerprint,
        replica: replica,
      ));

      // Update MoveStatus on the ReconItems
      if (delEntry.value.item.replicas case Different(diff: var delDiff)) {
        final movedOut = MovedOut(createdPath);
        final rc = replica == 1 ? delDiff.rc1 : delDiff.rc2;
        // Replace with a new ReplicaContent that has moveStatus
        final newRc = ReplicaContent(
          content: rc.content,
          status: rc.status,
          desc: rc.desc,
          size: rc.size,
          moveStatus: movedOut,
        );
        if (replica == 1) {
          delDiff = Difference(
            rc1: newRc, rc2: delDiff.rc2,
            direction: delDiff.direction,
            defaultDirection: delDiff.defaultDirection,
          );
        }
      }

      break; // One match per deleted file
    }
  }
}

FullFingerprint? _extractFingerprint(ReplicaContent rc) {
  if (rc.content case FileContent(contentsChange: var cc)) {
    return switch (cc) {
      ContentsUpdated(fingerprint: var fp) => fp,
      _ => null,
    };
  }
  return null;
}

class _FpEntry {
  final FullFingerprint fingerprint;
  final ReconItem item;
  _FpEntry(this.fingerprint, this.item);
}
