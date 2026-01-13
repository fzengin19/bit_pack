/// VarInt Encoding/Decoding
///
/// Variable-length integer encoding using continuation bit scheme.
/// Similar to Protocol Buffers varint encoding.
///
/// Encoding scheme:
/// - Each byte uses 7 bits for data, bit 7 as continuation flag
/// - If bit 7 = 1, more bytes follow
/// - If bit 7 = 0, this is the last byte
///
/// Size:
/// - Values 0-127: 1 byte
/// - Values 128-16383: 2 bytes
/// - Values 16384-2097151: 3 bytes
/// - Values 2097152-268435455: 4 bytes
/// - Larger values: 5 bytes

library;

import 'dart:typed_data';

import '../core/exceptions.dart';

/// VarInt encoder/decoder for compact integer representation
class VarInt {
  VarInt._(); // Prevent instantiation

  /// Maximum value that can be encoded (5 bytes = 35 bits)
  static const int maxValue = 0x7FFFFFFFF; // 34359738367

  /// Continuation bit mask (bit 7)
  static const int _continuationBit = 0x80;

  /// Data bits mask (bits 0-6)
  static const int _dataBits = 0x7F;

  /// Calculate the encoded length for a value
  ///
  /// [value] Non-negative integer to encode
  /// Returns number of bytes required (1-5)
  static int encodedLength(int value) {
    if (value < 0) {
      throw ArgumentError('VarInt cannot encode negative values: $value');
    }
    if (value < 128) return 1; // 2^7
    if (value < 16384) return 2; // 2^14
    if (value < 2097152) return 3; // 2^21
    if (value < 268435456) return 4; // 2^28
    return 5;
  }

  /// Encode a value to VarInt bytes
  ///
  /// [value] Non-negative integer to encode
  /// Returns Uint8List containing the encoded bytes
  static Uint8List encode(int value) {
    if (value < 0) {
      throw ArgumentError('VarInt cannot encode negative values: $value');
    }

    final length = encodedLength(value);
    final result = Uint8List(length);
    var remaining = value;

    for (int i = 0; i < length; i++) {
      if (i == length - 1) {
        // Last byte: no continuation bit
        result[i] = remaining & _dataBits;
      } else {
        // More bytes follow: set continuation bit
        result[i] = (remaining & _dataBits) | _continuationBit;
        remaining >>= 7;
      }
    }

    return result;
  }

  /// Write VarInt to buffer at offset
  ///
  /// [buffer] Destination buffer
  /// [offset] Starting offset
  /// [value] Value to encode
  /// Returns number of bytes written
  static int write(Uint8List buffer, int offset, int value) {
    if (value < 0) {
      throw ArgumentError('VarInt cannot encode negative values: $value');
    }

    var remaining = value;
    int bytesWritten = 0;

    do {
      int byte = remaining & _dataBits;
      remaining >>= 7;

      if (remaining != 0) {
        byte |= _continuationBit;
      }

      buffer[offset + bytesWritten] = byte;
      bytesWritten++;
    } while (remaining != 0);

    return bytesWritten;
  }

  /// Decode VarInt from bytes
  ///
  /// [bytes] Source bytes
  /// [offset] Starting offset (default 0)
  /// Returns tuple of (decodedValue, bytesRead)
  ///
  /// Throws [DecodingException] if data is truncated
  static (int value, int bytesRead) decode(Uint8List bytes, [int offset = 0]) {
    if (offset >= bytes.length) {
      throw DecodingException('VarInt decode: no data at offset $offset');
    }

    int value = 0;
    int shift = 0;
    int bytesRead = 0;

    while (true) {
      if (offset + bytesRead >= bytes.length) {
        throw DecodingException(
          'VarInt decode: truncated data at offset ${offset + bytesRead}',
        );
      }

      final byte = bytes[offset + bytesRead];
      value |= (byte & _dataBits) << shift;
      bytesRead++;

      if ((byte & _continuationBit) == 0) {
        // Last byte
        break;
      }

      shift += 7;

      // Safety check for overflow (max 5 bytes)
      if (bytesRead >= 5) {
        throw DecodingException('VarInt decode: value too large (> 5 bytes)');
      }
    }

    return (value, bytesRead);
  }

  /// Read VarInt from ByteData
  ///
  /// [data] Source ByteData
  /// [offset] Starting offset
  /// Returns tuple of (decodedValue, bytesRead)
  static (int value, int bytesRead) read(ByteData data, int offset) {
    int value = 0;
    int shift = 0;
    int bytesRead = 0;

    while (true) {
      if (offset + bytesRead >= data.lengthInBytes) {
        throw DecodingException(
          'VarInt read: truncated data at offset ${offset + bytesRead}',
        );
      }

      final byte = data.getUint8(offset + bytesRead);
      value |= (byte & _dataBits) << shift;
      bytesRead++;

      if ((byte & _continuationBit) == 0) {
        break;
      }

      shift += 7;

      if (bytesRead >= 5) {
        throw DecodingException('VarInt read: value too large (> 5 bytes)');
      }
    }

    return (value, bytesRead);
  }

  /// Encode a signed integer using ZigZag encoding
  ///
  /// ZigZag maps signed integers to unsigned:
  /// 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3, 2 -> 4, ...
  ///
  /// This allows efficient VarInt encoding of small negative numbers.
  static int zigZagEncode(int value) {
    return (value << 1) ^ (value >> 63);
  }

  /// Decode a ZigZag-encoded value back to signed
  static int zigZagDecode(int encoded) {
    return (encoded >> 1) ^ -(encoded & 1);
  }

  /// Encode a signed integer to VarInt bytes using ZigZag
  static Uint8List encodeSigned(int value) {
    return encode(zigZagEncode(value));
  }

  /// Decode VarInt bytes to signed integer using ZigZag
  static (int value, int bytesRead) decodeSigned(
    Uint8List bytes, [
    int offset = 0,
  ]) {
    final (encoded, bytesRead) = decode(bytes, offset);
    return (zigZagDecode(encoded), bytesRead);
  }
}
