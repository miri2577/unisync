import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unison_fpcache_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('FpCache', () {
    test('empty cache returns false for dataClearlyUnchanged', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        length: 100,
      );
      expect(cache.dataClearlyUnchanged('/some/path', props), isFalse);
    });

    test('returns true when props match cached entry', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1, 12, 0, 0),
        length: 100,
      );
      final fp = Fingerprint(Uint8List.fromList(List.filled(16, 0x42)));
      cache.put('/some/path', props, fp);

      expect(cache.dataClearlyUnchanged('/some/path', props), isTrue);
    });

    test('returns false when size changed', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        length: 100,
      );
      cache.put('/path', props, Fingerprint(Uint8List(16)));

      final changed = props.copyWith(length: 200);
      expect(cache.dataClearlyUnchanged('/path', changed), isFalse);
    });

    test('returns false when mtime changed', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        length: 100,
      );
      cache.put('/path', props, Fingerprint(Uint8List(16)));

      final changed = props.copyWith(modTime: DateTime(2024, 1, 2));
      expect(cache.dataClearlyUnchanged('/path', changed), isFalse);
    });

    test('getCachedFingerprint returns fp when unchanged', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        length: 100,
      );
      final fp = Fingerprint(Uint8List.fromList(List.filled(16, 0xAB)));
      cache.put('/path', props, fp);

      expect(cache.getCachedFingerprint('/path', props), equals(fp));
    });

    test('getCachedFingerprint returns null when changed', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        length: 100,
      );
      cache.put('/path', props, Fingerprint(Uint8List(16)));

      final changed = props.copyWith(length: 999);
      expect(cache.getCachedFingerprint('/path', changed), isNull);
    });

    test('invalidate removes entry', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        length: 100,
      );
      cache.put('/path', props, Fingerprint(Uint8List(16)));
      cache.invalidate('/path');
      expect(cache.dataClearlyUnchanged('/path', props), isFalse);
    });

    test('clear removes all entries', () {
      final cache = FpCache();
      final props = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 1),
        length: 100,
      );
      cache.put('/a', props, Fingerprint(Uint8List(16)));
      cache.put('/b', props, Fingerprint(Uint8List(16)));
      expect(cache.size, 2);
      cache.clear();
      expect(cache.size, 0);
    });

    test('save and load roundtrip', () {
      final cache = FpCache();
      final props1 = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 6, 15, 10, 30),
        length: 1234,
      );
      final fp1 = Fingerprint(Uint8List.fromList(List.filled(16, 0xAA)));
      cache.put('/path/file1.txt', props1, fp1);

      final props2 = Props(
        permissions: 0x1A4,
        modTime: DateTime(2024, 3, 20, 8, 0),
        length: 5678,
      );
      final fp2 = Fingerprint(Uint8List.fromList(List.filled(16, 0xBB)));
      cache.put('/path/file2.txt', props2, fp2);

      // Save
      final cacheFile = '${tempDir.path}/fpcache.bin';
      cache.saveToDisk(cacheFile);

      // Load into new cache
      final loaded = FpCache();
      loaded.loadFromDisk(cacheFile);
      expect(loaded.size, 2);

      // Verify entries
      expect(
        loaded.getCachedFingerprint('/path/file1.txt', props1),
        equals(fp1),
      );
      expect(
        loaded.getCachedFingerprint('/path/file2.txt', props2),
        equals(fp2),
      );
    });

    test('loadFromDisk handles missing file gracefully', () {
      final cache = FpCache();
      cache.loadFromDisk('${tempDir.path}/nonexistent.bin');
      expect(cache.size, 0);
    });

    test('loadFromDisk handles corrupted file gracefully', () {
      final file = File('${tempDir.path}/bad.bin');
      file.writeAsBytesSync(Uint8List.fromList([0xFF, 0xFE]));
      final cache = FpCache();
      cache.loadFromDisk(file.path);
      expect(cache.size, 0);
    });
  });
}
