import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

/// Generate test data of given size.
Uint8List _genData(int size, [int seed = 0]) {
  final rng = Random(seed);
  return Uint8List.fromList(List.generate(size, (_) => rng.nextInt(256)));
}

void main() {
  const rsync = Rsync();

  group('Rsync block size', () {
    test('computeBlockSize returns reasonable values', () {
      expect(Rsync.computeBlockSize(0), 700);
      expect(Rsync.computeBlockSize(1000), greaterThanOrEqualTo(700));
      expect(Rsync.computeBlockSize(1000000), greaterThanOrEqualTo(700));
      expect(Rsync.computeBlockSize(1000000), lessThanOrEqualTo(131072));
    });

    test('computeChecksumSize returns 2-16', () {
      final cs = Rsync.computeChecksumSize(10000, 10000, 1024);
      expect(cs, greaterThanOrEqualTo(2));
      expect(cs, lessThanOrEqualTo(16));
    });
  });

  group('Rsync delta transfer', () {
    test('identical files → only block tokens', () {
      final data = _genData(10000);
      final tokens = rsync.computeDelta(data, Uint8List.fromList(data));
      final blockSize = Rsync.computeBlockSize(data.length);
      final result = rsync.decompress(blockSize, data, tokens);
      expect(result, equals(data));

      // Most tokens should be block references
      final blockTokens = tokens.whereType<BlockToken>().length;
      expect(blockTokens, greaterThan(0));
    });

    test('small modification → mostly block tokens + small string', () {
      final oldData = _genData(10000, 42);
      final newData = Uint8List.fromList(oldData);
      // Modify a few bytes in the middle
      newData[5000] = 0xFF;
      newData[5001] = 0xFE;
      newData[5002] = 0xFD;

      final tokens = rsync.computeDelta(oldData, newData);
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, equals(newData));
    });

    test('appended data → blocks + trailing string', () {
      final oldData = _genData(8000, 1);
      final appendix = _genData(2000, 2);
      final newData = Uint8List.fromList([...oldData, ...appendix]);

      final tokens = rsync.computeDelta(oldData, newData);
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, equals(newData));
    });

    test('prepended data → string + blocks', () {
      final oldData = _genData(8000, 3);
      final prefix = _genData(2000, 4);
      final newData = Uint8List.fromList([...prefix, ...oldData]);

      final tokens = rsync.computeDelta(oldData, newData);
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, equals(newData));
    });

    test('inserted block in middle → reconstructs correctly', () {
      final oldData = _genData(10000, 5);
      final insertion = _genData(500, 6);
      final newData = Uint8List.fromList([
        ...oldData.sublist(0, 5000),
        ...insertion,
        ...oldData.sublist(5000),
      ]);

      final tokens = rsync.computeDelta(oldData, newData);
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, equals(newData));
    });

    test('deleted block in middle → reconstructs correctly', () {
      final oldData = _genData(10000, 7);
      final newData = Uint8List.fromList([
        ...oldData.sublist(0, 3000),
        ...oldData.sublist(5000),
      ]);

      final tokens = rsync.computeDelta(oldData, newData);
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, equals(newData));
    });

    test('completely different file → all string tokens', () {
      final oldData = _genData(5000, 10);
      final newData = _genData(5000, 20);

      final tokens = rsync.computeDelta(oldData, newData);
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, equals(newData));
    });

    test('empty new file → empty result', () {
      final oldData = _genData(5000);
      final tokens = rsync.computeDelta(oldData, Uint8List(0));
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, isEmpty);
    });

    test('empty old file → full string transfer', () {
      final newData = _genData(5000);
      final tokens = rsync.computeDelta(Uint8List(0), newData);
      final blockSize = Rsync.computeBlockSize(0);
      final result = rsync.decompress(blockSize, Uint8List(0), tokens);
      expect(result, equals(newData));
    });

    test('small file below threshold → full transfer', () {
      final oldData = Uint8List.fromList('short'.codeUnits);
      final newData = Uint8List.fromList('small'.codeUnits);
      final tokens = rsync.computeDelta(oldData, newData);
      // Should be just a string token + EOF
      expect(tokens.whereType<StringToken>().length, 1);
      expect(tokens.whereType<BlockToken>().length, 0);
    });
  });

  group('Rsync efficiency', () {
    test('localized change in large file → delta smaller than full', () {
      final oldData = _genData(100000, 99);
      final newData = Uint8List.fromList(oldData);
      // Modify a contiguous 1KB region (simulates realistic edit)
      for (var i = 50000; i < 51000; i++) {
        newData[i] = (newData[i] + 1) % 256;
      }

      final tokens = rsync.computeDelta(oldData, newData);

      // Count literal bytes transferred
      var literalBytes = 0;
      for (final t in tokens) {
        if (t is StringToken) literalBytes += t.data.length;
      }

      // Should be much less than the full file
      expect(literalBytes, lessThan(newData.length * 0.3),
          reason: 'Delta should be <30% of full file for localized change');

      // Verify reconstruction
      final blockSize = Rsync.computeBlockSize(oldData.length);
      final result = rsync.decompress(blockSize, oldData, tokens);
      expect(result, equals(newData));
    });
  });
}
