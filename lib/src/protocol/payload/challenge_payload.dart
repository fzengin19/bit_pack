/// Challenge Payload (0x1D) - Protocol v1.1.1
///
/// Secure challenge payload for zero-knowledge verification with optional identity.
///
/// Layout (v1.1.1):
/// ```
/// BYTE 0:     FLAGS
///             Bit 7: Has sender ID
///             Bit 6: Has recipient ID
///             Bits 5-0: Reserved
/// [BYTES 1-N]: SENDER_ID length (1 byte) + SENDER_ID (UTF-8)
/// [BYTES N-M]: RECIPIENT_ID length (1 byte) + RECIPIENT_ID (UTF-8)
/// NEXT 16 BYTES: SALT
/// NEXT 1 BYTE:  Q_LEN (question length)
/// NEXT Q_LEN:   QUESTION (UTF-8)
/// REMAINING:    CIPHERTEXT
/// ```

library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/types.dart';
import '../../core/exceptions.dart';
import 'payload.dart';

/// Secure challenge payload with optional identity
class ChallengePayload extends Payload {
  /// Flag: has sender ID
  static const int _flagHasSender = 0x80;

  /// Flag: has recipient ID
  static const int _flagHasRecipient = 0x40;

  /// Random salt (16 bytes)
  final Uint8List salt;

  /// Challenge question text
  final String question;

  /// Encrypted answer/nonce (ciphertext)
  final Uint8List ciphertext;

  /// Sender identifier (optional)
  final String? senderId;

  /// Recipient identifier (optional)
  final String? recipientId;

  /// Create a challenge payload
  ChallengePayload({
    required this.salt,
    required this.question,
    required this.ciphertext,
    this.senderId,
    this.recipientId,
  }) {
    // Validate salt length
    if (salt.length != 16) {
      throw ArgumentError('Salt must be 16 bytes, got ${salt.length}');
    }

    // Validate question length (max 255 bytes UTF-8)
    final qBytes = utf8.encode(question);
    if (qBytes.length > 255) {
      throw ArgumentError(
        'Question too long: ${qBytes.length} bytes (max 255)',
      );
    }
  }

  /// Create a broadcast challenge
  factory ChallengePayload.broadcast({
    required Uint8List salt,
    required String question,
    required Uint8List ciphertext,
    String? senderId,
  }) {
    return ChallengePayload(
      salt: salt,
      question: question,
      ciphertext: ciphertext,
      senderId: senderId,
    );
  }

  /// Create a direct challenge to a specific recipient
  factory ChallengePayload.direct({
    required Uint8List salt,
    required String question,
    required Uint8List ciphertext,
    required String recipientId,
    String? senderId,
  }) {
    return ChallengePayload(
      salt: salt,
      question: question,
      ciphertext: ciphertext,
      senderId: senderId,
      recipientId: recipientId,
    );
  }

  @override
  MessageType get type => MessageType.challenge;

  /// Check if this is a broadcast challenge
  bool get isBroadcast => recipientId == null;

  @override
  int get sizeInBytes {
    int size = 1; // FLAGS byte

    if (senderId != null) {
      size += 1 + utf8.encode(senderId!).length;
    }

    if (recipientId != null) {
      size += 1 + utf8.encode(recipientId!).length;
    }

    final qLen = utf8.encode(question).length;
    size +=
        16 +
        1 +
        qLen +
        ciphertext.length; // Salt + QLen + Question + Ciphertext

    return size;
  }

  @override
  Uint8List encode() {
    final qBytes = utf8.encode(question);
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

    // SALT (16 bytes)
    buffer.setRange(offset, offset + 16, salt);
    offset += 16;

    // Q_LEN (1 byte)
    buffer[offset++] = qBytes.length;

    // QUESTION
    buffer.setRange(offset, offset + qBytes.length, qBytes);
    offset += qBytes.length;

    // CIPHERTEXT (remaining)
    buffer.setRange(offset, offset + ciphertext.length, ciphertext);

    return buffer;
  }

  /// Decode from bytes
  factory ChallengePayload.decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw DecodingException('ChallengePayload: empty input');
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
        throw DecodingException('ChallengePayload: missing sender length');
      }
      final senderLen = bytes[offset++];
      if (offset + senderLen > bytes.length) {
        throw DecodingException('ChallengePayload: truncated sender');
      }
      senderId = utf8.decode(bytes.sublist(offset, offset + senderLen));
      offset += senderLen;
    }

    // RECIPIENT_ID
    if (hasRecipient) {
      if (offset >= bytes.length) {
        throw DecodingException('ChallengePayload: missing recipient length');
      }
      final recipientLen = bytes[offset++];
      if (offset + recipientLen > bytes.length) {
        throw DecodingException('ChallengePayload: truncated recipient');
      }
      recipientId = utf8.decode(bytes.sublist(offset, offset + recipientLen));
      offset += recipientLen;
    }

    // SALT (16 bytes)
    if (offset + 16 > bytes.length) {
      throw DecodingException(
        'ChallengePayload: insufficient salt data at offset $offset',
      );
    }
    final salt = bytes.sublist(offset, offset + 16);
    offset += 16;

    // Q_LEN
    if (offset >= bytes.length) {
      throw DecodingException('ChallengePayload: missing question length');
    }
    final qLen = bytes[offset++];

    // QUESTION
    if (offset + qLen > bytes.length) {
      throw DecodingException(
        'ChallengePayload: truncated question, expected $qLen bytes, '
        'available ${bytes.length - offset}',
      );
    }
    final qBytes = bytes.sublist(offset, offset + qLen);
    final question = utf8.decode(qBytes);
    offset += qLen;

    // CIPHERTEXT (remaining)
    final ciphertext = bytes.sublist(offset);

    return ChallengePayload(
      salt: Uint8List.fromList(salt),
      question: question,
      ciphertext: Uint8List.fromList(ciphertext),
      senderId: senderId,
      recipientId: recipientId,
    );
  }

  @override
  Payload copy() {
    return ChallengePayload(
      salt: Uint8List.fromList(salt),
      question: question,
      ciphertext: Uint8List.fromList(ciphertext),
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
    parts.add('salt: ${salt.length}B');
    parts.add('q: "$question"');
    parts.add('cipher: ${ciphertext.length}B');
    return 'ChallengePayload(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChallengePayload) return false;
    if (other.question != question) return false;
    if (other.senderId != senderId) return false;
    if (other.recipientId != recipientId) return false;
    if (other.salt.length != salt.length) return false;
    for (int i = 0; i < salt.length; i++) {
      if (other.salt[i] != salt[i]) return false;
    }
    if (other.ciphertext.length != ciphertext.length) return false;
    for (int i = 0; i < ciphertext.length; i++) {
      if (other.ciphertext[i] != ciphertext[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    question,
    senderId,
    recipientId,
    Object.hashAll(salt),
    Object.hashAll(ciphertext),
  );
}
