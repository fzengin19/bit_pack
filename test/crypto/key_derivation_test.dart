import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('KeyDerivation', () {
    group('deriveKey', () {
      test('derives 16-byte key for AES-128', () async {
        final salt = KeyDerivation.generateSalt();
        final key = await KeyDerivation.deriveKey(
          password: 'test password',
          salt: salt,
          keyLength: 16,
        );

        expect(key.length, equals(16));
      });

      test('derives 32-byte key for AES-256', () async {
        final salt = KeyDerivation.generateSalt();
        final key = await KeyDerivation.deriveKey(
          password: 'test password',
          salt: salt,
          keyLength: 32,
        );

        expect(key.length, equals(32));
      });

      test('same password and salt produce same key', () async {
        final salt = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
        
        final key1 = await KeyDerivation.deriveKey(
          password: 'consistent password',
          salt: salt,
        );
        
        final key2 = await KeyDerivation.deriveKey(
          password: 'consistent password',
          salt: salt,
        );

        expect(key1, equals(key2));
      });

      test('different passwords produce different keys', () async {
        final salt = KeyDerivation.generateSalt();
        
        final key1 = await KeyDerivation.deriveKey(
          password: 'password1',
          salt: salt,
        );
        
        final key2 = await KeyDerivation.deriveKey(
          password: 'password2',
          salt: salt,
        );

        expect(key1, isNot(equals(key2)));
      });

      test('different salts produce different keys', () async {
        final salt1 = KeyDerivation.generateSalt();
        final salt2 = KeyDerivation.generateSalt();
        
        final key1 = await KeyDerivation.deriveKey(
          password: 'same password',
          salt: salt1,
        );
        
        final key2 = await KeyDerivation.deriveKey(
          password: 'same password',
          salt: salt2,
        );

        expect(key1, isNot(equals(key2)));
      });

      test('throws on empty password', () async {
        final salt = KeyDerivation.generateSalt();
        
        expect(
          () => KeyDerivation.deriveKey(password: '', salt: salt),
          throwsA(isA<KeyDerivationException>()),
        );
      });

      test('throws on short salt', () async {
        final shortSalt = Uint8List.fromList([1, 2, 3, 4, 5]); // Only 5 bytes
        
        expect(
          () => KeyDerivation.deriveKey(password: 'password', salt: shortSalt),
          throwsA(isA<KeyDerivationException>()),
        );
      });

      test('throws on invalid key length', () async {
        final salt = KeyDerivation.generateSalt();
        
        expect(
          () => KeyDerivation.deriveKey(
            password: 'password',
            salt: salt,
            keyLength: 24, // Invalid, should be 16 or 32
          ),
          throwsA(isA<KeyDerivationException>()),
        );
      });

      test('works with custom iterations', () async {
        final salt = KeyDerivation.generateSalt();
        
        final key = await KeyDerivation.deriveKey(
          password: 'password',
          salt: salt,
          iterations: 5000,
        );

        expect(key.length, equals(16));
      });

      test('throws on too few iterations', () async {
        final salt = KeyDerivation.generateSalt();
        
        expect(
          () => KeyDerivation.deriveKey(
            password: 'password',
            salt: salt,
            iterations: 500, // Less than minimum
          ),
          throwsA(isA<KeyDerivationException>()),
        );
      });

      test('works with Turkish characters', () async {
        final salt = KeyDerivation.generateSalt();
        
        final key = await KeyDerivation.deriveKey(
          password: 'şifreli mesaj',
          salt: salt,
        );

        expect(key.length, equals(16));
      });
    });

    group('generateSalt', () {
      test('generates 16-byte salt by default', () {
        final salt = KeyDerivation.generateSalt();
        expect(salt.length, equals(16));
      });

      test('generates salt of specified length', () {
        final salt = KeyDerivation.generateSalt(32);
        expect(salt.length, equals(32));
      });

      test('generates different salts each time', () {
        final salt1 = KeyDerivation.generateSalt();
        final salt2 = KeyDerivation.generateSalt();
        
        expect(salt1, isNot(equals(salt2)));
      });

      test('throws on salt length below minimum', () {
        expect(
          () => KeyDerivation.generateSalt(4),
          throwsA(isA<KeyDerivationException>()),
        );
      });
    });

    group('createMessageSalt', () {
      test('creates 20-byte salt from IDs', () {
        final senderId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final recipientId = Uint8List.fromList([9, 10, 11, 12, 13, 14, 15, 16]);
        
        final salt = KeyDerivation.createMessageSalt(
          senderId: senderId,
          recipientId: recipientId,
          messageId: 0x12345678,
        );

        expect(salt.length, equals(20));
        
        // Verify structure
        expect(salt.sublist(0, 8), equals(senderId));
        expect(salt.sublist(8, 16), equals(recipientId));
        expect(salt[16], equals(0x12));
        expect(salt[17], equals(0x34));
        expect(salt[18], equals(0x56));
        expect(salt[19], equals(0x78));
      });

      test('pads short IDs', () {
        final senderId = Uint8List.fromList([1, 2, 3, 4]);
        final recipientId = Uint8List.fromList([5, 6]);
        
        final salt = KeyDerivation.createMessageSalt(
          senderId: senderId,
          recipientId: recipientId,
          messageId: 123,
        );

        expect(salt.length, equals(20));
      });

      test('truncates long IDs', () {
        final senderId = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        final recipientId = Uint8List.fromList([11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
        
        final salt = KeyDerivation.createMessageSalt(
          senderId: senderId,
          recipientId: recipientId,
          messageId: 456,
        );

        expect(salt.length, equals(20));
        expect(salt.sublist(0, 8), equals(senderId.sublist(0, 8)));
        expect(salt.sublist(8, 16), equals(recipientId.sublist(0, 8)));
      });
    });

    group('deriveKeyIsolated', () {
      test('derives key in background isolate', () async {
        final salt = KeyDerivation.generateSalt();
        final key = await KeyDerivation.deriveKeyIsolated(
          password: 'test password',
          salt: salt,
        );

        expect(key.length, equals(16));
      });

      test('produces same result as deriveKey', () async {
        final salt = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
        
        final key1 = await KeyDerivation.deriveKey(
          password: 'same password',
          salt: salt,
        );
        
        final key2 = await KeyDerivation.deriveKeyIsolated(
          password: 'same password',
          salt: salt,
        );

        expect(key1, equals(key2));
      });

      test('works with AES-256 key length', () async {
        final salt = KeyDerivation.generateSalt();
        final key = await KeyDerivation.deriveKeyIsolated(
          password: 'test password',
          salt: salt,
          keyLength: 32,
        );

        expect(key.length, equals(32));
      });

      test('throws on empty password', () async {
        final salt = KeyDerivation.generateSalt();
        
        expect(
          () => KeyDerivation.deriveKeyIsolated(password: '', salt: salt),
          throwsA(isA<KeyDerivationException>()),
        );
      });

      test('throws on invalid parameters', () async {
        final salt = Uint8List(4); // Too short
        
        expect(
          () => KeyDerivation.deriveKeyIsolated(password: 'test', salt: salt),
          throwsA(isA<KeyDerivationException>()),
        );
      });
    });
  });
}

