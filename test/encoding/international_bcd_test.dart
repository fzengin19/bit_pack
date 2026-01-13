import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/encoding/international_bcd.dart';
import 'package:bit_pack/src/core/types.dart';

void main() {
  group('InternationalBcd', () {
    group('Domestic encoding', () {
      test('encodes domestic number with implicit +90', () {
        final encoded = InternationalBcd.encode('5331234567', isDomestic: true);

        // Header: INT=0, LENGTH=5 (10 digits = 5 BCD pairs)
        expect(encoded[0] & 0x80, equals(0)); // INT=0
        expect((encoded[0] >> 3) & 0x0F, equals(5)); // LENGTH=5
      });

      test('encodes last 10 digits for long number', () {
        final encoded = InternationalBcd.encode(
          '905331234567',
          isDomestic: true,
        );

        // Should only encode last 10 digits: 5331234567
        expect((encoded[0] >> 3) & 0x0F, equals(5)); // 10 digits = 5 pairs
      });

      test('auto-detects domestic from number without +', () {
        final encoded = InternationalBcd.encode('5331234567');

        expect(encoded[0] & 0x80, equals(0)); // INT=0 (domestic)
      });
    });

    group('International encoding', () {
      test('encodes Turkey number with shortcut', () {
        final encoded = InternationalBcd.encode(
          '+905331234567',
          isDomestic: false,
        );

        // Header: INT=1, COUNTRY=6 (Turkey)
        expect(encoded[0] & 0x80, isNot(0)); // INT=1
        expect(encoded[0] & 0x07, equals(0x6)); // Turkey shortcut
      });

      test('encodes USA number with shortcut', () {
        final encoded = InternationalBcd.encode(
          '+15551234567',
          isDomestic: false,
        );

        // Header: INT=1, COUNTRY=1 (USA)
        expect(encoded[0] & 0x80, isNot(0)); // INT=1
        expect(encoded[0] & 0x07, equals(0x1)); // USA shortcut
      });

      test('encodes UK number with shortcut', () {
        final encoded = InternationalBcd.encode(
          '+442071234567',
          isDomestic: false,
        );

        expect(encoded[0] & 0x07, equals(0x2)); // UK shortcut
      });

      test('encodes Germany number with shortcut', () {
        final encoded = InternationalBcd.encode(
          '+4930123456',
          isDomestic: false,
        );

        expect(encoded[0] & 0x07, equals(0x3)); // Germany shortcut
      });

      test('encodes custom country with 0x7', () {
        // Jordan +962
        final encoded = InternationalBcd.encode(
          '+96271234567',
          isDomestic: false,
        );

        expect(encoded[0] & 0x07, equals(0x7)); // Custom
        // Next 2 bytes should contain country code BCD
        expect(encoded.length, greaterThan(3));
      });

      test('auto-detects international from + prefix', () {
        final encoded = InternationalBcd.encode('+15551234567');

        expect(encoded[0] & 0x80, isNot(0)); // INT=1
      });
    });

    group('encodeWithCountry', () {
      test('encodes with CountryCode enum', () {
        final encoded = InternationalBcd.encodeWithCountry(
          '5551234567',
          CountryCode.usaCanada,
        );

        expect(encoded[0] & 0x80, isNot(0)); // INT=1
        expect(encoded[0] & 0x07, equals(0x1)); // USA shortcut
      });

      test('encodes Turkey number', () {
        final encoded = InternationalBcd.encodeWithCountry(
          '5331234567',
          CountryCode.turkey,
        );

        expect(encoded[0] & 0x07, equals(0x6)); // Turkey shortcut
      });
    });

    group('decode', () {
      test('decodes domestic number', () {
        final encoded = InternationalBcd.encode('5331234567', isDomestic: true);
        final decoded = InternationalBcd.decode(encoded);

        expect(decoded, startsWith('+90'));
        expect(decoded, contains('5331234567'));
      });

      test('decodes Turkey international number', () {
        final encoded = InternationalBcd.encode(
          '+905331234567',
          isDomestic: false,
        );
        final decoded = InternationalBcd.decode(encoded);

        expect(decoded, startsWith('+90'));
      });

      test('decodes USA number', () {
        final encoded = InternationalBcd.encode(
          '+15551234567',
          isDomestic: false,
        );
        final decoded = InternationalBcd.decode(encoded);

        expect(decoded, startsWith('+1'));
      });

      test('throws on empty input', () {
        expect(
          () => InternationalBcd.decode(Uint8List(0)),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('getCountryCode', () {
      test('returns turkey for domestic', () {
        final encoded = InternationalBcd.encode('5331234567', isDomestic: true);
        expect(
          InternationalBcd.getCountryCode(encoded),
          equals(CountryCode.turkey),
        );
      });

      test('returns correct country for known codes', () {
        final usaEncoded = InternationalBcd.encode('+15551234567');
        expect(
          InternationalBcd.getCountryCode(usaEncoded),
          equals(CountryCode.usaCanada),
        );

        final ukEncoded = InternationalBcd.encode('+442071234567');
        expect(
          InternationalBcd.getCountryCode(ukEncoded),
          equals(CountryCode.uk),
        );

        final deEncoded = InternationalBcd.encode('+4930123456');
        expect(
          InternationalBcd.getCountryCode(deEncoded),
          equals(CountryCode.germany),
        );
      });

      test('returns null for custom country', () {
        final encoded = InternationalBcd.encode('+96271234567');
        expect(InternationalBcd.getCountryCode(encoded), isNull);
      });

      test('returns null for empty', () {
        expect(InternationalBcd.getCountryCode(Uint8List(0)), isNull);
      });
    });

    group('encodedSize', () {
      test('returns correct size for domestic', () {
        final size = InternationalBcd.encodedSize(
          '5331234567',
          isDomestic: true,
        );
        expect(size, equals(6)); // 1 header + 5 BCD pairs
      });
    });

    group('roundtrip', () {
      test('domestic roundtrip', () {
        const original = '5331234567';
        final encoded = InternationalBcd.encode(original, isDomestic: true);
        final decoded = InternationalBcd.decode(encoded);

        expect(decoded, equals('+90$original'));
      });

      test('international Turkey roundtrip', () {
        const original = '+905331234567';
        final encoded = InternationalBcd.encode(original);
        final decoded = InternationalBcd.decode(encoded);

        expect(decoded, contains('90'));
        expect(decoded, contains('5331234567'));
      });

      test('international USA roundtrip', () {
        const original = '+15551234567';
        final encoded = InternationalBcd.encode(original);
        final decoded = InternationalBcd.decode(encoded);

        expect(decoded, startsWith('+1'));
        expect(decoded, contains('5551234567'));
      });
    });
  });
}
