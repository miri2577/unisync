/// Rsync delta transfer algorithm.
///
/// Mirrors OCaml Unison's `transfer.ml`. Implements block-based delta
/// encoding using rolling checksums (weak) and MD5 (strong) for
/// efficient incremental file transfer.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'checksum.dart';

/// Minimum block size (files smaller than this use full transfer).
const _minBlockSize = 700;

/// Maximum block size.
const _maxBlockSize = 131072; // 128KB

// ---------------------------------------------------------------------------
// Block info — computed on the destination side from the old file
// ---------------------------------------------------------------------------

/// Information about blocks in the destination (old) file.
class RsyncBlockInfo {
  /// Block size in bytes.
  final int blockSize;

  /// Number of blocks.
  final int blockCount;

  /// How many bytes of the strong checksum to compare.
  final int checksumSize;

  /// Weak (rolling) checksum per block.
  final Int32List weakChecksums;

  /// Strong (MD5 prefix) checksum per block.
  /// Each entry is [checksumSize] bytes, stored flat.
  final Uint8List strongChecksums;

  const RsyncBlockInfo({
    required this.blockSize,
    required this.blockCount,
    required this.checksumSize,
    required this.weakChecksums,
    required this.strongChecksums,
  });
}

// ---------------------------------------------------------------------------
// Transfer tokens — the delta instructions
// ---------------------------------------------------------------------------

/// A delta instruction: either literal data or a reference to an old block.
sealed class TransferToken {
  const TransferToken();
}

/// Literal data that doesn't match any old block.
class StringToken extends TransferToken {
  final Uint8List data;
  const StringToken(this.data);
}

/// Reference to consecutive blocks in the old file.
class BlockToken extends TransferToken {
  /// Index of the first block.
  final int blockIndex;

  /// Number of consecutive blocks.
  final int blockCount;

  const BlockToken(this.blockIndex, [this.blockCount = 1]);
}

/// End of transfer.
class EofToken extends TransferToken {
  const EofToken();
}

// ---------------------------------------------------------------------------
// Rsync algorithm implementation
// ---------------------------------------------------------------------------

/// The rsync delta transfer engine.
class Rsync {
  const Rsync();

  /// Compute optimal block size from file lengths.
  ///
  /// blockSize = 2^round(log2(sqrt(dstLength))), clamped to [1024, 131072].
  static int computeBlockSize(int dstLength) {
    if (dstLength <= 0) return _minBlockSize;
    final sqrtLen = sqrt(dstLength.toDouble());
    final log2 = (log(sqrtLen) / ln2).round();
    final size = 1 << log2;
    return size.clamp(_minBlockSize, _maxBlockSize);
  }

  /// Compute the number of strong checksum bytes to use.
  ///
  /// Based on probability of false match.
  static int computeChecksumSize(int srcLength, int dstLength, int blockSize) {
    if (srcLength == 0 || dstLength == 0) return 2;
    final logProba = 120.0; // -log2(desired false positive rate)
    final weakBits = 27.0;
    final n = (srcLength / blockSize).ceil();
    final m = (dstLength / blockSize).ceil();
    final needed = (-logProba - weakBits + log(n.toDouble() * m) / ln2) / 8;
    return needed.ceil().clamp(2, 16);
  }

  /// Phase 1 (destination side): Preprocess the old file.
  ///
  /// Computes block checksums for the destination (old) file.
  RsyncBlockInfo preprocess(
    RandomAccessFile oldFile,
    int srcLength,
    int dstLength,
  ) {
    final blockSize = computeBlockSize(dstLength);
    final checksumSize = computeChecksumSize(srcLength, dstLength, blockSize);
    final blockCount = (dstLength / blockSize).ceil();

    if (blockCount == 0) {
      return RsyncBlockInfo(
        blockSize: blockSize,
        blockCount: 0,
        checksumSize: checksumSize,
        weakChecksums: Int32List(0),
        strongChecksums: Uint8List(0),
      );
    }

    final weakChecksums = Int32List(blockCount);
    final strongChecksums = Uint8List(blockCount * checksumSize);
    final buffer = Uint8List(blockSize);

    oldFile.setPositionSync(0);

    for (var i = 0; i < blockCount; i++) {
      final bytesRead = oldFile.readIntoSync(buffer);
      final actualLen = bytesRead > 0 ? bytesRead : 0;

      // Weak checksum
      weakChecksums[i] = checksumSubstring(buffer, 0, actualLen);

      // Strong checksum (MD5 prefix)
      final digest = md5.convert(
        actualLen == blockSize ? buffer : Uint8List.sublistView(buffer, 0, actualLen),
      );
      for (var j = 0; j < checksumSize; j++) {
        strongChecksums[i * checksumSize + j] = digest.bytes[j];
      }
    }

    return RsyncBlockInfo(
      blockSize: blockSize,
      blockCount: blockCount,
      checksumSize: checksumSize,
      weakChecksums: weakChecksums,
      strongChecksums: strongChecksums,
    );
  }

