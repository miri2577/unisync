import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Pattern', () {
    test('Name pattern matches final component', () {
      final p = Pattern.parse('Name *.tmp');
      expect(p.matches('file.tmp'), isTrue);
      expect(p.matches('dir/file.tmp'), isTrue);
      expect(p.matches('dir/sub/file.tmp'), isTrue);
      expect(p.matches('file.txt'), isFalse);
    });

    test('Path pattern matches full relative path', () {
      final p = Pattern.parse('Path a/b');
      expect(p.matches('a/b'), isTrue);
      expect(p.matches('a/b/c'), isFalse);
      expect(p.matches('x/a/b'), isFalse);
    });

    test('Path pattern with glob', () {
      final p = Pattern.parse('Path build/*');
      expect(p.matches('build/output'), isTrue);
      expect(p.matches('build/temp'), isTrue);
      expect(p.matches('src/build/output'), isFalse);
    });

    test('Regex pattern', () {
      final p = Pattern.parse(r'Regex .*\.bak$');
      expect(p.matches('file.bak'), isTrue);
      expect(p.matches('dir/file.bak'), isTrue);
      expect(p.matches('file.bak.old'), isFalse);
    });

    test('default (no prefix) treated as Name', () {
      final p = Pattern.parse('*.o');
      expect(p.type, PatternType.name);
      expect(p.matches('module.o'), isTrue);
      expect(p.matches('dir/module.o'), isTrue);
    });

    test('Name with alternation', () {
      final p = Pattern.parse('Name {CVS,*.cmo}');
      expect(p.matches('CVS'), isTrue);
      expect(p.matches('test.cmo'), isTrue);
      expect(p.matches('test.cmi'), isFalse);
    });

    test('Name .DS_Store', () {
      final p = Pattern.parse('Name .DS_Store');
      expect(p.matches('.DS_Store'), isTrue);
      expect(p.matches('dir/.DS_Store'), isTrue);
      expect(p.matches('DS_Store'), isFalse);
    });
  });

  group('Pred', () {
    test('empty pred matches nothing', () {
      final pred = Pred.empty();
      expect(pred.test('anything'), isFalse);
    });

    test('single pattern', () {
      final pred = Pred.fromStrings(['Name *.tmp']);
      expect(pred.test('file.tmp'), isTrue);
      expect(pred.test('file.txt'), isFalse);
    });

    test('multiple patterns (OR)', () {
      final pred = Pred.fromStrings([
        'Name *.tmp',
        'Name *.bak',
        'Name .DS_Store',
      ]);
      expect(pred.test('file.tmp'), isTrue);
      expect(pred.test('backup.bak'), isTrue);
      expect(pred.test('.DS_Store'), isTrue);
      expect(pred.test('readme.md'), isFalse);
    });

    test('mixed pattern types', () {
      final pred = Pred.fromStrings([
        'Name *.pyc',
        'Path .git',
        r'Regex .*/__pycache__/.*',
      ]);
      expect(pred.test('module.pyc'), isTrue);
      expect(pred.test('.git'), isTrue);
      expect(pred.test('src/__pycache__/cache.dat'), isTrue);
      expect(pred.test('src/main.py'), isFalse);
    });

    test('addSpec adds at runtime', () {
      final pred = Pred.empty();
      pred.addSpec('Name *.log');
      expect(pred.test('app.log'), isTrue);
      expect(pred.length, 1);
    });
  });
}
