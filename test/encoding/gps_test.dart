import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/encoding/gps.dart';

void main() {
  group('Gps', () {
    group('encodeLatitude', () {
      test('encodes 0.0 to 0', () {
        expect(Gps.encodeLatitude(0.0), equals(0));
      });

      test('encodes positive latitude', () {
        // 41.0082 (Istanbul) * 10000000 = 410082000
        expect(Gps.encodeLatitude(41.0082), equals(410082000));
      });

      test('encodes negative latitude', () {
        // -33.8688 (Sydney) * 10000000 = -338688000
        expect(Gps.encodeLatitude(-33.8688), equals(-338688000));
      });

      test('throws on latitude < -90', () {
        expect(() => Gps.encodeLatitude(-90.1), throwsA(isA<ArgumentError>()));
      });

      test('throws on latitude > 90', () {
        expect(() => Gps.encodeLatitude(90.1), throwsA(isA<ArgumentError>()));
      });
    });

    group('encodeLongitude', () {
      test('encodes 0.0 to 0', () {
        expect(Gps.encodeLongitude(0.0), equals(0));
      });

      test('encodes positive longitude', () {
        // 28.9784 (Istanbul) * 10000000 = 289784000
        expect(Gps.encodeLongitude(28.9784), equals(289784000));
      });

      test('encodes negative longitude', () {
        // -122.4194 (San Francisco) * 10000000 = -1224194000
        expect(Gps.encodeLongitude(-122.4194), equals(-1224194000));
      });

      test('throws on longitude < -180', () {
        expect(
          () => Gps.encodeLongitude(-180.1),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on longitude > 180', () {
        expect(() => Gps.encodeLongitude(180.1), throwsA(isA<ArgumentError>()));
      });
    });

    group('decodeLatitude', () {
      test('decodes 0 to 0.0', () {
        expect(Gps.decodeLatitude(0), equals(0.0));
      });

      test('decodes positive value', () {
        expect(Gps.decodeLatitude(410082000), closeTo(41.0082, 0.0000001));
      });

      test('decodes negative value', () {
        expect(Gps.decodeLatitude(-338688000), closeTo(-33.8688, 0.0000001));
      });
    });

    group('decodeLongitude', () {
      test('decodes 0 to 0.0', () {
        expect(Gps.decodeLongitude(0), equals(0.0));
      });

      test('decodes positive value', () {
        expect(Gps.decodeLongitude(289784000), closeTo(28.9784, 0.0000001));
      });

      test('decodes negative value', () {
        expect(Gps.decodeLongitude(-1224194000), closeTo(-122.4194, 0.0000001));
      });
    });

    group('encode', () {
      test('encodes to 8 bytes', () {
        final encoded = Gps.encode(41.0082, 28.9784);
        expect(encoded.length, equals(8));
      });

      test('encodes coordinates correctly', () {
        final encoded = Gps.encode(0.0, 0.0);
        // All zeros
        expect(encoded, equals([0, 0, 0, 0, 0, 0, 0, 0]));
      });
    });

    group('decode', () {
      test('decodes 8 bytes to coordinates', () {
        final encoded = Gps.encode(41.0082, 28.9784);
        final (lat, lon) = Gps.decode(encoded);

        expect(lat, closeTo(41.0082, 0.0000001));
        expect(lon, closeTo(28.9784, 0.0000001));
      });

      test('throws on insufficient data', () {
        expect(() => Gps.decode(Uint8List(7)), throwsA(isA<Exception>()));
      });

      test('decodes from offset', () {
        final buffer = Uint8List(12);
        Gps.write(buffer, 2, 41.0082, 28.9784);

        final (lat, lon) = Gps.decode(buffer, 2);
        expect(lat, closeTo(41.0082, 0.0000001));
        expect(lon, closeTo(28.9784, 0.0000001));
      });
    });

    group('write', () {
      test('writes to buffer at offset', () {
        final buffer = Uint8List(12);
        final written = Gps.write(buffer, 2, 41.0082, 28.9784);

        expect(written, equals(8));

        final (lat, lon) = Gps.decode(buffer, 2);
        expect(lat, closeTo(41.0082, 0.0000001));
        expect(lon, closeTo(28.9784, 0.0000001));
      });
    });

    group('validation', () {
      test('isValidLatitude returns true for valid values', () {
        expect(Gps.isValidLatitude(0.0), isTrue);
        expect(Gps.isValidLatitude(90.0), isTrue);
        expect(Gps.isValidLatitude(-90.0), isTrue);
        expect(Gps.isValidLatitude(41.0082), isTrue);
      });

      test('isValidLatitude returns false for invalid values', () {
        expect(Gps.isValidLatitude(90.1), isFalse);
        expect(Gps.isValidLatitude(-90.1), isFalse);
      });

      test('isValidLongitude returns true for valid values', () {
        expect(Gps.isValidLongitude(0.0), isTrue);
        expect(Gps.isValidLongitude(180.0), isTrue);
        expect(Gps.isValidLongitude(-180.0), isTrue);
      });

      test('isValidLongitude returns false for invalid values', () {
        expect(Gps.isValidLongitude(180.1), isFalse);
        expect(Gps.isValidLongitude(-180.1), isFalse);
      });

      test('isValid checks both coordinates', () {
        expect(Gps.isValid(41.0082, 28.9784), isTrue);
        expect(Gps.isValid(91.0, 0.0), isFalse);
        expect(Gps.isValid(0.0, 181.0), isFalse);
      });
    });

    group('roundtrip', () {
      test('encode then decode preserves coordinates', () {
        final testCases = [
          (0.0, 0.0),
          (41.0082, 28.9784), // Istanbul
          (-33.8688, 151.2093), // Sydney
          (40.7128, -74.0060), // New York
          (90.0, 180.0), // Max values
          (-90.0, -180.0), // Min values
        ];

        for (final (lat, lon) in testCases) {
          final encoded = Gps.encode(lat, lon);
          final (decodedLat, decodedLon) = Gps.decode(encoded);

          expect(
            decodedLat,
            closeTo(lat, 0.0000001),
            reason: 'Lat failed for ($lat, $lon)',
          );
          expect(
            decodedLon,
            closeTo(lon, 0.0000001),
            reason: 'Lon failed for ($lat, $lon)',
          );
        }
      });
    });

    group('distance', () {
      test('distance between same points is 0', () {
        expect(Gps.distance(41.0082, 28.9784, 41.0082, 28.9784), closeTo(0, 1));
      });

      test('distance calculation is reasonable', () {
        // Istanbul to Ankara is about 350km
        final istanbul = (41.0082, 28.9784);
        final ankara = (39.9208, 32.8541);

        final dist = Gps.distance(
          istanbul.$1,
          istanbul.$2,
          ankara.$1,
          ankara.$2,
        );

        // Should be roughly 350km (350000 meters)
        expect(dist, closeTo(350000, 50000)); // Within 50km tolerance
      });
    });

    group('precision', () {
      test('7 decimal places are preserved in roundtrip', () {
        // Test that 7 decimal places are preserved
        const lat = 41.1234567;
        const lon = 28.9876543;

        final encoded = Gps.encode(lat, lon);
        final (decodedLat, decodedLon) = Gps.decode(encoded);

        // 7 decimal places should be exact
        expect(decodedLat, closeTo(lat, 0.0000001));
        expect(decodedLon, closeTo(lon, 0.0000001));
      });
    });
  });
}
