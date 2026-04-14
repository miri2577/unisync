import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Props', () {
    test('identical props are similar', () {
      final p = Props(
        permissions: 0x1ED, // 0o755
        modTime: DateTime(2024, 1, 15, 10, 30),
        length: 1234,
      );
      expect(p.similar(p), isTrue);
    });

    test('different length is not similar', () {
      final a = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 15),
        length: 100,
      );
      final b = a.copyWith(length: 200);
      expect(a.similar(b), isFalse);
    });

    test('different modTime is not similar', () {
      final a = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 15, 10, 30, 0),
        length: 100,
      );
      final b = a.copyWith(modTime: DateTime(2024, 1, 15, 10, 30, 5));
      expect(a.similar(b), isFalse);
    });

    test('FAT tolerance allows 2-second difference', () {
      final a = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 15, 10, 30, 0),
        length: 100,
      );
      final b = a.copyWith(modTime: DateTime(2024, 1, 15, 10, 30, 2));
      expect(a.similar(b, fatTolerance: false), isFalse);
      expect(a.similar(b, fatTolerance: true), isTrue);
    });

    test('FAT tolerance does not allow 3-second difference', () {
      final a = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024, 1, 15, 10, 30, 0),
        length: 100,
      );
      final b = a.copyWith(modTime: DateTime(2024, 1, 15, 10, 30, 3));
      expect(a.similar(b, fatTolerance: true), isFalse);
    });

    test('copyWith preserves unset fields', () {
      final a = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024),
        length: 100,
      );
      final b = a.copyWith(length: 200);
      expect(b.permissions, 0x1ED);
      expect(b.length, 200);
    });

    test('equality', () {
      final a = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024),
        length: 100,
      );
      final b = Props(
        permissions: 0x1ED,
        modTime: DateTime(2024),
        length: 100,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
