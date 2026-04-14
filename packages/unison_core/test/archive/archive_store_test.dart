import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root1;
  late Fspath root2;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_store_test_');
    root1 = Fspath.fromLocal(
      Platform.isWindows ? 'C:/Users/test/a' : '/home/test/a',
    );
    root2 = Fspath.fromLocal(
      Platform.isWindows ? 'C:/Users/test/b' : '/home/test/b',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ArchiveStore', () {
    test('archiveHash is deterministic', () {
      final h1 = ArchiveStore.archiveHash(root1, root2);
      final h2 = ArchiveStore.archiveHash(root1, root2);
      expect(h1, h2);
    });

    test('archiveHash differs for different roots', () {
      final h1 = ArchiveStore.archiveHash(root1, root2);
      final h2 = ArchiveStore.archiveHash(root2, root1);
      expect(h1, isNot(equals(h2)));
    });

    test('load returns NoArchive when no file exists', () {
      final store = ArchiveStore(tempDir.path);
      final archive = store.load(root1, root2);
      expect(archive, isA<NoArchive>());
    });

    test('save and load roundtrip', () {
      final store = ArchiveStore(tempDir.path);

      final children = emptyNameMap();
      children[Name('file.txt')] = ArchiveFile(
        Props(permissions: 0x1ED, modTime: DateTime(2024, 6, 1), length: 500),
        FullFingerprint(Fingerprint(Uint8List.fromList(List.filled(16, 0xAA)))),
        const NoStamp(),
        RessStamp.zero,
      );
      final archive = ArchiveDir(
        Props(permissions: 0x1FF, modTime: DateTime(2024, 6, 1), length: 0),
        children,
      );

      store.save(root1, root2, archive);
      expect(store.exists(root1, root2), isTrue);

      final loaded = store.load(root1, root2);
      expect(loaded, isA<ArchiveDir>());
      final dir = loaded as ArchiveDir;
      expect(dir.children.length, 1);
      expect(dir.children[Name('file.txt')], isA<ArchiveFile>());
    });

    test('lock and unlock', () {
      final store = ArchiveStore(tempDir.path);
      expect(store.lock(root1, root2), isTrue);
      store.unlock(root1, root2);
    });

    test('delete removes archive files', () {
      final store = ArchiveStore(tempDir.path);
      store.save(root1, root2, const NoArchive());
      expect(store.exists(root1, root2), isTrue);
      store.delete(root1, root2);
      expect(store.exists(root1, root2), isFalse);
    });
  });
}
