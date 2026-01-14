import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('Packet.decode NACK', () {
    test('decodes NACK payload in Standard mode (CRC-32 required)', () {
      final payload = NackPayload.fromMissingIndices(
        originalMessageId: 0x12345678,
        missingIndices: [1, 2, 5, 8, 9, 10],
      );

      final header = StandardHeader(
        type: MessageType.nack,
        flags: PacketFlags(mesh: false),
        hopTtl: 10,
        messageId: 0x87654321,
        securityMode: SecurityMode.none,
        payloadLength: payload.sizeInBytes,
        ageMinutes: 0,
      );

      final packet = Packet(header: header, payload: payload);
      final encoded = packet.encode();
      final decoded = Packet.decode(encoded);

      expect(decoded.type, equals(MessageType.nack));
      expect(decoded.payload, isA<NackPayload>());
      expect(decoded.payload, equals(payload));
    });
  });
}

