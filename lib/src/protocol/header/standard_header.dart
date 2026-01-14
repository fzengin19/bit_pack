/// Standard Header Implementation (11 bytes)
///
/// BLE 5.0+ header with full features including Relative Age TTL.
/// Total size: 11 bytes
///
/// Layout:
/// ```
/// BYTE 0:    [MODE(1)][VERSION(1)][TYPE(6)]
/// BYTE 1:    [FLAGS(8)]
/// BYTE 2:    [HOP_TTL(8)]
/// BYTES 3-6: [MESSAGE_ID(32)]
/// BYTE 7:    [SEC_MODE(3)][PAYLOAD_LENGTH_HIGH(5)]
/// BYTE 8:    [PAYLOAD_LENGTH_LOW(8)]
/// BYTES 9-10: [AGE_MINUTES(16)]
/// ```

library;

import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/exceptions.dart';
import '../../core/types.dart';
import '../../encoding/bitwise.dart';
import 'packet_header.dart';

/// Standard packet header (10 bytes)
///
/// Full-featured header for BLE 5.0+ with:
/// - 32-bit message ID
/// - 8-bit hop TTL (0-255 hops)
/// - 16-bit relative age (minutes since creation)
/// - Security mode field
/// - Payload length field
class StandardHeader implements PacketHeader {
  /// Header size in bytes
  static const int headerSizeInBytes = kStandardHeaderSize; // 11

  @override
  int get sizeInBytes => headerSizeInBytes;

  /// Packet mode (always standard)
  @override
  final PacketMode mode = PacketMode.standard;

  /// Protocol version (0-1)
  final int version;

  /// Message type (6 bits, 0-63)
  @override
  final MessageType type;

  /// Packet flags (8 bits)
  @override
  final PacketFlags flags;

  /// Hop TTL (8 bits, 0-255)
  final int hopTtl;

  /// Message ID for duplicate detection (32 bits)
  @override
  final int messageId;

  /// Security mode (3 bits)
  final SecurityMode securityMode;

  /// Payload length in bytes (13 bits, max 8191)
  final int payloadLength;

  /// Minutes since message creation (16 bits)
  ///
  /// Used for relative time-based TTL without requiring clock sync.
  /// Each relay node adds its local hold time to this value.
  final int ageMinutes;

  // --- Internal state for age calculation ---

  /// Timestamp when this packet was received locally
  DateTime? _receivedAt;

  /// Create a new standard header
  StandardHeader({
    this.version = kProtocolVersion,
    required this.type,
    required this.flags,
    this.hopTtl = kDefaultHopTtl,
    required this.messageId,
    this.securityMode = SecurityMode.none,
    this.payloadLength = 0,
    this.ageMinutes = 0,
  }) {
    // Validate version
    if (version < 0 || version > 1) {
      throw ArgumentError('Version must be 0 or 1, got $version');
    }

    // Validate hop TTL
    if (hopTtl < 0 || hopTtl > kStandardMaxHops) {
      throw ArgumentError('Hop TTL must be 0-$kStandardMaxHops, got $hopTtl');
    }

    // Validate message ID (32-bit unsigned)
    if (messageId < 0 || messageId > kMaxMessageId32) {
      throw ArgumentError(
        'Message ID must be 0-$kMaxMessageId32, got $messageId',
      );
    }

    // Validate payload length (13 bits)
    if (payloadLength < 0 || payloadLength > kMaxPayloadLength) {
      throw ArgumentError(
        'Payload length must be 0-$kMaxPayloadLength, got $payloadLength',
      );
    }

    // Validate age minutes (16 bits)
    if (ageMinutes < 0 || ageMinutes > kMaxAgeMinutesAbsolute) {
      throw ArgumentError(
        'Age minutes must be 0-$kMaxAgeMinutesAbsolute, got $ageMinutes',
      );
    }
  }

