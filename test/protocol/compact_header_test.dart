import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/header/compact_header.dart';
import 'package:bit_pack/src/core/types.dart';
import 'package:bit_pack/src/core/exceptions.dart';
import 'package:bit_pack/src/encoding/bitwise.dart';

void main() {
  group('CompactHeader', () {
    group('Construction', () {
      test('creates header with required fields', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0x1234,
        );

        expect(header.mode, equals(PacketMode.compact));
        expect(header.type, equals(MessageType.sosBeacon));
        expect(header.ttl, equals(15)); // Default
        expect(header.messageId, equals(0x1234));
      });

      test('creates header with custom TTL', () {
        final header = CompactHeader(
          type: MessageType.ping,
          flags: PacketFlags(),
          ttl: 10,
          messageId: 0xABCD,
        );

        expect(header.ttl, equals(10));
      });

      test('throws on non-compact-compatible type', () {
        expect(
          () => CompactHeader(
            type: MessageType.handshakeInit, // 0x10, requires standard
            flags: PacketFlags(),
            messageId: 0x1234,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on TTL out of range', () {
        expect(
          () => CompactHeader(
            type: MessageType.sosBeacon,
            flags: PacketFlags(),
            ttl: 16, // Max is 15
            messageId: 0x1234,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => CompactHeader(
            type: MessageType.sosBeacon,
            flags: PacketFlags(),
            ttl: -1,
            messageId: 0x1234,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on message ID out of range', () {
        expect(
          () => CompactHeader(
            type: MessageType.sosBeacon,
            flags: PacketFlags(),
            messageId: 0x10000, // Max is 0xFFFF
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Encoding', () {
      test('encodes to exactly 4 bytes', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0x1234,
        );

        final encoded = header.encode();
        expect(encoded.length, equals(4));
      });

      test('encodes mode bit as 0', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0x0000,
        );

        final encoded = header.encode();
        // Bit 7 of byte 0 should be 0
        expect(encoded[0] & 0x80, equals(0));
      });

      test('encodes type in bits 6-3', () {
        final header = CompactHeader(
          type: MessageType.ping, // code = 0x03
          flags: PacketFlags(),
          messageId: 0x0000,
        );

        final encoded = header.encode();
        final typeCode = (encoded[0] >> 3) & 0x0F;
        expect(typeCode, equals(0x03));
      });

      test('encodes flags correctly', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(mesh: true, ackRequired: true, encrypted: true),
          messageId: 0x0000,
        );

        final encoded = header.encode();
        // Bits 2-0: [MESH, ACK, ENC]
        expect(encoded[0] & 0x07, equals(0x07));
      });

      test('encodes TTL in bits 7-4 of byte 1', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          ttl: 12,
          messageId: 0x0000,
        );

        final encoded = header.encode();
        final ttl = (encoded[1] >> 4) & 0x0F;
        expect(ttl, equals(12));
      });

      test('encodes message ID in big-endian', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0xABCD,
        );

        final encoded = header.encode();
        expect(encoded[2], equals(0xAB)); // High byte
        expect(encoded[3], equals(0xCD)); // Low byte
      });

      test('encodes compressed and urgent flags in byte 1', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(compressed: true, urgent: true),
          messageId: 0x0000,
        );

        final encoded = header.encode();
        // Bits 3-2 of byte 1: [COMPRESSED, URGENT]
        final flagsPart2 = (encoded[1] >> 2) & 0x03;
        expect(flagsPart2, equals(0x03));
      });
      test('SPEC COMPLIANCE: TTL=15 must match High Nibble (0xF0) in Byte 1', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          ttl: 15,
          messageId: 0x0000,
        );

        final encoded = header.encode();
        // Byte 1 should be 0xF0 (TTL=15 in bits 7-4, Flags=0, Reserved=0)
        expect(encoded[1] & 0xF0, equals(0xF0));
        expect(encoded[1] & 0x0F, equals(0x00));
      });
    });

    group('Decoding', () {
      test('decodes valid header', () {
        final original = CompactHeader(
          type: MessageType.location,
          flags: PacketFlags(mesh: true),
          ttl: 8,
          messageId: 0x5678,
        );

        final encoded = original.encode();
        final decoded = CompactHeader.decode(encoded);

        expect(decoded.type, equals(original.type));
        expect(decoded.flags.mesh, equals(original.flags.mesh));
        expect(decoded.ttl, equals(original.ttl));
        expect(decoded.messageId, equals(original.messageId));
      });

      test('throws on insufficient bytes', () {
        final shortData = Uint8List(3);

        expect(
          () => CompactHeader.decode(shortData),
          throwsA(isA<InsufficientHeaderException>()),
        );
      });

      test('throws on wrong mode bit', () {
        final data = Uint8List(4);
        data[0] = 0x80; // Mode = 1 (Standard)

        expect(
          () => CompactHeader.decode(data),
          throwsA(isA<InvalidModeException>()),
        );
      });

      test('throws on unknown message type', () {
        final data = Uint8List(4);
        data[0] = 0x78; // Type = 0x0F (unknown)

        expect(
          () => CompactHeader.decode(data),
          throwsA(isA<InvalidHeaderException>()),
        );
      });
    });

    group('Roundtrip', () {
      test('encode then decode preserves all fields', () {
        final testCases = [
          CompactHeader(
            type: MessageType.sosBeacon,
            flags: PacketFlags(mesh: true, urgent: true),
            ttl: 15,
            messageId: 0xFFFF,
          ),
          CompactHeader(
            type: MessageType.ping,
            flags: PacketFlags(ackRequired: true),
            ttl: 0,
            messageId: 0x0000,
          ),
          CompactHeader(
            type: MessageType.location,
            flags: PacketFlags(encrypted: true, compressed: true),
            ttl: 7,
            messageId: 0x5A5A,
          ),
        ];

        for (final original in testCases) {
          final encoded = original.encode();
          final decoded = CompactHeader.decode(encoded);

          expect(decoded.type, equals(original.type));
          expect(decoded.flags.mesh, equals(original.flags.mesh));
          expect(decoded.flags.ackRequired, equals(original.flags.ackRequired));
          expect(decoded.flags.encrypted, equals(original.flags.encrypted));
          expect(decoded.flags.compressed, equals(original.flags.compressed));
          expect(decoded.flags.urgent, equals(original.flags.urgent));
          expect(decoded.ttl, equals(original.ttl));
          expect(decoded.messageId, equals(original.messageId));
        }
      });
    });

    group('TTL Operations', () {
      test('isExpired returns true when TTL is 0', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          ttl: 0,
          messageId: 0x1234,
        );

        expect(header.isExpired, isTrue);
      });

      test('isExpired returns false when TTL > 0', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          ttl: 1,
          messageId: 0x1234,
        );

        expect(header.isExpired, isFalse);
      });

      test('decrementTtl creates copy with TTL-1', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(mesh: true),
          ttl: 5,
          messageId: 0x1234,
        );

        final decremented = header.decrementTtl();

        expect(decremented.ttl, equals(4));
        expect(decremented.type, equals(header.type));
        expect(decremented.messageId, equals(header.messageId));
        expect(header.ttl, equals(5)); // Original unchanged
      });

      test('decrementTtl does not go below 0', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          ttl: 0,
          messageId: 0x1234,
        );

        final decremented = header.decrementTtl();
        expect(decremented.ttl, equals(0));
      });
    });

    group('Equality and Hashing', () {
      test('equal headers are equal', () {
        final header1 = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(mesh: true),
          ttl: 10,
          messageId: 0x5678,
        );

        final header2 = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(mesh: true),
          ttl: 10,
          messageId: 0x5678,
        );

        expect(header1, equals(header2));
        expect(header1.hashCode, equals(header2.hashCode));
      });

      test('different headers are not equal', () {
        final header1 = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0x1234,
        );

        final header2 = CompactHeader(
          type: MessageType.ping,
          flags: PacketFlags(),
          messageId: 0x1234,
        );

        expect(header1, isNot(equals(header2)));
      });
    });

    group('copyWith', () {
      test('creates copy with modified fields', () {
        final original = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          ttl: 10,
          messageId: 0x1234,
        );

        final modified = original.copyWith(ttl: 5, messageId: 0xABCD);

        expect(modified.ttl, equals(5));
        expect(modified.messageId, equals(0xABCD));
        expect(modified.type, equals(original.type));
        expect(original.ttl, equals(10)); // Original unchanged
      });
    });
  });
}
