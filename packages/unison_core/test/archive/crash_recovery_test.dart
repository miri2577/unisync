import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root1;
  late Fspath root2;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_crash_test_');
    root1 = Fspath.fromLocal(
      Platform.isWindows ? 'C:/test/crash_a' : '/test/crash_a',
    );
    root2 = Fspath.fromLocal(
      Platform.isWindows ? 'C:/test/crash_b' : '/test/crash_b',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('Two-phase commit crash recovery', () {
    test('normal save creates no orphan files', () {
      final store = ArchiveStore(tempDir.path);
      final archive = ArchiveFile(
        Props(permissions: 0x1ED, modTime: DateTime(2024), length: 100),
        FullFingerprint(Fingerprint(Uint8List(16))),
        const NoStamp(),
        RessStamp.zero,
      );

      store.save(root1, root2, archive);

      // No commit log or temp files should remain
      final hash = ArchiveStore.archiveHash(root1, root2);
      expect(File('${tempDir.path}/cl$hash').existsSync(), isFalse);
      expect(File('${tempDir.path}/tm$hash').existsSync(), isFalse);
      expect(File('${tempDir.path}/old_ar$hash').existsSync(), isFalse);
      // Archive should exist
      expect(File('${tempDir.path}/ar$hash').existsSync(), isTrue);
    });

    test('recovery from PHASE1 crash rolls back', () {
      final store = ArchiveStore(tempDir.path);
      store.ensureDir();
      final hash = ArchiveStore.archiveHash(root1, root2);

      // Simulate crash after PHASE1: commit log + temp exist, no old backup
      File('${tempDir.path}/cl$hash').writeAsStringSync('PHASE1');
      File('${tempDir.path}/tm$hash').writeAsBytesSync([1, 2, 3]);

      // Recovery should delete temp and commit log
      store.recoverAll();

      expect(File('${tempDir.path}/cl$hash').existsSync(), isFalse);
      expect(File('${tempDir.path}/tm$hash').existsSync(), isFalse);
    });

    test('recovery from PHASE2 crash completes commit', () {
      final store = ArchiveStore(tempDir.path);
      store.ensureDir();
      final hash = ArchiveStore.archiveHash(root1, root2);

      // First, save a valid archive
      final archive = ArchiveFile(
        Props(permissions: 0x1ED, modTime: DateTime(2024), length: 50),
        FullFingerprint(Fingerprint(Uint8List(16))),
        const NoStamp(),
        RessStamp.zero,
      );
      final data = encodeArchive(archive);

      // Simulate PHASE2 crash: temp has new data, old has backup, commit log says PHASE2
      File('${tempDir.path}/tm$hash').writeAsBytesSync(data);
      File('${tempDir.path}/old_ar$hash').writeAsBytesSync([0]); // old archive
      File('${tempDir.path}/cl$hash').writeAsStringSync('PHASE2');

      // Recovery should complete: rename temp → archive, delete old + log
      store.recoverAll();

      expect(File('${tempDir.path}/ar$hash').existsSync(), isTrue);
      expect(File('${tempDir.path}/tm$hash').existsSync(), isFalse);
      expect(File('${tempDir.path}/old_ar$hash').existsSync(), isFalse);
      expect(File('${tempDir.path}/cl$hash').existsSync(), isFalse);

      // Verify the recovered archive is valid
      final loaded = store.load(root1, root2);
      expect(loaded, isA<ArchiveFile>());
    });

    test('recovery from PHASE3 cleans up', () {
      final store = ArchiveStore(tempDir.path);
      store.ensureDir();
      final hash = ArchiveStore.archiveHash(root1, root2);

      // PHASE3: archive already renamed, just cleanup needed
      final archive = ArchiveFile(
        Props(permissions: 0x1ED, modTime: DateTime(2024), length: 50),
        FullFingerprint(Fingerprint(Uint8List(16))),
        const NoStamp(),
        RessStamp.zero,
      );
      File('${tempDir.path}/ar$hash').writeAsBytesSync(encodeArchive(archive));
      File('${tempDir.path}/old_ar$hash').writeAsBytesSync([0]);
      File('${tempDir.path}/cl$hash').writeAsStringSync('PHASE3');

      store.recoverAll();

      expect(File('${tempDir.path}/ar$hash').existsSync(), isTrue);
      expect(File('${tempDir.path}/old_ar$hash').existsSync(), isFalse);
      expect(File('${tempDir.path}/cl$hash').existsSync(), isFalse);
    });

    test('orphaned temp files without commit log are cleaned', () {
      final store = ArchiveStore(tempDir.path);
      store.ensureDir();

      // Orphaned temp (no commit log)
      File('${tempDir.path}/tmorphan123456').writeAsBytesSync([1, 2]);

      store.recoverAll();

      expect(File('${tempDir.path}/tmorphan123456').existsSync(), isFalse);
    });

    test('load triggers recovery before reading', () {
      final store = ArchiveStore(tempDir.path);
      store.ensureDir();
      final hash = ArchiveStore.archiveHash(root1, root2);

      // Set up PHASE2 state
      final archive = ArchiveFile(
        Props(permissions: 0, modTime: DateTime(2024), length: 0),
        FullFingerprint(Fingerprint(Uint8List(16))),
        const NoStamp(),
        RessStamp.zero,
      );
      File('${tempDir.path}/tm$hash').writeAsBytesSync(encodeArchive(archive));
      File('${tempDir.path}/cl$hash').writeAsStringSync('PHASE2');

      // Load should recover and return the archive
      final loaded = store.load(root1, root2);
      expect(loaded, isA<ArchiveFile>());
    });
  });
}
