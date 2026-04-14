import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Rolling checksum', () {
    test('checksumSubstring produces consistent results', () {
      final data = Uint8List.fromList('Hello World!'.codeUnits);
      final cs1 = checksumSubstring(data, 0, data.length);
      final cs2 = checksumSubstring(data, 0, data.length);
      expect(cs1, equals(cs2));
    });

    test('different data produces different checksums', () {
      final a = Uint8List.fromList('AAAA'.codeUnits);
      final b = Uint8List.fromList('BBBB'.codeUnits);
      expect(checksumSubstring(a, 0, 4), isNot(equals(checksumSubstring(b, 0, 4))));
    });

    test('checksumRoll matches fresh computation', () {
      final data = Uint8List.fromList('ABCDEFGHIJ'.codeUnits);
      const blockSize = 4;
      final table = checksumInit(blockSize);

      // Checksum of [A,B,C,D]
      final cs1 = checksumSubstring(data, 0, blockSize);

      // Roll to [B,C,D,E]
      final rolled = checksumRoll(table, cs1, data[0], data[blockSize]);

      // Fresh computation of [B,C,D,E]
      final fresh = checksumSubstring(data, 1, blockSize);

      expect(rolled, equals(fresh));
    });

    test('multiple rolls match fresh computation', () {
      final data = Uint8List.fromList('The quick brown fox jumps'.codeUnits);
      const blockSize = 5;
      final table = checksumInit(blockSize);

      var cs = checksumSubstring(data, 0, blockSize);
      for (var i = 1; i + blockSize <= data.length; i++) {
        cs = checksumRoll(table, cs, data[i - 1], data[i + blockSize - 1]);
        final fresh = checksumSubstring(data, i, blockSize);
        expect(cs, equals(fresh), reason: 'Mismatch at offset $i');
      }
    });

    test('checksumInit produces table of correct size', () {
      final table = checksumInit(1024);
      expect(table.table.length, 256);
      expect(table.blockSize, 1024);
    });

    test('checksum is non-negative (31-bit)', () {
      final data = Uint8List.fromList(List.generate(100, (i) => i * 7 % 256));
      final cs = checksumSubstring(data, 0, data.length);
      expect(cs, greaterThanOrEqualTo(0));
    });
  });
}
