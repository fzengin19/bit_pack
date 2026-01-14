import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('PacketBuilder', () {
    group('basic usage', () {
      test('builds text packet', () {
        final packet = PacketBuilder()
            .text('Hello World')
            .mesh(true)
            .build();

        expect(packet.type, equals(MessageType.textShort));
        expect(packet.payload, isA<TextPayload>());
        expect((packet.payload as TextPayload).text, equals('Hello World'));
      });

      test('builds location packet', () {
        final packet = PacketBuilder()
            .location(41.0082, 28.9784)
            .build();

        expect(packet.type, equals(MessageType.location));
        expect(packet.payload, isA<LocationPayload>());
      });

      test('builds with custom payload', () {
        final packet = PacketBuilder()
            .type(MessageType.textShort)
            .payload(TextPayload(text: 'Custom'))
            .build();

        expect((packet.payload as TextPayload).text, equals('Custom'));
      });
    });

    group('mode selection', () {
      test('auto-selects compact for small payloads', () {
        final packet = PacketBuilder()
            .location(41.0, 28.0)
            .build();

        expect(packet.mode, equals(PacketMode.compact));
      });

      test('auto-selects standard for encrypted', () {
        final packet = PacketBuilder()
            .text('Hello')
            .encrypted(true)
            .build();

        expect(packet.mode, equals(PacketMode.standard));
      });

      test('auto-selects standard for standard-only message type', () {
        final packet = PacketBuilder()
            .type(MessageType.handshakeInit)
            .payload(TextPayload(text: 'x'))
            .build();

        expect(packet.mode, equals(PacketMode.standard));
      });

      test('auto-selects standard for fragmentation flags', () {
        final packet = PacketBuilder()
            .text('Hello')
            .fragment(true)
            .build();

        expect(packet.mode, equals(PacketMode.standard));
      });

      test('auto-selects standard for high TTL', () {
        final packet = PacketBuilder()
            .text('Hello')
            .ttl(20)
            .build();

        expect(packet.mode, equals(PacketMode.standard));
      });

      test('forces compact mode', () {
        final packet = PacketBuilder()
            .location(41.0, 28.0)
            .compact()
            .build();

        expect(packet.mode, equals(PacketMode.compact));
      });

      test('forces standard mode', () {
        final packet = PacketBuilder()
            .location(41.0, 28.0)
            .standard()
            .build();

        expect(packet.mode, equals(PacketMode.standard));
      });
    });

    group('flags', () {
      test('sets mesh flag', () {
        final packet = PacketBuilder()
            .text('Hello')
            .mesh(true)
            .standard() // Force standard for this test
            .build();

        final header = packet.header as StandardHeader;
        expect(header.flags.mesh, isTrue);
      });

      test('sets urgent flag', () {
        final packet = PacketBuilder()
            .text('Hello')
            .urgent(true)
            .standard() // Force standard for this test
            .build();

        final header = packet.header as StandardHeader;
        expect(header.flags.urgent, isTrue);
      });

      test('sets ackRequired flag', () {
        final packet = PacketBuilder()
            .text('Hello')
            .ackRequired(true)
            .standard() // Force standard for this test
            .build();

        final header = packet.header as StandardHeader;
        expect(header.flags.ackRequired, isTrue);
      });
    });

    group('message ID', () {
      test('auto-generates message ID', () {
        final packet = PacketBuilder()
            .text('Hello')
            .build();

        expect(packet.messageId, isNonZero);
      });

      test('uses provided message ID (standard mode)', () {
        final packet = PacketBuilder()
            .text('Hello')
            .standard()
            .messageId(0x12345678)
            .build();

        expect(packet.messageId, equals(0x12345678));
      });

      test('uses provided message ID (compact mode)', () {
        final packet = PacketBuilder()
            .location(41.0, 28.0)
            .compact()
            .messageId(0x1234)
            .build();

        expect(packet.messageId, equals(0x1234));
      });
    });

    group('TTL', () {
      test('clamps TTL for compact mode', () {
        final packet = PacketBuilder()
            .location(41.0, 28.0)
            .compact()
            .ttl(100) // Should be clamped to 15
            .build();

        final header = packet.header as CompactHeader;
        expect(header.ttl, equals(15));
      });

      test('allows high TTL in standard mode', () {
        final packet = PacketBuilder()
            .text('Hello')
            .ttl(200)
            .build();

        final header = packet.header as StandardHeader;
        expect(header.hopTtl, equals(200));
      });
    });

    group('reset', () {
      test('resets builder state', () {
        final builder = PacketBuilder()
            .text('Hello')
            .mesh(true)
            .urgent(true);

        builder.reset();

        expect(() => builder.build(), throwsA(isA<StateError>()));
      });
    });

    group('validation', () {
      test('throws if no payload set', () {
        expect(
          () => PacketBuilder().build(),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
