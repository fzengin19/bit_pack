/// Compact Header Implementation (4 bytes)
///
/// BLE 4.2 compatible header for emergency/low-overhead packets.
/// Total size: 4 bytes (fits within 20-byte MTU with 15-byte payload + 1 CRC)
///
/// Layout:
/// ```
/// BYTE 0: [MODE(1)][TYPE(4)][FLAGS_PART1(3)]
/// BYTE 1: [TTL(4)][FLAGS_PART2(2)][RESERVED(2)]
/// BYTES 2-3: MESSAGE_ID (16 bits, big-endian)
/// ```

library;

import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/exceptions.dart';
import '../../core/types.dart';
import '../../encoding/bitwise.dart';

/// Compact packet header (4 bytes)
///
/// Designed for BLE 4.2 compatibility with minimal overhead.
/// - 16-bit message ID (vs 32-bit in Standard)
/// - 4-bit hop TTL (max 15 hops)
/// - No relative age tracking (only hop-count based expiration)
class CompactHeader {
  /// Header size in bytes
  static const int sizeInBytes = kCompactHeaderSize; // 4

  /// Packet mode (always compact)
  final PacketMode mode = PacketMode.compact;

  /// Message type (4 bits, 0-15)
  final MessageType type;

  /// Packet flags
  final PacketFlags flags;

  /// Hop TTL (4 bits, 0-15)
  final int ttl;

  /// Message ID for duplicate detection (16 bits)
  final int messageId;

  /// Create a new compact header
  ///
  /// [type] Message type (must be compact-compatible, code <= 0x0F)
  /// [flags] Packet flags
  /// [ttl] Hop TTL (0-15), defaults to [kDefaultHopTtl]
  /// [messageId] 16-bit message ID (0-65535)
  CompactHeader({
    required this.type,
    required this.flags,
    this.ttl = kDefaultHopTtl,
    required this.messageId,
  }) {
    // Validate type is compact-compatible
    if (!type.isCompactCompatible) {
      throw ArgumentError(
        'MessageType ${type.name} (0x${type.code.toRadixString(16)}) '
        'is not compatible with Compact mode. Use Standard mode.',
      );
    }

    // Validate TTL range
    if (ttl < 0 || ttl > kCompactMaxHops) {
      throw ArgumentError('TTL must be 0-$kCompactMaxHops, got $ttl');
    }

    // Validate message ID range
    if (messageId < 0 || messageId > kMaxMessageId16) {
      throw ArgumentError(
        'Message ID must be 0-$kMaxMessageId16, got $messageId',
      );
    }
  }

  /// Check if this message has expired (TTL = 0)
  bool get isExpired => ttl <= 0;

  /// Create a copy with TTL decremented for relay
  CompactHeader decrementTtl() {
    return CompactHeader(
      type: type,
      flags: flags,
      ttl: ttl > 0 ? ttl - 1 : 0,
      messageId: messageId,
    );
  }

  /// Encode header to 4 bytes
  ///
  /// Layout:
  /// ```
  /// BYTE 0: [0][TYPE:4][MESH][ACK_REQ][ENCRYPTED]
  ///         MODE=0 (compact)
  /// BYTE 1: [TTL:4][COMPRESSED][URGENT][RESERVED:2]
  /// BYTES 2-3: MESSAGE_ID (16 bits, big-endian)
  /// ```
  Uint8List encode() {
    final buffer = Uint8List(sizeInBytes);

    // Get flag values for compact encoding
    final (byte0Flags, byte1Flags) = flags.toCompactBytes();

    // BYTE 0: MODE(1=0) + TYPE(4) + FLAGS_PART1(3)
    // Bit 7: MODE = 0 (compact)
    // Bits 6-3: TYPE (4 bits)
    // Bits 2-0: [MESH, ACK_REQ, ENCRYPTED]
    buffer[0] = ((type.code & 0x0F) << 3) | (byte0Flags & 0x07);

    // BYTE 1: TTL(4) + FLAGS_PART2(2) + RESERVED(2)
    // Bits 7-4: TTL (4 bits)
    // Bits 3-2: [COMPRESSED, URGENT] from byte1Flags (shifted)
    // Bits 1-0: Reserved
    final flagsPart2 =
        ((byte1Flags >> 6) & 0x03) << 2; // Move bits 7-6 to bits 3-2
    buffer[1] = ((ttl & 0x0F) << 4) | flagsPart2;

    // BYTES 2-3: MESSAGE_ID (big-endian)
    Bitwise.write16BE(buffer, 2, messageId);

    return buffer;
  }

  /// Decode header from bytes
  ///
  /// [bytes] At least 4 bytes of data
  /// Throws [InvalidHeaderException] if data is invalid
  factory CompactHeader.decode(Uint8List bytes) {
    if (bytes.length < sizeInBytes) {
      throw InsufficientHeaderException(
        expected: sizeInBytes,
        actual: bytes.length,
      );
    }

    final byte0 = bytes[0];
    final byte1 = bytes[1];

    // Check mode bit (bit 7 of byte 0 should be 0 for compact)
    final mode = (byte0 >> 7) & 0x01;
    if (mode != 0) {
      throw InvalidModeException(mode);
    }

    // Extract TYPE (bits 6-3)
    final typeCode = (byte0 >> 3) & 0x0F;

    // Extract FLAGS_PART1 (bits 2-0)
    final byte0Flags = byte0 & 0x07;

    // Extract TTL (bits 7-4 of byte 1)
    final ttl = (byte1 >> 4) & 0x0F;

    // Extract FLAGS_PART2 (bits 3-2 of byte 1) -> convert back to bits 7-6
    final byte1Flags = ((byte1 >> 2) & 0x03) << 6;

    // Extract MESSAGE_ID (bytes 2-3, big-endian)
    final messageId = Bitwise.read16BE(bytes, 2);

    // Parse type
    MessageType type;
    try {
      type = MessageType.fromCode(typeCode);
    } catch (e) {
      throw InvalidHeaderException(
        'Unknown message type: 0x${typeCode.toRadixString(16)}',
        cause: e,
      );
    }

    // Parse flags
    final flags = PacketFlags.fromCompactBytes(byte0Flags, byte1Flags);

    return CompactHeader(
      type: type,
      flags: flags,
      ttl: ttl,
      messageId: messageId,
    );
  }

  /// Create a copy with optional modifications
  CompactHeader copyWith({
    MessageType? type,
    PacketFlags? flags,
    int? ttl,
    int? messageId,
  }) {
    return CompactHeader(
      type: type ?? this.type,
      flags: flags ?? this.flags,
      ttl: ttl ?? this.ttl,
      messageId: messageId ?? this.messageId,
    );
  }

  @override
  String toString() {
    return 'CompactHeader('
        'type: ${type.name}, '
        'ttl: $ttl, '
        'msgId: 0x${messageId.toRadixString(16)}, '
        'flags: $flags)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CompactHeader &&
        other.type == type &&
        other.flags == flags &&
        other.ttl == ttl &&
        other.messageId == messageId;
  }

  @override
  int get hashCode => Object.hash(type, flags, ttl, messageId);
}
