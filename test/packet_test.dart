import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/packet.dart';
import 'package:bit_pack/src/protocol/payload/sos_payload.dart';
import 'package:bit_pack/src/protocol/payload/ack_payload.dart';
import 'package:bit_pack/src/protocol/header/compact_header.dart';
import 'package:bit_pack/src/core/types.dart';

void main() {
  group('Packet', () {
    group('Packet.sos factory', () {
      test('creates SOS packet', () {
        final packet = Packet.sos(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
          phoneNumber: '+905331234567',
        );

        expect(packet.mode, equals(PacketMode.compact));
        expect(packet.type, equals(MessageType.sosBeacon));
        expect(packet.payload, isA<SosPayload>());
        expect(packet.header, isA<CompactHeader>());
      });

      test('SOS packet fits in 20 bytes', () {
        final packet = Packet.sos(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );

        // 4 (header) + 15 (payload) + 1 (CRC-8) = 20 bytes
        expect(packet.sizeInBytes, equals(20));
        expect(packet.fitsCompact, isTrue);
      });

      test('SOS packet encodes to 20 bytes (CRC-8 is mandatory)', () {
        final packet = Packet.sos(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );

        final encoded = packet.encode();
        expect(encoded.length, equals(20));
      });
    });

    group('Packet.location factory', () {
      test('creates compact location packet', () {
        final packet = Packet.location(
          latitude: 41.0082,
          longitude: 28.9784,
          compact: true,
        );

        expect(packet.mode, equals(PacketMode.compact));
        expect(packet.type, equals(MessageType.location));
        // 4 (header) + 8 (payload) + 1 (CRC-8) = 13 bytes
        expect(packet.sizeInBytes, equals(13));
      });

      test('creates extended location packet', () {
        final packet = Packet.location(
          latitude: 41.0082,
          longitude: 28.9784,
          altitude: 150,
          accuracy: 10,
          compact: false,
        );

        expect(packet.mode, equals(PacketMode.standard));
        // 11 (header) + 12 (payload) + 4 (CRC-32) = 27 bytes
        expect(packet.sizeInBytes, equals(27));
      });
    });

    group('Packet.text factory', () {
      test('creates text packet', () {
        final packet = Packet.text(text: 'Hello World!', senderId: 'user1');

        expect(packet.mode, equals(PacketMode.standard));
        expect(packet.type, equals(MessageType.textShort));
      });
    });

    group('Packet.ack factory', () {
      test('creates compact ACK', () {
        final packet = Packet.ack(
          originalMessageId: 0x1234,
          status: AckStatus.received,
          compact: true,
        );

        expect(packet.mode, equals(PacketMode.compact));
        expect(packet.type, equals(MessageType.sosAck));
        // 4 (header) + 3 (payload) + 1 (CRC-8) = 8 bytes
        expect(packet.sizeInBytes, equals(8));
      });
    });

    group('encode', () {
      test('encodes packet correctly', () {
        final packet = Packet.sos(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );

        final encoded = packet.encode();
        expect(encoded.length, equals(20)); // 4 + 15 + 1 (CRC-8)
      });
    });

    group('decode', () {
      test('decodes SOS packet', () {
        final original = Packet.sos(
          sosType: SosType.injured,
          latitude: 41.0082,
          longitude: 28.9784,
          messageId: 0x1234,
        );

        final encoded = original.encode();
        final decoded = Packet.decode(encoded);

        expect(decoded.type, equals(MessageType.sosBeacon));
        expect(decoded.messageId, equals(0x1234));
        expect(decoded.payload, isA<SosPayload>());
      });

      test('throws on CRC mismatch', () {
        final packet = Packet.sos(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );

        final encoded = packet.encode();
        // Corrupt the CRC-8
        encoded[encoded.length - 1] ^= 0xFF;

        expect(
          () => Packet.decode(encoded),
          throwsA(isA<Exception>()),
        );
      });

      test('throws on empty input', () {
        expect(() => Packet.decode(Uint8List(0)), throwsA(isA<Exception>()));
      });
    });

    group('roundtrip', () {
      test('SOS packet roundtrip', () {
        final original = Packet.sos(
          sosType: SosType.trapped,
          latitude: 41.0082,
          longitude: 28.9784,
          phoneNumber: '12345678',
          altitude: 150,
          batteryPercent: 75,
          messageId: 0xABCD,
        );

        final encoded = original.encode();
        final decoded = Packet.decode(encoded);

        expect(decoded.messageId, equals(0xABCD));

        final sosPayload = decoded.payload as SosPayload;
        expect(sosPayload.sosType, equals(SosType.trapped));
        expect(sosPayload.latitude, closeTo(41.0082, 0.0000001));
        expect(sosPayload.longitude, closeTo(28.9784, 0.0000001));
      });
    });
  });
}