  /// Mark when this packet was received (for age calculation during relay)
  void markReceived() {
    _receivedAt = DateTime.now();
  }

  /// Get the actual received timestamp
  DateTime? get receivedAt => _receivedAt;

  /// Calculate current age including local hold time
  ///
  /// This accounts for how long the packet has been held locally
  /// since it was received. Used when preparing for relay.
  int get currentAgeMinutes {
    if (_receivedAt == null) return ageMinutes;

    final localHoldDuration = DateTime.now().difference(_receivedAt!);
    final localHoldMinutes = localHoldDuration.inMinutes;

    // Clamp to max 16-bit value
    final totalAge = ageMinutes + localHoldMinutes;
    return totalAge.clamp(0, kMaxAgeMinutesAbsolute);
  }

  /// Check if this message has expired
  ///
  /// A message expires when:
  /// - hopTtl reaches 0, OR
  /// - ageMinutes exceeds [kMaxAgeMinutes] (24 hours)
  @override
  bool get isExpired {
    return hopTtl <= 0 || currentAgeMinutes >= kMaxAgeMinutes;
  }

  @override
  int get ttl => hopTtl;

  /// Create a copy prepared for relay
  ///
  /// - Decrements hopTtl by 1
  /// - Updates ageMinutes with local hold time
  StandardHeader prepareForRelay() {
    return StandardHeader(
      version: version,
      type: type,
      flags: flags,
      hopTtl: hopTtl > 0 ? hopTtl - 1 : 0,
      messageId: messageId,
      securityMode: securityMode,
      payloadLength: payloadLength,
      ageMinutes: currentAgeMinutes,
    );
  }

  /// Encode header to 11 bytes
  ///
  /// All multi-byte values are encoded as big-endian.
  @override
  Uint8List encode() {
    final buffer = Uint8List(sizeInBytes);

    // BYTE 0: MODE(1) + VERSION(1) + TYPE(6)
    // Bit 7: MODE = 1 (standard)
    // Bit 6: VERSION
    // Bits 5-0: TYPE
    buffer[0] =
        0x80 | // MODE = 1
        ((version & 0x01) << 6) |
        (type.code & 0x3F);

    // BYTE 1: FLAGS (8 bits)
    buffer[1] = flags.toStandardByte();

    // BYTE 2: HOP_TTL (8 bits)
    buffer[2] = hopTtl & 0xFF;

    // BYTES 3-6: MESSAGE_ID (32 bits, big-endian)
    Bitwise.write32BE(buffer, 3, messageId);

    // BYTE 7: SEC_MODE(3) + PAYLOAD_LENGTH_HIGH(5)
    // Bits 7-5: SEC_MODE (3 bits)
    // Bits 4-0: PAYLOAD_LENGTH high 5 bits
    final secModeBits = (securityMode.code & 0x07) << 5;
    final payloadHigh = (payloadLength >> 8) & 0x1F;
    buffer[7] = secModeBits | payloadHigh;

    // BYTE 8: PAYLOAD_LENGTH_LOW (8 bits)
    buffer[8] = payloadLength & 0xFF;

    // BYTES 9-10: AGE_MINUTES (16 bits, big-endian)
    Bitwise.write16BE(buffer, 9, ageMinutes);

    return buffer;
  }

