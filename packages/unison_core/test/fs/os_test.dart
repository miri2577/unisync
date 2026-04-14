import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;
  late Fspath root;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_os_test_');
    root = Fspath.fromLocal(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('OsFs', () {
    const os = OsFs();

    test('childrenOf lists files sorted', () {
      File('${tempDir.path}/charlie.txt').writeAsStringSync('c');
      File('${tempDir.path}/alpha.txt').writeAsStringSync('a');
      File('${tempDir.path}/bravo.txt').writeAsStringSync('b');

      final children = os.childrenOf(root, SyncPath.empty);
      expect(children.map((n) => n.raw).toList(), [
        'alpha.txt',
        'bravo.txt',
        'charlie.txt',
      ]);
    });

    test('childrenOf returns empty for nonexistent dir', () {
      final children = os.childrenOf(root, SyncPath.fromString('nope'));
      expect(children, isEmpty);
    });

    test('childrenOf includes subdirectories', () {
      Directory('${tempDir.path}/subdir').createSync();
      File('${tempDir.path}/file.txt').writeAsStringSync('x');

      final children = os.childrenOf(root, SyncPath.empty);
      expect(children.length, 2);
      final names = children.map((n) => n.raw).toSet();
      expect(names, containsAll(['subdir', 'file.txt']));
    });

    test('exists detects files and dirs', () {
      File('${tempDir.path}/test.txt').writeAsStringSync('x');
      Directory('${tempDir.path}/dir').createSync();

      expect(os.exists(root, SyncPath.fromString('test.txt')), isTrue);
      expect(os.exists(root, SyncPath.fromString('dir')), isTrue);
      expect(os.exists(root, SyncPath.fromString('missing')), isFalse);
    });

    test('createDir creates nested directories', () {
      os.createDir(root, SyncPath.fromString('a/b/c'));
      expect(Directory('${tempDir.path}/a/b/c').existsSync(), isTrue);
    });

    test('delete removes file', () {
      File('${tempDir.path}/kill.txt').writeAsStringSync('x');
      os.delete(root, SyncPath.fromString('kill.txt'));
      expect(File('${tempDir.path}/kill.txt').existsSync(), isFalse);
    });

    test('delete removes directory recursively', () {
      Directory('${tempDir.path}/dir/sub').createSync(recursive: true);
      File('${tempDir.path}/dir/sub/f.txt').writeAsStringSync('x');
      os.delete(root, SyncPath.fromString('dir'));
      expect(Directory('${tempDir.path}/dir').existsSync(), isFalse);
    });

    test('rename moves file', () {
      File('${tempDir.path}/old.txt').writeAsStringSync('data');
      os.rename(root, SyncPath.fromString('old.txt'), SyncPath.fromString('new.txt'));
      expect(File('${tempDir.path}/old.txt').existsSync(), isFalse);
      expect(File('${tempDir.path}/new.txt').readAsStringSync(), 'data');
    });

    test('tempPath generates valid path', () {
      final tmp = os.tempPath(root, SyncPath.fromString('somefile.txt'));
      expect(tmp, contains('.unison'));
      expect(tmp, endsWith('.unison.tmp'));
      // Must be in same directory
      expect(tmp, startsWith(tempDir.path));
    });

    test('tempPath stays under 143 byte filename', () {
      final tmp = os.tempPath(root, SyncPath.fromString('x' * 200));
      final basename = tmp.split(Platform.pathSeparator).last;
      expect(basename.length, lessThanOrEqualTo(143));
    });
  });
}
