import 'dart:convert';
import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('AesGcmCipher', () {
    late Uint8List key128;
    late Uint8List key256;

    setUp(() async {
      // Generate test keys
      final salt = KeyDerivation.generateSalt();
      key128 = await KeyDerivation.deriveKey(
        password: 'test key 128',
        salt: salt,
        keyLength: 16,
      );
      key256 = await KeyDerivation.deriveKey(
        password: 'test key 256',
        salt: salt,
        keyLength: 32,
      );
    });

    group('encrypt/decrypt roundtrip', () {
      test('encrypts and decrypts with AES-128-GCM', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Hello, World!'));

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        final decrypted = await AesGcmCipher.decrypt(
          ciphertext: encrypted,
          key: key128,
        );

        expect(decrypted, equals(plaintext));
      });

      test('encrypts and decrypts with AES-256-GCM', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Hello, World!'));

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key256,
        );

        final decrypted = await AesGcmCipher.decrypt(
          ciphertext: encrypted,
          key: key256,
        );

        expect(decrypted, equals(plaintext));
      });

      test('works with empty plaintext', () async {
        final plaintext = Uint8List(0);

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        final decrypted = await AesGcmCipher.decrypt(
          ciphertext: encrypted,
          key: key128,
        );

        expect(decrypted, equals(plaintext));
      });

      test('works with large plaintext', () async {
        final plaintext = Uint8List.fromList(
          List.generate(10000, (i) => i % 256),
        );

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key256,
        );

        final decrypted = await AesGcmCipher.decrypt(
          ciphertext: encrypted,
          key: key256,
        );

        expect(decrypted, equals(plaintext));
      });

      test('works with Turkish characters', () async {
        final plaintext = Uint8List.fromList(
          utf8.encode('Merhaba Dünya! Şifreli mesaj.'),
        );

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        final decrypted = await AesGcmCipher.decrypt(
          ciphertext: encrypted,
          key: key128,
        );

        expect(utf8.decode(decrypted), equals('Merhaba Dünya! Şifreli mesaj.'));
      });
    });

    group('ciphertext structure', () {
      test('output has correct format: nonce + ciphertext + tag', () async {
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        // Expected: 12 (nonce) + 5 (plaintext) + 16 (tag) = 33 bytes
        expect(encrypted.length, equals(33));
      });

      test('encryptedSize calculates correct output length', () {
        expect(AesGcmCipher.encryptedSize(0), equals(28)); // nonce + tag
        expect(AesGcmCipher.encryptedSize(10), equals(38));
        expect(AesGcmCipher.encryptedSize(100), equals(128));
      });

      test('maxPlaintextSize calculates correct input length', () {
        expect(AesGcmCipher.maxPlaintextSize(28), equals(0)); // min size
        expect(AesGcmCipher.maxPlaintextSize(38), equals(10));
        expect(AesGcmCipher.maxPlaintextSize(128), equals(100));
        expect(AesGcmCipher.maxPlaintextSize(20), equals(0)); // too small
      });

      test('same plaintext produces different ciphertext each time', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Same message'));

        final encrypted1 = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        final encrypted2 = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        // Different nonces should produce different ciphertexts
        expect(encrypted1, isNot(equals(encrypted2)));
      });
    });

    group('authentication', () {
      test('wrong key throws AuthenticationException', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Secret message'));

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        // Try to decrypt with different key
        expect(
          () => AesGcmCipher.decrypt(ciphertext: encrypted, key: key256),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('tampered ciphertext throws AuthenticationException', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Secret message'));

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        // Tamper with ciphertext
        encrypted[15] ^= 0xFF;

        expect(
          () => AesGcmCipher.decrypt(ciphertext: encrypted, key: key128),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('tampered tag throws AuthenticationException', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Secret message'));

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
        );

        // Tamper with auth tag (last 16 bytes)
        encrypted[encrypted.length - 1] ^= 0xFF;

        expect(
          () => AesGcmCipher.decrypt(ciphertext: encrypted, key: key128),
          throwsA(isA<AuthenticationException>()),
        );
      });
    });

    group('AAD (Additional Authenticated Data)', () {
      test('encrypt/decrypt with AAD works', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Payload'));
        final header = Uint8List.fromList([0x80, 0x12, 0x34, 0x56]);

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
          additionalData: header,
        );

        final decrypted = await AesGcmCipher.decrypt(
          ciphertext: encrypted,
          key: key128,
          additionalData: header,
        );

        expect(decrypted, equals(plaintext));
      });

      test('wrong AAD throws AuthenticationException', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Payload'));
        final header = Uint8List.fromList([0x80, 0x12, 0x34, 0x56]);
        final wrongHeader = Uint8List.fromList([0x80, 0x12, 0x34, 0x00]);

        final encrypted = await AesGcmCipher.encrypt(
          plaintext: plaintext,
          key: key128,
          additionalData: header,
        );

        expect(
          () => AesGcmCipher.decrypt(
            ciphertext: encrypted,
            key: key128,
            additionalData: wrongHeader,
          ),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('encryptWithHeader convenience method works', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Payload'));
        final header = Uint8List.fromList([0x80, 0x12, 0x34, 0x56]);

        final encrypted = await AesGcmCipher.encryptWithHeader(
          plaintext: plaintext,
          key: key128,
          header: header,
        );

        final decrypted = await AesGcmCipher.decryptWithHeader(
          ciphertext: encrypted,
          key: key128,
          header: header,
        );

        expect(decrypted, equals(plaintext));
      });
    });

    group('error handling', () {
      test('throws on invalid key length', () async {
        final invalidKey = Uint8List(24); // Invalid: should be 16 or 32
        final plaintext = Uint8List.fromList([1, 2, 3]);

        expect(
          () => AesGcmCipher.encrypt(plaintext: plaintext, key: invalidKey),
          throwsA(isA<CryptoException>()),
        );
      });

      test('throws on ciphertext too short', () async {
        final shortCiphertext = Uint8List(20); // Less than nonce + tag

        expect(
          () => AesGcmCipher.decrypt(ciphertext: shortCiphertext, key: key128),
          throwsA(isA<DecryptionException>()),
        );
      });

      test('throws on invalid nonce length', () async {
        final plaintext = Uint8List.fromList([1, 2, 3]);
        final invalidNonce = Uint8List(8); // Should be 12

        expect(
          () => AesGcmCipher.encrypt(
            plaintext: plaintext,
            key: key128,
            nonce: invalidNonce,
          ),
          throwsA(isA<CryptoException>()),
        );
      });
    });
  });
}
