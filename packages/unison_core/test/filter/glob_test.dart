import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  /// Helper: compile glob and test full match.
  bool matches(String glob, String input) {
    final regex = RegExp('^${globToRegex(glob)}\$');
    return regex.hasMatch(input);
  }

  group('Glob to regex', () {
    test('literal string', () {
      expect(matches('hello', 'hello'), isTrue);
      expect(matches('hello', 'world'), isFalse);
    });

    test('* matches any non-slash chars', () {
      expect(matches('*.txt', 'file.txt'), isTrue);
      expect(matches('*.txt', 'readme.txt'), isTrue);
      expect(matches('*.txt', 'file.md'), isFalse);
      expect(matches('*.txt', 'dir/file.txt'), isFalse); // * doesn't match /
    });

    test('? matches single non-slash char', () {
      expect(matches('?.txt', 'a.txt'), isTrue);
      expect(matches('?.txt', 'ab.txt'), isFalse);
      expect(matches('file.???', 'file.txt'), isTrue);
      expect(matches('file.???', 'file.c'), isFalse);
    });

    test('character class [abc]', () {
      expect(matches('[abc].txt', 'a.txt'), isTrue);
      expect(matches('[abc].txt', 'b.txt'), isTrue);
      expect(matches('[abc].txt', 'd.txt'), isFalse);
    });

    test('character class range [a-z]', () {
      expect(matches('[a-z].txt', 'f.txt'), isTrue);
      expect(matches('[a-z].txt', 'F.txt'), isFalse);
    });

    test('negated character class [!abc]', () {
      expect(matches('[!abc].txt', 'd.txt'), isTrue);
      expect(matches('[!abc].txt', 'a.txt'), isFalse);
    });

    test('alternation {a,b,c}', () {
      expect(matches('{foo,bar,baz}', 'foo'), isTrue);
      expect(matches('{foo,bar,baz}', 'bar'), isTrue);
      expect(matches('{foo,bar,baz}', 'qux'), isFalse);
    });

    test('alternation with extensions', () {
      expect(matches('*.{jpg,png,gif}', 'photo.jpg'), isTrue);
      expect(matches('*.{jpg,png,gif}', 'photo.png'), isTrue);
      expect(matches('*.{jpg,png,gif}', 'photo.bmp'), isFalse);
    });

    test('escaped special chars', () {
      expect(matches('file\\.txt', 'file.txt'), isTrue);
      expect(matches('file\\*', 'file*'), isTrue);
    });

    test('complex pattern', () {
      expect(matches('{CVS,*.cmo}', 'CVS'), isTrue);
      expect(matches('{CVS,*.cmo}', 'module.cmo'), isTrue);
      expect(matches('{CVS,*.cmo}', 'other'), isFalse);
    });

    test('dot in filename', () {
      expect(matches('.*', '.gitignore'), isTrue);
      expect(matches('.*', '.DS_Store'), isTrue);
    });

    test('regex special chars in glob are escaped', () {
      expect(matches('file(1).txt', 'file(1).txt'), isTrue);
      expect(matches('a+b.txt', 'a+b.txt'), isTrue);
      expect(matches('price\$5', 'price\$5'), isTrue);
    });
  });
}
