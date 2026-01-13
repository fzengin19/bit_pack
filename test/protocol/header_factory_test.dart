import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/header/header_factory.dart';
import 'package:bit_pack/src/protocol/header/compact_header.dart';
import 'package:bit_pack/src/protocol/header/standard_header.dart';
import 'package:bit_pack/src/core/types.dart';
import 'package:bit_pack/src/core/exceptions.dart';
import 'package:bit_pack/src/encoding/bitwise.dart';

void main() {
  group('HeaderFactory', () {
    group('Mode Detection', () {
      test('detectMode returns compact for mode bit 0', () {
        expect(HeaderFactory.detectMode(0x00), equals(PacketMode.compact));
        expect(HeaderFactory.detectMode(0x7F), equals(PacketMode.compact));
      });

      test('detectMode returns standard for mode bit 1', () {
        expect(HeaderFactory.detectMode(0x80), equals(PacketMode.standard));
        expect(HeaderFactory.detectMode(0xFF), equals(PacketMode.standard));
      });

      test('detectModeFromBytes detects from byte array', () {
        final compact = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
        final standard = Uint8List.fromList([
          0x80,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
        ]);

        expect(
          HeaderFactory.detectModeFromBytes(compact),
          equals(PacketMode.compact),
        );
        expect(
          HeaderFactory.detectModeFromBytes(standard),
          equals(PacketMode.standard),
        );
      });

      test('detectModeFromBytes throws on empty data', () {
        expect(
          () => HeaderFactory.detectModeFromBytes(Uint8List(0)),
          throwsA(isA<DecodingException>()),
        );
      });
    });

    group('Header Size', () {
      test('getHeaderSize returns 4 for compact', () {
        expect(HeaderFactory.getHeaderSize(0x00), equals(4));
      });

      test('getHeaderSize returns 11 for standard', () {
        expect(HeaderFactory.getHeaderSize(0x80), equals(11));
      });

      test('hasCompleteHeader returns false for empty data', () {
        expect(HeaderFactory.hasCompleteHeader(Uint8List(0)), isFalse);
      });

      test('hasCompleteHeader returns true when data is sufficient', () {
        final compact = Uint8List(4);
        compact[0] = 0x00; // Mode = 0
        expect(HeaderFactory.hasCompleteHeader(compact), isTrue);

        final standard = Uint8List(11);
        standard[0] = 0x80; // Mode = 1
        expect(HeaderFactory.hasCompleteHeader(standard), isTrue);
      });

      test('hasCompleteHeader returns false when data is insufficient', () {
        final compact = Uint8List(3);
        compact[0] = 0x00;
        expect(HeaderFactory.hasCompleteHeader(compact), isFalse);

        final standard = Uint8List(9);
        standard[0] = 0x80;
        expect(HeaderFactory.hasCompleteHeader(standard), isFalse);
      });
    });

    group('Decoding', () {
      test('decode returns CompactHeader for mode 0', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0x1234,
        );

        final encoded = header.encode();
        final decoded = HeaderFactory.decode(encoded);

        expect(decoded, isA<CompactHeader>());
      });

      test('decode returns StandardHeader for mode 1', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
        );

        final encoded = header.encode();
        final decoded = HeaderFactory.decode(encoded);

        expect(decoded, isA<StandardHeader>());
      });

      test('decode throws on empty data', () {
        expect(
          () => HeaderFactory.decode(Uint8List(0)),
          throwsA(isA<DecodingException>()),
        );
      });

      test('decodeCompact decodes compact header', () {
        final original = CompactHeader(
          type: MessageType.ping,
          flags: PacketFlags(mesh: true),
          messageId: 0xABCD,
        );

        final encoded = original.encode();
        final decoded = HeaderFactory.decodeCompact(encoded);

        expect(decoded.type, equals(original.type));
        expect(decoded.messageId, equals(original.messageId));
      });

      test('decodeStandard decodes standard header', () {
        final original = StandardHeader(
          type: MessageType.handshakeInit,
          flags: PacketFlags(encrypted: true),
          messageId: 0xDEADBEEF,
        );

        final encoded = original.encode();
        final decoded = HeaderFactory.decodeStandard(encoded);

        expect(decoded.type, equals(original.type));
        expect(decoded.messageId, equals(original.messageId));
      });
    });

    group('decodeWithPayload', () {
      test('returns header and empty payload when no payload', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0x1234,
        );

        final encoded = header.encode();
        final (decodedHeader, payload) = HeaderFactory.decodeWithPayload(
          encoded,
        );

        expect(decodedHeader, isA<CompactHeader>());
        expect(payload.length, equals(0));
      });

      test('returns header and payload when payload exists', () {
        final header = CompactHeader(
          type: MessageType.sosBeacon,
          flags: PacketFlags(),
          messageId: 0x1234,
        );

        final headerBytes = header.encode();
        final payloadBytes = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
        final fullPacket = Uint8List(headerBytes.length + payloadBytes.length);
        fullPacket.setAll(0, headerBytes);
        fullPacket.setAll(headerBytes.length, payloadBytes);

        final (decodedHeader, payload) = HeaderFactory.decodeWithPayload(
          fullPacket,
        );

        expect(decodedHeader, isA<CompactHeader>());
        expect(payload, equals(payloadBytes));
      });
    });

    group('Creating Headers', () {
      test('createCompact creates compact header', () {
        final header = HeaderFactory.createCompact(
          type: MessageType.sosBeacon,
          messageId: 0x1234,
          flags: PacketFlags(mesh: true),
          ttl: 10,
        );

        expect(header.type, equals(MessageType.sosBeacon));
        expect(header.messageId, equals(0x1234));
        expect(header.flags.mesh, isTrue);
        expect(header.ttl, equals(10));
      });

      test('createStandard creates standard header', () {
        final header = HeaderFactory.createStandard(
          type: MessageType.dataEncrypted,
          messageId: 0x12345678,
          securityMode: SecurityMode.symmetric,
          payloadLength: 100,
          ageMinutes: 30,
        );

        expect(header.type, equals(MessageType.dataEncrypted));
        expect(header.messageId, equals(0x12345678));
        expect(header.securityMode, equals(SecurityMode.symmetric));
        expect(header.payloadLength, equals(100));
        expect(header.ageMinutes, equals(30));
      });

      test('createAuto chooses compact for simple message', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.sosBeacon,
          messageId: 0x1234,
        );

        expect(header, isA<CompactHeader>());
      });

      test('createAuto chooses standard for 32-bit message ID', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.sosBeacon,
          messageId: 0x12345678, // > 16-bit
        );

        expect(header, isA<StandardHeader>());
      });

      test('createAuto chooses standard for standard-only type', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.handshakeInit, // Requires standard
          messageId: 0x1234,
        );

        expect(header, isA<StandardHeader>());
      });

      test('createAuto chooses standard for encryption', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.sosBeacon,
          messageId: 0x1234,
          securityMode: SecurityMode.symmetric,
        );

        expect(header, isA<StandardHeader>());
      });

      test('createAuto chooses standard for fragmentation', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.sosBeacon,
          messageId: 0x1234,
          flags: PacketFlags(isFragment: true),
        );

        expect(header, isA<StandardHeader>());
      });

      test('createAuto chooses standard for age tracking', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.sosBeacon,
          messageId: 0x1234,
          ageMinutes: 1,
        );

        expect(header, isA<StandardHeader>());
      });

      test('createAuto chooses standard for high TTL', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.sosBeacon,
          messageId: 0x1234,
          ttl: 16, // > 15
        );

        expect(header, isA<StandardHeader>());
      });

      test('createAuto respects forceStandard', () {
        final header = HeaderFactory.createAuto(
          type: MessageType.sosBeacon,
          messageId: 0x1234,
          forceStandard: true,
        );

        expect(header, isA<StandardHeader>());
      });
    });
  });
}
