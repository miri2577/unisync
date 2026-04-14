import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unison_core/unison_core.dart';

void main() {
  group('Marshal', () {
    test('int roundtrip for small values', () {
      final enc = MarshalEncoder();
      enc.writeInt(0);
      enc.writeInt(1);
      enc.writeInt(127);

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readInt(), 0);
      expect(dec.readInt(), 1);
      expect(dec.readInt(), 127);
    });

    test('int roundtrip for large values', () {
      final enc = MarshalEncoder();
      enc.writeInt(128);
      enc.writeInt(16384);
      enc.writeInt(1000000);

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readInt(), 128);
      expect(dec.readInt(), 16384);
      expect(dec.readInt(), 1000000);
    });

    test('signed int roundtrip', () {
      final enc = MarshalEncoder();
      enc.writeSignedInt(0);
      enc.writeSignedInt(42);
      enc.writeSignedInt(-42);
      enc.writeSignedInt(-1);

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readSignedInt(), 0);
      expect(dec.readSignedInt(), 42);
      expect(dec.readSignedInt(), -42);
      expect(dec.readSignedInt(), -1);
    });

    test('int64 roundtrip', () {
      final enc = MarshalEncoder();
      enc.writeInt64(0);
      enc.writeInt64(0x7FFFFFFFFFFFFFFF);
      enc.writeInt64(-1);

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readInt64(), 0);
      expect(dec.readInt64(), 0x7FFFFFFFFFFFFFFF);
      expect(dec.readInt64(), -1);
    });

    test('string roundtrip', () {
      final enc = MarshalEncoder();
      enc.writeString('');
      enc.writeString('hello');
      enc.writeString('Ünïcödé');

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readString(), '');
      expect(dec.readString(), 'hello');
      expect(dec.readString(), 'Ünïcödé');
    });

    test('byte array roundtrip', () {
      final enc = MarshalEncoder();
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      enc.writeByteArray(data);

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readByteArray(), data);
    });

    test('bool roundtrip', () {
      final enc = MarshalEncoder();
      enc.writeBool(true);
      enc.writeBool(false);

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readBool(), true);
      expect(dec.readBool(), false);
    });

    test('DateTime roundtrip', () {
      final enc = MarshalEncoder();
      final now = DateTime(2024, 6, 15, 12, 30, 45);
      enc.writeDateTime(now);

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readDateTime(), now);
    });

    test('mixed types roundtrip', () {
      final enc = MarshalEncoder();
      enc.writeTag(3);
      enc.writeString('test');
      enc.writeInt(42);
      enc.writeBool(true);
      enc.writeByteArray(Uint8List.fromList([0xDE, 0xAD]));

      final dec = MarshalDecoder(enc.toBytes());
      expect(dec.readTag(), 3);
      expect(dec.readString(), 'test');
      expect(dec.readInt(), 42);
      expect(dec.readBool(), true);
      expect(dec.readByteArray(), Uint8List.fromList([0xDE, 0xAD]));
      expect(dec.hasMore, isFalse);
    });

    test('throws on read past end', () {
      final dec = MarshalDecoder(Uint8List(0));
      expect(() => dec.readByte(), throwsStateError);
    });
  });
}
