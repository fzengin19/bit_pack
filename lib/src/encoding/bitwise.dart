/// Bitwise Manipulation Utilities
///
/// High-performance bitwise operations for binary protocol encoding/decoding.
/// Optimized for Dart's integer operations with proper masking.

library;

import 'dart:typed_data';

// ============================================================================
// BIT MANIPULATION
// ============================================================================

/// Bitwise utilities for bit-level data manipulation
class Bitwise {
  Bitwise._(); // Prevent instantiation

  // --------------------------------------------------------------------------
  // SINGLE BIT OPERATIONS
  // --------------------------------------------------------------------------

  /// Set a specific bit to 1
  ///
  /// [value] The integer to modify
  /// [position] Bit position (0 = LSB, 7 = MSB for a byte)
  /// Returns the modified value
  static int setBit(int value, int position) {
    return value | (1 << position);
  }

  /// Clear a specific bit to 0
  ///
  /// [value] The integer to modify
  /// [position] Bit position (0 = LSB)
  /// Returns the modified value
  static int clearBit(int value, int position) {
    return value & ~(1 << position);
  }

  /// Toggle a specific bit
  ///
  /// [value] The integer to modify
  /// [position] Bit position (0 = LSB)
  /// Returns the modified value
  static int toggleBit(int value, int position) {
    return value ^ (1 << position);
  }

  /// Get the value of a specific bit
  ///
  /// [value] The integer to read from
  /// [position] Bit position (0 = LSB)
  /// Returns true if bit is 1, false if 0
  static bool getBit(int value, int position) {
    return ((value >> position) & 1) == 1;
  }

  /// Set a bit to a specific value (0 or 1)
  ///
  /// [value] The integer to modify
  /// [position] Bit position (0 = LSB)
  /// [on] If true, set bit to 1; if false, set to 0
  /// Returns the modified value
  static int writeBit(int value, int position, bool on) {
    return on ? setBit(value, position) : clearBit(value, position);
  }

  // --------------------------------------------------------------------------
  // BIT RANGE OPERATIONS
  // --------------------------------------------------------------------------

  /// Extract a range of bits from a value
  ///
  /// [value] The integer to read from
  /// [startBit] Starting bit position (0 = LSB)
  /// [bitCount] Number of bits to extract
  /// Returns the extracted bits (right-aligned)
  ///
  /// Example: extractBits(0b11010110, 2, 4) -> 0b0101 (extracts bits 2-5)
  static int extractBits(int value, int startBit, int bitCount) {
    final mask = (1 << bitCount) - 1;
    return (value >> startBit) & mask;
  }

  /// Insert bits into a value at a specific position
  ///
  /// [value] The integer to modify
  /// [bits] The bits to insert (right-aligned)
  /// [startBit] Starting bit position (0 = LSB)
  /// [bitCount] Number of bits to insert
  /// Returns the modified value
  ///
  /// Example: insertBits(0b11110000, 0b1010, 2, 4) -> 0b11101000
  static int insertBits(int value, int bits, int startBit, int bitCount) {
    final mask = (1 << bitCount) - 1;
    final clearedValue = value & ~(mask << startBit);
    return clearedValue | ((bits & mask) << startBit);
  }

  /// Create a bitmask with [count] bits set to 1
  ///
  /// Example: mask(4) -> 0b1111 (0x0F)
  static int mask(int count) {
    if (count >= 64) return -1; // All bits set
    return (1 << count) - 1;
  }

  // --------------------------------------------------------------------------
  // MULTI-FIELD PACKING
  // --------------------------------------------------------------------------

  /// Pack multiple values into a single integer
  ///
  /// [values] List of integer values to pack
  /// [bitWidths] List of bit widths for each value (same length as values)
  /// Returns the packed integer
  ///
  /// Example: pack([3, 5, 1, 1], [3, 3, 1, 1]) -> 0b011_101_1_1 = 0xED
  /// Fields are packed from LSB to MSB in order
  static int pack(List<int> values, List<int> bitWidths) {
    assert(
      values.length == bitWidths.length,
      'Values and bitWidths must have same length',
    );

    int result = 0;
    int bitPosition = 0;

    for (int i = 0; i < values.length; i++) {
      final value = values[i] & mask(bitWidths[i]);
      result |= value << bitPosition;
      bitPosition += bitWidths[i];
    }

    return result;
  }

