import 'dart:io' show Platform;

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Fspath', () {
    test('rejects empty path', () {
      expect(() => Fspath.fromLocal(''), throwsArgumentError);
    });

    test('child appends name', () {
      final root = Fspath.fromLocal(Platform.isWindows ? 'C:/' : '/');
      final child = root.child(Name('foo'));
      if (Platform.isWindows) {
        expect(child.toString(), 'C:/foo');
      } else {
        expect(child.toString(), '/foo');
      }
    });

    test('concat joins with SyncPath', () {
      final root = Fspath.fromLocal(Platform.isWindows ? 'C:/' : '/home');
      final rel = SyncPath.fromString('a/b');
      final result = root.concat(rel);
      expect(result.toString(), contains('a/b'));
    });

    test('parent of root is null', () {
      final root = Fspath.fromLocal(Platform.isWindows ? 'C:/' : '/');
      expect(root.parent, isNull);
    });

    test('parent works for non-root', () {
      final p = Fspath.fromLocal(
        Platform.isWindows ? 'C:/foo/bar' : '/foo/bar',
      );
      expect(p.parent?.toString(), contains('foo'));
    });

    test('finalName returns last component', () {
      final p = Fspath.fromLocal(
        Platform.isWindows ? 'C:/foo/bar' : '/foo/bar',
      );
      expect(p.finalName, 'bar');
    });

    test('equality', () {
      final a = Fspath.fromLocal(Platform.isWindows ? 'C:/foo' : '/foo');
      final b = Fspath.fromLocal(Platform.isWindows ? 'C:/foo' : '/foo');
      expect(a, equals(b));
    });

    if (Platform.isWindows) {
      test('converts backslashes', () {
        final p = Fspath.fromLocal('C:\\Users\\test');
        expect(p.toString(), 'C:/Users/test');
      });

      test('toLocal uses backslashes on Windows', () {
        final p = Fspath.fromLocal('C:/Users/test');
        expect(p.toLocal(), 'C:\\Users\\test');
      });

      test('rejects relative paths on Windows', () {
        expect(() => Fspath.fromLocal('relative/path'), throwsArgumentError);
      });
    }
  });
}
