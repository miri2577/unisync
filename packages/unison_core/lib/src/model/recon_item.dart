/// Reconciliation output types.
///
/// Mirrors OCaml Unison's `common.ml` reconItem/direction types.
/// Produced by the reconciliation phase (comparing two replicas' update trees).
library;

import 'props.dart';
import 'sync_path.dart';
import 'update_item.dart';

// ---------------------------------------------------------------------------
// Sync direction
// ---------------------------------------------------------------------------

/// The action to take for a reconciliation item.
sealed class Direction {
  const Direction();
}

/// Both replicas changed differently — user must decide.
class Conflict extends Direction {
  final String reason;
  const Conflict(this.reason);

  @override
  String toString() => 'Conflict($reason)';
}

/// Both sides changed, eligible for 3-way merge.
class Merge extends Direction {
  const Merge();

  @override
  String toString() => 'Merge';
}

/// Propagate from replica 1 to replica 2.
class Replica1ToReplica2 extends Direction {
  const Replica1ToReplica2();

  @override
  String toString() => '→';
}

/// Propagate from replica 2 to replica 1.
class Replica2ToReplica1 extends Direction {
  const Replica2ToReplica1();

  @override
  String toString() => '←';
}

// ---------------------------------------------------------------------------
// Replica content status
// ---------------------------------------------------------------------------

/// Status of a replica entry relative to the archive.
enum ReplicaStatus {
  unchanged,
  created,
  modified,
  propsChanged,
  deleted,
}

/// Move-related status (optimization — detect renames).
sealed class MoveStatus {
  const MoveStatus();
}

/// Not a move.
class NotMoved extends MoveStatus {
  const NotMoved();
}

/// This entry was moved away to [newPath].
class MovedOut extends MoveStatus {
  final SyncPath newPath;
  const MovedOut(this.newPath);
}

/// This entry was moved here from [oldPath].
class MovedIn extends MoveStatus {
  final SyncPath oldPath;
  const MovedIn(this.oldPath);
}

/// Description of one side of a reconciliation item.
class ReplicaContent {
  /// What type of filesystem entry this is.
  final UpdateContent content;

  /// How this entry changed relative to the archive.
  final ReplicaStatus status;

  /// File properties.
  final Props desc;

  /// Size: (number of items, total bytes).
  final (int, int) size;

  /// Move detection result.
  final MoveStatus moveStatus;

  const ReplicaContent({
    required this.content,
    required this.status,
    required this.desc,
    required this.size,
    this.moveStatus = const NotMoved(),
  });
}

// ---------------------------------------------------------------------------
// Difference (a reconciliation item that needs action)
// ---------------------------------------------------------------------------

/// A path where the two replicas differ.
class Difference {
  final ReplicaContent rc1;
  final ReplicaContent rc2;

  /// The computed sync direction (mutable — can be changed by user or prefs).
  Direction direction;

  /// The originally computed direction before any overrides.
  final Direction defaultDirection;

  /// Deep filesystem errors encountered on replica 1.
  final List<String> errors1;

  /// Deep filesystem errors encountered on replica 2.
  final List<String> errors2;

  Difference({
    required this.rc1,
    required this.rc2,
    required this.direction,
    required this.defaultDirection,
    this.errors1 = const [],
    this.errors2 = const [],
  });

  /// Reset direction to the auto-computed default.
  void revertToDefault() {
    direction = defaultDirection;
  }
}

// ---------------------------------------------------------------------------
// Replicas (problem or difference)
// ---------------------------------------------------------------------------

/// The sync status at one path — either an error or a difference.
sealed class Replicas {
  const Replicas();
}

/// Could not determine sync status (e.g. scan error).
class Problem extends Replicas {
  final String message;
  const Problem(this.message);
}

/// Two replicas differ — includes direction and content for both sides.
class Different extends Replicas {
  final Difference diff;
  const Different(this.diff);
}

// ---------------------------------------------------------------------------
// ReconItem — one entry in the reconciliation result list
// ---------------------------------------------------------------------------

/// A single reconciliation result entry.
///
/// Displayed to the user in the sync UI. Each item represents a path
/// that differs between the two replicas.
class ReconItem {
  /// Path on replica 1.
  final SyncPath path1;

  /// Path on replica 2 (usually identical to path1, may differ in case).
  final SyncPath path2;

  /// The sync status for this path.
  final Replicas replicas;

  const ReconItem({
    required this.path1,
    required this.path2,
    required this.replicas,
  });

  /// Convenience: get the direction, or null if this is a Problem.
  Direction? get direction => switch (replicas) {
    Different(diff: var d) => d.direction,
    Problem() => null,
  };

  /// Convenience: set the direction (no-op for Problems).
  set direction(Direction? dir) {
    if (dir != null) {
      if (replicas case Different(diff: var d)) {
        d.direction = dir;
      }
    }
  }
}
