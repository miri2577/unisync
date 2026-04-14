import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_stasher_test_');
    root = Fspath.fromLocal(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('Stasher', () {
    test('backup creates copy in central location', () {
      File('${tempDir.path}/file.txt').writeAsStringSync('original');

      final stasher = Stasher(
        config: BackupConfig(
          location: BackupLocation.central,
          backupDir: '${tempDir.path}/backups',
        ),
      );

      final backupPath = stasher.backup(root, SyncPath.fromString('file.txt'));
      expect(backupPath, isNotNull);
      expect(File(backupPath!).existsSync(), isTrue);
      expect(File(backupPath).readAsStringSync(), 'original');
    });

    test('backup creates copy in local location', () {
      File('${tempDir.path}/local.txt').writeAsStringSync('data');

      final stasher = Stasher(
        config: const BackupConfig(location: BackupLocation.local),
      );

      final backupPath = stasher.backup(root, SyncPath.fromString('local.txt'));
      expect(backupPath, isNotNull);
      expect(File(backupPath!).existsSync(), isTrue);
      // Should be in same directory
      expect(backupPath, contains(tempDir.path));
    });

    test('backup returns null for missing file', () {
      final stasher = Stasher();
      final result = stasher.backup(root, SyncPath.fromString('missing.txt'));
      expect(result, isNull);
    });

    test('backup rotates versions', () {
      final stasher = Stasher(
        config: BackupConfig(
          location: BackupLocation.central,
          backupDir: '${tempDir.path}/backups',
          maxBackups: 3,
        ),
      );

      // Create and backup 4 times
      for (var i = 0; i < 4; i++) {
        File('${tempDir.path}/rotate.txt').writeAsStringSync('v$i');
        stasher.backup(root, SyncPath.fromString('rotate.txt'));
      }

      // Should have at most maxBackups versions
      final backupDir = Directory('${tempDir.path}/backups');
      final backupFiles = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('rotate'))
          .toList();
      expect(backupFiles.length, lessThanOrEqualTo(3));
    });

    test('backup preserves directory structure in central mode', () {
      Directory('${tempDir.path}/sub/deep').createSync(recursive: true);
      File('${tempDir.path}/sub/deep/nested.txt').writeAsStringSync('deep');

      final stasher = Stasher(
        config: BackupConfig(
          location: BackupLocation.central,
          backupDir: '${tempDir.path}/backups',
        ),
      );

      final backupPath = stasher.backup(
        root,
        SyncPath.fromString('sub/deep/nested.txt'),
      );
      expect(backupPath, isNotNull);
      expect(backupPath!, contains('sub'));
      expect(backupPath, contains('deep'));
      expect(File(backupPath).existsSync(), isTrue);
    });

    test('backupConflict creates timestamped copy', () {
      File('${tempDir.path}/conflict.txt').writeAsStringSync('conflicted');

      final stasher = Stasher();
      final result =
          stasher.backupConflict(root, SyncPath.fromString('conflict.txt'));

      expect(result, isNotNull);
      expect(File(result!).existsSync(), isTrue);
      expect(result, contains('conflict on'));
      expect(File(result).readAsStringSync(), 'conflicted');
    });

    test('backupConflict increments number for same day', () {
      File('${tempDir.path}/dup.txt').writeAsStringSync('data');

      final stasher = Stasher();
      final r1 = stasher.backupConflict(root, SyncPath.fromString('dup.txt'));
      final r2 = stasher.backupConflict(root, SyncPath.fromString('dup.txt'));

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r1, isNot(equals(r2)));
      expect(File(r1!).existsSync(), isTrue);
      expect(File(r2!).existsSync(), isTrue);
    });

    test('backupConflict preserves extension', () {
      File('${tempDir.path}/report.pdf').writeAsStringSync('pdf');

      final stasher = Stasher();
      final result =
          stasher.backupConflict(root, SyncPath.fromString('report.pdf'));

      expect(result, isNotNull);
      expect(result!, endsWith('.pdf'));
    });

    test('backupConflict returns null for missing file', () {
      final stasher = Stasher();
      final result =
          stasher.backupConflict(root, SyncPath.fromString('nope.txt'));
      expect(result, isNull);
    });

    test('getLatestBackup finds existing backup', () {
      File('${tempDir.path}/find.txt').writeAsStringSync('findme');

      final stasher = Stasher(
        config: BackupConfig(
          location: BackupLocation.central,
          backupDir: '${tempDir.path}/backups',
        ),
      );

      stasher.backup(root, SyncPath.fromString('find.txt'));
      final latest =
          stasher.getLatestBackup(root, SyncPath.fromString('find.txt'));
      expect(latest, isNotNull);
      expect(File(latest!).readAsStringSync(), 'findme');
    });

    test('getLatestBackup returns null when no backup', () {
      final stasher = Stasher(
        config: BackupConfig(
          location: BackupLocation.central,
          backupDir: '${tempDir.path}/backups',
        ),
      );

      final latest =
          stasher.getLatestBackup(root, SyncPath.fromString('nobackup.txt'));
      expect(latest, isNull);
    });

    test('custom prefix and suffix', () {
      File('${tempDir.path}/custom.txt').writeAsStringSync('data');

      final stasher = Stasher(
        config: BackupConfig(
          location: BackupLocation.central,
          backupDir: '${tempDir.path}/backups',
          prefix: 'backup_',
          suffix: '.old',
        ),
      );

      final result = stasher.backup(root, SyncPath.fromString('custom.txt'));
      expect(result, isNotNull);
      final filename = result!.replaceAll('\\', '/').split('/').last;
      expect(filename, startsWith('backup_'));
      expect(filename, contains('.old'));
    });
  });
}
