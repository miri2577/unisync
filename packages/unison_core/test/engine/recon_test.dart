import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

/// Helper to create a file UpdateItem with ContentsUpdated.
Updates _fileUpdate(String fpByte, int size, {bool isNew = false}) {
  final fp = FullFingerprint(
    Fingerprint(Uint8List.fromList(List.filled(16, fpByte.codeUnitAt(0)))),
  );
  final desc = Props(
    permissions: 0x1ED,
    modTime: DateTime(2024, 6, 15),
    length: size,
  );
  return Updates(
    FileContent(desc, ContentsUpdated(fp, const NoStamp(), RessStamp.zero)),
    isNew ? const NewEntry() : PrevFile(
      Props(permissions: 0x1ED, modTime: DateTime(2024, 1, 1), length: size),
      FullFingerprint(Fingerprint(Uint8List.fromList(List.filled(16, 0)))),
      const NoStamp(),
      RessStamp.zero,
    ),
  );
}

/// Helper: file with only props changed.
Updates _propsUpdate(int newPerm) {
  final fp = FullFingerprint(Fingerprint(Uint8List(16)));
  return Updates(
    FileContent(
      Props(permissions: newPerm, modTime: DateTime(2024), length: 100),
      const ContentsSame(),
    ),
    PrevFile(
      Props(permissions: 0x1ED, modTime: DateTime(2024), length: 100),
      fp, const NoStamp(), RessStamp.zero,
    ),
  );
}

/// Helper: deletion update.
Updates _deleteUpdate() {
  return Updates(
    const Absent(),
    PrevFile(
      Props(permissions: 0x1ED, modTime: DateTime(2024), length: 50),
      FullFingerprint(Fingerprint(Uint8List(16))),
      const NoStamp(),
      RessStamp.zero,
    ),
  );
}

