import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/encoding/bcd.dart';

void main() {
  group('Bcd', () {
    group('encode', () {
      test('encodes empty string to empty bytes', () {
        final encoded = Bcd.encode('');
        expect(encoded, isEmpty);
      });

      test('encodes single digit with padding', () {
        final encoded = Bcd.encode('5');
        expect(encoded, equals([0x5F]));
      });

      test('encodes two digits', () {
        final encoded = Bcd.encode('12');
        expect(encoded, equals([0x12]));
      });

      test('encodes 10 digits (typical phone number)', () {
        final encoded = Bcd.encode('1234567890');
        expect(encoded, equals([0x12, 0x34, 0x56, 0x78, 0x90]));
      });

      test('encodes odd-length number with padding', () {
        final encoded = Bcd.encode('12345');
        expect(encoded, equals([0x12, 0x34, 0x5F]));
      });

      test('strips non-digit characters', () {
        final encoded = Bcd.encode('+90 (533) 123-4567');
        expect(encoded, equals([0x90, 0x53, 0x31, 0x23, 0x45, 0x67]));
      });
    });

    group('decode', () {
      test('decodes empty bytes to empty string', () {
        final decoded = Bcd.decode(Uint8List(0));
        expect(decoded, isEmpty);
      });

      test('decodes single byte with padding', () {
        final decoded = Bcd.decode(Uint8List.fromList([0x5F]));
        expect(decoded, equals('5'));
      });

      test('decodes two digits', () {
        final decoded = Bcd.decode(Uint8List.fromList([0x12]));
        expect(decoded, equals('12'));
      });

      test('decodes 10 digits', () {
        final decoded = Bcd.decode(
          Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0x90]),
        );
        expect(decoded, equals('1234567890'));
      });

      test('decodes with padding nibble', () {
        final decoded = Bcd.decode(Uint8List.fromList([0x12, 0x34, 0x5F]));
        expect(decoded, equals('12345'));
      });

      test('throws on invalid nibble', () {
        expect(
          () => Bcd.decode(Uint8List.fromList([0xAB])), // A and B are invalid
          throwsA(isA<Exception>()),
        );
      });
    });

    group('encodeLastDigits', () {
      test('encodes last 8 digits', () {
        final encoded = Bcd.encodeLastDigits('+905331234567', 8);
        // Last 8 digits: 31234567
        expect(encoded, equals([0x31, 0x23, 0x45, 0x67]));
      });

      test('pads if fewer digits available', () {
        final encoded = Bcd.encodeLastDigits('12345', 8);
        expect(encoded, equals([0x12, 0x34, 0x5F]));
      });

      test('works with exactly requested digits', () {
        final encoded = Bcd.encodeLastDigits('12345678', 8);
        expect(encoded, equals([0x12, 0x34, 0x56, 0x78]));
      });
    });

    group('write and read', () {
      test('write writes to buffer at offset', () {
        final buffer = Uint8List(10);
        final written = Bcd.write(buffer, 2, '1234');

        expect(written, equals(2));
        expect(buffer[2], equals(0x12));
        expect(buffer[3], equals(0x34));
      });

      test('read reads from buffer at offset', () {
        final buffer = Uint8List.fromList([0xFF, 0x12, 0x34, 0xFF]);
        final decoded = Bcd.read(buffer, 1, 2);

        expect(decoded, equals('1234'));
      });

      test('read throws on insufficient data', () {
        final buffer = Uint8List.fromList([0x12]);
        expect(() => Bcd.read(buffer, 0, 5), throwsA(isA<Exception>()));
      });
    });

    group('encodedLength', () {
      test('calculates correct byte count', () {
        expect(Bcd.encodedLength(1), equals(1));
        expect(Bcd.encodedLength(2), equals(1));
        expect(Bcd.encodedLength(3), equals(2));
        expect(Bcd.encodedLength(4), equals(2));
        expect(Bcd.encodedLength(10), equals(5));
        expect(Bcd.encodedLength(11), equals(6));
      });
    });

    group('format', () {
      test('formats with default Turkey code', () {
        expect(Bcd.format('5331234567'), equals('+905331234567'));
      });

      test('formats with custom country code', () {
        expect(
          Bcd.format('5551234567', countryCode: '+1'),
          equals('+15551234567'),
        );
      });
    });

    group('roundtrip', () {
      test('encode then decode preserves digits', () {
        final testCases = [
          '0',
          '12',
          '123',
          '1234567890',
          '5331234567',
          '00000',
        ];

        for (final original in testCases) {
          final encoded = Bcd.encode(original);
          final decoded = Bcd.decode(encoded);
          expect(decoded, equals(original), reason: 'Failed for "$original"');
        }
      });
    });
  });
}
