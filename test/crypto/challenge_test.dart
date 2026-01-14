import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('ChallengeBlock', () {
    late Uint8List key128;
    late Uint8List key256;
    late Uint8List wrongKey;

    setUp(() async {
      final salt = KeyDerivation.generateSalt();
      
      key128 = await KeyDerivation.deriveKey(
        password: 'correct password',
        salt: salt,
        keyLength: 16,
      );
      
      key256 = await KeyDerivation.deriveKey(
        password: 'correct password 256',
        salt: salt,
        keyLength: 32,
      );
      
      wrongKey = await KeyDerivation.deriveKey(
        password: 'wrong password',
        salt: salt,
        keyLength: 16,
      );
    });

    group('create', () {
      test('creates challenge of correct length', () async {
        final challenge = await ChallengeBlock.create(key128);
        
        // 12 (nonce) + 16 (plaintext) + 16 (tag) = 44 bytes
        expect(challenge.length, equals(44));
        expect(challenge.length, equals(ChallengeBlock.encryptedLength));
      });

      test('creates different challenges each time', () async {
        final challenge1 = await ChallengeBlock.create(key128);
        final challenge2 = await ChallengeBlock.create(key128);
        
        // Due to random nonce and padding, challenges should differ
        expect(challenge1, isNot(equals(challenge2)));
      });

      test('works with AES-256 key', () async {
        final challenge = await ChallengeBlock.create(key256);
        expect(challenge.length, equals(44));
      });
    });

    group('verify', () {
      test('verifies with correct key', () async {
        final challenge = await ChallengeBlock.create(key128);
        final result = await ChallengeBlock.verify(challenge, key128);
        
        expect(result, isTrue);
      });

      test('fails with wrong key', () async {
        final challenge = await ChallengeBlock.create(key128);
        final result = await ChallengeBlock.verify(challenge, wrongKey);
        
        expect(result, isFalse);
      });

      test('fails with tampered challenge', () async {
        final challenge = await ChallengeBlock.create(key128);
        
        // Tamper with the ciphertext
        challenge[20] ^= 0xFF;
        
        final result = await ChallengeBlock.verify(challenge, key128);
        expect(result, isFalse);
      });

      test('fails with too short data', () async {
        final shortData = Uint8List(10);
        final result = await ChallengeBlock.verify(shortData, key128);
        
        expect(result, isFalse);
      });

      test('fails with empty data', () async {
        final result = await ChallengeBlock.verify(Uint8List(0), key128);
        expect(result, isFalse);
      });

      test('works with AES-256 key', () async {
        final challenge = await ChallengeBlock.create(key256);
        final result = await ChallengeBlock.verify(challenge, key256);
        
        expect(result, isTrue);
      });
    });

    group('verifyOrThrow', () {
      test('succeeds with correct key', () async {
        final challenge = await ChallengeBlock.create(key128);
        
        // Should not throw
        await ChallengeBlock.verifyOrThrow(challenge, key128);
      });

      test('throws ChallengeVerificationException with wrong key', () async {
        final challenge = await ChallengeBlock.create(key128);
        
        expect(
          () => ChallengeBlock.verifyOrThrow(challenge, wrongKey),
          throwsA(isA<ChallengeVerificationException>()),
        );
      });

      test('throws ChallengeVerificationException with tampered data', () async {
        final challenge = await ChallengeBlock.create(key128);
        challenge[15] ^= 0xFF;
        
        expect(
          () => ChallengeBlock.verifyOrThrow(challenge, key128),
          throwsA(isA<ChallengeVerificationException>()),
        );
      });
    });

    group('createPair', () {
      test('creates valid challenge-response pair', () async {
        final pair = await ChallengeBlock.createPair(key128);
        
        // Challenge should be encrypted
        expect(pair.challenge.length, equals(44));
        
        // Response should be decrypted plaintext (16 bytes)
        expect(pair.response.length, equals(16));
        
        // Response should start with magic
        expect(
          String.fromCharCodes(pair.response.sublist(0, 8)),
          equals('BITPACK\x00'),
        );
      });

      test('challenge from pair can be verified', () async {
        final pair = await ChallengeBlock.createPair(key128);
        final result = await ChallengeBlock.verify(pair.challenge, key128);
        
        expect(result, isTrue);
      });
    });

    group('magic prefix', () {
      test('magic constant is correct', () {
        expect(ChallengeBlock.magic, equals('BITPACK\x00'));
      });

      test('magicBytes has correct length', () {
        expect(ChallengeBlock.magicBytes.length, equals(8));
      });

      test('magicBytes matches magic string', () {
        final expected = Uint8List.fromList([
          0x42, // B
          0x49, // I
          0x54, // T
          0x50, // P
          0x41, // A
          0x43, // C
          0x4B, // K
          0x00, // \x00
        ]);
        expect(ChallengeBlock.magicBytes, equals(expected));
      });
    });

    group('validateKey', () {
      test('accepts 16-byte key', () {
        expect(
          () => ChallengeBlock.validateKey(key128),
          returnsNormally,
        );
      });

      test('accepts 32-byte key', () {
        expect(
          () => ChallengeBlock.validateKey(key256),
          returnsNormally,
        );
      });

      test('throws on invalid key length', () {
        final invalidKey = Uint8List(24);
        expect(
          () => ChallengeBlock.validateKey(invalidKey),
          throwsA(isA<CryptoException>()),
        );
      });
    });

    group('integration', () {
      test('full handshake flow simulation', () async {
        // Alice derives key from shared secret
        final salt = KeyDerivation.generateSalt();
        final aliceKey = await KeyDerivation.deriveKey(
          password: 'our shared secret',
          salt: salt,
        );
        
        // Alice creates challenge
        final challenge = await ChallengeBlock.create(aliceKey);
        
        // Bob derives same key from shared secret
        final bobKey = await KeyDerivation.deriveKey(
          password: 'our shared secret',
          salt: salt,
        );
        
        // Bob verifies challenge
        final verified = await ChallengeBlock.verify(challenge, bobKey);
        expect(verified, isTrue);
        
        // Eve cannot verify with wrong secret
        final eveKey = await KeyDerivation.deriveKey(
          password: 'wrong secret',
          salt: salt,
        );
        final eveVerified = await ChallengeBlock.verify(challenge, eveKey);
        expect(eveVerified, isFalse);
      });
    });
  });
}