void main() {
  const recon = Reconciler();
  const config = ReconConfig();
  final path = SyncPath.fromString('test.txt');

  setUp(() {
    currentCaseMode = CaseMode.sensitive;
  });

  group('Reconciler basics', () {
    test('both NoUpdates produces no items', () {
      final result = recon.reconcileAll(
        [(path, const NoUpdates(), const NoUpdates())],
        config,
      );
      expect(result.items, isEmpty);
    });

    test('replica1 changed, replica2 unchanged → Replica1ToReplica2', () {
      final u1 = _fileUpdate('A', 100, isNew: true);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        config,
      );
      expect(result.items.length, 1);
      expect(result.items[0].direction, isA<Replica1ToReplica2>());
    });

    test('replica1 unchanged, replica2 changed → Replica2ToReplica1', () {
      final u2 = _fileUpdate('B', 200, isNew: true);
      final result = recon.reconcileAll(
        [(path, const NoUpdates(), u2)],
        config,
      );
      expect(result.items.length, 1);
      expect(result.items[0].direction, isA<Replica2ToReplica1>());
    });

    test('both changed to same content → equal (no items)', () {
      final u1 = _fileUpdate('X', 100);
      final u2 = _fileUpdate('X', 100);
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        config,
      );
      // Equal items are not added to the result list
      expect(result.items, isEmpty);
    });

    test('both changed differently → Conflict', () {
      final u1 = _fileUpdate('A', 100);
      final u2 = _fileUpdate('B', 200);
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        config,
      );
      expect(result.items.length, 1);
      expect(result.items[0].direction, isA<Conflict>());
    });
  });

  group('Conflict types', () {
    test('deleted on one side, modified on other → Conflict', () {
      final u1 = _deleteUpdate();
      final u2 = _fileUpdate('M', 100);
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        config,
      );
      expect(result.items.length, 1);
      expect(result.items[0].direction, isA<Conflict>());
      final c = result.items[0].direction as Conflict;
      expect(c.reason, contains('deleted'));
    });

    test('both deleted → equal (no items)', () {
      final u1 = _deleteUpdate();
      final u2 = _deleteUpdate();
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        config,
      );
      expect(result.items, isEmpty);
    });
  });

  group('Replica status', () {
    test('new file has status created', () {
      final u1 = _fileUpdate('A', 100, isNew: true);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        config,
      );
      final diff = (result.items[0].replicas as Different).diff;
      expect(diff.rc1.status, ReplicaStatus.created);
    });

    test('deleted file has status deleted', () {
      final u1 = _deleteUpdate();
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        config,
      );
      final diff = (result.items[0].replicas as Different).diff;
      expect(diff.rc1.status, ReplicaStatus.deleted);
    });

    test('props-only change has status propsChanged', () {
      final u1 = _propsUpdate(0x1A4);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        config,
      );
      final diff = (result.items[0].replicas as Different).diff;
      expect(diff.rc1.status, ReplicaStatus.propsChanged);
    });

    test('content change has status modified', () {
      final u1 = _fileUpdate('M', 200);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        config,
      );
      final diff = (result.items[0].replicas as Different).diff;
      expect(diff.rc1.status, ReplicaStatus.modified);
    });
  });

  group('Error handling', () {
    test('error on replica 1 becomes Problem', () {
      final result = recon.reconcileAll(
        [(path, const UpdateError('read error'), const NoUpdates())],
        config,
      );
      expect(result.items.length, 1);
      expect(result.items[0].replicas, isA<Problem>());
      expect((result.items[0].replicas as Problem).message, 'read error');
    });

    test('error on replica 2 becomes Problem', () {
      final result = recon.reconcileAll(
        [(path, const NoUpdates(), const UpdateError('disk fail'))],
        config,
      );
      expect(result.items.length, 1);
      expect(result.items[0].replicas, isA<Problem>());
    });
  });

  group('Preference overrides', () {
    test('force replica1→2 overrides all directions', () {
      final u2 = _fileUpdate('B', 100, isNew: true);
      final result = recon.reconcileAll(
        [(path, const NoUpdates(), u2)],
        const ReconConfig(force: true),
      );
      expect(result.items[0].direction, isA<Replica1ToReplica2>());
    });

    test('force replica2→1 overrides all directions', () {
      final u1 = _fileUpdate('A', 100, isNew: true);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        const ReconConfig(force: false),
      );
      expect(result.items[0].direction, isA<Replica2ToReplica1>());
    });

    test('prefer replica1 resolves conflicts', () {
      final u1 = _fileUpdate('A', 100);
      final u2 = _fileUpdate('B', 200);
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        const ReconConfig(prefer: true),
      );
      expect(result.items[0].direction, isA<Replica1ToReplica2>());
    });

    test('prefer replica2 resolves conflicts', () {
      final u1 = _fileUpdate('A', 100);
      final u2 = _fileUpdate('B', 200);
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        const ReconConfig(prefer: false),
      );
      expect(result.items[0].direction, isA<Replica2ToReplica1>());
    });

    test('noDeletion blocks deletion propagation', () {
      final u1 = _deleteUpdate();
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        const ReconConfig(noDeletion: true),
      );
      expect(result.items[0].direction, isA<Conflict>());
      final c = result.items[0].direction as Conflict;
      expect(c.reason, contains('deletion not allowed'));
    });

    test('noCreation blocks creation propagation', () {
      final u1 = _fileUpdate('A', 100, isNew: true);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        const ReconConfig(noCreation: true),
      );
      expect(result.items[0].direction, isA<Conflict>());
    });

    test('noUpdate blocks modification propagation', () {
      final u1 = _fileUpdate('A', 100);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        const ReconConfig(noUpdate: true),
      );
      expect(result.items[0].direction, isA<Conflict>());
    });
  });

  group('Merge', () {
    test('both files changed with shouldMerge → Merge direction', () {
      final u1 = _fileUpdate('A', 100);
      final u2 = _fileUpdate('B', 200);
      final mergeConfig = ReconConfig(
        shouldMerge: (_) => true,
      );
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        mergeConfig,
      );
      expect(result.items[0].direction, isA<Merge>());
    });

    test('shouldMerge false → remains Conflict', () {
      final u1 = _fileUpdate('A', 100);
      final u2 = _fileUpdate('B', 200);
      final mergeConfig = ReconConfig(
        shouldMerge: (_) => false,
      );
      final result = recon.reconcileAll(
        [(path, u1, u2)],
        mergeConfig,
      );
      expect(result.items[0].direction, isA<Conflict>());
    });
  });

  group('Direction manipulation', () {
    test('revertToDefault restores original direction', () {
      final u1 = _fileUpdate('A', 100, isNew: true);
      final result = recon.reconcileAll(
        [(path, u1, const NoUpdates())],
        config,
      );
      final diff = (result.items[0].replicas as Different).diff;
      expect(diff.direction, isA<Replica1ToReplica2>());

      // Change manually
      diff.direction = const Replica2ToReplica1();
      expect(diff.direction, isA<Replica2ToReplica1>());

      // Revert
      diff.revertToDefault();
      expect(diff.direction, isA<Replica1ToReplica2>());
    });
  });

  group('Sorting', () {
    test('conflicts sorted before non-conflicts', () {
      final conflict = _fileUpdate('A', 100);
      final conflictB = _fileUpdate('B', 200);
      final simple = _fileUpdate('C', 300, isNew: true);

      final result = recon.reconcileAll([
        (SyncPath.fromString('z_simple.txt'), simple, const NoUpdates()),
        (SyncPath.fromString('a_conflict.txt'), conflict, conflictB),
      ], config);

      expect(result.items.length, 2);
      expect(result.items[0].direction, isA<Conflict>());
      expect(result.items[0].path1.toString(), 'a_conflict.txt');
    });
  });

  group('Multiple items', () {
    test('reconciles multiple paths', () {
      final result = recon.reconcileAll([
        (SyncPath.fromString('new.txt'),
            _fileUpdate('A', 10, isNew: true), const NoUpdates()),
        (SyncPath.fromString('del.txt'),
            _deleteUpdate(), const NoUpdates()),
        (SyncPath.fromString('mod.txt'),
            const NoUpdates(), _fileUpdate('B', 20)),
      ], config);

      expect(result.items.length, 3);
    });
  });

  group('Directory reconciliation', () {
    test('nested children in directories are reconciled', () {
      final u1 = Updates(
        DirContent(
          Props(permissions: 0x1FF, modTime: DateTime(2024), length: 0),
          [
            (Name('child1.txt'), _fileUpdate('A', 10, isNew: true)),
          ],
          PermChange.propsSame,
          false,
        ),
        PrevDir(Props(permissions: 0x1FF, modTime: DateTime(1970), length: 0)),
      );
      final u2 = Updates(
        DirContent(
          Props(permissions: 0x1FF, modTime: DateTime(2024), length: 0),
          [
            (Name('child2.txt'), _fileUpdate('B', 20, isNew: true)),
          ],
          PermChange.propsSame,
          false,
        ),
        PrevDir(Props(permissions: 0x1FF, modTime: DateTime(1970), length: 0)),
      );

      final result = recon.reconcileUpdates(
        SyncPath.fromString('dir'),
        u1, u2,
        config,
      );

      // child1 from replica1, child2 from replica2
      expect(result.items.length, 2);
      final paths = result.items.map((i) => i.path1.toString()).toSet();
      expect(paths, containsAll(['dir/child1.txt', 'dir/child2.txt']));
    });
  });
}
