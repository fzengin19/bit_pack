/// CRC-8-CCITT Implementation
///
/// High-performance CRC-8 checksum using pre-computed lookup table.
/// Polynomial: x⁸ + x² + x + 1 = 0x07
/// Used for packet integrity verification in BitPack protocol.

library;

import 'dart:typed_data';

import '../core/constants.dart';
import '../core/exceptions.dart';

/// CRC-8-CCITT checksum calculator
///
/// Uses lookup table for O(1) per-byte calculation.
/// Total table size: 256 bytes (static, one-time allocation)
class Crc8 {
  Crc8._(); // Prevent instantiation

  /// CRC-8-CCITT polynomial: x⁸ + x² + x + 1
  static const int polynomial = kCrc8Polynomial; // 0x07

  /// Initial CRC value
  static const int initialValue = kCrc8InitialValue; // 0x00

  /// Pre-computed lookup table for fast CRC calculation
  /// Each entry is the CRC for a single byte value (0-255)
  static final Uint8List _table = _generateTable();

  /// Generate the lookup table
  ///
  /// For each possible byte value (0-255), pre-compute the CRC.
  /// This converts CRC calculation from 8 iterations per byte
  /// to a single table lookup.
  static Uint8List _generateTable() {
    final table = Uint8List(256);

    for (int i = 0; i < 256; i++) {
      int crc = i;

      for (int bit = 0; bit < 8; bit++) {
        // If MSB is 1, shift left and XOR with polynomial
        // If MSB is 0, just shift left
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ polynomial) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }

      table[i] = crc;
    }

    return table;
  }

  /// Compute CRC-8 for given data
  ///
  /// [data] The byte array to compute CRC for
  /// Returns 8-bit CRC value (0-255)
  ///
  /// Performance: O(n) where n is data length
  /// ~0.15 μs for 19-byte SOS packet on modern CPU
  static int compute(Uint8List data) {
    int crc = initialValue;

    for (int i = 0; i < data.length; i++) {
      // XOR current CRC with data byte, look up result in table
      crc = _table[(crc ^ data[i]) & 0xFF];
    }

    return crc;
  }

  /// Compute CRC-8 for a portion of data
  ///
  /// [data] The byte array
  /// [offset] Starting offset
  /// [length] Number of bytes to include
  /// Returns 8-bit CRC value
  static int computeRange(Uint8List data, int offset, int length) {
    int crc = initialValue;
    final end = offset + length;

    for (int i = offset; i < end; i++) {
      crc = _table[(crc ^ data[i]) & 0xFF];
    }

    return crc;
  }

  /// Continue CRC calculation from a previous value
  ///
  /// [crc] Previous CRC value to continue from
  /// [data] Additional data to include
  /// Returns updated CRC value
  ///
  /// Useful for calculating CRC incrementally:
  /// ```dart
  /// int crc = Crc8.compute(header);
  /// crc = Crc8.update(crc, payload);
  /// ```
  static int update(int crc, Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      crc = _table[(crc ^ data[i]) & 0xFF];
    }
    return crc;
  }

  /// Update CRC with a single byte
  ///
  /// [crc] Current CRC value
  /// [byte] Single byte to include
  /// Returns updated CRC value
  static int updateByte(int crc, int byte) {
    return _table[(crc ^ byte) & 0xFF];
  }

  /// Verify CRC of data (assumes last byte is CRC)
  ///
  /// [dataWithCrc] Data with CRC appended as last byte
  /// Returns true if CRC is valid, false otherwise
  ///
  /// Note: If dataWithCrc is empty, returns false
  static bool verify(Uint8List dataWithCrc) {
    if (dataWithCrc.isEmpty) return false;

    // Calculate CRC of all data except last byte
    final dataLength = dataWithCrc.length - 1;
    final expectedCrc = dataWithCrc[dataLength];

    int crc = initialValue;
    for (int i = 0; i < dataLength; i++) {
      crc = _table[(crc ^ dataWithCrc[i]) & 0xFF];
    }

    return crc == expectedCrc;
  }

  /// Verify CRC and throw exception if invalid
  ///
  /// [dataWithCrc] Data with CRC appended as last byte
  /// Throws [CrcMismatchException] if CRC is invalid
  static void verifyOrThrow(Uint8List dataWithCrc) {
    if (dataWithCrc.isEmpty) {
      throw DecodingException('Cannot verify CRC of empty data');
    }

    final dataLength = dataWithCrc.length - 1;
    final expectedCrc = dataWithCrc[dataLength];

    int crc = initialValue;
    for (int i = 0; i < dataLength; i++) {
      crc = _table[(crc ^ dataWithCrc[i]) & 0xFF];
    }

    if (crc != expectedCrc) {
      throw CrcMismatchException(expected: expectedCrc, actual: crc);
    }
  }

  /// Append CRC to data
  ///
  /// [data] Original data without CRC
  /// Returns new Uint8List with CRC appended
  ///
  /// The returned array is data.length + 1 bytes.
  static Uint8List appendCrc(Uint8List data) {
    final crc = compute(data);
    final result = Uint8List(data.length + 1);
    result.setAll(0, data);
    result[data.length] = crc;
    return result;
  }

  /// Append CRC in-place (requires pre-allocated space)
  ///
  /// [buffer] Buffer with at least dataLength + 1 bytes
  /// [dataLength] Length of actual data (CRC written at buffer[dataLength])
  ///
  /// This avoids allocation by writing CRC to existing buffer.
  static void appendCrcInPlace(Uint8List buffer, int dataLength) {
    assert(
      buffer.length >= dataLength + 1,
      'Buffer too small for CRC: need ${dataLength + 1}, have ${buffer.length}',
    );

    int crc = initialValue;
    for (int i = 0; i < dataLength; i++) {
      crc = _table[(crc ^ buffer[i]) & 0xFF];
    }
    buffer[dataLength] = crc;
  }

  /// Strip CRC from data
  ///
  /// [dataWithCrc] Data with CRC as last byte
  /// [verify] If true, verify CRC before stripping (throws on mismatch)
  /// Returns data without CRC byte
  static Uint8List stripCrc(Uint8List dataWithCrc, {bool verify = true}) {
    if (dataWithCrc.isEmpty) {
      throw DecodingException('Cannot strip CRC from empty data');
    }

    if (verify) {
      verifyOrThrow(dataWithCrc);
    }

    return dataWithCrc.sublist(0, dataWithCrc.length - 1);
  }

  /// Get the lookup table (for testing/debugging)
  static Uint8List get table => Uint8List.fromList(_table);
}
