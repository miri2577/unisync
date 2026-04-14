/// Rolling checksum for rsync block matching.
///
/// Mirrors OCaml Unison's `checksum.ml`. Uses a polynomial rolling hash
/// with base 16381 (prime) for fast sliding-window computation.
library;

import 'dart:typed_data';

/// Base for the rolling polynomial hash.
/// 16381 is prime, close to 2^14, enabling fast multiply via bit shifts.
const _base = 16381;

/// Mask for 31-bit unsigned result.
const _mask = 0x7FFFFFFF;

/// Precomputed table for rolling: table[c] = c * base^blockSize mod 2^31.
/// Used to efficiently subtract the outgoing byte's contribution.
class ChecksumTable {
  /// Lookup table: byte value → precomputed multiplier.
  final Int32List table;

  /// Block size this table was computed for.
  final int blockSize;

  ChecksumTable._(this.table, this.blockSize);
}

/// Initialize a checksum table for a given block size.
///
/// Precomputes `base^blockSize mod 2^31` for each possible byte value (0-255).
ChecksumTable checksumInit(int blockSize) {
  // Compute base^blockSize mod 2^31
  var power = 1;
  for (var i = 0; i < blockSize; i++) {
    power = (power * _base) & _mask;
  }

  final table = Int32List(256);
  for (var c = 0; c < 256; c++) {
    table[c] = (c * power) & _mask;
  }

  return ChecksumTable._(table, blockSize);
}

/// Compute checksum of a byte range from scratch.
///
/// checksum([c_0, c_1, ..., c_{n-1}]) = Sum(c_i * base^(n-1-i)) mod 2^31
int checksumSubstring(Uint8List data, int offset, int length) {
  var sum = 0;
  for (var i = 0; i < length; i++) {
    sum = ((sum * _base) + data[offset + i]) & _mask;
  }
  return sum;
}

/// Roll the checksum by one byte position.
///
/// Given checksum of [c_0, c_1, ..., c_{n-1}], compute checksum of
/// [c_1, ..., c_{n-1}, incoming] where outgoing = c_0.
///
/// Math: new = (old - outgoing * base^(n-1)) * base + incoming
int checksumRoll(ChecksumTable table, int checksum, int outgoing, int incoming) {
  // Remove outgoing byte's contribution: outgoing * base^(blockSize-1)
  // Note: table stores c * base^blockSize, but we need base^(blockSize-1).
  // We precompute base^blockSize per byte, so table[outgoing] = outgoing * base^blockSize.
  // old - outgoing * base^(blockSize-1) then * base + incoming
  // = old * base - outgoing * base^blockSize + incoming
  var newCs = (checksum * _base - table.table[outgoing] + incoming) & _mask;
  return newCs;
}
