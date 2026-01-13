/// BitPack Protocol Types
///
/// Core enumerations and type definitions for the BitPack mesh protocol.
/// Includes message types, security modes, packet modes, and SOS types.

library;

// ============================================================================
// PACKET MODE
// ============================================================================

/// Packet mode determines header format and capabilities
enum PacketMode {
  /// Compact mode: 4-byte header, BLE 4.2 compatible
  /// - 16-bit message ID
  /// - 4-bit hop TTL
  /// - No relative age tracking
  compact(0),

  /// Standard mode: 10-byte header, BLE 5.0+
  /// - 32-bit message ID
  /// - 8-bit hop TTL
  /// - 16-bit relative age (minutes since creation)
  standard(1);

  final int code;
  const PacketMode(this.code);

  /// Create from mode bit (0 or 1)
  static PacketMode fromCode(int code) {
    return code == 0 ? PacketMode.compact : PacketMode.standard;
  }
}

// ============================================================================
// MESSAGE TYPE
// ============================================================================

/// Message type identifiers
///
/// Compact mode: 4 bits (0x0 - 0xF)
/// Standard mode: 6 bits (0x00 - 0x3F)
enum MessageType {
  // === Compact Mode Types (0x0 - 0xF) ===

  /// Emergency SOS beacon with GPS coordinates
  sosBeacon(0x00),

  /// Acknowledgment for SOS beacon
  sosAck(0x01),

  /// Location sharing (GPS only)
  location(0x02),

  /// Connectivity check ping
  ping(0x03),

  /// Ping response
  pong(0x04),

  /// Short text message (compact)
  textShort(0x05),

  /// Relay capability announcement
  relayAnnounce(0x06),

  // Reserved: 0x07 - 0x0F for future compact types

  // === Standard Mode Types (0x10 - 0x3F) ===

  /// Connection handshake initiation
  handshakeInit(0x10),

  /// Handshake acknowledgment
  handshakeAck(0x11),

  /// Encrypted data payload
  dataEncrypted(0x12),

  /// Data acknowledgment
  dataAck(0x13),

  /// Capability query (MTU, features)
  capabilityQuery(0x14),

  /// Capability response
  capabilityResponse(0x15),

  /// Negative acknowledgment for selective repeat ARQ
  nack(0x16),

  /// Fragment retransmission request
  fragmentRequest(0x17),

  /// Extended text message
  textExtended(0x18),

  /// File/binary data chunk
  binaryData(0x19),

  /// Group message broadcast
  groupBroadcast(0x1A),

  /// Peer discovery beacon
  peerDiscovery(0x1B);

  final int code;
  const MessageType(this.code);

  /// Create MessageType from code value
  static MessageType fromCode(int code) {
    for (final type in MessageType.values) {
      if (type.code == code) return type;
    }
    throw ArgumentError(
      'Unknown MessageType code: 0x${code.toRadixString(16)}',
    );
  }

  /// Check if this type is valid for Compact mode (4 bits)
  bool get isCompactCompatible => code <= 0x0F;

  /// Check if this type requires Standard mode
  bool get requiresStandardMode => code > 0x0F;
}

// ============================================================================
// SECURITY MODE
// ============================================================================

/// Security mode for packet encryption
enum SecurityMode {
  /// No encryption (plaintext)
  /// Used for emergency SOS broadcasts
  none(0x00),

  /// Symmetric encryption (AES-128-GCM)
  /// Key derived from shared secret via PBKDF2
  symmetric(0x01),

  /// Asymmetric encryption (X25519 + AES-256-GCM)
  /// Full end-to-end encryption with ephemeral keys
  asymmetric(0x02),

  /// Contact-only mode (blinded recipients)
  /// Only pre-registered contacts can decrypt
  contactOnly(0x03);

  final int code;
  const SecurityMode(this.code);