  /// Phase 2 (source side): Compress by finding matching blocks.
  ///
  /// Scans the new (source) file with a sliding window, matching against
  /// the block info from the old file. Emits [TransferToken]s.
  List<TransferToken> compress(
    RsyncBlockInfo blockInfo,
    Uint8List srcData,
  ) {
    if (blockInfo.blockCount == 0 || srcData.isEmpty) {
      // No old blocks — send everything as literal
      return [
        if (srcData.isNotEmpty) StringToken(Uint8List.fromList(srcData)),
        const EofToken(),
      ];
    }

    final blockSize = blockInfo.blockSize;
    final checksumSize = blockInfo.checksumSize;
    final tokens = <TransferToken>[];

    // Build hash table: weakChecksum → list of (blockIndex)
    final hashTable = <int, List<int>>{};
    for (var i = 0; i < blockInfo.blockCount; i++) {
      hashTable.putIfAbsent(blockInfo.weakChecksums[i], () => []).add(i);
    }

    final rollTable = checksumInit(blockSize);
    var offset = 0;
    var pendingStart = 0; // start of unmatched literal data

    // Initial window checksum
    final windowEnd = min(blockSize, srcData.length);
    var windowCs = checksumSubstring(srcData, 0, windowEnd);

    while (offset + blockSize <= srcData.length) {
      // Try to match against old blocks
      final candidates = hashTable[windowCs];
      int? matchedBlock;

      if (candidates != null) {
        // Compute strong checksum and compare
        final digest = md5.convert(
          Uint8List.sublistView(srcData, offset, offset + blockSize),
        );
        for (final blockIdx in candidates) {
          var match = true;
          for (var j = 0; j < checksumSize; j++) {
            if (digest.bytes[j] !=
                blockInfo.strongChecksums[blockIdx * checksumSize + j]) {
              match = false;
              break;
            }
          }
          if (match) {
            matchedBlock = blockIdx;
            break;
          }
        }
      }

      if (matchedBlock != null) {
        // Emit pending literal data
        if (offset > pendingStart) {
          tokens.add(StringToken(
            Uint8List.fromList(srcData.sublist(pendingStart, offset)),
          ));
        }

        // Emit block reference
        tokens.add(BlockToken(matchedBlock));

        offset += blockSize;
        pendingStart = offset;

        // Recompute window checksum at new position
        if (offset + blockSize <= srcData.length) {
          windowCs = checksumSubstring(srcData, offset, blockSize);
        }
      } else {
        // No match — slide by 1
        if (offset + blockSize < srcData.length) {
          windowCs = checksumRoll(
            rollTable,
            windowCs,
            srcData[offset],
            srcData[offset + blockSize],
          );
        }
        offset++;
      }
    }

    // Emit remaining literal data
    if (pendingStart < srcData.length) {
      tokens.add(StringToken(
        Uint8List.fromList(srcData.sublist(pendingStart)),
      ));
    }

    tokens.add(const EofToken());
    return tokens;
  }

  /// Phase 3 (destination side): Decompress to reconstruct the new file.
  ///
  /// Applies transfer tokens against the old file to produce the new file.
  Uint8List decompress(
    int blockSize,
    Uint8List oldData,
    List<TransferToken> tokens,
  ) {
    final output = BytesBuilder(copy: false);

    for (final token in tokens) {
      switch (token) {
        case StringToken(data: var data):
          output.add(data);

        case BlockToken(blockIndex: var idx, blockCount: var count):
          final start = idx * blockSize;
          final end = min(start + count * blockSize, oldData.length);
          output.add(Uint8List.sublistView(oldData, start, end));

        case EofToken():
          break;
      }
    }

    return output.toBytes();
  }

  /// High-level: compute delta between old and new file.
  ///
  /// Returns tokens that, combined with the old file, reconstruct the new file.
  List<TransferToken> computeDelta(Uint8List oldData, Uint8List newData) {
    if (oldData.isEmpty || newData.length < _minBlockSize) {
      return [
        if (newData.isNotEmpty) StringToken(Uint8List.fromList(newData)),
        const EofToken(),
      ];
    }

    // Use a temporary RandomAccessFile for preprocessing
    final blockInfo = _preprocessFromBytes(oldData, newData.length);
    return compress(blockInfo, newData);
  }

  /// Apply delta tokens to reconstruct the new file from old data.
  Uint8List applyDelta(Uint8List oldData, List<TransferToken> tokens) {
    final blockSize = _inferBlockSize(oldData.length);
    return decompress(blockSize, oldData, tokens);
  }

  /// High-level file-based delta transfer.
  ///
  /// Reads old file, computes delta against new file, writes result.
  void deltaTransferFile(
    String oldFilePath,
    String newFilePath,
    String outputPath,
  ) {
    final oldData = File(oldFilePath).readAsBytesSync();
    final newData = File(newFilePath).readAsBytesSync();

    final tokens = computeDelta(oldData, newData);
    final blockSize = computeBlockSize(oldData.length);
    final result = decompress(blockSize, oldData, tokens);

    File(outputPath).writeAsBytesSync(result);
  }

  RsyncBlockInfo _preprocessFromBytes(Uint8List oldData, int srcLength) {
    final blockSize = computeBlockSize(oldData.length);
    final checksumSize = computeChecksumSize(srcLength, oldData.length, blockSize);
    final blockCount = (oldData.length / blockSize).ceil();

    final weakChecksums = Int32List(blockCount);
    final strongChecksums = Uint8List(blockCount * checksumSize);

    for (var i = 0; i < blockCount; i++) {
      final start = i * blockSize;
      final end = min(start + blockSize, oldData.length);
      final block = Uint8List.sublistView(oldData, start, end);

      weakChecksums[i] = checksumSubstring(block, 0, block.length);

      final digest = md5.convert(block);
      for (var j = 0; j < checksumSize; j++) {
        strongChecksums[i * checksumSize + j] = digest.bytes[j];
      }
    }

    return RsyncBlockInfo(
      blockSize: blockSize,
      blockCount: blockCount,
      checksumSize: checksumSize,
      weakChecksums: weakChecksums,
      strongChecksums: strongChecksums,
    );
  }

  int _inferBlockSize(int oldLength) => computeBlockSize(oldLength);
}
