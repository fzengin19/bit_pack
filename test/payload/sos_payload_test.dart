import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/payload/sos_payload.dart';
import 'package:bit_pack/src/core/types.dart';

void main() {
  group('SosPayload', () {
    group('construction', () {
      test('creates with required parameters', () {
        final payload = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );

        expect(payload.sosType, equals(SosType.needRescue));
        expect(payload.latitude, closeTo(41.0082, 0.0000001));
        expect(payload.longitude, closeTo(28.9784, 0.0000001));
        expect(payload.peopleCount, equals(1));
        expect(payload.hasInjured, isFalse);
        expect(payload.isTrapped, isFalse);
      });

      test('creates with all parameters', () {
        final payload = SosPayload(
          sosType: SosType.injured,
          latitude: 41.0082,
          longitude: 28.9784,
          peopleCount: 5,
          hasInjured: true,
          isTrapped: true,
          phoneNumber: '+905331234567',
          altitude: 150,
          batteryPercent: 75,
        );

        expect(payload.peopleCount, equals(5));
        expect(payload.hasInjured, isTrue);
        expect(payload.isTrapped, isTrue);
        expect(payload.phoneNumber, equals('+905331234567'));
        expect(payload.altitude, equals(150));
        expect(payload.batteryPercent, equals(75));
      });

      test('throws on invalid people count', () {
        expect(
          () => SosPayload(
            sosType: SosType.needRescue,
            latitude: 41.0,
            longitude: 29.0,
            peopleCount: 8, // Max is 7
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on invalid coordinates', () {
        expect(
          () => SosPayload(
            sosType: SosType.needRescue,
            latitude: 91.0, // Invalid
            longitude: 29.0,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on invalid altitude', () {
        expect(
          () => SosPayload(
            sosType: SosType.needRescue,
            latitude: 41.0,
            longitude: 29.0,
            altitude: 5000, // Max is 4095
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('encode', () {
      test('encodes to 15 bytes', () {
        final payload = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );

        final encoded = payload.encode();
        expect(encoded.length, equals(15));
      });

      test('encodes SOS type correctly', () {
        final payload = SosPayload(
          sosType: SosType.trapped, // code = 2
          latitude: 41.0082,
          longitude: 28.9784,
        );

        final encoded = payload.encode();
        // Bits 7-5 should be 010 (2)
        expect((encoded[0] >> 5) & 0x07, equals(2));
      });

      test('encodes people count correctly', () {
        final payload = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
          peopleCount: 5,
        );

        final encoded = payload.encode();
        // Bits 4-2 should be 101 (5)
        expect((encoded[0] >> 2) & 0x07, equals(5));
      });

      test('encodes flags correctly', () {
        final payload = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
          hasInjured: true,
          isTrapped: true,
        );

        final encoded = payload.encode();
        expect(encoded[0] & 0x02, isNot(0)); // hasInjured
        expect(encoded[0] & 0x01, isNot(0)); // isTrapped
      });
    });

    group('decode', () {
      test('decodes 15 bytes correctly', () {
        final original = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
          peopleCount: 3,
          hasInjured: true,
          isTrapped: false,
          phoneNumber: '31234567',
          altitude: 150,
          batteryPercent: 75,
        );

        final encoded = original.encode();
        final decoded = SosPayload.decode(encoded);

        expect(decoded.sosType, equals(original.sosType));
        expect(decoded.latitude, closeTo(original.latitude, 0.0000001));
        expect(decoded.longitude, closeTo(original.longitude, 0.0000001));
        expect(decoded.peopleCount, equals(original.peopleCount));
        expect(decoded.hasInjured, equals(original.hasInjured));
        expect(decoded.isTrapped, equals(original.isTrapped));
      });

      test('throws on insufficient data', () {
        expect(
          () => SosPayload.decode(Uint8List(10)),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('roundtrip', () {
      test('encode then decode preserves all fields', () {
        final testCases = [
          SosPayload(
            sosType: SosType.needRescue,
            latitude: 0.0,
            longitude: 0.0,
          ),
          SosPayload(
            sosType: SosType.safe,
            latitude: 41.0082,
            longitude: 28.9784,
            peopleCount: 7,
            hasInjured: true,
            isTrapped: true,
            phoneNumber: '12345678',
            altitude: 4000,
            batteryPercent: 100,
          ),
          SosPayload(
            sosType: SosType.canHelp,
            latitude: -33.8688,
            longitude: 151.2093,
          ),
        ];

        for (final original in testCases) {
          final encoded = original.encode();
          final decoded = SosPayload.decode(encoded);

          expect(decoded.sosType, equals(original.sosType));
          expect(decoded.latitude, closeTo(original.latitude, 0.0000001));
          expect(decoded.longitude, closeTo(original.longitude, 0.0000001));
          expect(decoded.peopleCount, equals(original.peopleCount));
          expect(decoded.hasInjured, equals(original.hasInjured));
          expect(decoded.isTrapped, equals(original.isTrapped));
        }
      });
    });

    group('properties', () {
      test('sizeInBytes is always 15', () {
        final payload = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );
        expect(payload.sizeInBytes, equals(15));
      });

      test('fitsCompactMode is true', () {
        final payload = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );
        expect(payload.fitsCompactMode, isTrue);
      });

      test('type is sosBeacon', () {
        final payload = SosPayload(
          sosType: SosType.needRescue,
          latitude: 41.0082,
          longitude: 28.9784,
        );
        expect(payload.type, equals(MessageType.sosBeacon));
      });
    });
  });
}
