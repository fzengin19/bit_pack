/// Text Location Payload (0x1C) - Protocol v1.1.1
///
/// Hybrid payload combining GPS coordinates, text message, and optional identity.
/// Optimized for low-bandwidth by avoiding delimiters.
///
/// Layout (v1.1.1):
/// ```
/// BYTE 0:     FLAGS
///             Bit 7: Has sender ID
///             Bit 6: Has recipient ID (0 = broadcast)
///             Bits 5-0: Reserved
/// [BYTES 1-N]: SENDER_ID length (1 byte) + SENDER_ID (UTF-8)
/// [BYTES N-M]: RECIPIENT_ID length (1 byte) + RECIPIENT_ID (UTF-8)
/// NEXT 8 BYTES: LAT (4 bytes) + LON (4 bytes) (fixed-point)
/// REMAINING:   TEXT (UTF-8, variable length)
/// ```

library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../core/types.dart';
import '../../encoding/gps.dart';
import 'payload.dart';

/// Hybrid payload with fixed-point GPS, text, and optional identity
class TextLocationPayload extends Payload with GeoPayload {
  /// Flag: has sender ID
  static const int _flagHasSender = 0x80;

  /// Flag: has recipient ID
  static const int _flagHasRecipient = 0x40;

  @override
  final double latitude;

  @override
  final double longitude;

  /// Text message content
  final String text;

  /// Sender identifier (optional)
  final String? senderId;

  /// Recipient identifier (null = broadcast)
  final String? recipientId;

  @override
  final int? altitude = null; // Altitude not supported in this compact format

  /// Create a text location payload
  TextLocationPayload({
    required this.latitude,
    required this.longitude,
    required this.text,
    this.senderId,
    this.recipientId,
  }) {
    // Validate coordinates
    if (!Gps.isValid(latitude, longitude)) {
      throw ArgumentError('Invalid coordinates: $latitude, $longitude');
    }
  }

  /// Create a broadcast text location message
  factory TextLocationPayload.broadcast(
    double latitude,
    double longitude,
    String text, {
    String? senderId,
  }) {
    return TextLocationPayload(
      latitude: latitude,
      longitude: longitude,
      text: text,
      senderId: senderId,
    );
  }

  /// Create a direct text location message
  factory TextLocationPayload.direct(
    double latitude,
    double longitude,
    String text, {
    required String recipientId,
    String? senderId,
  }) {
    return TextLocationPayload(
      latitude: latitude,
      longitude: longitude,
      text: text,
      senderId: senderId,
      recipientId: recipientId,
    );
  }

  @override
  MessageType get type => MessageType.textLocation;

  /// Check if this is a broadcast message
  bool get isBroadcast => recipientId == null;

  @override
  int get sizeInBytes {
    int size = 1; // FLAGS byte

    if (senderId != null) {
      size += 1 + utf8.encode(senderId!).length; // Length + data
    }

    if (recipientId != null) {
      size += 1 + utf8.encode(recipientId!).length; // Length + data
    }

    size += Gps.encodedSize; // GPS (8 bytes)
    size += utf8.encode(text).length; // Text

    return size;
  }

  @override
  Uint8List encode() {
    final textBytes = utf8.encode(text);
    final senderBytes = senderId != null ? utf8.encode(senderId!) : null;
    final recipientBytes = recipientId != null
        ? utf8.encode(recipientId!)
        : null;

    final buffer = Uint8List(sizeInBytes);
    int offset = 0;

    // BYTE 0: FLAGS
    int flags = 0;
    if (senderId != null) flags |= _flagHasSender;
    if (recipientId != null) flags |= _flagHasRecipient;
    buffer[offset++] = flags;

    // SENDER_ID (if present)
    if (senderBytes != null) {
      buffer[offset++] = senderBytes.length;
      buffer.setRange(offset, offset + senderBytes.length, senderBytes);
      offset += senderBytes.length;
    }

    // RECIPIENT_ID (if present)
    if (recipientBytes != null) {
      buffer[offset++] = recipientBytes.length;
      buffer.setRange(offset, offset + recipientBytes.length, recipientBytes);
      offset += recipientBytes.length;
    }

    // GPS (8 bytes at dynamic offset)
    Gps.write(buffer, offset, latitude, longitude);
    offset += Gps.encodedSize;

    // TEXT (remaining bytes)
    buffer.setRange(offset, offset + textBytes.length, textBytes);

    return buffer;
  }

  /// Decode from bytes
  factory TextLocationPayload.decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw DecodingException('TextLocationPayload: empty input');
    }

    int offset = 0;

    // BYTE 0: FLAGS
    final flags = bytes[offset++];
    final hasSender = (flags & _flagHasSender) != 0;
    final hasRecipient = (flags & _flagHasRecipient) != 0;

    String? senderId;
    String? recipientId;

    // SENDER_ID
    if (hasSender) {
      if (offset >= bytes.length) {
        throw DecodingException('TextLocationPayload: missing sender length');
      }
      final senderLen = bytes[offset++];
      if (offset + senderLen > bytes.length) {
        throw DecodingException('TextLocationPayload: truncated sender');
      }
      senderId = utf8.decode(bytes.sublist(offset, offset + senderLen));
      offset += senderLen;
    }

    // RECIPIENT_ID
    if (hasRecipient) {
      if (offset >= bytes.length) {
        throw DecodingException(
          'TextLocationPayload: missing recipient length',
        );
      }
      final recipientLen = bytes[offset++];
      if (offset + recipientLen > bytes.length) {
        throw DecodingException('TextLocationPayload: truncated recipient');
      }
      recipientId = utf8.decode(bytes.sublist(offset, offset + recipientLen));
      offset += recipientLen;
    }

    // GPS
    if (offset + Gps.encodedSize > bytes.length) {
      throw DecodingException(
        'TextLocationPayload: insufficient GPS data at offset $offset',
      );
    }
    final (lat, lon) = Gps.read(bytes, offset);
    offset += Gps.encodedSize;

    // TEXT
    final textBytes = bytes.sublist(offset);
    final text = utf8.decode(textBytes);

    return TextLocationPayload(
      latitude: lat,
      longitude: lon,
      text: text,
      senderId: senderId,
      recipientId: recipientId,
    );
  }

  @override
  Payload copy() {
    return TextLocationPayload(
      latitude: latitude,
      longitude: longitude,
      text: text,
      senderId: senderId,
      recipientId: recipientId,
    );
  }

  @override
  String toString() {
    final parts = <String>[];
    if (senderId != null) parts.add('from: $senderId');
    if (recipientId != null) {
      parts.add('to: $recipientId');
    } else {
      parts.add('broadcast');
    }
    parts.add('lat: $latitude');
    parts.add('lon: $longitude');
    final preview = text.length > 20 ? '${text.substring(0, 20)}...' : text;
    parts.add('text: "$preview"');
    return 'TextLocationPayload(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextLocationPayload &&
        (other.latitude - latitude).abs() < 0.0000001 &&
        (other.longitude - longitude).abs() < 0.0000001 &&
        other.text == text &&
        other.senderId == senderId &&
        other.recipientId == recipientId;
  }

  @override
  int get hashCode => Object.hash(
    latitude.toStringAsFixed(6),
    longitude.toStringAsFixed(6),
    text,
    senderId,
    recipientId,
  );
}
