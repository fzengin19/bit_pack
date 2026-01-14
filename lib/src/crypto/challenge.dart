/// BitPack Challenge Block
///
/// Zero-knowledge verification using encrypted challenge blocks.
/// Allows peers to verify they share the same secret without
/// revealing the secret itself.

library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

import '../core/exceptions.dart';
import 'aes_gcm.dart';

// ============================================================================
// CHALLENGE BLOCK
// ============================================================================

/// Challenge block for zero-knowledge secret verification
///
/// Creates encrypted challenge blocks containing a magic prefix.
/// If decryption succeeds and the magic prefix is correct, both
/// parties share the same secret.
///
/// Challenge format:
/// - Magic prefix: "BITPACK\x00" (8 bytes)
/// - Random padding: 8 bytes
/// - Total plaintext: 16 bytes
///
/// Encrypted format:
/// - Nonce: 12 bytes
/// - Ciphertext: 16 bytes
/// - Auth tag: 16 bytes
/// - Total: 44 bytes
///
/// Example:
/// ```dart
/// // Sender creates challenge
/// final challenge = await ChallengeBlock.create(sharedKey);
/// 
/// // Recipient verifies
/// final verified = await ChallengeBlock.verify(challenge, sharedKey);
/// if (verified) {
///   print('Shared secret confirmed!');
/// }
/// ```
class ChallengeBlock {
  /// Magic prefix for challenge verification
  /// "BITPACK\x00" = 8 bytes
  static const String magic = 'BITPACK\x00';

  /// Magic prefix as bytes
  static final Uint8List magicBytes = Uint8List.fromList(utf8.encode(magic));

  /// Random padding length
  static const int paddingLength = 8;

  /// Total plaintext length (magic + padding)
  static const int plaintextLength = 16;

  /// Total encrypted challenge length
  static int get encryptedLength => AesGcmCipher.encryptedSize(plaintextLength);

  /// Create an encrypted challenge block
  ///
  /// Generates "BITPACK\x00" + 8 random bytes, then encrypts with the key.
  ///
  /// Parameters:
  /// - [key]: Encryption key (16 or 32 bytes)
  ///
  /// Returns the encrypted challenge (44 bytes).
  ///
  /// Throws [CryptoException] if encryption fails.
  static Future<Uint8List> create(Uint8List key) async {
    // Create plaintext: magic (8 bytes) + random padding (8 bytes)
    final plaintext = Uint8List(plaintextLength);
    plaintext.setRange(0, magicBytes.length, magicBytes);

    // Add random padding
    final padding = crypto.SecretKeyData.random(length: paddingLength);
    plaintext.setRange(magicBytes.length, plaintextLength, padding.bytes);

    // Encrypt
    return AesGcmCipher.encrypt(
      plaintext: plaintext,
      key: key,
    );
  }

  /// Verify an encrypted challenge block
  ///
  /// Attempts to decrypt with the key and checks for magic prefix.
  /// Returns true only if both decryption succeeds AND magic matches.
  ///
  /// Parameters:
  /// - [encrypted]: Encrypted challenge block
  /// - [key]: Decryption key
  ///
  /// Returns true if verification succeeds, false otherwise.
  /// Does NOT throw exceptions for verification failures.
  static Future<bool> verify(Uint8List encrypted, Uint8List key) async {
    try {
      // Validate minimum length
      if (encrypted.length < AesGcmCipher.minCiphertextLength) {
        return false;
      }

      // Attempt decryption
      final plaintext = await AesGcmCipher.decrypt(
        ciphertext: encrypted,
        key: key,
      );

      // Check plaintext length
      if (plaintext.length != plaintextLength) {
        return false;
      }

      // Check magic prefix
      return _hasMagicPrefix(plaintext);
    } on AuthenticationException {
      // Wrong key or tampered data
      return false;
    } on DecryptionException {
      // Decryption failed
      return false;
    } catch (_) {
      // Any other error
      return false;
    }
  }

  /// Verify challenge and throw if invalid
  ///
  /// Same as [verify] but throws [ChallengeVerificationException]
  /// on failure instead of returning false.
  ///
  /// Parameters:
  /// - [encrypted]: Encrypted challenge block
  /// - [key]: Decryption key
  ///
  /// Throws [ChallengeVerificationException] if verification fails.
  static Future<void> verifyOrThrow(Uint8List encrypted, Uint8List key) async {
    final result = await verify(encrypted, key);
    if (!result) {
      throw const ChallengeVerificationException();
    }
  }

  /// Create a challenge-response pair
  ///
  /// Creates a challenge and its expected response.
  /// The response is the decrypted plaintext.
  ///
  /// Returns a record with (challenge, expectedResponse).
  static Future<({Uint8List challenge, Uint8List response})> createPair(
    Uint8List key,
  ) async {
    final challenge = await create(key);
    // Response is just the decrypted plaintext
    final response = await AesGcmCipher.decrypt(ciphertext: challenge, key: key);
    return (challenge: challenge, response: response);
  }

  /// Check if plaintext starts with magic prefix
  static bool _hasMagicPrefix(Uint8List plaintext) {
    if (plaintext.length < magicBytes.length) return false;

    for (var i = 0; i < magicBytes.length; i++) {
      if (plaintext[i] != magicBytes[i]) return false;
    }
    return true;
  }

  /// Validate key length
  static void validateKey(Uint8List key) {
    if (key.length != 16 && key.length != 32) {
      throw CryptoException(
        'Invalid key length: ${key.length}. Expected 16 (AES-128) or 32 (AES-256)',
      );
    }
  }
}