  /// Pack multiple values into a single integer (MSB first order)
  ///
  /// [values] List of integer values to pack
  /// [bitWidths] List of bit widths for each value
  /// Returns the packed integer
  ///
  /// Example: packMsbFirst([3, 5, 1, 1], [3, 3, 1, 1]) -> 0b011_101_1_1 = 0x6D
  /// Fields are packed from MSB to LSB in order (first value is highest bits)
  static int packMsbFirst(List<int> values, List<int> bitWidths) {
    assert(
      values.length == bitWidths.length,
      'Values and bitWidths must have same length',
    );

    int result = 0;
    int totalBits = bitWidths.fold(0, (a, b) => a + b);
    int bitPosition = totalBits;

    for (int i = 0; i < values.length; i++) {
      bitPosition -= bitWidths[i];
      final value = values[i] & mask(bitWidths[i]);
      result |= value << bitPosition;
    }

    return result;
  }

  /// Unpack an integer into multiple values
  ///
  /// [packed] The packed integer
  /// [bitWidths] List of bit widths for each field
  /// Returns list of extracted values
  ///
  /// Example: unpack(0xED, [3, 3, 1, 1]) -> [3, 5, 1, 1]
  /// Fields are unpacked from LSB to MSB
  static List<int> unpack(int packed, List<int> bitWidths) {
    final values = <int>[];
    int bitPosition = 0;

    for (final width in bitWidths) {
      values.add(extractBits(packed, bitPosition, width));
      bitPosition += width;
    }

    return values;
  }

  /// Unpack an integer into multiple values (MSB first order)
  ///
  /// [packed] The packed integer
  /// [bitWidths] List of bit widths for each field
  /// Returns list of extracted values
  static List<int> unpackMsbFirst(int packed, List<int> bitWidths) {
    final values = <int>[];
    int totalBits = bitWidths.fold(0, (a, b) => a + b);
    int bitPosition = totalBits;

    for (final width in bitWidths) {
      bitPosition -= width;
      values.add(extractBits(packed, bitPosition, width));
    }

    return values;
  }

  // --------------------------------------------------------------------------
  // BYTE OPERATIONS
  // --------------------------------------------------------------------------

  /// Get high nibble (upper 4 bits) of a byte
  static int highNibble(int byte) {
    return (byte >> 4) & 0x0F;
  }

  /// Get low nibble (lower 4 bits) of a byte
  static int lowNibble(int byte) {
    return byte & 0x0F;
  }

  /// Combine two nibbles into a byte
  /// [high] High nibble (bits 7-4)
  /// [low] Low nibble (bits 3-0)
  static int combineNibbles(int high, int low) {
    return ((high & 0x0F) << 4) | (low & 0x0F);
  }

  /// Get high byte of a 16-bit value
  static int highByte16(int value) {
    return (value >> 8) & 0xFF;
  }

  /// Get low byte of a 16-bit value
  static int lowByte16(int value) {
    return value & 0xFF;
  }

  /// Combine two bytes into a 16-bit value (big-endian)
  static int combine16BE(int high, int low) {
    return ((high & 0xFF) << 8) | (low & 0xFF);
  }

  /// Combine two bytes into a 16-bit value (little-endian)
  static int combine16LE(int low, int high) {
    return ((high & 0xFF) << 8) | (low & 0xFF);
  }

  /// Combine four bytes into a 32-bit value (big-endian)
  static int combine32BE(int b3, int b2, int b1, int b0) {
    return ((b3 & 0xFF) << 24) |
        ((b2 & 0xFF) << 16) |
        ((b1 & 0xFF) << 8) |
        (b0 & 0xFF);
  }

  // --------------------------------------------------------------------------
  // BIT COUNTING
  // --------------------------------------------------------------------------

