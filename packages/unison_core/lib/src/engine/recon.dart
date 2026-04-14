/// Reconciliation — compares two replicas' update trees.
///
/// Mirrors OCaml Unison's `recon.ml`. Takes paired [UpdateItem] trees
/// from two replicas and produces [ReconItem] lists with sync directions.
library;

import '../filter/pred.dart';
import '../model/fileinfo.dart';
import '../model/fingerprint.dart';
import '../model/name.dart';
import '../model/props.dart';
import '../model/recon_item.dart';
import '../model/sync_path.dart';
import '../model/update_item.dart';

/// Sort mode for reconciliation items.
enum SortMode {
  /// Default: conflicts first, then by path.
  byDefault,

  /// Sort by file size (largest first).
  bySize,

  /// Sort new files first.
  newFirst,

  /// Sort by path name.
  byName,
}

/// Configuration for reconciliation behavior.
class ReconConfig {
  /// Force all changes in one direction (overrides conflicts).
  final bool? force;

  /// Prefer one side for conflict resolution.
  final bool? prefer;

  /// Prefer newer file for conflicts.
  final bool preferNewer;

  /// Prevent deletions from being propagated.
  final bool noDeletion;

  /// Prevent updates from being propagated.
  final bool noUpdate;

  /// Prevent creations from being propagated.
  final bool noCreation;

  /// Predicate for paths eligible for merging.
  final bool Function(SyncPath path)? shouldMerge;

  /// Sort mode for result items.
  final SortMode sortMode;

  /// Path-specific force overrides.
  /// Maps pattern (e.g. "Name docs/*") to direction (true = replica1→2).
  final List<(Pred, bool)> forcePartial;

  /// Path-specific prefer overrides.
  /// Maps pattern to preference (true = prefer replica1).
  final List<(Pred, bool)> preferPartial;

  const ReconConfig({
    this.force,
    this.prefer,
    this.preferNewer = false,
    this.noDeletion = false,
    this.noUpdate = false,
    this.noCreation = false,
    this.shouldMerge,
    this.sortMode = SortMode.byDefault,
    this.forcePartial = const [],
    this.preferPartial = const [],
  });
}

/// Result of reconciliation.
class ReconResult {
  /// Items that differ between replicas (need action).
  final List<ReconItem> items;

  /// Items that are equal on both sides (no action needed).
  final int equalCount;

  /// Paths with errors.
  final List<(SyncPath, String)> errors;

  const ReconResult({
    required this.items,
    required this.equalCount,
    required this.errors,
  });
}

/// Reconciles two replicas' update trees into sync actions.
class Reconciler {
  const Reconciler();

  /// Reconcile paired update items from both replicas.
  ///
  /// [updates] is a list of (path, updateItem1, updateItem2) triples.
  ReconResult reconcileAll(
    List<(SyncPath, UpdateItem, UpdateItem)> updates,
    ReconConfig config,
  ) {
    final items = <ReconItem>[];
    final errors = <(SyncPath, String)>[];
    var equalCount = 0;

    for (final (path, ui1, ui2) in updates) {
      _reconcile(path, ui1, ui2, items, errors, equalCount, config);
    }

    // Apply preference overrides
    if (config.force != null ||
        config.prefer != null ||
        config.preferNewer ||
        config.noDeletion ||
        config.noUpdate ||
        config.noCreation) {
      _overrideChoices(items, config);
    }

    // Sort items
    items.sort((a, b) => _compareReconItems(a, b, config.sortMode));

    return ReconResult(
      items: items,
      equalCount: equalCount,
      errors: errors,
    );
  }

  /// Reconcile a single paired update from a common root path.
  ///
  /// Handles the case where findUpdates returns a single UpdateItem per root
  /// that may contain nested DirContent children.
  ReconResult reconcileUpdates(
    SyncPath rootPath,
    UpdateItem ui1,
    UpdateItem ui2,
    ReconConfig config,
  ) {
    final items = <ReconItem>[];
    final errors = <(SyncPath, String)>[];
    var equalCount = 0;

    _reconcile(rootPath, ui1, ui2, items, errors, equalCount, config);

    if (config.force != null ||
        config.prefer != null ||
        config.preferNewer ||
        config.noDeletion ||
        config.noUpdate ||
        config.noCreation) {
      _overrideChoices(items, config);
    }

    items.sort((a, b) => _compareReconItems(a, b, config.sortMode));

    return ReconResult(
      items: items,
      equalCount: equalCount,
      errors: errors,
    );
  }

