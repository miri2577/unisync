/// Batch operations on reconciliation items.
///
/// Provides functions to bulk-set directions on [ReconItem] lists,
/// matching OCaml Unison's TUI batch commands (A, 1, 2, C, P, /, etc.).
library;

import '../model/recon_item.dart';

/// Apply a direction to all items matching a condition.
int batchSetDirection(
  List<ReconItem> items,
  bool Function(ReconItem) predicate,
  Direction direction,
) {
  var count = 0;
  for (final item in items) {
    if (predicate(item)) {
      if (item.replicas case Different(diff: var diff)) {
        diff.direction = direction;
        count++;
      }
    }
  }
  return count;
}

/// Set all non-conflict items to their default direction.
int batchAcceptDefaults(List<ReconItem> items) {
  var count = 0;
  for (final item in items) {
    if (item.replicas case Different(diff: var diff)) {
      if (diff.direction is! Conflict) {
        diff.direction = diff.defaultDirection;
        count++;
      }
    }
  }
  return count;
}

/// Revert all items to their default computed direction.
int batchRevertAll(List<ReconItem> items) {
  var count = 0;
  for (final item in items) {
    if (item.replicas case Different(diff: var diff)) {
      diff.revertToDefault();
      count++;
    }
  }
  return count;
}

/// Skip all items (set to Conflict "skipped").
int batchSkipAll(List<ReconItem> items) {
  return batchSetDirection(
    items,
    (_) => true,
    Conflict('skipped by user'),
  );
}

/// Set all items to Replica1 → Replica2.
int batchForceRight(List<ReconItem> items) {
  return batchSetDirection(
    items,
    (_) => true,
    const Replica1ToReplica2(),
  );
}

/// Set all items to Replica2 → Replica1.
int batchForceLeft(List<ReconItem> items) {
  return batchSetDirection(
    items,
    (_) => true,
    const Replica2ToReplica1(),
  );
}

// ---------------------------------------------------------------------------
// Predicate-based batch operations
// ---------------------------------------------------------------------------

/// Matches items that are conflicts.
bool isConflict(ReconItem item) =>
    item.direction is Conflict;

/// Matches items going left → right.
bool isLeftToRight(ReconItem item) =>
    item.direction is Replica1ToReplica2;

/// Matches items going right → left.
bool isRightToLeft(ReconItem item) =>
    item.direction is Replica2ToReplica1;

/// Matches items that are merges.
bool isMerge(ReconItem item) =>
    item.direction is Merge;

/// Matches items where only properties changed.
bool isPropsOnly(ReconItem item) {
  if (item.replicas case Different(diff: var d)) {
    return d.rc1.status == ReplicaStatus.propsChanged ||
           d.rc2.status == ReplicaStatus.propsChanged;
  }
  return false;
}

/// Matches items where a file was created (new).
bool isCreated(ReconItem item) {
  if (item.replicas case Different(diff: var d)) {
    return d.rc1.status == ReplicaStatus.created ||
           d.rc2.status == ReplicaStatus.created;
  }
  return false;
}

/// Matches items where a file was deleted.
bool isDeleted(ReconItem item) {
  if (item.replicas case Different(diff: var d)) {
    return d.rc1.status == ReplicaStatus.deleted ||
           d.rc2.status == ReplicaStatus.deleted;
  }
  return false;
}

/// Matches items where content was modified.
bool isModified(ReconItem item) {
  if (item.replicas case Different(diff: var d)) {
    return d.rc1.status == ReplicaStatus.modified ||
           d.rc2.status == ReplicaStatus.modified;
  }
  return false;
}

/// Invert a predicate.
bool Function(ReconItem) invertPredicate(bool Function(ReconItem) pred) {
  return (item) => !pred(item);
}

/// Combine two predicates with AND.
bool Function(ReconItem) andPredicate(
  bool Function(ReconItem) a,
  bool Function(ReconItem) b,
) {
  return (item) => a(item) && b(item);
}

/// Combine two predicates with OR.
bool Function(ReconItem) orPredicate(
  bool Function(ReconItem) a,
  bool Function(ReconItem) b,
) {
  return (item) => a(item) || b(item);
}

// ---------------------------------------------------------------------------
// Convenience: resolve all conflicts in one direction
// ---------------------------------------------------------------------------

/// Resolve all conflicts by preferring replica 1.
int batchResolveConflictsLeft(List<ReconItem> items) {
  return batchSetDirection(items, isConflict, const Replica1ToReplica2());
}

/// Resolve all conflicts by preferring replica 2.
int batchResolveConflictsRight(List<ReconItem> items) {
  return batchSetDirection(items, isConflict, const Replica2ToReplica1());
}

/// Skip all conflicts.
int batchSkipConflicts(List<ReconItem> items) {
  return batchSetDirection(items, isConflict, Conflict('skipped by user'));
}

/// Skip all deletions.
int batchSkipDeletions(List<ReconItem> items) {
  return batchSetDirection(items, isDeleted, Conflict('deletion skipped'));
}
