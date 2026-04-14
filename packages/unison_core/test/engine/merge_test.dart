import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('MergeExecutor.parseMergeSpec', () {
    test('parses valid spec', () {
      final result =
          MergeExecutor.parseMergeSpec('Name *.txt -> diff3 -m CURRENT1 CURRENTARCH CURRENT2 > NEW');
      expect(result, isNotNull);
      expect(result!.$1, 'Name *.txt');
      expect(result.$2, 'diff3 -m CURRENT1 CURRENTARCH CURRENT2 > NEW');
    });

    test('returns null for spec without arrow', () {
      final result = MergeExecutor.parseMergeSpec('no arrow here');
      expect(result, isNull);
    });

    test('returns null for empty pattern', () {
      final result = MergeExecutor.parseMergeSpec('-> some command');
      expect(result, isNull);
    });

    test('returns null for empty command', () {
      final result = MergeExecutor.parseMergeSpec('Name *.txt ->');
      // trim() of empty string
      expect(result, isNull);
    });

    test('handles complex merge spec', () {
      final result = MergeExecutor.parseMergeSpec(
          'Regex .* -> opendiff CURRENT1 CURRENT2 -ancestor CURRENTARCH -merge NEW');
      expect(result, isNotNull);
      expect(result!.$1, 'Regex .*');
      expect(result.$2, contains('opendiff'));
    });
  });
}
