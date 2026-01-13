/// Text Payload
///
/// UTF-8 text message payload with optional sender/recipient identifiers.
///
/// Layout:
/// ```
/// BYTE 0:     FLAGS
///             Bit 7: Has sender ID
///             Bit 6: Has recipient ID (0 = broadcast)
///             Bits 5-0: Reserved
/// [BYTES 1-N]: SENDER_ID length (1 byte) + SENDER_ID (UTF-8)
/// [BYTES N-M]: RECIPIENT_ID length (1 byte) + RECIPIENT_ID (UTF-8)
/// REMAINING:   TEXT (UTF-8, variable length)
/// ```

library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../core/types.dart';
import 'payload.dart';

/// Text message payload
class TextPayload extends Payload {
  /// Maximum text length for standard mode
  static const int maxTextLength = 8000; // Leave room for headers

  /// Flag: has sender ID
  static const int _flagHasSender = 0x80;

  /// Flag: has recipient ID
  static const int _flagHasRecipient = 0x40;

  /// Message text (UTF-8)
  final String text;

  /// Sender identifier (optional)
  final String? senderId;

  /// Recipient identifier (null = broadcast)
  final String? recipientId;

  /// Create a new text payload
  TextPayload({required this.text, this.senderId, this.recipientId}) {
    if (text.isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    final textBytes = utf8.encode(text);
    if (textBytes.length > maxTextLength) {
      throw ArgumentError(
        'Text too long: ${textBytes.length} bytes (max $maxTextLength)',
      );
    }
  }

  /// Create a broadcast text message
  factory TextPayload.broadcast(String text, {String? senderId}) {
    return TextPayload(text: text, senderId: senderId);
  }

  /// Create a direct text message
  factory TextPayload.direct(
    String text, {
    required String recipientId,
    String? senderId,
  }) {
    return TextPayload(
      text: text,
      recipientId: recipientId,
      senderId: senderId,
    );
  }

  @override
  MessageType get type => MessageType.textShort;

  /// Check if this is a broadcast message
  bool get isBroadcast => recipientId == null;

  @override
  int get sizeInBytes {
    int size = 1; // Flags byte

    if (senderId != null) {
      size += 1 + utf8.encode(senderId!).length; // Length + data
    }

    if (recipientId != null) {
      size += 1 + utf8.encode(recipientId!).length; // Length + data
    }

    size += utf8.encode(text).length;

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

    // TEXT
    buffer.setRange(offset, offset + textBytes.length, textBytes);

    return buffer;
  }

  /// Decode text payload from bytes
  factory TextPayload.decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw DecodingException('TextPayload: empty input');
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
        throw DecodingException('TextPayload: missing sender length');
      }
      final senderLen = bytes[offset++];
      if (offset + senderLen > bytes.length) {
        throw DecodingException('TextPayload: truncated sender');
      }
      senderId = utf8.decode(bytes.sublist(offset, offset + senderLen));
      offset += senderLen;
    }

    // RECIPIENT_ID
    if (hasRecipient) {
      if (offset >= bytes.length) {
        throw DecodingException('TextPayload: missing recipient length');
      }
      final recipientLen = bytes[offset++];
      if (offset + recipientLen > bytes.length) {
        throw DecodingException('TextPayload: truncated recipient');
      }
      recipientId = utf8.decode(bytes.sublist(offset, offset + recipientLen));
      offset += recipientLen;
    }

    // TEXT
    if (offset >= bytes.length) {
      throw DecodingException('TextPayload: missing text');
    }
    final text = utf8.decode(bytes.sublist(offset));

    return TextPayload(
      text: text,
      senderId: senderId,
      recipientId: recipientId,
    );
  }

  @override
  TextPayload copy() {
    return TextPayload(
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
    final preview = text.length > 30 ? '${text.substring(0, 30)}...' : text;
    parts.add('text: "$preview"');
    return 'TextPayload(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextPayload &&
        other.text == text &&
        other.senderId == senderId &&
        other.recipientId == recipientId;
  }

  @override
  int get hashCode => Object.hash(text, senderId, recipientId);
}
