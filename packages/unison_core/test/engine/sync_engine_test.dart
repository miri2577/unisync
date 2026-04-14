import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Directory dir1;
  late Directory dir2;
  late Fspath root1;
  late Fspath root2;
  late ArchiveStore store;
  late SyncEngine engine;

  setUp(() {
    currentCaseMode = CaseMode.sensitive;
    tempDir = Directory.systemTemp.createTempSync('unison_sync_test_');
    dir1 = Directory('${tempDir.path}/replica1')..createSync();
    dir2 = Directory('${tempDir.path}/replica2')..createSync();
    root1 = Fspath.fromLocal(dir1.path);
    root2 = Fspath.fromLocal(dir2.path);
    store = ArchiveStore('${tempDir.path}/archive');
    engine = SyncEngine(archiveStore: store);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Verify two directories have identical contents.
  void expectDirsEqual(String path1, String path2) {
    final d1 = Directory(path1);
    final d2 = Directory(path2);

    final entries1 = d1.listSync(recursive: true, followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    final entries2 = d2.listSync(recursive: true, followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));

    // Same number of entries
    final names1 = entries1.map((e) =>
        e.path.substring(path1.length).replaceAll('\\', '/')).toList();
    final names2 = entries2.map((e) =>
        e.path.substring(path2.length).replaceAll('\\', '/')).toList();
    expect(names1, equals(names2), reason: 'Directory trees differ');

    // Same file contents
    for (var i = 0; i < entries1.length; i++) {
      if (entries1[i] is File && entries2[i] is File) {
        final c1 = (entries1[i] as File).readAsStringSync();
        final c2 = (entries2[i] as File).readAsStringSync();
        expect(c1, equals(c2),
            reason: 'Content differs at ${names1[i]}');
      }
    }
  }

  group('SyncEngine end-to-end', () {
    test('first sync: new file propagated from replica1 to replica2', () {
      File('${dir1.path}/hello.txt').writeAsStringSync('Hello World!');

      final result = engine.sync(root1, root2);

      expect(result.propagated, 1);
      expect(File('${dir2.path}/hello.txt').existsSync(), isTrue);
      expect(File('${dir2.path}/hello.txt').readAsStringSync(), 'Hello World!');
    });

    test('first sync: new file propagated from replica2 to replica1', () {
      File('${dir2.path}/from_r2.txt').writeAsStringSync('From R2');

      final result = engine.sync(root1, root2);

      expect(result.propagated, 1);
      expect(File('${dir1.path}/from_r2.txt').readAsStringSync(), 'From R2');
    });

    test('first sync: files on both sides (no overlap)', () {
      File('${dir1.path}/a.txt').writeAsStringSync('A');
      File('${dir2.path}/b.txt').writeAsStringSync('B');

      final result = engine.sync(root1, root2);

      expect(result.propagated, 2);
      expectDirsEqual(dir1.path, dir2.path);
    });

    test('first sync: nested directories', () {
      Directory('${dir1.path}/sub/deep').createSync(recursive: true);
      File('${dir1.path}/sub/deep/file.txt').writeAsStringSync('Deep');
      File('${dir1.path}/sub/top.txt').writeAsStringSync('Top');

      final result = engine.sync(root1, root2);

      expect(result.propagated, greaterThan(0));
      expect(
        File('${dir2.path}/sub/deep/file.txt').readAsStringSync(),
        'Deep',
      );
      expect(
        File('${dir2.path}/sub/top.txt').readAsStringSync(),
        'Top',
      );
    });

    test('second sync: modification propagated', () {
      // Initial state
      File('${dir1.path}/mod.txt').writeAsStringSync('version one');
      File('${dir2.path}/mod.txt').writeAsStringSync('version one');
      engine.sync(root1, root2,
          updateConfig: const UpdateConfig(useFastCheck: false));

      // Modify on replica1 (different length to ensure detection)
      File('${dir1.path}/mod.txt').writeAsStringSync('version two - modified');

      final result = engine.sync(root1, root2,
          updateConfig: const UpdateConfig(useFastCheck: false));

      expect(result.propagated, 1);
      expect(File('${dir2.path}/mod.txt').readAsStringSync(),
          'version two - modified');
    });

    test('second sync: deletion propagated', () {
      const uc = UpdateConfig(useFastCheck: false);
      // Initial state
      File('${dir1.path}/del.txt').writeAsStringSync('delete me');
      File('${dir2.path}/del.txt').writeAsStringSync('delete me');
      engine.sync(root1, root2, updateConfig: uc);

      // Delete on replica1
      File('${dir1.path}/del.txt').deleteSync();

      final result = engine.sync(root1, root2, updateConfig: uc);

      expect(result.propagated, 1);
      expect(File('${dir2.path}/del.txt').existsSync(), isFalse);
    });

    test('conflict: both sides modified differently', () {
      const uc = UpdateConfig(useFastCheck: false);
      // Initial state
      File('${dir1.path}/conflict.txt').writeAsStringSync('original');
      File('${dir2.path}/conflict.txt').writeAsStringSync('original');
      engine.sync(root1, root2, updateConfig: uc);

      // Modify differently on both sides
      File('${dir1.path}/conflict.txt').writeAsStringSync('version A from replica 1');
      File('${dir2.path}/conflict.txt').writeAsStringSync('version B from replica 2');

      final result = engine.sync(root1, root2, updateConfig: uc);

      // Should be skipped as conflict
      expect(result.skipped, greaterThan(0));
      // Both files should be untouched
      expect(File('${dir1.path}/conflict.txt').readAsStringSync(), 'version A from replica 1');
      expect(File('${dir2.path}/conflict.txt').readAsStringSync(), 'version B from replica 2');
    });

    test('conflict resolved with prefer', () {
      const uc = UpdateConfig(useFastCheck: false);
      File('${dir1.path}/pref.txt').writeAsStringSync('original');
      File('${dir2.path}/pref.txt').writeAsStringSync('original');
      engine.sync(root1, root2, updateConfig: uc);

      File('${dir1.path}/pref.txt').writeAsStringSync('from replica 1');
      File('${dir2.path}/pref.txt').writeAsStringSync('from replica 2');

      final result = engine.sync(
        root1,
        root2,
        updateConfig: uc,
        reconConfig: const ReconConfig(prefer: true), // prefer replica1
      );

      expect(result.propagated, greaterThan(0));
      expect(File('${dir2.path}/pref.txt').readAsStringSync(), 'from replica 1');
    });

    test('empty directories synced', () {
      Directory('${dir1.path}/empty_dir').createSync();

      final result = engine.sync(root1, root2);

      expect(result.propagated, greaterThan(0));
      expect(Directory('${dir2.path}/empty_dir').existsSync(), isTrue);
    });

    test('multiple files and dirs in one sync', () {
      Directory('${dir1.path}/docs').createSync();
      File('${dir1.path}/docs/readme.md').writeAsStringSync('# Readme');
      File('${dir1.path}/docs/notes.txt').writeAsStringSync('Notes here');
      File('${dir1.path}/config.json').writeAsStringSync('{}');
      File('${dir2.path}/data.csv').writeAsStringSync('a,b,c');

      final result = engine.sync(root1, root2);

      expect(result.failed, 0);
      expectDirsEqual(dir1.path, dir2.path);
    });

    test('idempotent: second sync with no changes produces no items', () {
      const uc = UpdateConfig(useFastCheck: false, fatTolerance: true);
      File('${dir1.path}/stable.txt').writeAsStringSync('stable');
      engine.sync(root1, root2, updateConfig: uc);

      final result = engine.sync(root1, root2, updateConfig: uc);

      expect(result.propagated, 0);
      expect(result.reconItems, isEmpty);
    });

    test('progress callback is called', () {
      File('${dir1.path}/progress.txt').writeAsStringSync('test');

      final phases = <SyncPhase>[];
      engine.sync(
        root1,
        root2,
        onProgress: (phase, msg) => phases.add(phase),
      );

      expect(phases, contains(SyncPhase.scanning));
      expect(phases, contains(SyncPhase.reconciling));
      expect(phases, contains(SyncPhase.propagating));
      expect(phases, contains(SyncPhase.done));
    });
  });
}
