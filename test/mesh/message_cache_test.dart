import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('MessageCacheEntry', () {
    test('creates with current time', () {
      final entry = MessageCacheEntry();
      expect(entry.firstSeen.difference(DateTime.now()).inSeconds.abs(), lessThan(1));
      expect(entry.relayedTo, isEmpty);
    });

    test('touch updates lastAccess', () async {
      final entry = MessageCacheEntry();
      final initial = entry.lastAccess;

      await Future.delayed(Duration(milliseconds: 10));
      entry.touch();

      expect(entry.lastAccess.isAfter(initial), isTrue);
    });

    test('isExpired works correctly', () {
      final entry = MessageCacheEntry(
        firstSeen: DateTime.now().subtract(Duration(hours: 25)),
      );

      expect(entry.isExpired(Duration(hours: 24)), isTrue);
      expect(entry.isExpired(Duration(hours: 26)), isFalse);
    });
  });

  group('MessageCache', () {
    group('basic operations', () {
      test('hasSeen returns false for new message', () {
        final cache = MessageCache();
        expect(cache.hasSeen(0x1234), isFalse);
      });

      test('hasSeen returns true after markSeen', () {
        final cache = MessageCache();
        cache.markSeen(0x1234);
        expect(cache.hasSeen(0x1234), isTrue);
      });

      test('tracks size correctly', () {
        final cache = MessageCache();
        expect(cache.size, equals(0));

        cache.markSeen(0x1111);
        cache.markSeen(0x2222);
        cache.markSeen(0x3333);

        expect(cache.size, equals(3));
      });

      test('updates hit/miss statistics', () {
        final cache = MessageCache();

        cache.hasSeen(0x1111); // miss
        cache.hasSeen(0x2222); // miss
        cache.markSeen(0x1111);
        cache.hasSeen(0x1111); // hit

        expect(cache.misses, equals(2));
        expect(cache.hits, equals(1));
        expect(cache.hitRatio, closeTo(0.333, 0.01));
      });
    });

    group('relay tracking', () {
      test('getRelayedTo returns empty for unknown message', () {
        final cache = MessageCache();
        expect(cache.getRelayedTo(0x9999), isEmpty);
      });

      test('markRelayedTo tracks peers', () {
        final cache = MessageCache();

        cache.markRelayedTo(0x1234, 'peer-A');
        cache.markRelayedTo(0x1234, 'peer-B');

        expect(cache.getRelayedTo(0x1234), equals({'peer-A', 'peer-B'}));
      });

      test('wasRelayedTo checks specific peer', () {
        final cache = MessageCache();

        cache.markRelayedTo(0x1234, 'peer-A');

        expect(cache.wasRelayedTo(0x1234, 'peer-A'), isTrue);
        expect(cache.wasRelayedTo(0x1234, 'peer-B'), isFalse);
      });
    });

    group('LRU eviction', () {
      test('evicts oldest when at capacity', () {
        final cache = MessageCache(maxSize: 3);

        cache.markSeen(0x1111);
        cache.markSeen(0x2222);
        cache.markSeen(0x3333);
        cache.markSeen(0x4444); // Should evict 0x1111

        expect(cache.size, equals(3));
        expect(cache.hasSeen(0x1111), isFalse);
        expect(cache.hasSeen(0x2222), isTrue);
        expect(cache.hasSeen(0x4444), isTrue);
      });

      test('access updates LRU order', () {
        final cache = MessageCache(maxSize: 3);

        cache.markSeen(0x1111);
        cache.markSeen(0x2222);
        cache.markSeen(0x3333);

        // Access 0x1111 to make it recently used
        cache.hasSeen(0x1111);

        cache.markSeen(0x4444); // Should evict 0x2222 (oldest unused)

        expect(cache.hasSeen(0x1111), isTrue);
        expect(cache.hasSeen(0x2222), isFalse);
      });
    });

    group('TTL expiry', () {
      test('expired entries are not found', () {
        final cache = MessageCache(ttl: Duration(milliseconds: 50));

        cache.markSeen(0x1234);
        expect(cache.hasSeen(0x1234), isTrue);
      });

      test('cleanup removes expired entries', () async {
        final cache = MessageCache(ttl: Duration(milliseconds: 20));

        cache.markSeen(0x1111);
        cache.markSeen(0x2222);

        expect(cache.size, equals(2));

        await Future.delayed(Duration(milliseconds: 50));

        final removed = cache.cleanup();
        expect(removed, equals(2));
        expect(cache.size, equals(0));
      });
    });

    group('clear', () {
      test('removes all entries and resets stats', () {
        final cache = MessageCache();

        cache.markSeen(0x1111);
        cache.markSeen(0x2222);
        cache.hasSeen(0x1111);

        cache.clear();

        expect(cache.size, equals(0));
        expect(cache.hits, equals(0));
        expect(cache.misses, equals(0));
      });
    });
  });
}
