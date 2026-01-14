/// Challenge Payload (0x1D)
///
/// Secure challenge payload for zero-knowledge verification.
///
/// Layout:
/// [SALT: 16 bytes][Q_LEN: 1 byte][QUESTION: N bytes][CIPHERTEXT: Remaining]

library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/types.dart';
import '../../core/exceptions.dart';
import 'payload.dart';

/// Secure challenge payload
class ChallengePayload extends Payload {
  /// Random salt (16 bytes)
  final Uint8List salt;

  /// Challenge question text
  final String question;

  /// Encrypted answer/nonce (ciphertext)
  final Uint8List ciphertext;

  /// Create a challenge payload
  ChallengePayload({
    required this.salt,
    required this.question,
    required this.ciphertext,
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

  @override
  MessageType get type => MessageType.challenge;

  @override
  int get sizeInBytes {
    final qLen = utf8.encode(question).length;
    return 16 + 1 + qLen + ciphertext.length;
  }

  @override
  Uint8List encode() {
    final qBytes = utf8.encode(question);
    final size = 16 + 1 + qBytes.length + ciphertext.length;
    final buffer = Uint8List(size);

    // 1. Write Salt (16 bytes)
    buffer.setRange(0, 16, salt);

    // 2. Write Question Length (1 byte)
    buffer[16] = qBytes.length;

    // 3. Write Question Bytes
    buffer.setRange(17, 17 + qBytes.length, qBytes);

    // 4. Write Ciphertext (Remaining)
    buffer.setRange(17 + qBytes.length, size, ciphertext);

    return buffer;
  }

  /// Decode from bytes
  factory ChallengePayload.decode(Uint8List bytes) {
    if (bytes.length < 17) {
      throw DecodingException(
        'ChallengePayload too short: ${bytes.length} bytes (min 17)',
      );
    }

    // 1. Read Salt
    final salt = bytes.sublist(0, 16);

    // 2. Read Question Length
    final qLen = bytes[16];

    // Check bounds
    if (bytes.length < 17 + qLen) {
      throw DecodingException(
        'ChallengePayload truncated question: expected $qLen bytes, '
        'available ${bytes.length - 17}',
      );
    }

    // 3. Read Question
    final qBytes = bytes.sublist(17, 17 + qLen);
    final question = utf8.decode(qBytes);

    // 4. Read Ciphertext
    final ciphertext = bytes.sublist(17 + qLen);

    return ChallengePayload(
      salt: salt,
      question: question,
      ciphertext: ciphertext,
    );
  }

  @override
  Payload copy() {
    return ChallengePayload(
      salt: Uint8List.fromList(salt),
      question: question,
      ciphertext: Uint8List.fromList(ciphertext),
    );
  }

  @override
  String toString() {
    return 'ChallengePayload('
        'salt: ${salt.length}B, '
        'q: "$question", '
        'cipher: ${ciphertext.length}B)';
  }
}
