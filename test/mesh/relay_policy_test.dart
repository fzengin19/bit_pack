import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('RelayPolicy', () {
    late MessageCache cache;
    late RelayPolicy policy;

    setUp(() {
      cache = MessageCache();
      policy = RelayPolicy();
    });

    Packet createPacket({
      bool mesh = true,
      int ttl = 10,
      int ageMinutes = 0,
      bool urgent = false,
      int messageId = 0x12345678,
    }) {
      final header = StandardHeader(
        type: MessageType.textShort,
        flags: PacketFlags(mesh: mesh, urgent: urgent),
        hopTtl: ttl,
        messageId: messageId,
        securityMode: SecurityMode.none,
        payloadLength: 6,
        ageMinutes: ageMinutes,
      );
      return Packet(header: header, payload: TextPayload(text: 'Hello'));
    }

    group('shouldRelay', () {
      test('returns false for non-StandardHeader', () {
        final header = CompactHeader(
          type: MessageType.textShort,
          flags: PacketFlags(),
          messageId: 0x1234,
        );
        final packet = Packet(header: header, payload: TextPayload(text: 'Hi'));

        expect(policy.shouldRelay(packet, cache), isFalse);
      });

      test('returns false if MESH flag not set', () {
        final packet = createPacket(mesh: false);
        expect(policy.shouldRelay(packet, cache), isFalse);
      });

      test('returns false if TTL is 0', () {
        final packet = createPacket(ttl: 0);
        expect(policy.shouldRelay(packet, cache), isFalse);
      });

      test('returns false if message expired', () {
        final packet = createPacket(ageMinutes: 1500); // > 24h
        expect(policy.shouldRelay(packet, cache), isFalse);
      });

      test('returns false if already seen', () {
        final packet = createPacket();
        cache.markSeen(0x12345678);

        expect(policy.shouldRelay(packet, cache), isFalse);
      });

      test('returns true for valid relay candidate', () {
        final packet = createPacket();
        expect(policy.shouldRelay(packet, cache), isTrue);
      });

      test('checks peer-specific relay', () {
        final packet = createPacket();
        cache.markSeen(0x12345678);
        cache.markRelayedTo(0x12345678, 'peer-A');

        // Already relayed to peer-A
        expect(
          policy.shouldRelay(packet, cache, targetPeerId: 'peer-A'),
          isFalse,
        );

        // Not relayed to peer-B
        expect(
          policy.shouldRelay(packet, cache, targetPeerId: 'peer-B'),
          isTrue,
        );
      });
    });

    group('prepareForRelay', () {
      test('decrements TTL', () {
        final packet = createPacket(ttl: 10);
        final prepared = policy.prepareForRelay(packet);

        expect((prepared.header as StandardHeader).hopTtl, equals(9));
      });

      test('adds age if specified', () {
        final packet = createPacket(ageMinutes: 5);
        final prepared = policy.prepareForRelay(packet, additionalAgeMinutes: 2);

        expect((prepared.header as StandardHeader).ageMinutes, equals(7));
      });

      test('preserves other properties', () {
        final packet = createPacket(mesh: true, urgent: true);
        final prepared = policy.prepareForRelay(packet);

        final header = prepared.header as StandardHeader;
        expect(header.flags.mesh, isTrue);
        expect(header.flags.urgent, isTrue);
        expect(header.messageId, equals(0x12345678));
      });
    });

    group('calculatePriority', () {
      test('urgent messages have higher priority', () {
        final normal = createPacket(urgent: false);
        final urgent = createPacket(urgent: true);

        expect(
          policy.calculatePriority(urgent),
          greaterThan(policy.calculatePriority(normal)),
        );
      });

      test('lower TTL has higher priority', () {
        final highTtl = createPacket(ttl: 15);
        final lowTtl = createPacket(ttl: 5);

        expect(
          policy.calculatePriority(lowTtl),
          greaterThan(policy.calculatePriority(highTtl)),
        );
      });
    });
  });
}
