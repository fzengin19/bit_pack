import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/payload/ack_payload.dart';
import 'package:bit_pack/src/core/types.dart';

void main() {
  group('AckPayload', () {
    group('construction', () {
      test('creates with defaults', () {
        final payload = AckPayload(originalMessageId: 0x1234);

        expect(payload.originalMessageId, equals(0x1234));
        expect(payload.status, equals(AckStatus.received));
        expect(payload.isCompact, isFalse);
        expect(payload.reason, isNull);
      });

      test('creates compact ACK', () {
        final payload = AckPayload(originalMessageId: 0x1234, isCompact: true);
        expect(payload.isCompact, isTrue);
      });

      test('factory received', () {
        final payload = AckPayload.received(0x5678, compact: true);
        expect(payload.status, equals(AckStatus.received));
        expect(payload.isCompact, isTrue);
      });

      test('factory delivered', () {
        final payload = AckPayload.delivered(0x5678);
        expect(payload.status, equals(AckStatus.delivered));
      });

      test('factory relayed', () {
        final payload = AckPayload.relayed(0x5678);
        expect(payload.status, equals(AckStatus.relayed));
      });

      test('factory failed with reason', () {
        final payload = AckPayload.failed(0x5678, reason: 'timeout');
        expect(payload.status, equals(AckStatus.failed));
        expect(payload.reason, equals('timeout'));
      });

      test('throws on invalid compact message ID', () {
        expect(
          () => AckPayload(
            originalMessageId: 0x10000, // > 16 bits
            isCompact: true,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('sizeInBytes', () {
      test('compact is 3 bytes', () {
        final payload = AckPayload(originalMessageId: 0x1234, isCompact: true);
        expect(payload.sizeInBytes, equals(3));
      });

      test('standard is 5 bytes', () {
        final payload = AckPayload(originalMessageId: 0x12345678);
        expect(payload.sizeInBytes, equals(5));
      });

      test('with reason adds length', () {
        final payload = AckPayload.failed(0x1234, reason: 'error');
        // 5 (standard) + 1 (len) + 5 (reason)
        expect(payload.sizeInBytes, equals(11));
      });
    });

    group('encode', () {
      test('encodes compact ACK', () {
        final payload = AckPayload(originalMessageId: 0x1234, isCompact: true);
        final encoded = payload.encode();

        expect(encoded.length, equals(3));
        expect(encoded[0], equals(0x12)); // High byte
        expect(encoded[1], equals(0x34)); // Low byte
        expect(encoded[2], equals(0x00)); // Status: received
      });

      test('encodes standard ACK', () {
        final payload = AckPayload(originalMessageId: 0x12345678);
        final encoded = payload.encode();

        expect(encoded.length, equals(5));
      });

      test('encodes status correctly', () {
        final payload = AckPayload(
          originalMessageId: 0x1234,
          status: AckStatus.delivered,
          isCompact: true,
        );
        final encoded = payload.encode();

        expect(encoded[2], equals(0x01)); // delivered = 1
      });
    });

    group('decode', () {
      test('decodes compact ACK', () {
        final original = AckPayload(
          originalMessageId: 0x1234,
          status: AckStatus.relayed,
          isCompact: true,
        );
        final encoded = original.encode();
        final decoded = AckPayload.decode(encoded, compact: true);

        expect(decoded.originalMessageId, equals(0x1234));
        expect(decoded.status, equals(AckStatus.relayed));
      });

      test('decodes standard ACK', () {
        final original = AckPayload(
          originalMessageId: 0x12345678,
          status: AckStatus.delivered,
        );
        final encoded = original.encode();
        final decoded = AckPayload.decode(encoded);

        expect(decoded.originalMessageId, equals(0x12345678));
        expect(decoded.status, equals(AckStatus.delivered));
      });

      test('throws on insufficient data', () {
        expect(
          () => AckPayload.decode(Uint8List(2)), // Need at least 3 for compact
          throwsA(isA<Exception>()),
        );
      });
    });

    group('roundtrip', () {
      test('encode then decode preserves all fields', () {
        final testCases = [
          AckPayload.received(0x1234, compact: true),
          AckPayload.delivered(0x12345678),
          AckPayload.relayed(0xABCD, compact: true),
          AckPayload.failed(0x5678, reason: 'timeout'),
        ];

        for (final original in testCases) {
          final encoded = original.encode();
          final decoded = AckPayload.decode(
            encoded,
            compact: original.isCompact,
          );

          expect(decoded.originalMessageId, equals(original.originalMessageId));
          expect(decoded.status, equals(original.status));
        }
      });
    });

    group('AckStatus', () {
      test('fromCode returns correct status', () {
        expect(AckStatus.fromCode(0), equals(AckStatus.received));
        expect(AckStatus.fromCode(1), equals(AckStatus.delivered));
        expect(AckStatus.fromCode(2), equals(AckStatus.read));
        expect(AckStatus.fromCode(3), equals(AckStatus.failed));
        expect(AckStatus.fromCode(4), equals(AckStatus.rejected));
        expect(AckStatus.fromCode(5), equals(AckStatus.relayed));
      });

      test('fromCode returns received for unknown', () {
        expect(AckStatus.fromCode(99), equals(AckStatus.received));
      });
    });

    group('properties', () {
      test('type is sosAck', () {
        final payload = AckPayload(originalMessageId: 0x1234);
        expect(payload.type, equals(MessageType.sosAck));
      });
    });
  });
}
