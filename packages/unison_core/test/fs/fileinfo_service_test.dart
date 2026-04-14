import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_fileinfo_test_');
    root = Fspath.fromLocal(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('FileinfoService', () {
    const svc = FileinfoService();

    test('returns absent for missing file', () {
      final info = svc.get(root, SyncPath.fromString('nope.txt'));
      expect(info.typ, FileType.absent);
    });

    test('returns file type and size for regular file', () {
      File('${tempDir.path}/hello.txt').writeAsStringSync('Hello World!');
      final info = svc.get(root, SyncPath.fromString('hello.txt'));
      expect(info.typ, FileType.file);
      expect(info.desc.length, 12);
    });

    test('returns directory type', () {
      Directory('${tempDir.path}/subdir').createSync();
      final info = svc.get(root, SyncPath.fromString('subdir'));
      expect(info.typ, FileType.directory);
    });

    test('modTime is reasonable', () {
      File('${tempDir.path}/f.txt').writeAsStringSync('x');
      final info = svc.get(root, SyncPath.fromString('f.txt'));
      final now = DateTime.now();
      expect(
        info.desc.modTime.difference(now).inSeconds.abs(),
        lessThan(5),
      );
    });

    test('getType returns only the type', () {
      File('${tempDir.path}/t.txt').writeAsStringSync('x');
      expect(svc.getType(root, SyncPath.fromString('t.txt')), FileType.file);
      expect(svc.getType(root, SyncPath.fromString('nope')), FileType.absent);
    });

    test('handles empty file', () {
      File('${tempDir.path}/empty.txt').writeAsStringSync('');
      final info = svc.get(root, SyncPath.fromString('empty.txt'));
      expect(info.typ, FileType.file);
      expect(info.desc.length, 0);
    });

    test('nested path works', () {
      Directory('${tempDir.path}/a/b').createSync(recursive: true);
      File('${tempDir.path}/a/b/deep.txt').writeAsStringSync('deep');
      final info = svc.get(root, SyncPath.fromString('a/b/deep.txt'));
      expect(info.typ, FileType.file);
      expect(info.desc.length, 4);
    });
  });
}
