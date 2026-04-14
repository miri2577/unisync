import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  setUp(() {
    currentCaseMode = CaseMode.sensitive;
  });

  group('IgnoreFilter', () {
    test('empty filter ignores nothing', () {
      final filter = IgnoreFilter();
      expect(filter.shouldIgnore(SyncPath.fromString('file.txt')), isFalse);
    });

    test('never ignores root', () {
      final filter = IgnoreFilter(ignorePatterns: ['Name *']);
      expect(filter.shouldIgnore(SyncPath.empty), isFalse);
    });

    test('built-in patterns: .unison temp files', () {
      final filter = IgnoreFilter();
      expect(
        filter.shouldIgnore(SyncPath.fromString('.unison.abcdef.unison.tmp')),
        isTrue,
      );
    });

    test('user ignore patterns', () {
      final filter = IgnoreFilter(ignorePatterns: [
        'Name *.tmp',
        'Name *.bak',
        'Path .git',
      ]);
      expect(filter.shouldIgnore(SyncPath.fromString('file.tmp')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('dir/file.bak')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('.git')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('src/main.dart')), isFalse);
    });

    test('ignorenot overrides ignore', () {
      final filter = IgnoreFilter(
        ignorePatterns: ['Name *.log'],
        ignoreNotPatterns: ['Name important.log'],
      );
      expect(filter.shouldIgnore(SyncPath.fromString('debug.log')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('important.log')), isFalse);
    });

    test('ignorenot takes precedence over built-in', () {
      final filter = IgnoreFilter(
        ignoreNotPatterns: ['Name .unison.keep.unison.tmp'],
      );
      expect(
        filter.shouldIgnore(SyncPath.fromString('.unison.keep.unison.tmp')),
        isFalse,
      );
    });

    test('nested paths checked against Name patterns', () {
      final filter = IgnoreFilter(ignorePatterns: ['Name __pycache__']);
      expect(
        filter.shouldIgnore(SyncPath.fromString('src/__pycache__')),
        isTrue,
      );
      expect(
        filter.shouldIgnore(SyncPath.fromString('a/b/__pycache__')),
        isTrue,
      );
    });

    test('shouldIgnoreString works with raw strings', () {
      final filter = IgnoreFilter(ignorePatterns: ['Name *.o']);
      expect(filter.shouldIgnoreString('module.o'), isTrue);
      expect(filter.shouldIgnoreString('dir/module.o'), isTrue);
      expect(filter.shouldIgnoreString('module.c'), isFalse);
    });

    test('addIgnore adds at runtime', () {
      final filter = IgnoreFilter();
      expect(filter.shouldIgnore(SyncPath.fromString('test.log')), isFalse);
      filter.addIgnore('Name *.log');
      expect(filter.shouldIgnore(SyncPath.fromString('test.log')), isTrue);
    });

    test('fromPrefs factory', () {
      final filter = IgnoreFilter.fromPrefs(
        ['Name *.tmp', 'Path build'],
        ['Name keep.tmp'],
      );
      expect(filter.shouldIgnore(SyncPath.fromString('x.tmp')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('keep.tmp')), isFalse);
      expect(filter.shouldIgnore(SyncPath.fromString('build')), isTrue);
    });

    test('complex real-world pattern set', () {
      final filter = IgnoreFilter(ignorePatterns: [
        'Name {*.o,*.cmo,*.cmi,*.cmx}',
        'Name .DS_Store',
        'Name {CVS,.svn,.git}',
        r'Regex .*~$',
        'Path node_modules',
      ]);

      expect(filter.shouldIgnore(SyncPath.fromString('main.o')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('lib/mod.cmo')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('.DS_Store')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('.git')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('file.txt~')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('node_modules')), isTrue);
      expect(filter.shouldIgnore(SyncPath.fromString('src/main.ml')), isFalse);
      expect(filter.shouldIgnore(SyncPath.fromString('README.md')), isFalse);
    });
  });
}