  void _reconcile(
    SyncPath path,
    UpdateItem ui1,
    UpdateItem ui2,
    List<ReconItem> items,
    List<(SyncPath, String)> errors,
    int equalCount,
    ReconConfig config,
  ) {
    switch ((ui1, ui2)) {
      // Both unchanged — nothing to do
      case (NoUpdates(), NoUpdates()):
        return;

      // Error on either side
      case (UpdateError(message: var msg), _):
        errors.add((path, msg));
        items.add(ReconItem(
          path1: path,
          path2: path,
          replicas: Problem(msg),
        ));
      case (_, UpdateError(message: var msg)):
        errors.add((path, msg));
        items.add(ReconItem(
          path1: path,
          path2: path,
          replicas: Problem(msg),
        ));

      // One side changed, other unchanged
      case (Updates() && var u1, NoUpdates()):
        items.add(_buildReconItem(
          path, u1, null, const Replica1ToReplica2(), config,
        ));
      case (NoUpdates(), Updates() && var u2):
        items.add(_buildReconItem(
          path, null, u2, const Replica2ToReplica1(), config,
        ));

      // Both sides changed
      case (Updates() && var u1, Updates() && var u2):
        _reconcileBothChanged(path, u1, u2, items, errors, equalCount, config);
    }
  }

  void _reconcileBothChanged(
    SyncPath path,
    Updates u1,
    Updates u2,
    List<ReconItem> items,
    List<(SyncPath, String)> errors,
    int equalCount,
    ReconConfig config,
  ) {
    // Both are directories — always recurse into children (never skip)
    if (u1.content case DirContent(children: var ch1, desc: var desc1, permChange: var pc1)) {
      if (u2.content case DirContent(children: var ch2, desc: var desc2, permChange: var pc2)) {
        _reconcileDirectories(path, ch1, ch2, desc1, desc2, pc1, pc2,
            u1, u2, items, errors, equalCount, config);
        return;
      }
    }

    // Check if both sides changed to the same thing (non-directory)
    if (_contentEqual(u1.content, u2.content)) {
      equalCount++;
      return;
    }

    // Both are files — check for merge eligibility
    if (u1.content is FileContent &&
        u2.content is FileContent &&
        config.shouldMerge != null &&
        config.shouldMerge!(path)) {
      items.add(_buildReconItem(path, u1, u2, const Merge(), config));
      return;
    }

    // Conflict
    final reason = _conflictReason(u1.content, u2.content);
    items.add(_buildReconItem(path, u1, u2, Conflict(reason), config));
  }

  void _reconcileDirectories(
    SyncPath path,
    List<(Name, UpdateItem)> ch1,
    List<(Name, UpdateItem)> ch2,
    Props desc1,
    Props desc2,
    PermChange pc1,
    PermChange pc2,
    Updates u1,
    Updates u2,
    List<ReconItem> items,
    List<(SyncPath, String)> errors,
    int equalCount,
    ReconConfig config,
  ) {
    // Check directory property changes
    if (pc1 == PermChange.propsUpdated || pc2 == PermChange.propsUpdated) {
      if (pc1 == PermChange.propsUpdated && pc2 == PermChange.propsUpdated) {
        if (!desc1.similar(desc2)) {
          items.add(_buildReconItem(
            path, u1, u2, Conflict('properties changed on both sides'), config,
          ));
        }
      } else if (pc1 == PermChange.propsUpdated) {
        items.add(_buildReconItem(
          path, u1, null, const Replica1ToReplica2(), config,
        ));
      } else {
        items.add(_buildReconItem(
          path, null, u2, const Replica2ToReplica1(), config,
        ));
      }
    }

    // Sorted merge of children from both sides
    final merged = _mergeChildren(ch1, ch2);
    for (final (name, child1, child2) in merged) {
      _reconcile(
        path.child(name),
        child1 ?? const NoUpdates(),
        child2 ?? const NoUpdates(),
        items,
        errors,
        equalCount,
        config,
      );
    }
  }

  /// Check if two update contents are identical.
  bool _contentEqual(UpdateContent uc1, UpdateContent uc2) {
    return switch ((uc1, uc2)) {
      (Absent(), Absent()) => true,
      (FileContent(desc: var d1, contentsChange: var cc1),
       FileContent(desc: var d2, contentsChange: var cc2)) =>
        _contentsChangeEqual(cc1, cc2) && d1.similar(d2),
      (SymlinkContent(target: var t1), SymlinkContent(target: var t2)) =>
        t1 == t2,
      (DirContent(desc: var d1), DirContent(desc: var d2)) =>
        d1.similar(d2),
      _ => false,
    };
  }

  bool _contentsChangeEqual(ContentsChange cc1, ContentsChange cc2) {
    return switch ((cc1, cc2)) {
      (ContentsSame(), ContentsSame()) => true,
      (ContentsUpdated(fingerprint: var f1), ContentsUpdated(fingerprint: var f2)) =>
        f1 == f2,
      _ => false,
    };
  }

