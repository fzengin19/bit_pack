import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('FragmentHeader', () {
    group('constructor', () {
      test('creates valid header', () {
        final header = FragmentHeader(fragmentIndex: 5, totalFragments: 10);
        expect(header.fragmentIndex, equals(5));
        expect(header.totalFragments, equals(10));
      });

      test('allows maximum values', () {
        final header = FragmentHeader(
          fragmentIndex: 4094,
          totalFragments: 4095,
        );
        expect(header.fragmentIndex, equals(4094));
        expect(header.totalFragments, equals(4095));
      });

      test('allows first fragment (index 0)', () {
        final header = FragmentHeader(fragmentIndex: 0, totalFragments: 5);
        expect(header.isFirst, isTrue);
        expect(header.isLast, isFalse);
      });

      test('allows last fragment (index = total - 1)', () {
        final header = FragmentHeader(fragmentIndex: 4, totalFragments: 5);
        expect(header.isFirst, isFalse);
        expect(header.isLast, isTrue);
      });

      test('throws on negative index', () {
        expect(
          () => FragmentHeader(fragmentIndex: -1, totalFragments: 10),
          throwsA(isA<FragmentationException>()),
        );
      });

      test('throws on index >= total', () {
        expect(
          () => FragmentHeader(fragmentIndex: 10, totalFragments: 10),
          throwsA(isA<FragmentationException>()),
        );
      });

      test('throws on zero total fragments', () {
        expect(
          () => FragmentHeader(fragmentIndex: 0, totalFragments: 0),
          throwsA(isA<FragmentationException>()),
        );
      });

      test('throws on index exceeding max', () {
        expect(
          () => FragmentHeader(fragmentIndex: 4096, totalFragments: 4096),
          throwsA(isA<FragmentationException>()),
        );
      });
    });

    group('encode/decode roundtrip', () {
      test('roundtrip with small values', () {
        final original = FragmentHeader(fragmentIndex: 3, totalFragments: 8);
        final encoded = original.encode();
        final decoded = FragmentHeader.decode(encoded);

        expect(decoded.fragmentIndex, equals(3));
        expect(decoded.totalFragments, equals(8));
        expect(decoded, equals(original));
      });

      test('roundtrip with maximum values', () {
        // 12 bits max = 4095, so max index is 4094 with total of 4095
        final original = FragmentHeader(
          fragmentIndex: 4094,
          totalFragments: 4095,
        );
        final encoded = original.encode();
        final decoded = FragmentHeader.decode(encoded);

        expect(decoded.fragmentIndex, equals(4094));
        expect(decoded.totalFragments, equals(4095));
      });

      test('roundtrip with first fragment', () {
        final original = FragmentHeader(fragmentIndex: 0, totalFragments: 100);
        final encoded = original.encode();
        final decoded = FragmentHeader.decode(encoded);

        expect(decoded.isFirst, isTrue);
        expect(decoded.fragmentIndex, equals(0));
      });

      test('encoded size is 3 bytes', () {
        final header = FragmentHeader(fragmentIndex: 100, totalFragments: 200);
        expect(header.encode().length, equals(3));
        expect(FragmentHeader.sizeInBytes, equals(3));
      });
    });

    group('decode validation', () {
      test('throws on insufficient bytes', () {
        expect(
          () => FragmentHeader.decode(Uint8List(2)),
          throwsA(isA<DecodingException>()),
        );
      });

      test('throws on zero total fragments in data', () {
        // Craft bytes where total = 0
        final bytes = Uint8List.fromList([0x00, 0x00, 0x00]);
        expect(
          () => FragmentHeader.decode(bytes),
          throwsA(isA<DecodingException>()),
        );
      });

      test('decode with offset', () {
        final prefix = Uint8List.fromList([0xFF, 0xFF]);
        final header = FragmentHeader(fragmentIndex: 5, totalFragments: 10);
        final headerBytes = header.encode();

        final combined = Uint8List(prefix.length + headerBytes.length);
        combined.setRange(0, prefix.length, prefix);
        combined.setRange(prefix.length, combined.length, headerBytes);

        final decoded = FragmentHeader.decode(combined, prefix.length);
        expect(decoded.fragmentIndex, equals(5));
        expect(decoded.totalFragments, equals(10));
      });
    });

    group('properties', () {
      test('isFirst is true only for index 0', () {
        expect(FragmentHeader(fragmentIndex: 0, totalFragments: 5).isFirst, isTrue);
        expect(FragmentHeader(fragmentIndex: 1, totalFragments: 5).isFirst, isFalse);
      });

      test('isLast is true only for last index', () {
        expect(FragmentHeader(fragmentIndex: 4, totalFragments: 5).isLast, isTrue);
        expect(FragmentHeader(fragmentIndex: 3, totalFragments: 5).isLast, isFalse);
      });

      test('single fragment is both first and last', () {
        final header = FragmentHeader(fragmentIndex: 0, totalFragments: 1);
        expect(header.isFirst, isTrue);
        expect(header.isLast, isTrue);
      });
    });

    group('equality', () {
      test('equal headers are equal', () {
        final a = FragmentHeader(fragmentIndex: 5, totalFragments: 10);
        final b = FragmentHeader(fragmentIndex: 5, totalFragments: 10);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different headers are not equal', () {
        final a = FragmentHeader(fragmentIndex: 5, totalFragments: 10);
        final b = FragmentHeader(fragmentIndex: 6, totalFragments: 10);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