  /// Decode header from bytes
  ///
  /// [bytes] At least 10 bytes of data
  /// Throws [InvalidHeaderException] if data is invalid
  ///
  /// Automatically calls [markReceived] to track local hold time.
  factory StandardHeader.decode(Uint8List bytes) {
    if (bytes.length < headerSizeInBytes) {
      throw InsufficientHeaderException(
        expected: headerSizeInBytes,
        actual: bytes.length,
      );
    }

    final byte0 = bytes[0];

    // Check mode bit (bit 7 should be 1 for standard)
    final mode = (byte0 >> 7) & 0x01;
    if (mode != 1) {
      throw InvalidModeException(mode);
    }

    // Extract VERSION (bit 6)
    final version = (byte0 >> 6) & 0x01;

    // Extract TYPE (bits 5-0)
    final typeCode = byte0 & 0x3F;

    // Extract FLAGS (byte 1)
    final flagsByte = bytes[1];
    final flags = PacketFlags.fromStandardByte(flagsByte);

    // Extract HOP_TTL (byte 2)
    final hopTtl = bytes[2];

    // Extract MESSAGE_ID (bytes 3-6, big-endian)
    final messageId = Bitwise.read32BE(bytes, 3);

    // Extract SEC_MODE (bits 7-5 of byte 7) + PAYLOAD_LENGTH (13 bits)
    final byte7 = bytes[7];
    final secModeCode = (byte7 >> 5) & 0x07;
    final payloadHigh = byte7 & 0x1F;
    final payloadLow = bytes[8];
    final payloadLength = (payloadHigh << 8) | payloadLow;

    // Extract AGE_MINUTES (bytes 9-10, big-endian)
    final ageMinutes = Bitwise.read16BE(bytes, 9);

    // Parse message type
    MessageType type;
    try {
      type = MessageType.fromCode(typeCode);
    } catch (e) {
      throw InvalidHeaderException(
        'Unknown message type: 0x${typeCode.toRadixString(16)}',
        cause: e,
      );
    }

    // Parse security mode
    SecurityMode securityMode;
    try {
      securityMode = SecurityMode.fromCode(secModeCode);
    } catch (e) {
      throw InvalidHeaderException(
        'Unknown security mode: $secModeCode',
        cause: e,
      );
    }

    final header = StandardHeader(
      version: version,
      type: type,
      flags: flags,
      hopTtl: hopTtl,
      messageId: messageId,
      securityMode: securityMode,
      payloadLength: payloadLength,
      ageMinutes: ageMinutes,
    );

    // Mark as received for future age calculation
    header.markReceived();

    return header;
  }

  /// Create a copy with optional modifications
  StandardHeader copyWith({
    int? version,
    MessageType? type,
    PacketFlags? flags,
    int? hopTtl,
    int? messageId,
    SecurityMode? securityMode,
    int? payloadLength,
    int? ageMinutes,
  }) {
    return StandardHeader(
      version: version ?? this.version,
      type: type ?? this.type,
      flags: flags ?? this.flags,
      hopTtl: hopTtl ?? this.hopTtl,
      messageId: messageId ?? this.messageId,
      securityMode: securityMode ?? this.securityMode,
      payloadLength: payloadLength ?? this.payloadLength,
      ageMinutes: ageMinutes ?? this.ageMinutes,
    );
  }

  /// Get time remaining before age-based expiration
  ///
  /// Returns null if already expired or age-based TTL not applicable.
  Duration? get remainingAge {
    if (currentAgeMinutes >= kMaxAgeMinutes) return null;

    final remainingMinutes = kMaxAgeMinutes - currentAgeMinutes;
    return Duration(minutes: remainingMinutes);
  }

  @override
  String toString() {
    return 'StandardHeader('
        'v$version, '
        'type: ${type.name}, '
        'hopTtl: $hopTtl, '
        'msgId: 0x${messageId.toRadixString(16)}, '
        'sec: ${securityMode.name}, '
        'payloadLen: $payloadLength, '
        'age: ${ageMinutes}min, '
        'flags: $flags)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StandardHeader &&
        other.version == version &&
        other.type == type &&
        other.flags == flags &&
        other.hopTtl == hopTtl &&
        other.messageId == messageId &&
        other.securityMode == securityMode &&
        other.payloadLength == payloadLength &&
        other.ageMinutes == ageMinutes;
  }

  @override
  int get hashCode => Object.hash(
    version,
    type,
    flags,
    hopTtl,
    messageId,
    securityMode,
    payloadLength,
    ageMinutes,
  );
}