  /// Count the number of set bits (population count / Hamming weight)
  static int popCount(int value) {
    // Brian Kernighan's algorithm
    int count = 0;
    while (value != 0) {
      value &= value - 1;
      count++;
    }
    return count;
  }

  /// Find the position of the highest set bit (0-indexed from LSB)
  /// Returns -1 if value is 0
  static int highestBit(int value) {
    if (value == 0) return -1;

    int position = 0;
    while (value > 1) {
      value >>= 1;
      position++;
    }
    return position;
  }

  /// Find the position of the lowest set bit (0-indexed from LSB)
  /// Returns -1 if value is 0
  static int lowestBit(int value) {
    if (value == 0) return -1;

    int position = 0;
    while ((value & 1) == 0) {
      value >>= 1;
      position++;
    }
    return position;
  }

  // --------------------------------------------------------------------------
  // BYTE ARRAY OPERATIONS
  // --------------------------------------------------------------------------

  /// Read a 16-bit big-endian value from byte array
  static int read16BE(Uint8List bytes, int offset) {
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  /// Read a 16-bit little-endian value from byte array
  static int read16LE(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  /// Read a 32-bit big-endian value from byte array
  static int read32BE(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  /// Read a 32-bit little-endian value from byte array
  static int read32LE(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  /// Write a 16-bit big-endian value to byte array
  static void write16BE(Uint8List bytes, int offset, int value) {
    bytes[offset] = (value >> 8) & 0xFF;
    bytes[offset + 1] = value & 0xFF;
  }

  /// Write a 16-bit little-endian value to byte array
  static void write16LE(Uint8List bytes, int offset, int value) {
    bytes[offset] = value & 0xFF;
    bytes[offset + 1] = (value >> 8) & 0xFF;
  }

  /// Write a 32-bit big-endian value to byte array
  static void write32BE(Uint8List bytes, int offset, int value) {
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }

  /// Write a 32-bit little-endian value to byte array
  static void write32LE(Uint8List bytes, int offset, int value) {
    bytes[offset] = value & 0xFF;
    bytes[offset + 1] = (value >> 8) & 0xFF;
    bytes[offset + 2] = (value >> 16) & 0xFF;
    bytes[offset + 3] = (value >> 24) & 0xFF;
  }
}

// ============================================================================
// PACKET FLAGS
// ============================================================================

/// Packet flags management with bitwise operations
///
/// Compact Mode uses 5 bits:
/// - Bit 0: ENCRYPTED
/// - Bit 1: ACK_REQ
/// - Bit 2: MESH
/// - Bit 3: URGENT (in byte 1)
/// - Bit 4: COMPRESSED (in byte 1)
///
/// Standard Mode uses 8 bits:
/// - Bit 0: Reserved
/// - Bit 1: MORE_FRAGMENTS
/// - Bit 2: FRAGMENT
/// - Bit 3: URGENT
/// - Bit 4: COMPRESSED
/// - Bit 5: ENCRYPTED
/// - Bit 6: ACK_REQ
/// - Bit 7: MESH
class PacketFlags {
  // Standard mode bit positions (byte 1)
  static const int _meshBit = 7;
  static const int _ackReqBit = 6;
  static const int _encryptedBit = 5;
  static const int _compressedBit = 4;
  static const int _urgentBit = 3;
  static const int _fragmentBit = 2;
  static const int _moreFragmentsBit = 1;
  // Bit 0 reserved

  // Compact mode bit positions
  // Byte 0 bits 2-0: [MESH][ACK_REQ][ENCRYPTED]
  // Byte 1 bits 7-6: [COMPRESSED][URGENT]

  /// Enable mesh relay
  bool mesh;

  /// Request acknowledgment
  bool ackRequired;

  /// Payload is encrypted
  bool encrypted;

  /// Payload is compressed
  bool compressed;

  /// High priority / urgent message
  bool urgent;

  /// This packet is a fragment
  bool isFragment;

  /// More fragments follow
  bool moreFragments;

  PacketFlags({
    this.mesh = false,
    this.ackRequired = false,
    this.encrypted = false,
    this.compressed = false,
    this.urgent = false,
    this.isFragment = false,
    this.moreFragments = false,
  });

  /// Encode flags for Compact Mode
  ///
  /// Returns tuple of (byte0_flags, byte1_flags)
  /// - byte0_flags: bits 2-0 contain [MESH, ACK_REQ, ENCRYPTED]
  /// - byte1_flags: bits 7-6 contain [COMPRESSED, URGENT]
  (int, int) toCompactBytes() {
    int byte0Flags = 0;
    if (mesh) byte0Flags |= 0x04; // bit 2
    if (ackRequired) byte0Flags |= 0x02; // bit 1
    if (encrypted) byte0Flags |= 0x01; // bit 0

    int byte1Flags = 0;
    if (compressed) byte1Flags |= 0x80; // bit 7
    if (urgent) byte1Flags |= 0x40; // bit 6

    return (byte0Flags, byte1Flags);
  }

  /// Decode flags from Compact Mode bytes
  factory PacketFlags.fromCompactBytes(int byte0Flags, int byte1Flags) {
    return PacketFlags(
      mesh: (byte0Flags & 0x04) != 0,
      ackRequired: (byte0Flags & 0x02) != 0,
      encrypted: (byte0Flags & 0x01) != 0,
      compressed: (byte1Flags & 0x80) != 0,
      urgent: (byte1Flags & 0x40) != 0,
      isFragment: false, // Compact mode doesn't support fragmentation
      moreFragments: false,
    );
  }

  /// Encode flags for Standard Mode (single byte)
  int toStandardByte() {
    int flags = 0;
    if (mesh) flags |= (1 << _meshBit);
    if (ackRequired) flags |= (1 << _ackReqBit);
    if (encrypted) flags |= (1 << _encryptedBit);
    if (compressed) flags |= (1 << _compressedBit);
    if (urgent) flags |= (1 << _urgentBit);
    if (isFragment) flags |= (1 << _fragmentBit);
    if (moreFragments) flags |= (1 << _moreFragmentsBit);
    return flags;
  }

  /// Decode flags from Standard Mode byte
  factory PacketFlags.fromStandardByte(int flags) {
    return PacketFlags(
      mesh: Bitwise.getBit(flags, _meshBit),
      ackRequired: Bitwise.getBit(flags, _ackReqBit),
      encrypted: Bitwise.getBit(flags, _encryptedBit),
      compressed: Bitwise.getBit(flags, _compressedBit),
      urgent: Bitwise.getBit(flags, _urgentBit),
      isFragment: Bitwise.getBit(flags, _fragmentBit),
      moreFragments: Bitwise.getBit(flags, _moreFragmentsBit),
    );
  }

  /// Create a copy with optional modifications
  PacketFlags copyWith({
    bool? mesh,
    bool? ackRequired,
    bool? encrypted,
    bool? compressed,
    bool? urgent,
    bool? isFragment,
    bool? moreFragments,
  }) {
    return PacketFlags(
      mesh: mesh ?? this.mesh,
      ackRequired: ackRequired ?? this.ackRequired,
      encrypted: encrypted ?? this.encrypted,
      compressed: compressed ?? this.compressed,
      urgent: urgent ?? this.urgent,
      isFragment: isFragment ?? this.isFragment,
      moreFragments: moreFragments ?? this.moreFragments,
    );
  }

  @override
  String toString() {
    final active = <String>[];
    if (mesh) active.add('MESH');
    if (ackRequired) active.add('ACK');
    if (encrypted) active.add('ENC');
    if (compressed) active.add('CMP');
    if (urgent) active.add('URG');
    if (isFragment) active.add('FRG');
    if (moreFragments) active.add('MOR');
    return 'PacketFlags(${active.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PacketFlags &&
        other.mesh == mesh &&
        other.ackRequired == ackRequired &&
        other.encrypted == encrypted &&
        other.compressed == compressed &&
        other.urgent == urgent &&
        other.isFragment == isFragment &&
        other.moreFragments == moreFragments;
  }

  @override
  int get hashCode => Object.hash(
    mesh,
    ackRequired,
    encrypted,
    compressed,
    urgent,
    isFragment,
    moreFragments,
  );
}
