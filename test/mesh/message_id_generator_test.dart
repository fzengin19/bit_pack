import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('MessageIdGenerator', () {
    group('generate (16-bit)', () {
      test('generates valid 16-bit ID', () {
        final id = MessageIdGenerator.generate();
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0xFFFF));
      });

      test('generates different IDs', () {
        final ids = <int>{};
        for (int i = 0; i < 100; i++) {
          ids.add(MessageIdGenerator.generate());
        }
        // Should have at least 50 unique IDs (random component)
        expect(ids.length, greaterThan(50));
      });

      test('time window is consistent within same minute', () {
        final id1 = MessageIdGenerator.generate();
        final id2 = MessageIdGenerator.generate();

        // Same time window (high byte)
        expect(
          MessageIdGenerator.extractTimeWindow16(id1),
          equals(MessageIdGenerator.extractTimeWindow16(id2)),
        );
      });
    });

    group('generate32 (32-bit)', () {
      test('generates valid 32-bit ID', () {
        final id = MessageIdGenerator.generate32();
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0xFFFFFFFF));
      });

      test('generates different IDs', () {
        final ids = <int>{};
        for (int i = 0; i < 100; i++) {
          ids.add(MessageIdGenerator.generate32());
        }
        expect(ids.length, greaterThan(90));
      });
    });

    group('extractTimeWindow', () {
      test('extracts 16-bit time window correctly', () {
        // New layout: 4-bit time window (high) + 12-bit random (low)
        final id = 0xA123; // time window = 0xA (10), random = 0x123
        expect(MessageIdGenerator.extractTimeWindow16(id), equals(0x0A));
        expect(MessageIdGenerator.extractRandom16(id), equals(0x123));
      });

      test('extracts 32-bit time window correctly', () {
        final id = 0xABCD1234; // time window = 0xABCD, random = 0x1234
        expect(MessageIdGenerator.extractTimeWindow32(id), equals(0xABCD));
        expect(MessageIdGenerator.extractRandom32(id), equals(0x1234));
      });
    });

    group('sameTimeWindow', () {
      test('detects same time window (16-bit)', () {
        // New layout: 4-bit time window (high) + 12-bit random (low)
        expect(
          MessageIdGenerator.sameTimeWindow16(0xA123, 0xA456), // same A
          isTrue,
        );
        expect(
          MessageIdGenerator.sameTimeWindow16(0xA123, 0xB123), // different A vs B
          isFalse,
        );
      });

      test('detects same time window (32-bit)', () {
        expect(
          MessageIdGenerator.sameTimeWindow32(0xABCD1234, 0xABCD5678),
          isTrue,
        );
        expect(
          MessageIdGenerator.sameTimeWindow32(0xABCD1234, 0x12341234),
          isFalse,
        );
      });
    });

    group('generateForMode', () {
      test('generates 16-bit for compact mode', () {
        final id = MessageIdGenerator.generateForMode(true);
        expect(id, lessThanOrEqualTo(0xFFFF));
      });

      test('generates 32-bit for standard mode', () {
        final id = MessageIdGenerator.generateForMode(false);
        // Just verify it's a valid int (32-bit can exceed 16-bit max)
        expect(id, isA<int>());
      });
    });
  });
}
