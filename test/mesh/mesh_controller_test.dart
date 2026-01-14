import 'dart:math';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('MeshController', () {
    test('relays new compact packets and does not relay duplicates', () async {
      int broadcastCount = 0;
      Packet? lastBroadcast;

      final controller = MeshController(
        backoff: RelayBackoff(
          baseDelayMs: 0,
          maxDelayMs: 0,
          jitterPercent: 0,
          hopMultiplier: 1.0,
          random: Random(0),
        ),
        onBroadcast: (packet) async {
          broadcastCount++;
          lastBroadcast = packet;
        },
      );

      final packet = Packet.sos(
        sosType: SosType.needRescue,
        latitude: 41.0,
        longitude: 28.0,
        messageId: 0x1234,
      );

      await controller.handleIncomingPacket(packet, fromPeerId: 'peer-A');
      expect(broadcastCount, equals(1));
      expect(lastBroadcast, isNotNull);
      expect(lastBroadcast!.messageId, equals(0x1234));
      expect((lastBroadcast!.header as CompactHeader).ttl, equals(14));

      // Duplicate should not be relayed
      await controller.handleIncomingPacket(packet, fromPeerId: 'peer-A');
      expect(broadcastCount, equals(1));
    });
  });
}

