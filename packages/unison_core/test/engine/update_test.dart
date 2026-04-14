import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root;
  late UpdateDetector detector;

  setUp(() {
    currentCaseMode = CaseMode.sensitive;
    tempDir = Directory.systemTemp.createTempSync('unison_update_test_');
    root = Fspath.fromLocal(tempDir.path);
    detector = UpdateDetector();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  const config = UpdateConfig(useFastCheck: false);

  group('UpdateDetector', () {
    test('empty dir vs NoArchive returns new dir', () {
      // Create an empty directory structure
      Directory('${tempDir.path}/sub').createSync();

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('sub'),
        const NoArchive(),
        config,
      );

      expect(update, isA<Updates>());
      final u = update as Updates;
      expect(u.content, isA<DirContent>());
      expect(u.prevState, isA<NewEntry>());
    });

    test('new file detected', () {
      File('${tempDir.path}/hello.txt').writeAsStringSync('Hello!');

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('hello.txt'),
        const NoArchive(),
        config,
      );

      expect(update, isA<Updates>());
      final u = update as Updates;
      expect(u.content, isA<FileContent>());
      expect(u.prevState, isA<NewEntry>());
      final fc = u.content as FileContent;
      expect(fc.contentsChange, isA<ContentsUpdated>());
      expect(fc.desc.length, 6);
    });

    test('unchanged file returns NoUpdates', () {
      File('${tempDir.path}/test.txt').writeAsStringSync('content');
      // Build archive matching current state
      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('test.txt'),
        config,
      );

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('test.txt'),
        archive,
        config,
      );

      expect(update, isA<NoUpdates>());
    });

    test('modified file detected', () {
      File('${tempDir.path}/mod.txt').writeAsStringSync('original');
      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('mod.txt'),
        config,
      );

      // Modify the file
      File('${tempDir.path}/mod.txt').writeAsStringSync('modified');

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('mod.txt'),
        archive,
        config,
      );

      expect(update, isA<Updates>());
      final u = update as Updates;
      expect(u.content, isA<FileContent>());
      final fc = u.content as FileContent;
      expect(fc.contentsChange, isA<ContentsUpdated>());
    });

    test('deleted file detected', () {
      File('${tempDir.path}/del.txt').writeAsStringSync('gone');
      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('del.txt'),
        config,
      );

      // Delete the file
      File('${tempDir.path}/del.txt').deleteSync();

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('del.txt'),
        archive,
        config,
      );

      expect(update, isA<Updates>());
      final u = update as Updates;
      expect(u.content, isA<Absent>());
    });

    test('new file in existing directory detected', () {
      Directory('${tempDir.path}/dir').createSync();
      File('${tempDir.path}/dir/old.txt').writeAsStringSync('old');

      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('dir'),
        config,
      );

      // Add a new file
      File('${tempDir.path}/dir/new.txt').writeAsStringSync('new');

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('dir'),
        archive,
        config,
      );

      expect(update, isA<Updates>());
      final u = update as Updates;
      expect(u.content, isA<DirContent>());
      final dc = u.content as DirContent;
      // Only the new file should appear as an update
      expect(dc.children.any((c) => c.$1 == Name('new.txt')), isTrue);
      final newChild = dc.children.firstWhere((c) => c.$1 == Name('new.txt'));
      expect(newChild.$2, isA<Updates>());
    });

    test('deleted file in directory detected', () {
      Directory('${tempDir.path}/dir2').createSync();
      File('${tempDir.path}/dir2/keep.txt').writeAsStringSync('keep');
      File('${tempDir.path}/dir2/remove.txt').writeAsStringSync('remove');

      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('dir2'),
        config,
      );

      File('${tempDir.path}/dir2/remove.txt').deleteSync();

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('dir2'),
        archive,
        config,
      );

      expect(update, isA<Updates>());
      final dc = (update as Updates).content as DirContent;
      expect(dc.children.any((c) => c.$1 == Name('remove.txt')), isTrue);
      final removed = dc.children.firstWhere((c) => c.$1 == Name('remove.txt'));
      expect((removed.$2 as Updates).content, isA<Absent>());
    });

    test('unchanged directory returns NoUpdates', () {
      Directory('${tempDir.path}/stable').createSync();
      File('${tempDir.path}/stable/a.txt').writeAsStringSync('a');
      File('${tempDir.path}/stable/b.txt').writeAsStringSync('b');

      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('stable'),
        config,
      );

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('stable'),
        archive,
        config,
      );

      expect(update, isA<NoUpdates>());
    });

    test('nested directory changes detected', () {
      Directory('${tempDir.path}/a/b').createSync(recursive: true);
      File('${tempDir.path}/a/b/deep.txt').writeAsStringSync('deep');

      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('a'),
        config,
      );

      File('${tempDir.path}/a/b/deep.txt').writeAsStringSync('modified deep');

      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('a'),
        archive,
        config,
      );

      expect(update, isA<Updates>());
    });

    test('absent path vs NoArchive returns NoUpdates', () {
      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('nonexistent'),
        const NoArchive(),
        config,
      );
      expect(update, isA<NoUpdates>());
    });

    test('buildArchiveFromFs captures directory tree', () {
      Directory('${tempDir.path}/tree/sub').createSync(recursive: true);
      File('${tempDir.path}/tree/a.txt').writeAsStringSync('a');
      File('${tempDir.path}/tree/sub/b.txt').writeAsStringSync('b');

      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('tree'),
        config,
      );

      expect(archive, isA<ArchiveDir>());
      final dir = archive as ArchiveDir;
      expect(dir.children.length, 2);
      expect(dir.children[Name('a.txt')], isA<ArchiveFile>());
      expect(dir.children[Name('sub')], isA<ArchiveDir>());
      final sub = dir.children[Name('sub')] as ArchiveDir;
      expect(sub.children[Name('b.txt')], isA<ArchiveFile>());
    });

    test('ignore predicate skips paths', () {
      Directory('${tempDir.path}/ign').createSync();
      File('${tempDir.path}/ign/keep.txt').writeAsStringSync('keep');
      File('${tempDir.path}/ign/skip.tmp').writeAsStringSync('skip');

      final ignoreConfig = UpdateConfig(
        useFastCheck: false,
        shouldIgnore: (path) => path.finalName?.raw.endsWith('.tmp') ?? false,
      );

      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('ign'),
        ignoreConfig,
      );

      final dir = archive as ArchiveDir;
      expect(dir.children.length, 1);
      expect(dir.children.containsKey(Name('keep.txt')), isTrue);
      expect(dir.children.containsKey(Name('skip.tmp')), isFalse);
    });

    test('fast-check skips fingerprint when metadata unchanged', () {
      File('${tempDir.path}/fast.txt').writeAsStringSync('fast check');
      final fastConfig = UpdateConfig(useFastCheck: true);

      // Build archive (this also populates the FP cache)
      final archive = detector.buildArchiveFromFs(
        root,
        SyncPath.fromString('fast.txt'),
        fastConfig,
      );

      // With fast-check, unchanged file should return NoUpdates
      final (update, _) = detector.findUpdates(
        root,
        SyncPath.fromString('fast.txt'),
        archive,
        fastConfig,
      );

      expect(update, isA<NoUpdates>());
    });
  });
}
