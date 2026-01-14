/// BitPack Fragment Header
///
/// 3-byte fragment header appended after main packet header when
/// the FRAGMENT flag is set. Used for splitting large messages
/// across multiple BLE packets.
///
/// Format:
/// ```
/// ┌────────────────────────────────────────────────────────┐
/// │  FRAGMENT_INDEX (12 bits)  │  TOTAL_FRAGMENTS (12 bits)│
/// └────────────────────────────────────────────────────────┘
/// ```
///
/// - 12 bits each = max 4096 fragments
/// - 4096 × 240 bytes payload = ~1MB max message size

library;

import 'dart:typed_data';

import '../core/exceptions.dart';
import '../encoding/bitwise.dart';

// ============================================================================
// FRAGMENT HEADER
// ============================================================================

/// Fragment header for packet fragmentation (3 bytes)
///
/// Appended to the main header when [PacketFlags.isFragment] is true.
/// Contains fragment index and total fragment count.
///
/// Example:
/// ```dart
/// final header = FragmentHeader(
///   fragmentIndex: 2,
///   totalFragments: 10,
/// );
/// final bytes = header.encode(); // 3 bytes
/// ```
class FragmentHeader {
  /// Size of fragment header in bytes
  static const int sizeInBytes = 3;

  /// Maximum fragment index (12 bits: 0-4095)
  static const int maxFragmentIndex = 4095;

  /// Maximum total fragments (12 bits: 1-4095)
  /// Note: 12 bits can represent 0-4095, but 0 is invalid for total
  static const int maxTotalFragments = 4095;

  /// Zero-based index of this fragment (0 to totalFragments-1)
  final int fragmentIndex;

  /// Total number of fragments for this message
  final int totalFragments;

  /// Create a fragment header
  ///
  /// [fragmentIndex] must be 0 to [totalFragments]-1
  /// [totalFragments] must be 1 to 4096
  FragmentHeader({
    required this.fragmentIndex,
    required this.totalFragments,
  }) {
    if (fragmentIndex < 0 || fragmentIndex > maxFragmentIndex) {
      throw FragmentationException(
        'Fragment index must be 0-$maxFragmentIndex, got $fragmentIndex',
      );
    }
    if (totalFragments < 1 || totalFragments > maxTotalFragments) {
      throw FragmentationException(
        'Total fragments must be 1-$maxTotalFragments, got $totalFragments',
      );
    }
    if (fragmentIndex >= totalFragments) {
      throw FragmentationException(
        'Fragment index ($fragmentIndex) must be less than total ($totalFragments)',
      );
    }
  }

  /// Check if this is the first fragment
  bool get isFirst => fragmentIndex == 0;

  /// Check if this is the last fragment
  bool get isLast => fragmentIndex == totalFragments - 1;

  /// Encode fragment header to 3 bytes
  ///
  /// Layout (big-endian):
  /// - Byte 0: fragmentIndex[11:4] (high 8 bits)
  /// - Byte 1: fragmentIndex[3:0] (low 4 bits) | totalFragments[11:8] (high 4 bits)
  /// - Byte 2: totalFragments[7:0] (low 8 bits)
  Uint8List encode() {
    final bytes = Uint8List(sizeInBytes);

    // Fragment index: 12 bits
    // Total fragments: 12 bits
    // Pack as: [index_high:8][index_low:4 | total_high:4][total_low:8]

    bytes[0] = (fragmentIndex >> 4) & 0xFF; // High 8 bits of index
    bytes[1] = ((fragmentIndex & 0x0F) << 4) | ((totalFragments >> 8) & 0x0F);
    bytes[2] = totalFragments & 0xFF; // Low 8 bits of total

    return bytes;
  }

  /// Decode fragment header from 3 bytes
  ///
  /// Throws [DecodingException] if bytes are insufficient.
  factory FragmentHeader.decode(Uint8List bytes, [int offset = 0]) {
    if (bytes.length < offset + sizeInBytes) {
      throw DecodingException(
        'Insufficient bytes for fragment header: '
        'need $sizeInBytes, got ${bytes.length - offset}',
        offset: offset,
      );
    }

    // Unpack: [index_high:8][index_low:4 | total_high:4][total_low:8]
    final byte0 = bytes[offset];
    final byte1 = bytes[offset + 1];
    final byte2 = bytes[offset + 2];

    final fragmentIndex = (byte0 << 4) | ((byte1 >> 4) & 0x0F);
    final totalFragments = ((byte1 & 0x0F) << 8) | byte2;

    // Validate decoded values
    if (totalFragments == 0) {
      throw DecodingException(
        'Invalid fragment header: total fragments cannot be 0',
        offset: offset,
      );
    }

    if (fragmentIndex >= totalFragments) {
      throw DecodingException(
        'Invalid fragment header: index ($fragmentIndex) >= total ($totalFragments)',
        offset: offset,
      );
    }

    return FragmentHeader(
      fragmentIndex: fragmentIndex,
      totalFragments: totalFragments,
    );
  }

  @override
  String toString() {
    return 'FragmentHeader($fragmentIndex/$totalFragments)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FragmentHeader &&
        other.fragmentIndex == fragmentIndex &&
        other.totalFragments == totalFragments;
  }

  @override
  int get hashCode => Object.hash(fragmentIndex, totalFragments);
}
