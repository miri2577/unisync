/// Binary serialization helpers for archive persistence.
///
/// Custom binary format for encoding/decoding archive trees, fingerprints,
/// props, and other sync engine data structures.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Binary encoder — writes to a growing byte buffer.
class MarshalEncoder {
  final BytesBuilder _buf = BytesBuilder(copy: false);

  /// Write a single byte.
  void writeByte(int b) => _buf.addByte(b);

  /// Write raw bytes.
  void writeBytes(Uint8List data) => _buf.add(data);

  /// Write a variable-length integer (LEB128-like encoding).
  ///
  /// Positive integers only. Uses 7 bits per byte, MSB = continuation.
  void writeInt(int value) {
    assert(value >= 0, 'writeInt only supports non-negative values');
    while (value >= 0x80) {
      _buf.addByte((value & 0x7F) | 0x80);
      value >>= 7;
    }
    _buf.addByte(value & 0x7F);
  }

  /// Write a signed integer.
  void writeSignedInt(int value) {
    if (value >= 0) {
      writeInt(value * 2);
    } else {
      writeInt((-value) * 2 - 1);
    }
  }

  /// Write an int64 value as 8 bytes (little-endian).
  void writeInt64(int value) {
    final data = Uint8List(8);
    final bd = ByteData.sublistView(data);
    bd.setInt64(0, value, Endian.little);
    _buf.add(data);
  }

  /// Write a length-prefixed UTF-8 string.
  void writeString(String s) {
    final bytes = utf8.encode(s);
    writeInt(bytes.length);
    _buf.add(bytes);
  }

  /// Write a length-prefixed byte array.
  void writeByteArray(Uint8List data) {
    writeInt(data.length);
    _buf.add(data);
  }

  /// Write a boolean.
  void writeBool(bool b) => _buf.addByte(b ? 1 : 0);

  /// Write a DateTime as milliseconds since epoch.
  void writeDateTime(DateTime dt) {
    writeInt64(dt.millisecondsSinceEpoch);
  }

  /// Write a tagged union discriminator.
  void writeTag(int tag) => writeByte(tag);

  /// Get the encoded bytes.
  Uint8List toBytes() => _buf.toBytes();
}

/// Binary decoder — reads from a byte buffer.
class MarshalDecoder {
  final Uint8List _data;
  int _pos = 0;

  MarshalDecoder(this._data);

  /// Current read position.
  int get position => _pos;

  /// Whether there's more data to read.
  bool get hasMore => _pos < _data.length;

  /// Read a single byte.
  int readByte() {
    if (_pos >= _data.length) throw StateError('Unexpected end of data');
    return _data[_pos++];
  }

  /// Read [length] bytes.
  Uint8List readBytes(int length) {
    if (_pos + length > _data.length) {
      throw StateError('Unexpected end of data');
    }
    final result = Uint8List.sublistView(_data, _pos, _pos + length);
    _pos += length;
    return result;
  }

  /// Read a variable-length integer.
  int readInt() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = readByte();
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  /// Read a signed integer.
  int readSignedInt() {
    final v = readInt();
    if (v.isEven) {
      return v ~/ 2;
    } else {
      return -((v + 1) ~/ 2);
    }
  }

  /// Read an int64 (8 bytes, little-endian).
  int readInt64() {
    final data = readBytes(8);
    return ByteData.sublistView(data).getInt64(0, Endian.little);
  }

  /// Read a length-prefixed UTF-8 string.
  String readString() {
    final length = readInt();
    final bytes = readBytes(length);
    return utf8.decode(bytes);
  }

  /// Read a length-prefixed byte array.
  Uint8List readByteArray() {
    final length = readInt();
    return readBytes(length);
  }

  /// Read a boolean.
  bool readBool() => readByte() != 0;

  /// Read a DateTime from milliseconds since epoch.
  DateTime readDateTime() {
    final ms = readInt64();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Read a tag byte.
  int readTag() => readByte();
}
