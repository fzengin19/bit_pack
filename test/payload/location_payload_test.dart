import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/payload/location_payload.dart';
import 'package:bit_pack/src/core/types.dart';

void main() {
  group('LocationPayload', () {
    group('construction', () {
      test('creates compact payload', () {
        final payload = LocationPayload(latitude: 41.0082, longitude: 28.9784);

        expect(payload.latitude, closeTo(41.0082, 0.0000001));
        expect(payload.longitude, closeTo(28.9784, 0.0000001));
        expect(payload.altitude, isNull);
        expect(payload.accuracy, isNull);
        expect(payload.isExtended, isFalse);
      });

      test('creates extended payload', () {
        final payload = LocationPayload(
          latitude: 41.0082,
          longitude: 28.9784,
          altitude: 150,
          accuracy: 10,
        );

        expect(payload.altitude, equals(150));
        expect(payload.accuracy, equals(10));
        expect(payload.isExtended, isTrue);
      });

      test('throws on invalid latitude', () {
        expect(
          () => LocationPayload(latitude: 91.0, longitude: 0.0),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on invalid longitude', () {
        expect(
          () => LocationPayload(latitude: 0.0, longitude: 181.0),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on invalid altitude', () {
        expect(
          () => LocationPayload(
            latitude: 41.0,
            longitude: 29.0,
            altitude: 40000, // Max is 32767
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('sizeInBytes', () {
      test('compact is 8 bytes', () {
        final payload = LocationPayload(latitude: 0.0, longitude: 0.0);
        expect(payload.sizeInBytes, equals(8));
      });

      test('extended is 12 bytes', () {
        final payload = LocationPayload(
          latitude: 0.0,
          longitude: 0.0,
          altitude: 100,
        );
        expect(payload.sizeInBytes, equals(12));
      });
    });

    group('encode', () {
      test('encodes compact to 8 bytes', () {
        final payload = LocationPayload(latitude: 0.0, longitude: 0.0);
        expect(payload.encode().length, equals(8));
      });

      test('encodes extended to 12 bytes', () {
        final payload = LocationPayload(
          latitude: 0.0,
          longitude: 0.0,
          altitude: 100,
        );
        expect(payload.encode().length, equals(12));
      });
    });

    group('decode', () {
      test('decodes compact payload', () {
        final original = LocationPayload(latitude: 41.0082, longitude: 28.9784);
        final encoded = original.encode();
        final decoded = LocationPayload.decode(encoded);

        expect(decoded.latitude, closeTo(original.latitude, 0.0000001));
        expect(decoded.longitude, closeTo(original.longitude, 0.0000001));
      });

      test('decodes extended payload', () {
        final original = LocationPayload(
          latitude: 41.0082,
          longitude: 28.9784,
          altitude: 150,
          accuracy: 10,
        );
        final encoded = original.encode();
        final decoded = LocationPayload.decode(encoded, extended: true);

        expect(decoded.altitude, equals(original.altitude));
        expect(decoded.accuracy, equals(original.accuracy));
      });

      test('throws on insufficient data', () {
        expect(
          () => LocationPayload.decode(Uint8List(5)),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('roundtrip', () {
      test('encode then decode preserves compact', () {
        final testCases = [
          (0.0, 0.0),
          (41.0082, 28.9784),
          (-33.8688, 151.2093),
          (90.0, -180.0),
        ];

        for (final (lat, lon) in testCases) {
          final original = LocationPayload(latitude: lat, longitude: lon);
          final encoded = original.encode();
          final decoded = LocationPayload.decode(encoded);

          expect(decoded.latitude, closeTo(lat, 0.0000001));
          expect(decoded.longitude, closeTo(lon, 0.0000001));
        }
      });

      test('encode then decode preserves extended', () {
        final original = LocationPayload(
          latitude: 41.0082,
          longitude: 28.9784,
          altitude: -100,
          accuracy: 5000,
        );
        final encoded = original.encode();
        final decoded = LocationPayload.decode(encoded, extended: true);

        expect(decoded.latitude, closeTo(original.latitude, 0.0000001));
        expect(decoded.longitude, closeTo(original.longitude, 0.0000001));
        expect(decoded.altitude, equals(original.altitude));
        expect(decoded.accuracy, equals(original.accuracy));
      });
    });

    group('properties', () {
      test('type is location', () {
        final payload = LocationPayload(latitude: 0.0, longitude: 0.0);
        expect(payload.type, equals(MessageType.location));
      });
    });
  });
}