  String _conflictReason(UpdateContent uc1, UpdateContent uc2) {
    if (uc1 is Absent && uc2 is! Absent) return 'deleted on one side, modified on other';
    if (uc2 is Absent && uc1 is! Absent) return 'deleted on one side, modified on other';
    if (uc1 is FileContent && uc2 is FileContent) return 'file changed on both sides';
    if (uc1 is SymlinkContent && uc2 is SymlinkContent) return 'symlink changed on both sides';
    if (uc1.runtimeType != uc2.runtimeType) return 'type changed on both sides';
    return 'conflicting updates';
  }

  ReconItem _buildReconItem(
    SyncPath path,
    Updates? u1,
    Updates? u2,
    Direction direction,
    ReconConfig config,
  ) {
    final rc1 = u1 != null
        ? _buildReplicaContent(u1)
        : ReplicaContent(
            content: const Absent(),
            status: ReplicaStatus.unchanged,
            desc: Props.absent,
            size: (0, 0),
          );

    final rc2 = u2 != null
        ? _buildReplicaContent(u2)
        : ReplicaContent(
            content: const Absent(),
            status: ReplicaStatus.unchanged,
            desc: Props.absent,
            size: (0, 0),
          );

    return ReconItem(
      path1: path,
      path2: path,
      replicas: Different(Difference(
        rc1: rc1,
        rc2: rc2,
        direction: direction,
        defaultDirection: direction,
      )),
    );
  }

  ReplicaContent _buildReplicaContent(Updates update) {
    final content = update.content;
    final status = _determineStatus(content, update.prevState);
    final desc = _contentDesc(content);
    final size = _contentSize(content);

    return ReplicaContent(
      content: content,
      status: status,
      desc: desc,
      size: size,
    );
  }

  ReplicaStatus _determineStatus(UpdateContent content, PrevState prev) {
    return switch ((content, prev)) {
      (Absent(), _) => ReplicaStatus.deleted,
      (_, NewEntry()) => ReplicaStatus.created,
      (FileContent(contentsChange: ContentsSame()), _) =>
        ReplicaStatus.propsChanged,
      (FileContent(contentsChange: ContentsUpdated()), _) =>
        ReplicaStatus.modified,
      (DirContent(permChange: PermChange.propsUpdated), _) =>
        ReplicaStatus.propsChanged,
      (DirContent(), _) => ReplicaStatus.modified,
      (SymlinkContent(), _) => ReplicaStatus.modified,
    };
  }

  Props _contentDesc(UpdateContent content) {
    return switch (content) {
      FileContent(desc: var d) => d,
      DirContent(desc: var d) => d,
      _ => Props.absent,
    };
  }

  (int, int) _contentSize(UpdateContent content) {
    return switch (content) {
      FileContent(desc: var d) => (1, d.length),
      DirContent(children: var ch) => (ch.length, 0),
      _ => (0, 0),
    };
  }

  /// Merge two sorted child lists by name.
  List<(Name, UpdateItem?, UpdateItem?)> _mergeChildren(
    List<(Name, UpdateItem)> ch1,
    List<(Name, UpdateItem)> ch2,
  ) {
    final result = <(Name, UpdateItem?, UpdateItem?)>[];
    var i = 0, j = 0;

    while (i < ch1.length && j < ch2.length) {
      final cmp = ch1[i].$1.compareTo(ch2[j].$1);
      if (cmp < 0) {
        result.add((ch1[i].$1, ch1[i].$2, null));
        i++;
      } else if (cmp > 0) {
        result.add((ch2[j].$1, null, ch2[j].$2));
        j++;
      } else {
        result.add((ch1[i].$1, ch1[i].$2, ch2[j].$2));
        i++;
        j++;
      }
    }
    while (i < ch1.length) {
      result.add((ch1[i].$1, ch1[i].$2, null));
      i++;
    }
    while (j < ch2.length) {
      result.add((ch2[j].$1, null, ch2[j].$2));
      j++;
    }
    return result;
  }

  /// Apply preference-based overrides to reconciliation results.
  void _overrideChoices(List<ReconItem> items, ReconConfig config) {
    for (final item in items) {
      if (item.replicas case Different(diff: var diff)) {
        // Path-specific overrides first (higher priority)
        _overrideByPath(item.path1, diff, config);
        _overrideDirection(diff, config);
      }
    }
  }

