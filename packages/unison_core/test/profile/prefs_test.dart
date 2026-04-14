import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Pref', () {
    test('has default value', () {
      final p = Pref<bool>(name: 'test', doc: 'doc', defaultValue: false);
      expect(p.value, isFalse);
      expect(p.isSet, isFalse);
    });

    test('setting marks as set', () {
      final p = Pref<String>(name: 'test', doc: 'doc', defaultValue: '');
      p.value = 'hello';
      expect(p.value, 'hello');
      expect(p.isSet, isTrue);
    });

    test('reset restores default', () {
      final p = Pref<int>(name: 'test', doc: 'doc', defaultValue: 42);
      p.value = 99;
      p.reset();
      expect(p.value, 42);
      expect(p.isSet, isFalse);
    });
  });

  group('ListPref', () {
    test('starts empty', () {
      final p = ListPref(name: 'test', doc: 'doc');
      expect(p.value, isEmpty);
    });

    test('add accumulates values', () {
      final p = ListPref(name: 'test', doc: 'doc');
      p.add('a');
      p.add('b');
      p.add('c');
      expect(p.value, ['a', 'b', 'c']);
    });

    test('reset clears list', () {
      final p = ListPref(name: 'test', doc: 'doc');
      p.add('x');
      p.reset();
      expect(p.value, isEmpty);
    });
  });

  group('PrefsRegistry', () {
    test('createBool registers and returns pref', () {
      final reg = PrefsRegistry();
      final p = reg.createBool(name: 'flag', doc: 'A flag', defaultValue: true);
      expect(p.value, isTrue);
      expect(reg.get('flag'), same(p));
    });

    test('setFromString parses bool', () {
      final reg = PrefsRegistry();
      reg.createBool(name: 'b', doc: 'doc');
      reg.setFromString('b', 'true');
      expect((reg.get('b') as Pref<bool>).value, isTrue);
    });

    test('setFromString parses int', () {
      final reg = PrefsRegistry();
      reg.createInt(name: 'n', doc: 'doc');
      reg.setFromString('n', '42');
      expect((reg.get('n') as Pref<int>).value, 42);
    });

    test('setFromString parses string', () {
      final reg = PrefsRegistry();
      reg.createString(name: 's', doc: 'doc');
      reg.setFromString('s', 'hello world');
      expect((reg.get('s') as Pref<String>).value, 'hello world');
    });

    test('setFromString accumulates list', () {
      final reg = PrefsRegistry();
      reg.createStringList(name: 'list', doc: 'doc');
      reg.setFromString('list', 'a');
      reg.setFromString('list', 'b');
      expect((reg.get('list') as ListPref).value, ['a', 'b']);
    });

    test('resetAll resets all prefs', () {
      final reg = PrefsRegistry();
      reg.createBool(name: 'a', doc: 'd', defaultValue: false);
      reg.createString(name: 'b', doc: 'd', defaultValue: 'x');
      reg.setFromString('a', 'true');
      reg.setFromString('b', 'y');
      reg.resetAll();
      expect((reg.get('a') as Pref<bool>).value, isFalse);
      expect((reg.get('b') as Pref<String>).value, 'x');
    });

    test('serialize outputs set preferences', () {
      final reg = PrefsRegistry();
      reg.createString(name: 'root', doc: 'd');
      reg.createBool(name: 'batch', doc: 'd');
      reg.setFromString('root', '/home/user');
      reg.setFromString('batch', 'true');
      final output = reg.serialize();
      expect(output, contains('root = /home/user'));
      expect(output, contains('batch = true'));
    });

    test('serialize outputs list prefs as multiple lines', () {
      final reg = PrefsRegistry();
      reg.createStringList(name: 'ignore', doc: 'd');
      reg.setFromString('ignore', 'Name *.tmp');
      reg.setFromString('ignore', 'Name .git');
      final output = reg.serialize();
      expect(output, contains('ignore = Name *.tmp'));
      expect(output, contains('ignore = Name .git'));
    });

    test('byCategory filters correctly', () {
      final reg = PrefsRegistry();
      reg.createBool(
        name: 'a', doc: 'd', category: PrefCategory.sync);
      reg.createBool(
        name: 'b', doc: 'd', category: PrefCategory.ui);
      reg.createBool(
        name: 'c', doc: 'd', category: PrefCategory.sync);
      expect(reg.byCategory(PrefCategory.sync).length, 2);
      expect(reg.byCategory(PrefCategory.ui).length, 1);
    });

    test('unknown pref name in setFromString is ignored', () {
      final reg = PrefsRegistry();
      reg.setFromString('nonexistent', 'value'); // no throw
    });
  });
}
