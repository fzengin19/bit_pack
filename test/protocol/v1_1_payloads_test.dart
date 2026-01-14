import 'dart:convert';
import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('Protocol v1.1 Payloads', () {
    group('TextLocationPayload (0x1C)', () {
      test('encodes and decodes correctly', () {
        final payload = TextLocationPayload(
          latitude: 37.7749,
          longitude: -122.4194,
          text: 'Emergency help needed!',
        );

        expect(payload.type, equals(MessageType.textLocation));

        // Size: 4 (lat) + 4 (lon) + 22 (text) = 30 bytes
        expect(payload.sizeInBytes, equals(30));

        final encoded = payload.encode();
        expect(encoded.length, equals(30));

        final decoded = TextLocationPayload.decode(encoded);
        expect(decoded.latitude, closeTo(37.7749, 0.000001));
        expect(decoded.longitude, closeTo(-122.4194, 0.000001));
        expect(decoded.text, equals('Emergency help needed!'));
      });

      test('validates coordinates', () {
        expect(
          () => TextLocationPayload(latitude: 91, longitude: 0, text: 'Fail'),
          throwsArgumentError,
        );
      });

      test('integration with Packet.decode', () {
        final payload = TextLocationPayload(
          latitude: 41.0082,
          longitude: 28.9784,
          text: 'Istanbul',
        );

        final packet = PacketBuilder()
            .textLocation(41.0082, 28.9784, 'Istanbul')
            .build();

        final encodedPacket = packet.encode();
        final decodedPacket = Packet.decode(encodedPacket);

        expect(decodedPacket.type, equals(MessageType.textLocation));
        final decodedPayload = decodedPacket.payload as TextLocationPayload;
        expect(decodedPayload.text, equals('Istanbul'));
        expect(decodedPayload.latitude, closeTo(41.0082, 0.000001));
      });
    });

    group('ChallengePayload (0x1D)', () {
      test('encodes and decodes correctly', () {
        final salt = Uint8List.fromList(List.generate(16, (i) => i));
        final ciphertext = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
        final question = 'Who goes there?';

        final payload = ChallengePayload(
          salt: salt,
          question: question,
          ciphertext: ciphertext,
        );

        expect(payload.type, equals(MessageType.challenge));

        // Size: 16 (salt) + 1 (qLen) + 15 (question) + 3 (cipher) = 35 bytes
        expect(payload.sizeInBytes, equals(35));

        final encoded = payload.encode();
        expect(encoded.length, equals(35));

        // Verify layout manually
        // Salt
        expect(encoded.sublist(0, 16), equals(salt));
        // QLen
        expect(encoded[16], equals(15));
        // Question
        expect(utf8.decode(encoded.sublist(17, 32)), equals(question));
        // Ciphertext
        expect(encoded.sublist(32), equals(ciphertext));

        final decoded = ChallengePayload.decode(encoded);
        expect(decoded.salt, equals(salt));
        expect(decoded.question, equals(question));
        expect(decoded.ciphertext, equals(ciphertext));
      });

      test('validates constraints', () {
        // Bad salt length
        expect(
          () => ChallengePayload(
            salt: Uint8List(15),
            question: 'Q',
            ciphertext: Uint8List(0),
          ),
          throwsArgumentError,
        );

        // Too long question (256 bytes)
        final longQ = 'A' * 256;
        expect(
          () => ChallengePayload(
            salt: Uint8List(16),
            question: longQ,
            ciphertext: Uint8List(0),
          ),
          throwsArgumentError,
        );
      });

      test('integration with Packet.decode', () {
        final salt = Uint8List(16);
        final packet = PacketBuilder()
            .challenge(salt, 'Auth?', Uint8List.fromList([1, 2, 3]))
            .build();

        final encoded = packet.encode();
        final decoded = Packet.decode(encoded);

        expect(decoded.type, equals(MessageType.challenge));
        final payload = decoded.payload as ChallengePayload;
        expect(payload.question, equals('Auth?'));
      });
    });
  });
}
