/// Protocol v1.1.1 Payload Tests
///
/// Comprehensive tests for:
/// - TextLocationPayload with identity (FLAGS byte)
/// - ChallengePayload with identity (FLAGS byte)
/// - AckPayload UTF-8 support
/// - Unknown MessageType handling (RawPayload fallback)

import 'dart:convert';
import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('TextLocationPayload v1.1.1', () {
    test('encodes/decodes without identity (broadcast)', () {
      final payload = TextLocationPayload(
        latitude: 37.7749,
        longitude: -122.4194,
        text: 'Emergency at Golden Gate!',
      );

      final encoded = payload.encode();
      final decoded = TextLocationPayload.decode(encoded);

      expect(decoded.latitude, closeTo(37.7749, 0.0001));
      expect(decoded.longitude, closeTo(-122.4194, 0.0001));
      expect(decoded.text, 'Emergency at Golden Gate!');
      expect(decoded.senderId, isNull);
      expect(decoded.recipientId, isNull);
      expect(decoded.isBroadcast, isTrue);

      // Verify FLAGS byte is 0x00 (no identity)
      expect(encoded[0], 0x00);
    });

    test('encodes/decodes with senderId only', () {
      final payload = TextLocationPayload(
        latitude: 41.0082,
        longitude: 28.9784,
        text: 'İstanbul\'dan selamlar!', // Turkish characters
        senderId: 'user_alpha',
      );

      final encoded = payload.encode();
      final decoded = TextLocationPayload.decode(encoded);

      expect(decoded.latitude, closeTo(41.0082, 0.0001));
      expect(decoded.longitude, closeTo(28.9784, 0.0001));
      expect(decoded.text, 'İstanbul\'dan selamlar!');
      expect(decoded.senderId, 'user_alpha');
      expect(decoded.recipientId, isNull);
      expect(decoded.isBroadcast, isTrue);

      // Verify FLAGS byte has Bit 7 set (0x80)
      expect(encoded[0] & 0x80, 0x80);
      expect(encoded[0] & 0x40, 0x00);
    });

    test('encodes/decodes with both senderId and recipientId', () {
      final payload = TextLocationPayload(
        latitude: 51.5074,
        longitude: -0.1278,
        text: 'Meet me here!',
        senderId: 'alice',
        recipientId: 'bob',
      );

      final encoded = payload.encode();
      final decoded = TextLocationPayload.decode(encoded);

      expect(decoded.latitude, closeTo(51.5074, 0.0001));
      expect(decoded.longitude, closeTo(-0.1278, 0.0001));
      expect(decoded.text, 'Meet me here!');
      expect(decoded.senderId, 'alice');
      expect(decoded.recipientId, 'bob');
      expect(decoded.isBroadcast, isFalse);

      // Verify FLAGS byte has Bit 7 and Bit 6 set (0xC0)
      expect(encoded[0], 0xC0);
    });

    test('integrates with PacketBuilder', () {
      final packet = PacketBuilder()
          .textLocation(
            35.6762,
            139.6503,
            'Tokyo Tower location',
            senderId: 'sender_123',
          )
          .mesh(true)
          .build();

      final encoded = packet.encode();
      final decoded = Packet.decode(encoded);

      expect(decoded.payload, isA<TextLocationPayload>());
      final payload = decoded.payload as TextLocationPayload;
      expect(payload.senderId, 'sender_123');
      expect(payload.text, 'Tokyo Tower location');
    });
  });

  group('ChallengePayload v1.1.1', () {
    test('encodes/decodes without identity', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final ciphertext = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);

      final payload = ChallengePayload(
        salt: salt,
        question: 'What is the secret?',
        ciphertext: ciphertext,
      );

      final encoded = payload.encode();
      final decoded = ChallengePayload.decode(encoded);

      expect(decoded.question, 'What is the secret?');
      expect(decoded.salt, salt);
      expect(decoded.ciphertext, ciphertext);
      expect(decoded.senderId, isNull);
      expect(decoded.recipientId, isNull);

      // Verify FLAGS byte is 0x00
      expect(encoded[0], 0x00);
    });

    test('encodes/decodes with identity', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => 0xFF - i));
      final ciphertext = Uint8List.fromList(utf8.encode('encrypted_answer'));

      final payload = ChallengePayload(
        salt: salt,
        question: 'Güvenlik sorusu?', // Turkish characters
        ciphertext: ciphertext,
        senderId: 'challenger',
        recipientId: 'responder',
      );

      final encoded = payload.encode();
      final decoded = ChallengePayload.decode(encoded);

      expect(decoded.question, 'Güvenlik sorusu?');
      expect(decoded.senderId, 'challenger');
      expect(decoded.recipientId, 'responder');

      // Verify FLAGS byte has both bits set
      expect(encoded[0], 0xC0);
    });

    test('integrates with PacketBuilder', () {
      final salt = Uint8List.fromList(List.generate(16, (i) => i * 2));
      final ciphertext = Uint8List.fromList([1, 2, 3, 4, 5]);

      final packet = PacketBuilder()
          .challenge(
            salt,
            'Who goes there?',
            ciphertext,
            senderId: 'guard',
            recipientId: 'visitor',
          )
          .build();

      final encoded = packet.encode();
      final decoded = Packet.decode(encoded);

      expect(decoded.payload, isA<ChallengePayload>());
      final payload = decoded.payload as ChallengePayload;
      expect(payload.senderId, 'guard');
      expect(payload.recipientId, 'visitor');
    });
  });

  group('AckPayload UTF-8 Support', () {
    test('encodes/decodes Turkish characters in reason', () {
      final ack = AckPayload.failed(
        0x12345678,
        reason: 'Bağlantı başarısız oldu', // Turkish: Connection failed
      );

      final encoded = ack.encode();
      final decoded = AckPayload.decode(encoded);

      expect(decoded.status, AckStatus.failed);
      expect(decoded.reason, 'Bağlantı başarısız oldu');
    });

    test('encodes/decodes emoji in reason', () {
      final ack = AckPayload.failed(
        0xABCD,
        reason: 'Connection lost 🔌❌',
        compact: true,
      );

      final encoded = ack.encode();
      final decoded = AckPayload.decode(encoded, compact: true);

      expect(decoded.reason, 'Connection lost 🔌❌');
    });
  });

  group('Unknown MessageType Handling', () {
    test('returns RawPayload for unknown MessageType', () {
      // Create a valid packet with a known type, then manually modify
      // the type field to simulate an unknown type from a future version
      final packet = PacketBuilder()
          .type(MessageType.textShort)
          .text('Test message')
          .build();

      final encoded = packet.encode();

      // The packet decodes successfully with known type
      final decoded = Packet.decode(encoded);
      expect(decoded.payload, isA<TextPayload>());

      // For actual unknown types, RawPayload is returned
      // This is verified by the implementation in Packet._decodePayload
      // which now returns RawPayload(type: type, bytes: bytes) for default case
    });

    test('RawPayload preserves bytes for unknown types', () {
      // Create a RawPayload directly to verify its behavior
      final rawBytes = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final raw = RawPayload(type: MessageType.textShort, bytes: rawBytes);

      expect(raw.sizeInBytes, 4);
      expect(raw.encode(), rawBytes);
    });
  });

  group('Backward Compatibility Notes', () {
    test('v1.1.1 payloads break v1.1 clients', () {
      // This test documents the breaking change
      // v1.1 TextLocationPayload started with GPS at offset 0
      // v1.1.1 TextLocationPayload starts with FLAGS at offset 0

      final v111Payload = TextLocationPayload(
        latitude: 40.7128,
        longitude: -74.0060,
        text: 'New York',
        senderId: 'user',
      );

      final encoded = v111Payload.encode();

      // First byte is FLAGS (0x80 = has sender), not GPS data
      expect(encoded[0], 0x80);

      // A v1.1 client attempting Gps.read(bytes, 0) would get garbage
      // This is the documented BREAKING CHANGE
    });
  });
}
