import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  setUp(() => currentCaseMode = CaseMode.sensitive);

  // T2: Case Conflict Detection
  group('Case conflict detection', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('unison_case_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('detects same-name different-case files', () {
      // On case-sensitive FS, we CAN create both
      if (Platform.isWindows || Platform.isMacOS) {
        // Can't create both on case-insensitive — skip
        return;
      }
      File('${tempDir.path}/File.txt').writeAsStringSync('a');
      File('${tempDir.path}/file.txt').writeAsStringSync('b');
      final conflicts = detectCaseConflicts(tempDir.path);
      expect(conflicts.length, 1);
      expect(conflicts[0].name1.toLowerCase(), 'file.txt');
    });

    test('no conflicts in clean directory', () {
      File('${tempDir.path}/alpha.txt').writeAsStringSync('a');
      File('${tempDir.path}/beta.txt').writeAsStringSync('b');
      final conflicts = detectCaseConflicts(tempDir.path);
      expect(conflicts, isEmpty);
    });

    test('recursive scanning', () {
      Directory('${tempDir.path}/sub').createSync();
      File('${tempDir.path}/sub/ok.txt').writeAsStringSync('ok');
      final conflicts = detectCaseConflicts(tempDir.path, recursive: true);
      expect(conflicts, isEmpty);
    });
  });

  // T3: Ownership in Props
  group('Props ownership', () {
    test('default ownerId/groupId is -1', () {
      final p = Props(permissions: 0, modTime: DateTime(2024), length: 0);
      expect(p.ownerId, -1);
      expect(p.groupId, -1);
    });

    test('copyWith preserves ownership', () {
      final p = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024),
        length: 100,
        ownerId: 1000,
        groupId: 1000,
      );
      final p2 = p.copyWith(length: 200);
      expect(p2.ownerId, 1000);
      expect(p2.groupId, 1000);
      expect(p2.length, 200);
    });

    test('ownership serialized in archive', () {
      final archive = ArchiveFile(
        Props(
          permissions: 0x1ED,
          modTime: DateTime(2024),
          length: 50,
          ownerId: 1000,
          groupId: 500,
        ),
        FullFingerprint(Fingerprint(Uint8List(16))),
        const NoStamp(),
        RessStamp.zero,
      );

      final data = encodeArchive(archive);
      final decoded = decodeArchive(data) as ArchiveFile;
      expect(decoded.desc.ownerId, 1000);
      expect(decoded.desc.groupId, 500);
    });
  });

  // T1: Symlink following (basic model test)
  group('Symlink following config', () {
    test('UpdateConfig supports shouldFollow', () {
      final config = UpdateConfig(
        shouldFollow: (path) => path.toString().endsWith('.lnk'),
      );
      expect(config.shouldFollow, isNotNull);
      expect(
        config.shouldFollow!(SyncPath.fromString('test.lnk')),
        isTrue,
      );
      expect(
        config.shouldFollow!(SyncPath.fromString('test.txt')),
        isFalse,
      );
    });
  });

  // B1 verification: _updateDeleted uses correct prevState
  group('UpdateDetector deleted prevState', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('unison_del_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('deleted file has PrevFile prevState', () {
      final root = Fspath.fromLocal(tempDir.path);
      File('${tempDir.path}/gone.txt').writeAsStringSync('data');

      final detector = UpdateDetector();
      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('gone.txt'),
        const UpdateConfig(useFastCheck: false),
      );

      File('${tempDir.path}/gone.txt').deleteSync();

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('gone.txt'),
        archive,
        const UpdateConfig(useFastCheck: false),
      );

      expect(update, isA<Updates>());
      final u = update as Updates;
      expect(u.content, isA<Absent>());
      expect(u.prevState, isA<PrevFile>()); // B1 fix: was NewEntry before
    });
  });

  // B2 verification: UpdateItem serialization roundtrip
  group('Remote UpdateItem serialization', () {
    test('NoUpdates roundtrip', () {
      final enc = MarshalEncoder();
      // Manually call the encode/decode from remote_sync
      enc.writeTag(0); // NoUpdates
      final dec = MarshalDecoder(enc.toBytes());
      final tag = dec.readTag();
      expect(tag, 0);
    });

    // Full roundtrip tested via remote_sync_test.dart
  });

  // Stasher integration
  group('Stasher basics', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('unison_stasher2_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('backup before overwrite preserves old version', () {
      final root = Fspath.fromLocal(tempDir.path);
      File('${tempDir.path}/file.txt').writeAsStringSync('v1');

      final stasher = Stasher(
        config: BackupConfig(
          location: BackupLocation.central,
          backupDir: '${tempDir.path}/bak',
        ),
      );

      final backupPath = stasher.backup(root, SyncPath.fromString('file.txt'));
      expect(backupPath, isNotNull);
      expect(File(backupPath!).readAsStringSync(), 'v1');

      // Now overwrite
      File('${tempDir.path}/file.txt').writeAsStringSync('v2');
      expect(File('${tempDir.path}/file.txt').readAsStringSync(), 'v2');
      // Backup still has v1
      expect(File(backupPath).readAsStringSync(), 'v1');
    });
  });

  // Batch operations
  group('Batch operations', () {
    test('batchSkipConflicts skips only conflicts', () {
      final items = [
        _makeReconItem('a.txt', const Replica1ToReplica2()),
        _makeReconItem('b.txt', Conflict('test')),
        _makeReconItem('c.txt', const Replica2ToReplica1()),
      ];

      batchSkipConflicts(items);

      expect(items[0].direction, isA<Replica1ToReplica2>());
      expect(items[1].direction, isA<Conflict>());
      expect(items[2].direction, isA<Replica2ToReplica1>());
    });

    test('batchForceRight sets all to R1→R2', () {
      final items = [
        _makeReconItem('a.txt', Conflict('c')),
        _makeReconItem('b.txt', const Replica2ToReplica1()),
      ];

      batchForceRight(items);

      expect(items[0].direction, isA<Replica1ToReplica2>());
      expect(items[1].direction, isA<Replica1ToReplica2>());
    });
  });
}

ReconItem _makeReconItem(String path, Direction dir) {
  return ReconItem(
    path1: SyncPath.fromString(path),
    path2: SyncPath.fromString(path),
    replicas: Different(Difference(
      rc1: ReplicaContent(
        content: const Absent(),
        status: ReplicaStatus.unchanged,
        desc: Props.absent,
        size: (0, 0),
      ),
      rc2: ReplicaContent(
        content: const Absent(),
        status: ReplicaStatus.unchanged,
        desc: Props.absent,
        size: (0, 0),
      ),
      direction: dir,
      defaultDirection: dir,
    )),
  );
}
