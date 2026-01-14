/// BitPack NACK Payload
///
/// Negative Acknowledgment payload for Selective Repeat ARQ.
/// Uses bitmask-based encoding to efficiently represent missing fragments.
///
/// Format:
/// ```
/// [originalMessageId: 4B][blockCount: 1B][Block 1][Block 2]...
///
/// Each Block (3 bytes):
/// ┌─────────────────────────────────────────────────────────────┐
/// │  startIndex (12 bits)  │  bitmask (12 bits)                 │
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// - startIndex: First fragment index in this block
/// - bitmask: 12-bit mask (bit N = fragment at startIndex+N is missing)
/// - Each block covers up to 12 consecutive fragments

library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../core/types.dart';
import '../../encoding/bitwise.dart';
import 'payload.dart';

// ============================================================================
// NACK BLOCK
// ============================================================================

/// A single NACK block representing up to 12 missing fragments
///
/// Format (3 bytes):
/// - startIndex: 12 bits (0-4095)
/// - bitmask: 12 bits (bit N = fragment at startIndex+N is missing)
class NackBlock {
  /// Size of a single block in bytes
  static const int sizeInBytes = 3;

  /// Maximum fragments representable per block
  static const int maxFragmentsPerBlock = 12;

  /// Maximum start index (12 bits)
  static const int maxStartIndex = 4095;

  /// Starting fragment index for this block
  final int startIndex;

  /// Bitmask of missing fragments (bit 0 = startIndex, bit 11 = startIndex+11)
  final int bitmask;

  NackBlock({
    required this.startIndex,
    required this.bitmask,
  }) {
    if (startIndex < 0 || startIndex > maxStartIndex) {
      throw FragmentationException(
        'Start index must be 0-$maxStartIndex, got $startIndex',
      );
    }
    if (bitmask < 0 || bitmask > 0xFFF) {
      throw FragmentationException(
        'Bitmask must be 12 bits (0-0xFFF), got 0x${bitmask.toRadixString(16)}',
      );
    }
  }

  /// Create a NackBlock from a list of missing fragment indices
  ///
  /// Returns null if no indices fall within the start range.
  factory NackBlock.fromMissingIndices(
    int startIndex,
    List<int> missingIndices,
  ) {
    int bitmask = 0;

    for (final index in missingIndices) {
      final offset = index - startIndex;
      if (offset >= 0 && offset < maxFragmentsPerBlock) {
        bitmask = Bitwise.setBit(bitmask, offset);
      }
    }

    return NackBlock(startIndex: startIndex, bitmask: bitmask);
  }

  /// Get list of missing fragment indices from this block
  List<int> get missingIndices {
    final indices = <int>[];
    for (int bit = 0; bit < maxFragmentsPerBlock; bit++) {
      if (Bitwise.getBit(bitmask, bit)) {
        indices.add(startIndex + bit);
      }
    }
    return indices;
  }

  /// Count of missing fragments in this block
  int get missingCount => Bitwise.popCount(bitmask);

  /// Check if a specific fragment index is marked as missing
  bool isMissing(int fragmentIndex) {
    final offset = fragmentIndex - startIndex;
    if (offset < 0 || offset >= maxFragmentsPerBlock) return false;
    return Bitwise.getBit(bitmask, offset);
  }

  /// Encode block to 3 bytes
  ///
  /// Layout: [startIndex_high:8][startIndex_low:4 | bitmask_high:4][bitmask_low:8]
  Uint8List encode() {
    final bytes = Uint8List(sizeInBytes);

    // Pack: 12-bit startIndex + 12-bit bitmask = 24 bits = 3 bytes
    bytes[0] = (startIndex >> 4) & 0xFF;
    bytes[1] = ((startIndex & 0x0F) << 4) | ((bitmask >> 8) & 0x0F);
    bytes[2] = bitmask & 0xFF;

    return bytes;
  }

  /// Decode block from 3 bytes
  factory NackBlock.decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length < offset + sizeInBytes) {
      throw DecodingException(
        'Insufficient bytes for NackBlock: need $sizeInBytes, got ${bytes.length - offset}',
        offset: offset,
      );
    }

    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];
    final byte2 = bytes[offset + 2];

    final startIndex = (byte0 << 4) | ((byte1 >> 4) & 0x0F);
    final bitmask = ((byte1 & 0x0F) << 8) | byte2;

    return NackBlock(startIndex: startIndex, bitmask: bitmask);
  }

  @override
  String toString() {
    return 'NackBlock(start: $startIndex, mask: 0x${bitmask.toRadixString(16)}, '
        'missing: ${missingIndices})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NackBlock &&
        other.startIndex == startIndex &&
        other.bitmask == bitmask;
  }

  @override
  int get hashCode => Object.hash(startIndex, bitmask);
}

// ============================================================================
// NACK PAYLOAD
// ============================================================================

