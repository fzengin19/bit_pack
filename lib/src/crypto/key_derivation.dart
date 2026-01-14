/// BitPack Key Derivation
///
/// PBKDF2-SHA256 based key derivation for symmetric encryption.
/// Uses the `cryptography` package for secure key generation.

library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/exceptions.dart';

// ============================================================================
// KEY DERIVATION
// ============================================================================

/// Key derivation utilities using PBKDF2-SHA256
///
/// Used to derive AES encryption keys from shared secrets (security answers).
/// The derived key is deterministic given the same password and salt.
///
/// Example:
/// ```dart
/// final salt = KeyDerivation.generateSalt();
/// final key = await KeyDerivation.deriveKey(
///   password: 'shared secret answer',
///   salt: salt,
///   keyLength: 16, // AES-128
/// );
/// ```
class KeyDerivation {
  /// Default number of PBKDF2 iterations
  ///
  /// 10000 is a good balance between security and performance
  /// for mobile devices in emergency scenarios.
  static const int defaultIterations = 10000;

  /// Minimum allowed iterations
  static const int minIterations = 1000;

  /// Maximum allowed iterations
  static const int maxIterations = 1000000;

  /// Minimum salt length in bytes
  static const int minSaltLength = 8;

  /// Default salt length in bytes
  static const int defaultSaltLength = 16;

  /// Derive an AES key from a password using PBKDF2-SHA256
  ///
  /// Parameters:
  /// - [password]: The shared secret (e.g., security answer)
  /// - [salt]: Random salt bytes (minimum 8 bytes)
  /// - [keyLength]: Output key length (16 for AES-128, 32 for AES-256)
  /// - [iterations]: PBKDF2 iteration count (default: 10000)
  ///
  /// Returns a [Uint8List] containing the derived key.
  ///
  /// Throws [KeyDerivationException] if parameters are invalid.
  static Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
    int keyLength = 16,
    int iterations = defaultIterations,
  }) async {
    // Validate parameters
    if (password.isEmpty) {
      throw const KeyDerivationException('Password cannot be empty');
    }

    if (salt.length < minSaltLength) {
      throw KeyDerivationException(
        'Salt must be at least $minSaltLength bytes, got ${salt.length}',
      );
    }

    if (keyLength != 16 && keyLength != 32) {
      throw KeyDerivationException(
        'Key length must be 16 (AES-128) or 32 (AES-256), got $keyLength',
      );
    }

    if (iterations < minIterations || iterations > maxIterations) {
      throw KeyDerivationException(
        'Iterations must be between $minIterations and $maxIterations, got $iterations',
      );
    }

    try {
      // Use PBKDF2 with SHA-256
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: keyLength * 8,
      );

      // Derive the key
      final secretKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      // Extract raw bytes
      final keyBytes = await secretKey.extractBytes();
      return Uint8List.fromList(keyBytes);
    } catch (e) {
      throw KeyDerivationException('Key derivation failed', e);
    }
  }

  /// Generate a cryptographically secure random salt
  ///
  /// Parameters:
  /// - [length]: Salt length in bytes (default: 16)
  ///
  /// Returns a [Uint8List] containing random bytes.
  static Uint8List generateSalt([int length = defaultSaltLength]) {
    if (length < minSaltLength) {
      throw KeyDerivationException(
        'Salt length must be at least $minSaltLength bytes, got $length',
      );
    }

    // Use secure random from cryptography package
    final random = SecretKeyData.random(length: length);
    return Uint8List.fromList(random.bytes);
  }

  /// Create a combined salt from sender, recipient, and message IDs
  ///
  /// This is useful for creating unique salts for each message
  /// without requiring additional random data exchange.
  ///
  /// Format: sender_id (8 bytes) || recipient_id (8 bytes) || msg_id (4 bytes)
  static Uint8List createMessageSalt({
    required Uint8List senderId,
    required Uint8List recipientId,
    required int messageId,
  }) {
    // Normalize sender/recipient to 8 bytes
    final senderPadded = _padOrTruncate(senderId, 8);
    final recipientPadded = _padOrTruncate(recipientId, 8);

    // Create salt: sender || recipient || message_id
    final salt = Uint8List(20);
    salt.setRange(0, 8, senderPadded);
    salt.setRange(8, 16, recipientPadded);

    // Add message ID as 4 bytes (big-endian)
    salt[16] = (messageId >> 24) & 0xFF;
    salt[17] = (messageId >> 16) & 0xFF;
    salt[18] = (messageId >> 8) & 0xFF;
    salt[19] = messageId & 0xFF;

    return salt;
  }

  /// Pad or truncate bytes to a specific length
  static Uint8List _padOrTruncate(Uint8List data, int length) {
    if (data.length == length) return data;
    if (data.length > length) return Uint8List.fromList(data.sublist(0, length));

    // Pad with zeros
    final padded = Uint8List(length);
    padded.setRange(0, data.length, data);
    return padded;
  }
}
