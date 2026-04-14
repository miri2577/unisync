import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Name', () {
    setUp(() {
      currentCaseMode = CaseMode.sensitive;
    });

    test('equality is case-sensitive by default', () {
      expect(Name('foo'), equals(Name('foo')));
      expect(Name('Foo'), isNot(equals(Name('foo'))));
    });

    test('equality is case-insensitive when mode set', () {
      currentCaseMode = CaseMode.insensitive;
      expect(Name('Foo'), equals(Name('foo')));
      expect(Name('FOO'), equals(Name('foo')));
    });

    test('compareTo respects case mode', () {
      currentCaseMode = CaseMode.sensitive;
      expect(Name('a').compareTo(Name('b')), lessThan(0));
      expect(Name('A').compareTo(Name('a')), isNot(0));

      currentCaseMode = CaseMode.insensitive;
      expect(Name('A').compareTo(Name('a')), equals(0));
    });

    test('hashCode matches equality contract', () {
      currentCaseMode = CaseMode.insensitive;
      expect(Name('Foo').hashCode, equals(Name('foo').hashCode));
    });

    test('toString returns raw value', () {
      expect(Name('MyFile.txt').toString(), 'MyFile.txt');
    });
  });
}
