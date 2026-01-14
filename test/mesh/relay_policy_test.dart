import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('RelayPolicy', () {
    late RelayPolicy policy;

    setUp(() {
      policy = RelayPolicy();
    });

    Packet createStandardPacket({
      bool mesh = true,
      int ttl = 10,
      int ageMinutes = 0,
      bool urgent = false,
      int messageId = 0x12345678,
    }) {
      final payload = TextPayload(text: 'Hello');
      final header = StandardHeader(
        type: MessageType.textShort,
        flags: PacketFlags(mesh: mesh, urgent: urgent),
        hopTtl: ttl,
        messageId: messageId,
        securityMode: SecurityMode.none,
        payloadLength: payload.sizeInBytes,
        ageMinutes: ageMinutes,
      );
      return Packet(header: header, payload: payload);
    }

    group('shouldRelay', () {
      test('returns false if MESH flag not set (compact)', () {
        final header = CompactHeader(
          type: MessageType.textShort,
          flags: PacketFlags(mesh: false),
          messageId: 0x1234,
        );
        final packet = Packet(header: header, payload: TextPayload(text: 'Hi'));

        expect(policy.shouldRelay(packet), isFalse);
      });

      test('returns true for valid relay candidate (compact)', () {
        final header = CompactHeader(
          type: MessageType.textShort,
          flags: PacketFlags(mesh: true),
          ttl: 10,
          messageId: 0x1234,
        );
        final packet = Packet(header: header, payload: TextPayload(text: 'Hi'));

        expect(policy.shouldRelay(packet), isTrue);
      });

      test('returns false if TTL is 0', () {
        final packet = createStandardPacket(ttl: 0);
        expect(policy.shouldRelay(packet), isFalse);
      });

      test('returns false if message expired', () {
        final packet = createStandardPacket(ageMinutes: 1500); // > 24h
        expect(policy.shouldRelay(packet), isFalse);
      });

      test('returns true for valid relay candidate', () {
        final packet = createStandardPacket();
        expect(policy.shouldRelay(packet), isTrue);
      });
    });

    group('prepareForRelay', () {
      test('decrements TTL (standard)', () {
        final packet = createStandardPacket(ttl: 10);
        final prepared = policy.prepareForRelay(packet);

        expect((prepared.header as StandardHeader).hopTtl, equals(9));
      });

      test('decrements TTL (compact)', () {
        final header = CompactHeader(
          type: MessageType.textShort,
          flags: PacketFlags(mesh: true),
          ttl: 10,
          messageId: 0x1234,
        );
        final packet = Packet(header: header, payload: TextPayload(text: 'Hi'));
        final prepared = policy.prepareForRelay(packet);

        expect((prepared.header as CompactHeader).ttl, equals(9));
      });

      test('preserves other properties', () {
        final packet = createStandardPacket(mesh: true, urgent: true);
        final prepared = policy.prepareForRelay(packet);

        final header = prepared.header as StandardHeader;
        expect(header.flags.mesh, isTrue);
        expect(header.flags.urgent, isTrue);
        expect(header.messageId, equals(0x12345678));
      });
    });

    group('calculatePriority', () {
      test('urgent messages have higher priority', () {
        final normal = createStandardPacket(urgent: false);
        final urgent = createStandardPacket(urgent: true);

        expect(
          policy.calculatePriority(urgent),
          greaterThan(policy.calculatePriority(normal)),
        );
      });

      test('lower TTL has higher priority', () {
        final highTtl = createStandardPacket(ttl: 15);
        final lowTtl = createStandardPacket(ttl: 5);

        expect(
          policy.calculatePriority(lowTtl),
          greaterThan(policy.calculatePriority(highTtl)),
        );
      });
    });
  });
}
