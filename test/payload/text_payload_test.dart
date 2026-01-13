import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/payload/text_payload.dart';
import 'package:bit_pack/src/core/types.dart';

void main() {
  group('TextPayload', () {
    group('construction', () {
      test('creates broadcast message', () {
        final payload = TextPayload(text: 'Hello World');

        expect(payload.text, equals('Hello World'));
        expect(payload.senderId, isNull);
        expect(payload.recipientId, isNull);
        expect(payload.isBroadcast, isTrue);
      });

      test('creates direct message', () {
        final payload = TextPayload(
          text: 'Hello',
          senderId: 'user1',
          recipientId: 'user2',
        );

        expect(payload.senderId, equals('user1'));
        expect(payload.recipientId, equals('user2'));
        expect(payload.isBroadcast, isFalse);
      });

      test('factory broadcast', () {
        final payload = TextPayload.broadcast('Hello', senderId: 'me');
        expect(payload.isBroadcast, isTrue);
        expect(payload.senderId, equals('me'));
      });

      test('factory direct', () {
        final payload = TextPayload.direct(
          'Hello',
          recipientId: 'you',
          senderId: 'me',
        );
        expect(payload.isBroadcast, isFalse);
        expect(payload.recipientId, equals('you'));
      });

      test('throws on empty text', () {
        expect(() => TextPayload(text: ''), throwsA(isA<ArgumentError>()));
      });
    });

    group('encode', () {
      test('encodes broadcast message', () {
        final payload = TextPayload(text: 'Hello');
        final encoded = payload.encode();

        // Flags (1) + text (5)
        expect(encoded.length, equals(6));
        expect(encoded[0], equals(0)); // No sender, no recipient
      });

      test('encodes with sender', () {
        final payload = TextPayload(text: 'Hi', senderId: 'abc');
        final encoded = payload.encode();

        // Flags (1) + sender len (1) + sender (3) + text (2)
        expect(encoded.length, equals(7));
        expect(encoded[0] & 0x80, isNot(0)); // Has sender flag
      });

      test('encodes with recipient', () {
        final payload = TextPayload(text: 'Hi', recipientId: 'xyz');
        final encoded = payload.encode();

        expect(encoded[0] & 0x40, isNot(0)); // Has recipient flag
      });
    });

    group('decode', () {
      test('decodes broadcast message', () {
        final original = TextPayload(text: 'Hello World!');
        final encoded = original.encode();
        final decoded = TextPayload.decode(encoded);

        expect(decoded.text, equals(original.text));
        expect(decoded.isBroadcast, isTrue);
      });

      test('decodes message with sender', () {
        final original = TextPayload(text: 'Hello', senderId: 'user123');
        final encoded = original.encode();
        final decoded = TextPayload.decode(encoded);

        expect(decoded.senderId, equals(original.senderId));
      });

      test('decodes message with recipient', () {
        final original = TextPayload(
          text: 'Hello',
          senderId: 'me',
          recipientId: 'you',
        );
        final encoded = original.encode();
        final decoded = TextPayload.decode(encoded);

        expect(decoded.senderId, equals('me'));
        expect(decoded.recipientId, equals('you'));
      });

      test('throws on empty input', () {
        expect(
          () => TextPayload.decode(Uint8List(0)),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('roundtrip', () {
      test('encode then decode preserves all fields', () {
        final testCases = [
          TextPayload(text: 'Simple'),
          TextPayload(text: 'With UTF-8: Türkçe 日本語 🎉'),
          TextPayload(text: 'Hi', senderId: 'sender1'),
          TextPayload(text: 'Hi', recipientId: 'recipient1'),
          TextPayload(
            text: 'Full message',
            senderId: 'alice',
            recipientId: 'bob',
          ),
        ];

        for (final original in testCases) {
          final encoded = original.encode();
          final decoded = TextPayload.decode(encoded);

          expect(decoded.text, equals(original.text));
          expect(decoded.senderId, equals(original.senderId));
          expect(decoded.recipientId, equals(original.recipientId));
        }
      });
    });

    group('properties', () {
      test('type is textShort', () {
        final payload = TextPayload(text: 'Hi');
        expect(payload.type, equals(MessageType.textShort));
      });

      test('sizeInBytes calculation', () {
        final payload = TextPayload(text: 'Hello'); // 5 bytes
        // Flags (1) + text (5) = 6
        expect(payload.sizeInBytes, equals(6));
      });
    });
  });
}
