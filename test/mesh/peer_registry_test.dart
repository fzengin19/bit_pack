import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('PeerInfo', () {
    test('creates with default values', () {
      final peer = PeerInfo(peerId: 'AA:BB:CC:DD:EE:FF');
      expect(peer.peerId, equals('AA:BB:CC:DD:EE:FF'));
      expect(peer.messageCount, equals(0));
      expect(peer.relayCount, equals(0));
      expect(peer.rssi, isNull);
    });

    test('touch updates lastSeen', () async {
      final peer = PeerInfo(peerId: 'test');
      final initial = peer.lastSeen;

      await Future.delayed(Duration(milliseconds: 10));
      peer.touch();

      expect(peer.lastSeen.isAfter(initial), isTrue);
    });

    test('isActive checks idle time', () {
      final peer = PeerInfo(peerId: 'test');
      expect(peer.isActive(Duration(minutes: 10)), isTrue);
    });

    test('signalQuality returns correct category', () {
      expect(PeerInfo(peerId: 'a', rssi: -40).signalQuality, 'excellent');
      expect(PeerInfo(peerId: 'b', rssi: -60).signalQuality, 'good');
      expect(PeerInfo(peerId: 'c', rssi: -80).signalQuality, 'fair');
      expect(PeerInfo(peerId: 'd', rssi: -90).signalQuality, 'poor');
      expect(PeerInfo(peerId: 'e').signalQuality, 'unknown');
    });
  });

  group('PeerRegistry', () {
    late PeerRegistry registry;

    setUp(() {
      registry = PeerRegistry();
    });

    group('register', () {
      test('adds new peer', () {
        registry.register('peer-1', rssi: -65);
        expect(registry.peerCount, equals(1));
        expect(registry.contains('peer-1'), isTrue);
      });

      test('updates existing peer', () {
        registry.register('peer-1', rssi: -65);
        registry.register('peer-1', rssi: -50);

        final peer = registry.get('peer-1')!;
        expect(peer.rssi, equals(-50));
      });

      test('evicts oldest when at capacity', () {
        final smallRegistry = PeerRegistry(maxPeers: 3);

        smallRegistry.register('peer-1');
        smallRegistry.register('peer-2');
        smallRegistry.register('peer-3');
        smallRegistry.register('peer-4'); // Should evict peer-1

        expect(smallRegistry.peerCount, equals(3));
        expect(smallRegistry.contains('peer-1'), isFalse);
        expect(smallRegistry.contains('peer-4'), isTrue);
      });
    });

    group('recordMessage', () {
      test('increments message count', () {
        registry.register('peer-1');
        registry.recordMessage('peer-1', 0x1234);
        registry.recordMessage('peer-1', 0x5678);

        expect(registry.get('peer-1')!.messageCount, equals(2));
      });

      test('tracks message sources', () {
        registry.register('peer-1');
        registry.register('peer-2');

        registry.recordMessage('peer-1', 0xABCD);
        registry.recordMessage('peer-2', 0xABCD);

        final sources = registry.getPeersWithMessage(0xABCD);
        expect(sources, containsAll(['peer-1', 'peer-2']));
      });
    });

    group('getActivePeers', () {
      test('returns only active peers', () {
        registry.register('active-peer');

        final active = registry.getActivePeers(Duration(minutes: 10));
        expect(active.length, equals(1));
        expect(active.first.peerId, equals('active-peer'));
      });
    });

    group('getPeersBySignal', () {
      test('sorts by signal strength', () {
        registry.register('weak', rssi: -90);
        registry.register('strong', rssi: -40);
        registry.register('medium', rssi: -70);

        final sorted = registry.getPeersBySignal();
        expect(sorted[0].peerId, equals('strong'));
        expect(sorted[1].peerId, equals('medium'));
        expect(sorted[2].peerId, equals('weak'));
      });
    });

    group('cleanup', () {
      test('removes inactive peers', () async {
        final shortThreshold = PeerRegistry(
          activityThreshold: Duration(milliseconds: 20),
        );

        shortThreshold.register('peer-1');

        await Future.delayed(Duration(milliseconds: 50));

        final removed = shortThreshold.cleanup();
        expect(removed, equals(1));
        expect(shortThreshold.peerCount, equals(0));
      });
    });

    group('stats', () {
      test('returns correct statistics', () {
        registry.register('peer-1', rssi: -60);
        registry.register('peer-2', rssi: -70);
        registry.recordMessage('peer-1', 0x1111);
        registry.recordMessage('peer-1', 0x2222);

        final stats = registry.stats;
        expect(stats['totalPeers'], equals(2));
        expect(stats['totalMessages'], equals(2));
        expect(stats['avgRssi'], equals(-65.0));
      });
    });
  });
}
