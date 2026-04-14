import 'dart:io';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_profile_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void writeProfile(String name, String content) {
    File('${tempDir.path}/$name.prf').writeAsStringSync(content);
  }

  group('ProfileParser', () {
    test('parses simple key=value', () {
      writeProfile('simple', '''
root = /home/user
root = /backup
batch = true
''');
      final parser = ProfileParser(tempDir.path);
      final (entries, errors) = parser.parseFile('simple');
      expect(errors, isEmpty);
      expect(entries.length, 3);
      expect(entries[0].name, 'root');
      expect(entries[0].value, '/home/user');
      expect(entries[1].name, 'root');
      expect(entries[1].value, '/backup');
      expect(entries[2].name, 'batch');
      expect(entries[2].value, 'true');
    });

    test('ignores comments and blank lines', () {
      writeProfile('comments', '''
# This is a comment
root = /data

# Another comment

batch = false
''');
      final parser = ProfileParser(tempDir.path);
      final (entries, errors) = parser.parseFile('comments');
      expect(errors, isEmpty);
      expect(entries.length, 2);
    });

    test('handles spaces around =', () {
      writeProfile('spaces', 'root   =   /path/with spaces  ');
      final parser = ProfileParser(tempDir.path);
      final (entries, errors) = parser.parseFile('spaces');
      expect(errors, isEmpty);
      expect(entries[0].name, 'root');
      expect(entries[0].value, '/path/with spaces');
    });

    test('reports error for lines without =', () {
      writeProfile('bad', 'this is invalid');
      final parser = ProfileParser(tempDir.path);
      final (_, errors) = parser.parseFile('bad');
      expect(errors.length, 1);
      expect(errors[0].message, contains("no '='"));
    });

    test('include directive works', () {
      writeProfile('main', '''
root = /a
include common
root = /b
''');
      writeProfile('common', '''
ignore = Name *.tmp
ignore = Name .git
''');
      final parser = ProfileParser(tempDir.path);
      final (entries, errors) = parser.parseFile('main');
      expect(errors, isEmpty);
      expect(entries.length, 4);
      expect(entries[0].value, '/a');
      expect(entries[1].name, 'ignore');
      expect(entries[1].value, 'Name *.tmp');
      expect(entries[2].name, 'ignore');
      expect(entries[3].value, '/b');
    });

    test('include? silently skips missing files', () {
      writeProfile('optional', '''
root = /data
include? nonexistent
batch = true
''');
      final parser = ProfileParser(tempDir.path);
      final (entries, errors) = parser.parseFile('optional');
      expect(errors, isEmpty);
      expect(entries.length, 2);
    });

    test('include reports error for missing required file', () {
      writeProfile('missing', 'include nonexistent');
      final parser = ProfileParser(tempDir.path);
      final (_, errors) = parser.parseFile('missing');
      expect(errors.length, 1);
      expect(errors[0].message, contains('not found'));
    });

    test('circular include detected', () {
      writeProfile('loop1', 'include loop2');
      writeProfile('loop2', 'include loop1');
      final parser = ProfileParser(tempDir.path);
      final (_, errors) = parser.parseFile('loop1');
      expect(errors.any((e) => e.message.contains('Circular')), isTrue);
    });

    test('loadProfile applies to registry', () {
      writeProfile('load', '''
root = /home/user
root = ssh://server/data
batch = true
ignore = Name *.o
ignore = Name .DS_Store
label = My Sync
''');
      final parser = ProfileParser(tempDir.path);
      final prefs = UnisonPrefs();
      final errors = parser.loadProfile('load', prefs.registry);
      expect(errors, isEmpty);
      expect(prefs.root.value, ['/home/user', 'ssh://server/data']);
      expect(prefs.batch.value, isTrue);
      expect(prefs.ignore.value, ['Name *.o', 'Name .DS_Store']);
      expect(prefs.label.value, 'My Sync');
    });

    test('listProfiles finds .prf files', () {
      writeProfile('alpha', 'root = /a');
      writeProfile('beta', 'root = /b');
      File('${tempDir.path}/notaprofile.txt').writeAsStringSync('x');

      final parser = ProfileParser(tempDir.path);
      final profiles = parser.listProfiles();
      expect(profiles, containsAll(['alpha', 'beta']));
      expect(profiles, isNot(contains('notaprofile')));
    });

    test('file not found returns error', () {
      final parser = ProfileParser(tempDir.path);
      final (_, errors) = parser.parseFile('nonexistent');
      expect(errors.length, 1);
    });
  });

  group('scanProfile', () {
    test('extracts metadata', () {
      writeProfile('meta', '''
root = /home/user
root = ssh://server/data
label = My Documents
key = 1
batch = true
''');
      final info = scanProfile(tempDir.path, 'meta');
      expect(info, isNotNull);
      expect(info!.name, 'meta');
      expect(info.roots, ['/home/user', 'ssh://server/data']);
      expect(info.label, 'My Documents');
      expect(info.key, '1');
    });

    test('returns null for missing profile', () {
      final info = scanProfile(tempDir.path, 'missing');
      expect(info, isNull);
    });
  });

  group('UnisonPrefs', () {
    test('all standard prefs registered', () {
      final prefs = UnisonPrefs();
      expect(prefs.registry.get('root'), isNotNull);
      expect(prefs.registry.get('batch'), isNotNull);
      expect(prefs.registry.get('ignore'), isNotNull);
      expect(prefs.registry.get('merge'), isNotNull);
      expect(prefs.registry.get('label'), isNotNull);
      expect(prefs.registry.get('fat'), isNotNull);
    });

    test('defaults are correct', () {
      final prefs = UnisonPrefs();
      expect(prefs.batch.value, isFalse);
      expect(prefs.fastCheck.value, isTrue);
      expect(prefs.times.value, isTrue);
      expect(prefs.links.value, isTrue);
      expect(prefs.maxBackups.value, 2);
      expect(prefs.height.value, 15);
      expect(prefs.sshCmd.value, 'ssh');
      expect(prefs.confirmBigDeletes.value, isTrue);
    });
  });
}
