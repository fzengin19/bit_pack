import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('NackBlock', () {
    group('constructor', () {
      test('creates valid block', () {
        final block = NackBlock(startIndex: 100, bitmask: 42);
        expect(block.startIndex, equals(100));
        expect(block.bitmask, equals(42));
      });

      test('throws on invalid startIndex', () {
        expect(
          () => NackBlock(startIndex: 5000, bitmask: 1),
          throwsA(isA<FragmentationException>()),
        );
      });

      test('throws on invalid bitmask', () {
        expect(
          () => NackBlock(startIndex: 0, bitmask: 0x1FFF),
          throwsA(isA<FragmentationException>()),
        );
      });
    });

    group('fromMissingIndices', () {
      test('creates block from indices', () {
        final block = NackBlock.fromMissingIndices(10, [10, 12, 15]);
        expect(block.startIndex, equals(10));
        expect(block.missingIndices, equals([10, 12, 15]));
      });

      test('ignores indices outside range', () {
        final block = NackBlock.fromMissingIndices(10, [5, 10, 25]);
        expect(block.missingIndices, equals([10]));
      });
    });

    group('missingIndices', () {
      test('returns correct indices', () {
        // Bitmask: bits 0, 2, 5 set = indices 100, 102, 105
        final block = NackBlock(startIndex: 100, bitmask: 37);
        expect(block.missingIndices, equals([100, 102, 105]));
      });

      test('returns empty for zero bitmask', () {
        final block = NackBlock(startIndex: 0, bitmask: 0);
        expect(block.missingIndices, isEmpty);
      });
    });

    group('isMissing', () {
      test('returns true for missing fragments', () {
        final block = NackBlock(startIndex: 50, bitmask: 10);
        expect(block.isMissing(51), isTrue);
        expect(block.isMissing(53), isTrue);
      });

      test('returns false for present fragments', () {
        final block = NackBlock(startIndex: 50, bitmask: 10);
        expect(block.isMissing(50), isFalse);
        expect(block.isMissing(52), isFalse);
      });

      test('returns false for out of range', () {
        final block = NackBlock(startIndex: 50, bitmask: 15);
        expect(block.isMissing(40), isFalse);
        expect(block.isMissing(70), isFalse);
      });
    });

    group('encode/decode roundtrip', () {
      test('roundtrip with small values', () {
        final original = NackBlock(startIndex: 15, bitmask: 7);
        final encoded = original.encode();
        final decoded = NackBlock.decode(encoded);

        expect(decoded.startIndex, equals(15));
        expect(decoded.bitmask, equals(7));
        expect(decoded, equals(original));
      });

      test('roundtrip with maximum values', () {
        final original = NackBlock(startIndex: 4095, bitmask: 0xFFF);
        final encoded = original.encode();
        final decoded = NackBlock.decode(encoded);

        expect(decoded.startIndex, equals(4095));
        expect(decoded.bitmask, equals(0xFFF));
      });

      test('encoded size is 3 bytes', () {
        final block = NackBlock(startIndex: 100, bitmask: 0x555);
        expect(block.encode().length, equals(3));
      });
    });
  });

  group('NackPayload', () {
    group('constructor', () {
      test('creates valid payload', () {
        final payload = NackPayload(
          originalMessageId: 0x12345678,
          blocks: [NackBlock(startIndex: 0, bitmask: 1)],
        );
        expect(payload.originalMessageId, equals(0x12345678));
        expect(payload.blocks.length, equals(1));
      });

      test('throws on empty blocks', () {
        expect(
          () => NackPayload(originalMessageId: 0, blocks: []),
          throwsA(isA<FragmentationException>()),
        );
      });

      test('throws on too many blocks', () {
        final blocks = List.generate(
          10,
          (i) => NackBlock(startIndex: i * 20, bitmask: 1),
        );
        expect(
          () => NackPayload(originalMessageId: 0, blocks: blocks),
          throwsA(isA<FragmentationException>()),
        );
      });
    });

    group('fromMissingIndices', () {
      test('creates single block for consecutive indices', () {
        final payload = NackPayload.fromMissingIndices(
          originalMessageId: 0xABCD,
          missingIndices: [5, 6, 7, 8],
        );

        expect(payload.blocks.length, equals(1));
        expect(payload.allMissingIndices, equals([5, 6, 7, 8]));
      });

      test('creates multiple blocks for distant indices', () {
        final payload = NackPayload.fromMissingIndices(
          originalMessageId: 0xABCD,
          missingIndices: [5, 6, 7, 100, 101, 102],
        );

        expect(payload.blocks.length, equals(2));
        expect(payload.allMissingIndices, equals([5, 6, 7, 100, 101, 102]));
      });

      test('prioritizes earliest indices if too many', () {
        // Create many gaps that would exceed maxBlocks
        final indices = List.generate(100, (i) => i * 20);
        final payload = NackPayload.fromMissingIndices(
          originalMessageId: 0x1234,
          missingIndices: indices,
          maxBlockCount: 3,
        );

        expect(payload.blocks.length, lessThanOrEqualTo(3));
        // Earliest indices should be included
        expect(payload.allMissingIndices.first, equals(0));
      });
    });

    group('properties', () {
      test('type is nack', () {
        final payload = NackPayload(
          originalMessageId: 0,
          blocks: [NackBlock(startIndex: 0, bitmask: 1)],
        );
        expect(payload.type, equals(MessageType.nack));
      });

      test('sizeInBytes is correct', () {
        final payload = NackPayload(
          originalMessageId: 0,
          blocks: [
            NackBlock(startIndex: 0, bitmask: 1),
            NackBlock(startIndex: 20, bitmask: 1),
          ],
        );
        // 5 (header) + 2 * 3 (blocks) = 11
        expect(payload.sizeInBytes, equals(11));
      });

      test('totalMissingCount is correct', () {
        final payload = NackPayload(
          originalMessageId: 0,
          blocks: [
            NackBlock(startIndex: 0, bitmask: 7), // 3 missing
            NackBlock(startIndex: 20, bitmask: 3), // 2 missing
          ],
        );
        expect(payload.totalMissingCount, equals(5));
      });
    });

    group('encode/decode roundtrip', () {
      test('roundtrip single block', () {
        final original = NackPayload.fromMissingIndices(
          originalMessageId: 0xDEADBEEF,
          missingIndices: [10, 11, 13],
        );

        final encoded = original.encode();
        final decoded = NackPayload.decode(encoded);

        expect(decoded.originalMessageId, equals(0xDEADBEEF));
        expect(decoded.allMissingIndices, equals([10, 11, 13]));
      });

      test('roundtrip multiple blocks', () {
        final original = NackPayload.fromMissingIndices(
          originalMessageId: 0x12345678,
          missingIndices: [5, 7, 50, 51, 52, 200],
        );

        final encoded = original.encode();
        final decoded = NackPayload.decode(encoded);

        expect(decoded.originalMessageId, equals(0x12345678));
        expect(decoded.allMissingIndices, equals(original.allMissingIndices));
      });
    });

    group('copy', () {
      test('creates independent copy', () {
        final original = NackPayload.fromMissingIndices(
          originalMessageId: 0x1234,
          missingIndices: [1, 2, 3],
        );

        final copy = original.copy() as NackPayload;

        expect(copy.originalMessageId, equals(original.originalMessageId));
        expect(copy.allMissingIndices, equals(original.allMissingIndices));
        expect(identical(copy, original), isFalse);
      });
    });
  });
}