  void _overrideByPath(SyncPath path, Difference diff, ReconConfig config) {
    final pathStr = path.toString();

    // forcepartial: overrides everything for matching paths
    for (final (pred, toReplica1) in config.forcePartial) {
      if (pred.test(pathStr)) {
        diff.direction = toReplica1
            ? const Replica1ToReplica2()
            : const Replica2ToReplica1();
        return;
      }
    }

    // preferpartial: resolves conflicts for matching paths
    if (diff.direction is Conflict) {
      for (final (pred, preferReplica1) in config.preferPartial) {
        if (pred.test(pathStr)) {
          diff.direction = preferReplica1
              ? const Replica1ToReplica2()
              : const Replica2ToReplica1();
          return;
        }
      }
    }
  }

  void _overrideDirection(Difference diff, ReconConfig config) {
    // Force overrides everything
    if (config.force != null) {
      diff.direction = config.force!
          ? const Replica1ToReplica2()
          : const Replica2ToReplica1();
      return;
    }

    // Prefer resolves conflicts
    if (diff.direction is Conflict && config.prefer != null) {
      diff.direction = config.prefer!
          ? const Replica1ToReplica2()
          : const Replica2ToReplica1();
      return;
    }

    // Prefer newer resolves conflicts between files
    if (diff.direction is Conflict &&
        config.preferNewer &&
        diff.rc1.content is FileContent &&
        diff.rc2.content is FileContent) {
      final t1 = diff.rc1.desc.modTime;
      final t2 = diff.rc2.desc.modTime;
      if (t1.isAfter(t2)) {
        diff.direction = const Replica1ToReplica2();
      } else if (t2.isAfter(t1)) {
        diff.direction = const Replica2ToReplica1();
      }
      return;
    }

    // Restriction preferences
    if (config.noDeletion) {
      if (diff.direction is Replica1ToReplica2 &&
          diff.rc1.status == ReplicaStatus.deleted) {
        diff.direction = Conflict('deletion not allowed (replica 1)');
      }
      if (diff.direction is Replica2ToReplica1 &&
          diff.rc2.status == ReplicaStatus.deleted) {
        diff.direction = Conflict('deletion not allowed (replica 2)');
      }
    }

    if (config.noCreation) {
      if (diff.direction is Replica1ToReplica2 &&
          diff.rc1.status == ReplicaStatus.created) {
        diff.direction = Conflict('creation not allowed (replica 1)');
      }
      if (diff.direction is Replica2ToReplica1 &&
          diff.rc2.status == ReplicaStatus.created) {
        diff.direction = Conflict('creation not allowed (replica 2)');
      }
    }

    if (config.noUpdate) {
      if (diff.direction is Replica1ToReplica2 &&
          diff.rc1.status == ReplicaStatus.modified) {
        diff.direction = Conflict('update not allowed (replica 1)');
      }
      if (diff.direction is Replica2ToReplica1 &&
          diff.rc2.status == ReplicaStatus.modified) {
        diff.direction = Conflict('update not allowed (replica 2)');
      }
    }
  }

  int _compareReconItems(ReconItem a, ReconItem b, SortMode mode) {
    // Conflicts/problems always first
    final aConflict = _isConflictOrProblem(a) ? 0 : 1;
    final bConflict = _isConflictOrProblem(b) ? 0 : 1;
    if (aConflict != bConflict) return aConflict.compareTo(bConflict);

    return switch (mode) {
      SortMode.byDefault => a.path1.compareTo(b.path1),
      SortMode.byName => a.path1.compareTo(b.path1),
      SortMode.bySize => _compareBySizeDesc(a, b),
      SortMode.newFirst => _compareNewFirst(a, b),
    };
  }

  bool _isConflictOrProblem(ReconItem item) {
    return item.direction is Conflict || item.replicas is Problem;
  }

  int _compareBySizeDesc(ReconItem a, ReconItem b) {
    final sizeA = _itemSize(a);
    final sizeB = _itemSize(b);
    final cmp = sizeB.compareTo(sizeA); // descending
    return cmp != 0 ? cmp : a.path1.compareTo(b.path1);
  }

  int _compareNewFirst(ReconItem a, ReconItem b) {
    final aNew = _isNewItem(a) ? 0 : 1;
    final bNew = _isNewItem(b) ? 0 : 1;
    if (aNew != bNew) return aNew.compareTo(bNew);
    return a.path1.compareTo(b.path1);
  }

  int _itemSize(ReconItem item) {
    if (item.replicas case Different(diff: var d)) {
      return d.rc1.size.$2 + d.rc2.size.$2;
    }
    return 0;
  }

  bool _isNewItem(ReconItem item) {
    if (item.replicas case Different(diff: var d)) {
      return d.rc1.status == ReplicaStatus.created ||
             d.rc2.status == ReplicaStatus.created;
    }
    return false;
  }
}
