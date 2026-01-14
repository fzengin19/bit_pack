/// Header Factory
///
/// Auto-detection and parsing of packet headers.
/// Determines Compact vs Standard mode from the mode bit.

library;

import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/exceptions.dart';
import '../../core/types.dart';
import '../../encoding/bitwise.dart';
import 'compact_header.dart';
import 'packet_header.dart';
import 'standard_header.dart';

/// Factory for creating and parsing packet headers
class HeaderFactory {
  HeaderFactory._(); // Prevent instantiation

  /// Detect packet mode from first byte
  ///
  /// [firstByte] The first byte of the packet
  /// Returns [PacketMode.compact] if bit 7 is 0, [PacketMode.standard] if 1
  static PacketMode detectMode(int firstByte) {
    return (firstByte & 0x80) != 0 ? PacketMode.standard : PacketMode.compact;
  }

  /// Detect packet mode from byte array
  ///
  /// [bytes] The packet data (at least 1 byte)
  /// Returns detected packet mode
  static PacketMode detectModeFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw DecodingException('Cannot detect mode from empty data');
    }
    return detectMode(bytes[0]);
  }

  /// Parse header from bytes (auto-detects mode)
  ///
  /// [bytes] Packet data (minimum 4 bytes for compact, 10 for standard)
  /// Returns parsed header (either CompactHeader or StandardHeader)
  ///
  /// Throws [InvalidHeaderException] if parsing fails
  static Object decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw DecodingException('Cannot decode header from empty data');
    }

    final mode = detectMode(bytes[0]);

    switch (mode) {
      case PacketMode.compact:
        return CompactHeader.decode(bytes);
      case PacketMode.standard:
        return StandardHeader.decode(bytes);
    }
  }

  /// Parse compact header from bytes
  static CompactHeader decodeCompact(Uint8List bytes) {
    return CompactHeader.decode(bytes);
  }

  /// Parse standard header from bytes
  static StandardHeader decodeStandard(Uint8List bytes) {
    return StandardHeader.decode(bytes);
  }

  /// Parse header and return remaining payload bytes
  ///
  /// [bytes] Complete packet data
  /// Returns tuple of (header object, payloadBytes)
  static (Object, Uint8List) decodeWithPayload(Uint8List bytes) {
    final header = decode(bytes);

    final headerSize = header is CompactHeader
        ? CompactHeader.headerSizeInBytes
        : StandardHeader.headerSizeInBytes;

    if (bytes.length <= headerSize) {
      // No payload
      return (header, Uint8List(0));
    }

    final payloadBytes = bytes.sublist(headerSize);
    return (header, payloadBytes);
  }

  /// Get required header size based on mode bit
  ///
  /// [firstByte] First byte of packet
  /// Returns 4 for compact, 10 for standard
  static int getHeaderSize(int firstByte) {
    return detectMode(firstByte) == PacketMode.compact
        ? CompactHeader.headerSizeInBytes
        : StandardHeader.headerSizeInBytes;
  }

  /// Check if there's enough data for a complete header
  ///
  /// [bytes] Available data
  /// Returns true if bytes contain a complete header
  static bool hasCompleteHeader(Uint8List bytes) {
    if (bytes.isEmpty) return false;

    final requiredSize = getHeaderSize(bytes[0]);
    return bytes.length >= requiredSize;
  }

  /// Create a new compact header
  static CompactHeader createCompact({
    required MessageType type,
    required int messageId,
    PacketFlags? flags,
    int ttl = kDefaultHopTtl,
  }) {
    return CompactHeader(
      type: type,
      flags: flags ?? PacketFlags(),
      ttl: ttl,
      messageId: messageId,
    );
  }

  /// Create a new standard header
  static StandardHeader createStandard({
    required MessageType type,
    required int messageId,
    PacketFlags? flags,
    int hopTtl = kDefaultHopTtl,
    SecurityMode securityMode = SecurityMode.none,
    int payloadLength = 0,
    int ageMinutes = 0,
  }) {
    return StandardHeader(
      type: type,
      flags: flags ?? PacketFlags(),
      hopTtl: hopTtl,
      messageId: messageId,
      securityMode: securityMode,
      payloadLength: payloadLength,
      ageMinutes: ageMinutes,
    );
  }

  /// Automatically select header type based on requirements
  ///
  /// Returns compact if possible, otherwise standard.
  static Object createAuto({
    required MessageType type,
    required int messageId,
    PacketFlags? flags,
    int ttl = kDefaultHopTtl,
    SecurityMode securityMode = SecurityMode.none,
    int payloadLength = 0,
    int ageMinutes = 0,
    bool forceStandard = false,
  }) {
    flags ??= PacketFlags();

    // Determine if we need Standard mode
    final needsStandard =
        forceStandard ||
        type.requiresStandardMode ||
        securityMode != SecurityMode.none ||
        flags.isFragment ||
        flags.moreFragments ||
        payloadLength > kCompactMaxPayload ||
        ageMinutes > 0 ||
        messageId > kMaxMessageId16 ||
        ttl > kCompactMaxHops;

    if (needsStandard) {
      return createStandard(
        type: type,
        messageId: messageId,
        flags: flags,
        hopTtl: ttl,
        securityMode: securityMode,
        payloadLength: payloadLength,
        ageMinutes: ageMinutes,
      );
    } else {
      return createCompact(
        type: type,
        messageId: messageId,
        flags: flags,
        ttl: ttl,
      );
    }
  }
}
