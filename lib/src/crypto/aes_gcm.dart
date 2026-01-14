/// BitPack AES-GCM Encryption
///
/// AES-GCM authenticated encryption for secure message payloads.
/// Uses the `cryptography` package for encryption/decryption.

library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;

import '../core/exceptions.dart';

// ============================================================================
// AES-GCM ENCRYPTION
// ============================================================================

/// AES-GCM authenticated encryption/decryption
///
/// Output format: nonce (12 bytes) + ciphertext + auth_tag (16 bytes)
///
/// Supports both AES-128-GCM (16-byte key) and AES-256-GCM (32-byte key).
///
/// Example:
/// ```dart
/// final key = await KeyDerivation.deriveKey(...);
/// 
/// // Encrypt
/// final encrypted = await AesGcmCipher.encrypt(
///   plaintext: utf8.encode('Hello, world!'),
///   key: key,
/// );
/// 
/// // Decrypt
/// final decrypted = await AesGcmCipher.decrypt(
///   ciphertext: encrypted,
///   key: key,
/// );
/// ```
class AesGcmCipher {
  /// Nonce length in bytes (96 bits is recommended for AES-GCM)
  static const int nonceLength = 12;

  /// Authentication tag length in bytes (128 bits)
  static const int tagLength = 16;

  /// Minimum ciphertext length (nonce + tag, no plaintext)
  static const int minCiphertextLength = nonceLength + tagLength;

  /// Encrypt plaintext with AES-GCM
  ///
  /// Parameters:
  /// - [plaintext]: Data to encrypt
  /// - [key]: Encryption key (16 bytes for AES-128, 32 bytes for AES-256)
  /// - [additionalData]: Optional AAD (e.g., packet header for integrity)
  /// - [nonce]: Optional custom nonce (12 bytes). Random if not provided.
  ///
  /// Returns: nonce (12 bytes) + ciphertext + auth_tag (16 bytes)
  ///
  /// Throws [CryptoException] if encryption fails.
  static Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required Uint8List key,
    Uint8List? additionalData,
    Uint8List? nonce,
  }) async {
    // Validate key length
    if (key.length != 16 && key.length != 32) {
      throw CryptoException(
        'Invalid key length: ${key.length}. Expected 16 (AES-128) or 32 (AES-256)',
      );
    }

    try {
      // Select algorithm based on key length
      final algorithm = key.length == 16 
          ? crypto.AesGcm.with128bits() 
          : crypto.AesGcm.with256bits();

      // Generate or use provided nonce
      final actualNonce = nonce ?? _generateNonce();
      if (actualNonce.length != nonceLength) {
        throw CryptoException(
          'Invalid nonce length: ${actualNonce.length}. Expected $nonceLength',
        );
      }

      // Encrypt
      final secretBox = await algorithm.encrypt(
        plaintext,
        secretKey: crypto.SecretKey(key),
        nonce: actualNonce,
        aad: additionalData ?? Uint8List(0),
      );

      // Combine: nonce + ciphertext + tag
      final ciphertextLen = secretBox.cipherText.length;
      final result = Uint8List(nonceLength + ciphertextLen + tagLength);

      result.setRange(0, nonceLength, actualNonce);
      result.setRange(nonceLength, nonceLength + ciphertextLen, secretBox.cipherText);
      result.setRange(result.length - tagLength, result.length, secretBox.mac.bytes);

      return result;
    } catch (e) {
      if (e is CryptoException) rethrow;
      throw CryptoException('Encryption failed', e);
    }
  }

  /// Decrypt ciphertext with AES-GCM
  ///
  /// Parameters:
  /// - [ciphertext]: Encrypted data (nonce + ciphertext + tag)
  /// - [key]: Decryption key (must match encryption key)
  /// - [additionalData]: Optional AAD (must match encryption AAD)
  ///
  /// Returns the decrypted plaintext.
  ///
  /// Throws [AuthenticationException] if the auth tag is invalid.
  /// Throws [DecryptionException] if decryption fails.
  static Future<Uint8List> decrypt({
    required Uint8List ciphertext,
    required Uint8List key,
    Uint8List? additionalData,
  }) async {
    // Validate key length
    if (key.length != 16 && key.length != 32) {
      throw CryptoException(
        'Invalid key length: ${key.length}. Expected 16 (AES-128) or 32 (AES-256)',
      );
    }

    // Validate ciphertext length
    if (ciphertext.length < minCiphertextLength) {
      throw DecryptionException(
        'Ciphertext too short: ${ciphertext.length} bytes. '
        'Minimum: $minCiphertextLength (nonce + tag)',
      );
    }

    try {
      // Select algorithm based on key length
      final algorithm = key.length == 16 
          ? crypto.AesGcm.with128bits() 
          : crypto.AesGcm.with256bits();

      // Extract components
      final extractedNonce = ciphertext.sublist(0, nonceLength);
      final encryptedData = ciphertext.sublist(
        nonceLength, 
        ciphertext.length - tagLength,
      );
      final tag = ciphertext.sublist(ciphertext.length - tagLength);

      // Create SecretBox
      final secretBox = crypto.SecretBox(
        encryptedData,
        nonce: extractedNonce,
        mac: crypto.Mac(tag),
      );

      // Decrypt and verify
      final decrypted = await algorithm.decrypt(
        secretBox,
        secretKey: crypto.SecretKey(key),
        aad: additionalData ?? Uint8List(0),
      );

      return Uint8List.fromList(decrypted);
    } on crypto.SecretBoxAuthenticationError {
      throw const AuthenticationException();
    } catch (e) {
      if (e is AuthenticationException) rethrow;
      if (e is DecryptionException) rethrow;
      throw DecryptionException('Decryption failed', e);
    }
  }

  /// Encrypt with AAD (Associated Authenticated Data)
  ///
  /// Convenience method for encrypting payload with header as AAD.
  /// This ensures the header cannot be modified without detection.
  ///
  /// Parameters:
  /// - [plaintext]: Payload to encrypt
  /// - [key]: Encryption key
  /// - [header]: Packet header bytes (authenticated but not encrypted)
  static Future<Uint8List> encryptWithHeader({
    required Uint8List plaintext,
    required Uint8List key,
    required Uint8List header,
  }) {
    return encrypt(
      plaintext: plaintext,
      key: key,
      additionalData: header,
    );
  }

  /// Decrypt with AAD (Associated Authenticated Data)
  ///
  /// Convenience method for decrypting payload with header as AAD.
  ///
  /// Parameters:
  /// - [ciphertext]: Encrypted payload
  /// - [key]: Decryption key
  /// - [header]: Packet header bytes (must match encryption header)
  static Future<Uint8List> decryptWithHeader({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List header,
  }) {
    return decrypt(
      ciphertext: ciphertext,
      key: key,
      additionalData: header,
    );
  }

  /// Generate a cryptographically secure random nonce
  static Uint8List _generateNonce() {
    final random = crypto.SecretKeyData.random(length: nonceLength);
    return Uint8List.fromList(random.bytes);
  }

  /// Calculate the encrypted size for a given plaintext size
  ///
  /// Encrypted size = nonceLength + plaintextLength + tagLength
  static int encryptedSize(int plaintextLength) {
    return nonceLength + plaintextLength + tagLength;
  }

  /// Calculate the maximum plaintext size for a given encrypted size
  ///
  /// Plaintext size = encryptedLength - nonceLength - tagLength
  static int maxPlaintextSize(int encryptedLength) {
    if (encryptedLength < minCiphertextLength) return 0;
    return encryptedLength - nonceLength - tagLength;
  }
}
