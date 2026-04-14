import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_watcher_test_');
    root = Fspath.fromLocal(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('WatcherService', () {
    test('detects file creation', () async {
      final watcher = WatcherService(
        root: root,
        debounce: const Duration(milliseconds: 100),
      );

      final completer = Completer<WatchBatch>();
      watcher.batches.listen((batch) {
        if (!completer.isCompleted) completer.complete(batch);
      });
      watcher.start();

      // Create a file
      await Future.delayed(const Duration(milliseconds: 50));
      File('${tempDir.path}/new_file.txt').writeAsStringSync('hello');

      final batch = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => WatchBatch(changedPaths: {}, timestamp: DateTime.now()),
      );

      expect(batch.changedPaths, isNotEmpty);
      expect(
        batch.changedPaths.any((p) => p.contains('new_file.txt')),
        isTrue,
      );

      await watcher.dispose();
    });

    test('detects file modification', () async {
      // Create file first
      File('${tempDir.path}/existing.txt').writeAsStringSync('v1');

      final watcher = WatcherService(
        root: root,
        debounce: const Duration(milliseconds: 100),
      );

      final completer = Completer<WatchBatch>();
      watcher.batches.listen((batch) {
        if (!completer.isCompleted) completer.complete(batch);
      });
      watcher.start();

      await Future.delayed(const Duration(milliseconds: 50));
      File('${tempDir.path}/existing.txt').writeAsStringSync('v2');

      final batch = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => WatchBatch(changedPaths: {}, timestamp: DateTime.now()),
      );

      expect(batch.changedPaths, isNotEmpty);

      await watcher.dispose();
    });

    test('detects file deletion', () async {
      File('${tempDir.path}/todelete.txt').writeAsStringSync('bye');

      final watcher = WatcherService(
        root: root,
        debounce: const Duration(milliseconds: 100),
      );

      final completer = Completer<WatchBatch>();
      watcher.batches.listen((batch) {
        if (!completer.isCompleted) completer.complete(batch);
      });
      watcher.start();

      await Future.delayed(const Duration(milliseconds: 50));
      File('${tempDir.path}/todelete.txt').deleteSync();

      final batch = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => WatchBatch(changedPaths: {}, timestamp: DateTime.now()),
      );

      expect(batch.changedPaths, isNotEmpty);

      await watcher.dispose();
    });

    test('debouncing batches rapid changes', () async {
      final watcher = WatcherService(
        root: root,
        debounce: const Duration(milliseconds: 200),
      );

      final batches = <WatchBatch>[];
      watcher.batches.listen(batches.add);
      watcher.start();

      // Rapid-fire create multiple files
      await Future.delayed(const Duration(milliseconds: 50));
      for (var i = 0; i < 5; i++) {
        File('${tempDir.path}/rapid_$i.txt').writeAsStringSync('$i');
      }

      // Wait for debounce to fire
      await Future.delayed(const Duration(milliseconds: 500));

      // Should have at most a couple of batches (not 5 separate ones)
      expect(batches.length, lessThanOrEqualTo(3));
      // Total changed paths should cover all files
      final allPaths = batches.expand((b) => b.changedPaths).toSet();
      expect(allPaths.length, greaterThanOrEqualTo(3));

      await watcher.dispose();
    });

    test('ignore filter excludes matching paths', () async {
      final filter = IgnoreFilter(ignorePatterns: ['Name *.tmp']);
      final watcher = WatcherService(
        root: root,
        filter: filter,
        debounce: const Duration(milliseconds: 100),
      );

      final batches = <WatchBatch>[];
      watcher.batches.listen(batches.add);
      watcher.start();

      await Future.delayed(const Duration(milliseconds: 50));
      File('${tempDir.path}/ignored.tmp').writeAsStringSync('skip');
      File('${tempDir.path}/tracked.txt').writeAsStringSync('keep');

      await Future.delayed(const Duration(milliseconds: 300));

      final allPaths = batches.expand((b) => b.changedPaths).toSet();
      expect(allPaths.any((p) => p.contains('tracked.txt')), isTrue);
      expect(allPaths.any((p) => p.contains('ignored.tmp')), isFalse);

      await watcher.dispose();
    });

    test('start/stop lifecycle', () async {
      final watcher = WatcherService(root: root);
      expect(watcher.isWatching, isFalse);

      watcher.start();
      expect(watcher.isWatching, isTrue);

      await watcher.stop();
      expect(watcher.isWatching, isFalse);

      await watcher.dispose();
    });

    test('detects nested directory changes', () async {
      Directory('${tempDir.path}/sub').createSync();

      final watcher = WatcherService(
        root: root,
        debounce: const Duration(milliseconds: 100),
      );

      final completer = Completer<WatchBatch>();
      watcher.batches.listen((batch) {
        if (!completer.isCompleted) completer.complete(batch);
      });
      watcher.start();

      await Future.delayed(const Duration(milliseconds: 50));
      File('${tempDir.path}/sub/nested.txt').writeAsStringSync('deep');

      final batch = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => WatchBatch(changedPaths: {}, timestamp: DateTime.now()),
      );

      expect(batch.changedPaths, isNotEmpty);
      expect(
        batch.changedPaths.any((p) => p.contains('nested.txt')),
        isTrue,
      );

      await watcher.dispose();
    });
  });

  group('WatchBatch', () {
    test('isEmpty/size', () {
      final empty = WatchBatch(changedPaths: const {}, timestamp: DateTime.now());
      expect(empty.isEmpty, isTrue);
      expect(empty.size, 0);

      final batch = WatchBatch(
        changedPaths: {'a.txt', 'b.txt'},
        timestamp: DateTime.now(),
      );
      expect(batch.isEmpty, isFalse);
      expect(batch.size, 2);
    });
  });
}
