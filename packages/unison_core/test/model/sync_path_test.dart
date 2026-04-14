import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  setUp(() {
    currentCaseMode = CaseMode.sensitive;
  });

  group('SyncPath', () {
    test('fromString parses simple path', () {
      final p = SyncPath.fromString('a/b/c');
      expect(p.segments.length, 3);
      expect(p.segments[0], Name('a'));
      expect(p.segments[2], Name('c'));
    });

    test('fromString rejects absolute paths', () {
      expect(() => SyncPath.fromString('/foo'), throwsArgumentError);
    });

    test('fromString rejects dot components', () {
      expect(() => SyncPath.fromString('a/../b'), throwsArgumentError);
      expect(() => SyncPath.fromString('./a'), throwsArgumentError);
    });

    test('fromString handles empty string', () {
      expect(SyncPath.fromString(''), equals(SyncPath.empty));
    });

    test('fromString strips trailing slashes', () {
      final p = SyncPath.fromString('a/b/');
      expect(p.segments.length, 2);
    });

    test('fromString converts backslashes', () {
      final p = SyncPath.fromString('a\\b\\c');
      expect(p.toString(), 'a/b/c');
    });

    test('child appends a name', () {
      final p = SyncPath.fromString('a/b');
      final child = p.child(Name('c'));
      expect(child.toString(), 'a/b/c');
    });

    test('parent returns parent path', () {
      final p = SyncPath.fromString('a/b/c');
      expect(p.parent.toString(), 'a/b');
    });

    test('parent of root is null', () {
      expect(SyncPath.empty.parent, isNull);
    });

    test('finalName returns last component', () {
      expect(SyncPath.fromString('a/b/c').finalName, Name('c'));
      expect(SyncPath.empty.finalName, isNull);
    });

    test('deconstruct splits into first and rest', () {
      final p = SyncPath.fromString('a/b/c');
      final (first, rest) = p.deconstruct()!;
      expect(first, Name('a'));
      expect(rest.toString(), 'b/c');
    });

    test('concat joins paths', () {
      final a = SyncPath.fromString('a/b');
      final b = SyncPath.fromString('c/d');
      expect(a.concat(b).toString(), 'a/b/c/d');
    });

    test('equality works', () {
      expect(SyncPath.fromString('a/b'), equals(SyncPath.fromString('a/b')));
      expect(
        SyncPath.fromString('a/b'),
        isNot(equals(SyncPath.fromString('a/c'))),
      );
    });

    test('compareTo sorts lexicographically by segment', () {
      final paths = [
        SyncPath.fromString('b'),
        SyncPath.fromString('a/b'),
        SyncPath.fromString('a'),
        SyncPath.fromString('a/a'),
      ]..sort();
      expect(paths.map((p) => p.toString()).toList(), [
        'a',
        'a/a',
        'a/b',
        'b',
      ]);
    });
  });
}