  /// Create SecurityMode from 3-bit code
  static SecurityMode fromCode(int code) {
    for (final mode in SecurityMode.values) {
      if (mode.code == code) return mode;
    }
    throw ArgumentError('Unknown SecurityMode code: $code');
  }

  /// Check if this mode uses encryption
  bool get isEncrypted => this != SecurityMode.none;

  /// Get required key length in bytes
  int get keyLength {
    switch (this) {
      case SecurityMode.none:
        return 0;
      case SecurityMode.symmetric:
        return 16; // AES-128
      case SecurityMode.asymmetric:
      case SecurityMode.contactOnly:
        return 32; // AES-256
    }
  }
}

// ============================================================================
// SOS TYPE
// ============================================================================

/// SOS beacon type (3 bits, 0-7)
enum SosType {
  /// Need rescue (general emergency)
  needRescue(0),

  /// Injured (medical emergency)
  injured(1),

  /// Trapped/buried (e.g., under rubble)
  trapped(2),

  /// Safe (status update)
  safe(3),

  /// Need supplies (food, water, medicine)
  needSupplies(4),

  /// Can help others
  canHelp(5),

  /// Deceased person nearby
  deceasedNearby(6),

  /// Custom (details in text payload)
  custom(7);

  final int code;
  const SosType(this.code);

  /// Create SosType from 3-bit code
  static SosType fromCode(int code) {
    for (final type in SosType.values) {
      if (type.code == code) return type;
    }
    throw ArgumentError('Unknown SosType code: $code');
  }

  /// Get human-readable Turkish description
  String get descriptionTr {
    switch (this) {
      case SosType.needRescue:
        return 'Kurtarın';
      case SosType.injured:
        return 'Yaralıyım';
      case SosType.trapped:
        return 'Enkaz altındayım';
      case SosType.safe:
        return 'Güvendeyim';
      case SosType.needSupplies:
        return 'Malzeme lazım';
      case SosType.canHelp:
        return 'Yardım edebilirim';
      case SosType.deceasedNearby:
        return 'Yakınımda vefat var';
      case SosType.custom:
        return 'Özel durum';
    }
  }

  /// Get human-readable English description
  String get descriptionEn {
    switch (this) {
      case SosType.needRescue:
        return 'Need rescue';
      case SosType.injured:
        return 'Injured';
      case SosType.trapped:
        return 'Trapped/buried';
      case SosType.safe:
        return 'Safe';
      case SosType.needSupplies:
        return 'Need supplies';
      case SosType.canHelp:
        return 'Can help';
      case SosType.deceasedNearby:
        return 'Deceased nearby';
      case SosType.custom:
        return 'Custom';
    }
  }
}

// ============================================================================
// COUNTRY CODE (for International BCD)
// ============================================================================

/// Common country code shortcuts (3 bits)
enum CountryCode {
  /// Reserved
  reserved(0x00, ''),

  /// USA/Canada (+1)
  usaCanada(0x01, '+1'),

  /// United Kingdom (+44)
  uk(0x02, '+44'),

  /// Germany (+49)
  germany(0x03, '+49'),

  /// France (+33)
  france(0x04, '+33'),

  /// Italy (+39)
  italy(0x05, '+39'),

  /// Turkey (+90) - default for domestic mode
  turkey(0x06, '+90'),

  /// Custom country code (encoded in BCD)
  custom(0x07, '');

  final int code;
  final String prefix;

  const CountryCode(this.code, this.prefix);

  /// Create CountryCode from 3-bit code
  static CountryCode fromCode(int code) {
    for (final cc in CountryCode.values) {
      if (cc.code == code) return cc;
    }
    return CountryCode.custom;
  }

  /// Find country code by phone prefix
  static CountryCode fromPrefix(String prefix) {
    final normalized = prefix.startsWith('+') ? prefix : '+$prefix';
    for (final cc in CountryCode.values) {
      if (cc.prefix == normalized) return cc;
    }
    return CountryCode.custom;
  }
}
