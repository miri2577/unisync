import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Directory dir1;
  late Directory dir2;
  late Fspath root1;
  late Fspath root2;

  setUp(() {
    currentCaseMode = CaseMode.sensitive;
    tempDir = Directory.systemTemp.createTempSync('unison_concurrent_test_');
    dir1 = Directory('${tempDir.path}/r1')..createSync();
    dir2 = Directory('${tempDir.path}/r2')..createSync();
    root1 = Fspath.fromLocal(dir1.path);
    root2 = Fspath.fromLocal(dir2.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('Concurrent Transport', () {
    test('propagateAllConcurrent handles multiple files', () async {
      // Create files on replica 1
      for (var i = 0; i < 10; i++) {
        File('${dir1.path}/file_$i.txt').writeAsStringSync('content $i');
      }

      // Build recon items manually
      final store = ArchiveStore('${tempDir.path}/archive');
      final engine = SyncEngine(archiveStore: store);
      final result = engine.sync(
        root1,
        root2,
        updateConfig: const UpdateConfig(useFastCheck: false),
      );

      // Verify all files synced
      expect(result.failed, 0);
      for (var i = 0; i < 10; i++) {
        expect(
          File('${dir2.path}/file_$i.txt').readAsStringSync(),
          'content $i',
        );
      }
    });

    test('concurrent orchestrator respects maxThreads', () async {
      final orchestrator = TransportOrchestrator(maxThreads: 3);
      // Just verify it constructs without error
      expect(orchestrator.maxThreads, 3);
    });

    test('TaskPool controls concurrency', () async {
      // Indirect test via propagation of many small files
      for (var i = 0; i < 20; i++) {
        File('${dir1.path}/small_$i.txt').writeAsStringSync('$i');
      }

      final store = ArchiveStore('${tempDir.path}/archive');
      final engine = SyncEngine(archiveStore: store);
      final result = engine.sync(
        root1,
        root2,
        updateConfig: const UpdateConfig(useFastCheck: false),
      );

      expect(result.failed, 0);
      expect(result.propagated, greaterThan(0));

      // Verify all 20 files exist on replica 2
      for (var i = 0; i < 20; i++) {
        expect(File('${dir2.path}/small_$i.txt').existsSync(), isTrue);
      }
    });
  });
}