/// NACK payload for requesting retransmission of missing fragments
///
/// Supports multiple blocks to handle non-consecutive gaps efficiently.
///
/// Format:
/// - originalMessageId: 4 bytes
/// - blockCount: 1 byte (1-255 blocks)
/// - blocks: 3 bytes each
///
/// Example:
/// ```dart
/// final nack = NackPayload.fromMissingIndices(
///   originalMessageId: 0x12345678,
///   missingIndices: [5, 7, 10, 100, 101, 102],
/// );
/// // Creates 2 blocks: one for 5,7,10 and one for 100,101,102
/// ```
class NackPayload implements Payload {
  /// Maximum blocks per NACK payload (keep packet small)
  static const int maxBlocks = 8;

  /// Header size (messageId + blockCount)
  static const int headerSize = 5;

  /// Original message ID being NACKed
  final int originalMessageId;

  /// List of NACK blocks
  final List<NackBlock> blocks;

  NackPayload({
    required this.originalMessageId,
    required this.blocks,
  }) {
    if (blocks.isEmpty) {
      throw FragmentationException('NACK payload must have at least one block');
    }
    if (blocks.length > maxBlocks) {
      throw FragmentationException(
        'NACK payload cannot have more than $maxBlocks blocks',
      );
    }
  }

  /// Create NACK from a list of missing fragment indices
  ///
  /// Automatically groups consecutive gaps into efficient blocks.
  /// Prioritizes earliest missing fragments if exceeding maxBlocks.
  factory NackPayload.fromMissingIndices({
    required int originalMessageId,
    required List<int> missingIndices,
    int maxBlockCount = maxBlocks,
  }) {
    if (missingIndices.isEmpty) {
      throw FragmentationException('Missing indices list cannot be empty');
    }

    // Sort indices
    final sorted = List<int>.from(missingIndices)..sort();

    // Group into blocks
    final blocks = <NackBlock>[];
    int i = 0;

    while (i < sorted.length && blocks.length < maxBlockCount) {
      final startIndex = sorted[i];

      // Find all indices that fit in this block (within 12 positions)
      final blockIndices = <int>[];
      while (i < sorted.length &&
          sorted[i] < startIndex + NackBlock.maxFragmentsPerBlock) {
        blockIndices.add(sorted[i]);
        i++;
      }

      final block = NackBlock.fromMissingIndices(startIndex, blockIndices);
      if (block.bitmask != 0) {
        blocks.add(block);
      }
    }

    return NackPayload(
      originalMessageId: originalMessageId,
      blocks: blocks,
    );
  }

  @override
  MessageType get type => MessageType.nack;

  @override
  int get sizeInBytes => headerSize + (blocks.length * NackBlock.sizeInBytes);

  /// Get all missing fragment indices from all blocks
  List<int> get allMissingIndices {
    final indices = <int>[];
    for (final block in blocks) {
      indices.addAll(block.missingIndices);
    }
    return indices..sort();
  }

  /// Total count of missing fragments
  int get totalMissingCount {
    return blocks.fold(0, (sum, block) => sum + block.missingCount);
  }

  @override
  Uint8List encode() {
    final bytes = Uint8List(sizeInBytes);

    // Write message ID (big-endian)
    Bitwise.write32BE(bytes, 0, originalMessageId);

    // Write block count
    bytes[4] = blocks.length;

    // Write blocks
    int offset = headerSize;
    for (final block in blocks) {
      final blockBytes = block.encode();
      bytes.setRange(offset, offset + NackBlock.sizeInBytes, blockBytes);
      offset += NackBlock.sizeInBytes;
    }

    return bytes;
  }

  /// Decode NACK payload from bytes
  factory NackPayload.decode(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw DecodingException(
        'Insufficient bytes for NackPayload header: need $headerSize, got ${bytes.length}',
      );
    }

    final originalMessageId = Bitwise.read32BE(bytes, 0);
    final blockCount = bytes[4];

    if (blockCount == 0) {
      throw DecodingException('NackPayload blockCount cannot be 0');
    }

    final expectedSize = headerSize + (blockCount * NackBlock.sizeInBytes);
    if (bytes.length < expectedSize) {
      throw DecodingException(
        'Insufficient bytes for $blockCount blocks: need $expectedSize, got ${bytes.length}',
      );
    }

    final blocks = <NackBlock>[];
    int offset = headerSize;
    for (int i = 0; i < blockCount; i++) {
      blocks.add(NackBlock.decode(bytes, offset));
      offset += NackBlock.sizeInBytes;
    }

    return NackPayload(
      originalMessageId: originalMessageId,
      blocks: blocks,
    );
  }

  @override
  Payload copy() {
    return NackPayload(
      originalMessageId: originalMessageId,
      blocks: blocks.map((b) => NackBlock(
        startIndex: b.startIndex,
        bitmask: b.bitmask,
      )).toList(),
    );
  }

  @override
  String toString() {
    return 'NackPayload(msgId: 0x${originalMessageId.toRadixString(16)}, '
        'missing: ${allMissingIndices})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NackPayload) return false;
    if (other.originalMessageId != originalMessageId) return false;
    if (other.blocks.length != blocks.length) return false;
    for (int i = 0; i < blocks.length; i++) {
      if (other.blocks[i] != blocks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(originalMessageId, Object.hashAll(blocks));
}
