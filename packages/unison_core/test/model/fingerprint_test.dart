import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Fingerprint', () {
    test('equality for identical bytes', () {
      final a = Fingerprint(Uint8List.fromList(List.filled(16, 0xAB)));
      final b = Fingerprint(Uint8List.fromList(List.filled(16, 0xAB)));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality for different bytes', () {
      final a = Fingerprint(Uint8List.fromList(List.filled(16, 0xAB)));
      final b = Fingerprint(Uint8List.fromList(List.filled(16, 0xCD)));
      expect(a, isNot(equals(b)));
    });

    test('dummy is all zeros', () {
      expect(Fingerprint.dummy.bytes, everyElement(0));
    });

    test('pseudo fingerprint is marked as pseudo', () {
      final fp = Fingerprint.pseudo('/some/path', 12345);
      expect(fp.isPseudo, isTrue);
    });

    test('real fingerprint is not pseudo', () {
      final fp = Fingerprint(Uint8List.fromList(List.filled(16, 0x42)));
      expect(fp.isPseudo, isFalse);
    });

    test('toHex produces 32-char string', () {
      final fp = Fingerprint(Uint8List.fromList(List.generate(16, (i) => i)));
      final hex = fp.toHex();
      expect(hex.length, 32);
      expect(hex, '000102030405060708090a0b0c0d0e0f');
    });

    test('shortHash uses first 3 bytes', () {
      final fp = Fingerprint(
        Uint8List.fromList([0x12, 0x34, 0x56, ...List.filled(13, 0)]),
      );
      expect(fp.shortHash, 0x12 | (0x34 << 8) | (0x56 << 16));
    });
  });

  group('FullFingerprint', () {
    test('equality without resource fork', () {
      final df = Fingerprint(Uint8List.fromList(List.filled(16, 1)));
      final a = FullFingerprint(df);
      final b = FullFingerprint(df);
      expect(a, equals(b));
    });

    test('equality with resource fork', () {
      final df = Fingerprint(Uint8List.fromList(List.filled(16, 1)));
      final rf = Fingerprint(Uint8List.fromList(List.filled(16, 2)));
      final a = FullFingerprint(df, rf);
      final b = FullFingerprint(df, rf);
      expect(a, equals(b));
    });

    test('inequality when resource fork differs', () {
      final df = Fingerprint(Uint8List.fromList(List.filled(16, 1)));
      final rf1 = Fingerprint(Uint8List.fromList(List.filled(16, 2)));
      final rf2 = Fingerprint(Uint8List.fromList(List.filled(16, 3)));
      expect(FullFingerprint(df, rf1), isNot(equals(FullFingerprint(df, rf2))));
    });
  });
}
