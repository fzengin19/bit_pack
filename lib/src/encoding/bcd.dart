/// BCD (Binary Coded Decimal) Phone Number Encoding
///
/// Encodes phone numbers using BCD format where each digit
/// occupies 4 bits (nibble), allowing 2 digits per byte.
///
/// Used for ultra-compact phone number storage in SOS payloads.
///
/// Format:
/// - Each byte contains 2 digits (high nibble, low nibble)
/// - 0xF is used as padding for odd-length numbers
/// - Example: "12345" → [0x12, 0x34, 0x5F]

library;

import 'dart:typed_data';

import '../core/exceptions.dart';

/// BCD codec for phone number encoding
class Bcd {
  Bcd._(); // Prevent instantiation

  /// Padding nibble for odd-length numbers
  static const int _padding = 0x0F;

  /// Encode a phone number string to BCD bytes
  ///
  /// [phoneNumber] Phone number string (digits only, or with + prefix)
  /// Returns BCD-encoded bytes
  ///
  /// Example: "1234567890" → [0x12, 0x34, 0x56, 0x78, 0x90]
  static Uint8List encode(String phoneNumber) {
    // Remove non-digit characters (keep only 0-9)
    final digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    if (digits.isEmpty) {
      return Uint8List(0);
    }

    return _encodeDigits(digits);
  }

  /// Encode only the last N digits of a phone number
  ///
  /// [phoneNumber] Phone number string
  /// [count] Number of digits to encode from the end
  /// Returns BCD-encoded bytes
  ///
  /// Example: encodeLastDigits("+905331234567", 8) → [0x31, 0x23, 0x45, 0x67]
  static Uint8List encodeLastDigits(String phoneNumber, int count) {
    final digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    if (digits.isEmpty) {
      return Uint8List(0);
    }

    final start = digits.length > count ? digits.length - count : 0;
    final lastDigits = digits.substring(start);

    return _encodeDigits(lastDigits);
  }

  /// Encode digit string to BCD bytes
  static Uint8List _encodeDigits(String digits) {
    // Calculate byte count (2 digits per byte, round up for odd length)
    final byteCount = (digits.length + 1) ~/ 2;
    final result = Uint8List(byteCount);

    for (int i = 0; i < digits.length; i += 2) {
      final highDigit = int.parse(digits[i]);

      int lowDigit;
      if (i + 1 < digits.length) {
        lowDigit = int.parse(digits[i + 1]);
      } else {
        lowDigit = _padding; // Padding for odd length
      }

      result[i ~/ 2] = (highDigit << 4) | lowDigit;
    }

    return result;
  }

  /// Decode BCD bytes to phone number string
  ///
  /// [encoded] BCD-encoded bytes
  /// Returns decoded phone number string (digits only)
  ///
  /// Example: [0x12, 0x34, 0x5F] → "12345"
  static String decode(Uint8List encoded) {
    if (encoded.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();

    for (int i = 0; i < encoded.length; i++) {
      final byte = encoded[i];
      final highNibble = (byte >> 4) & 0x0F;
      final lowNibble = byte & 0x0F;

      // High nibble
      if (highNibble <= 9) {
        buffer.write(highNibble);
      } else if (highNibble == _padding) {
        // Padding - skip
      } else {
        throw DecodingException(
          'Invalid BCD nibble: 0x${highNibble.toRadixString(16)}',
          offset: i,
        );
      }

      // Low nibble
      if (lowNibble <= 9) {
        buffer.write(lowNibble);
      } else if (lowNibble == _padding) {
        // Padding - skip (typically last nibble)
      } else {
        throw DecodingException(
          'Invalid BCD nibble: 0x${lowNibble.toRadixString(16)}',
          offset: i,
        );
      }
    }

    return buffer.toString();
  }

  /// Write BCD-encoded digits to buffer at offset
  ///
  /// [buffer] Destination buffer
  /// [offset] Starting offset
  /// [digits] Digit string to encode
  /// Returns number of bytes written
  static int write(Uint8List buffer, int offset, String digits) {
    final encoded = _encodeDigits(digits);
    buffer.setRange(offset, offset + encoded.length, encoded);
    return encoded.length;
  }

  /// Read BCD-encoded digits from buffer
  ///
  /// [buffer] Source buffer
  /// [offset] Starting offset
  /// [byteCount] Number of bytes to read
  /// Returns decoded digit string
  static String read(Uint8List buffer, int offset, int byteCount) {
    if (offset + byteCount > buffer.length) {
      throw DecodingException(
        'BCD read: insufficient data at offset $offset',
        offset: offset,
      );
    }

    return decode(buffer.sublist(offset, offset + byteCount));
  }

  /// Calculate the encoded byte count for a digit count
  ///
  /// [digitCount] Number of digits
  /// Returns number of bytes required
  static int encodedLength(int digitCount) {
    return (digitCount + 1) ~/ 2;
  }

  /// Format decoded phone number with country code
  ///
  /// [digits] Decoded digits (without country code)
  /// [countryCode] Country code to prepend (e.g., "+90")
  /// Returns formatted phone number
  static String format(String digits, {String countryCode = '+90'}) {
    return '$countryCode$digits';
  }
}
