import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/protocol/header/standard_header.dart';
import 'package:bit_pack/src/core/types.dart';
import 'package:bit_pack/src/core/exceptions.dart';
import 'package:bit_pack/src/core/constants.dart';
import 'package:bit_pack/src/encoding/bitwise.dart';

void main() {
  group('StandardHeader', () {
    group('Construction', () {
      test('creates header with required fields', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
        );

        expect(header.mode, equals(PacketMode.standard));
        expect(header.type, equals(MessageType.dataEncrypted));
        expect(header.hopTtl, equals(15)); // Default
        expect(header.messageId, equals(0x12345678));
        expect(header.securityMode, equals(SecurityMode.none));
        expect(header.payloadLength, equals(0));
        expect(header.ageMinutes, equals(0));
      });

      test('creates header with all fields', () {
        final header = StandardHeader(
          version: 1,
          type: MessageType.handshakeInit,
          flags: PacketFlags(mesh: true, encrypted: true),
          hopTtl: 100,
          messageId: 0xDEADBEEF,
          securityMode: SecurityMode.symmetric,
          payloadLength: 1024,
          ageMinutes: 60,
        );

        expect(header.version, equals(1));
        expect(header.hopTtl, equals(100));
        expect(header.securityMode, equals(SecurityMode.symmetric));
        expect(header.payloadLength, equals(1024));
        expect(header.ageMinutes, equals(60));
      });

      test('throws on version out of range', () {
        expect(
          () => StandardHeader(
            type: MessageType.dataEncrypted,
            flags: PacketFlags(),
            version: 2, // Max is 1
            messageId: 0x12345678,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on hopTtl out of range', () {
        expect(
          () => StandardHeader(
            type: MessageType.dataEncrypted,
            flags: PacketFlags(),
            hopTtl: 256, // Max is 255
            messageId: 0x12345678,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on payloadLength out of range', () {
        expect(
          () => StandardHeader(
            type: MessageType.dataEncrypted,
            flags: PacketFlags(),
            messageId: 0x12345678,
            payloadLength: 8192, // Max is 8191
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on ageMinutes out of range', () {
        expect(
          () => StandardHeader(
            type: MessageType.dataEncrypted,
            flags: PacketFlags(),
            messageId: 0x12345678,
            ageMinutes: 65536, // Max is 65535
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Encoding', () {
      test('encodes to exactly 11 bytes', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
        );

        final encoded = header.encode();
        expect(encoded.length, equals(11));
      });

      test('encodes mode bit as 1', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x00000000,
        );

        final encoded = header.encode();
        // Bit 7 of byte 0 should be 1
        expect(encoded[0] & 0x80, equals(0x80));
      });

      test('encodes version in bit 6', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          version: 1,
          messageId: 0x00000000,
        );

        final encoded = header.encode();
        expect((encoded[0] >> 6) & 0x01, equals(1));
      });

      test('encodes type in bits 5-0', () {
        final header = StandardHeader(
          type: MessageType.handshakeInit, // code = 0x10
          flags: PacketFlags(),
          messageId: 0x00000000,
        );

        final encoded = header.encode();
        expect(encoded[0] & 0x3F, equals(0x10));
      });

      test('encodes flags in byte 1', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(mesh: true, isFragment: true),
          messageId: 0x00000000,
        );

        final encoded = header.encode();
        // MESH = bit 7, FRAGMENT = bit 2
        expect(encoded[1] & 0x84, equals(0x84));
      });

      test('encodes hopTtl in byte 2', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          hopTtl: 200,
          messageId: 0x00000000,
        );

        final encoded = header.encode();
        expect(encoded[2], equals(200));
      });

      test('encodes messageId in bytes 3-6 big-endian', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0xDEADBEEF,
        );

        final encoded = header.encode();
        expect(encoded[3], equals(0xDE));
        expect(encoded[4], equals(0xAD));
        expect(encoded[5], equals(0xBE));
        expect(encoded[6], equals(0xEF));
      });

      test('encodes securityMode and payloadLength in bytes 7-8', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x00000000,
          securityMode: SecurityMode.asymmetric, // code = 2
          payloadLength: 0x1234, // 13 bits
        );

        final encoded = header.encode();
        // Byte 7: SEC_MODE(3) = 2 in bits 7-5, PAYLOAD_HIGH(5) = 0x12 in bits 4-0
        expect((encoded[7] >> 5) & 0x07, equals(2));
        expect(encoded[7] & 0x1F, equals(0x12));
        expect(encoded[8], equals(0x34));
      });

      test('encodes ageMinutes in bytes 9-10 big-endian', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x00000000,
          ageMinutes: 0xABCD,
        );

        final encoded = header.encode();
        expect(encoded[9], equals(0xAB));
        expect(encoded[10], equals(0xCD));
      });
    });

    group('Decoding', () {
      test('decodes valid header', () {
        final original = StandardHeader(
          version: 1,
          type: MessageType.textExtended,
          flags: PacketFlags(mesh: true, encrypted: true),
          hopTtl: 50,
          messageId: 0xCAFEBABE,
          securityMode: SecurityMode.symmetric,
          payloadLength: 500,
          ageMinutes: 120,
        );

        final encoded = original.encode();
        final decoded = StandardHeader.decode(encoded);

        expect(decoded.version, equals(original.version));
        expect(decoded.type, equals(original.type));
        expect(decoded.flags.mesh, equals(original.flags.mesh));
        expect(decoded.flags.encrypted, equals(original.flags.encrypted));
        expect(decoded.hopTtl, equals(original.hopTtl));
        expect(decoded.messageId, equals(original.messageId));
        expect(decoded.securityMode, equals(original.securityMode));
        expect(decoded.payloadLength, equals(original.payloadLength));
        expect(decoded.ageMinutes, equals(original.ageMinutes));
      });

      test('throws on insufficient bytes', () {
        final shortData = Uint8List(9);
        shortData[0] = 0x80; // Mode = 1

        expect(
          () => StandardHeader.decode(shortData),
          throwsA(isA<InsufficientHeaderException>()),
        );
      });

      test('throws on wrong mode bit', () {
        final data = Uint8List(11);
        data[0] = 0x00; // Mode = 0 (Compact)

        expect(
          () => StandardHeader.decode(data),
          throwsA(isA<InvalidModeException>()),
        );
      });

      test('sets receivedAt on decode', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
        );

        final encoded = header.encode();
        final decoded = StandardHeader.decode(encoded);

        expect(decoded.receivedAt, isNotNull);
      });
    });

    group('Roundtrip', () {
      test('encode then decode preserves all fields', () {
        final testCases = [
          StandardHeader(
            version: 0,
            type: MessageType.sosBeacon,
            flags: PacketFlags(mesh: true, urgent: true),
            hopTtl: 255,
            messageId: 0xFFFFFFFF,
            securityMode: SecurityMode.none,
            payloadLength: 8191,
            ageMinutes: 65535,
          ),
          StandardHeader(
            version: 1,
            type: MessageType.handshakeAck,
            flags: PacketFlags(isFragment: true, moreFragments: true),
            hopTtl: 0,
            messageId: 0x00000000,
            securityMode: SecurityMode.contactOnly,
            payloadLength: 0,
            ageMinutes: 0,
          ),
          StandardHeader(
            version: 0,
            type: MessageType.nack,
            flags: PacketFlags(compressed: true),
            hopTtl: 128,
            messageId: 0x5A5A5A5A,
            securityMode: SecurityMode.asymmetric,
            payloadLength: 4096,
            ageMinutes: 1440,
          ),
        ];

        for (final original in testCases) {
          final encoded = original.encode();
          final decoded = StandardHeader.decode(encoded);

          expect(decoded.version, equals(original.version));
          expect(decoded.type, equals(original.type));
          expect(decoded.hopTtl, equals(original.hopTtl));
          expect(decoded.messageId, equals(original.messageId));
          expect(decoded.securityMode, equals(original.securityMode));
          expect(decoded.payloadLength, equals(original.payloadLength));
          expect(decoded.ageMinutes, equals(original.ageMinutes));
        }
      });
    });

    group('Relative Age TTL', () {
      test('currentAgeMinutes returns ageMinutes when not received', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
          ageMinutes: 100,
        );

        expect(header.currentAgeMinutes, equals(100));
      });

      test('markReceived sets receivedAt', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
        );

        expect(header.receivedAt, isNull);
        header.markReceived();
        expect(header.receivedAt, isNotNull);
      });

      test('isExpired when hopTtl is 0', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          hopTtl: 0,
          messageId: 0x12345678,
        );

        expect(header.isExpired, isTrue);
      });

      test('isExpired when ageMinutes >= kMaxAgeMinutes', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
          ageMinutes: kMaxAgeMinutes, // 1440 (24 hours)
        );

        expect(header.isExpired, isTrue);
      });

      test('not expired when hopTtl > 0 and age < max', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          hopTtl: 10,
          messageId: 0x12345678,
          ageMinutes: 100,
        );

        expect(header.isExpired, isFalse);
      });

      test('prepareForRelay decrements hopTtl', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          hopTtl: 10,
          messageId: 0x12345678,
        );

        final relayed = header.prepareForRelay();
        expect(relayed.hopTtl, equals(9));
        expect(header.hopTtl, equals(10)); // Original unchanged
      });

      test('prepareForRelay does not go below 0', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          hopTtl: 0,
          messageId: 0x12345678,
        );

        final relayed = header.prepareForRelay();
        expect(relayed.hopTtl, equals(0));
      });

      test('remainingAge returns null when expired', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
          ageMinutes: kMaxAgeMinutes,
        );

        expect(header.remainingAge, isNull);
      });

      test('remainingAge returns correct duration', () {
        final header = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
          ageMinutes: 1000,
        );

        final remaining = header.remainingAge;
        expect(remaining, isNotNull);
        expect(remaining!.inMinutes, equals(kMaxAgeMinutes - 1000));
      });
    });

    group('Equality and Hashing', () {
      test('equal headers are equal', () {
        final header1 = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(mesh: true),
          hopTtl: 50,
          messageId: 0x12345678,
          securityMode: SecurityMode.symmetric,
          payloadLength: 100,
          ageMinutes: 30,
        );

        final header2 = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(mesh: true),
          hopTtl: 50,
          messageId: 0x12345678,
          securityMode: SecurityMode.symmetric,
          payloadLength: 100,
          ageMinutes: 30,
        );

        expect(header1, equals(header2));
        expect(header1.hashCode, equals(header2.hashCode));
      });

      test('different headers are not equal', () {
        final header1 = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x12345678,
        );

        final header2 = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          messageId: 0x87654321,
        );

        expect(header1, isNot(equals(header2)));
      });
    });

    group('copyWith', () {
      test('creates copy with modified fields', () {
        final original = StandardHeader(
          type: MessageType.dataEncrypted,
          flags: PacketFlags(),
          hopTtl: 50,
          messageId: 0x12345678,
          ageMinutes: 100,
        );

        final modified = original.copyWith(hopTtl: 25, ageMinutes: 200);

        expect(modified.hopTtl, equals(25));
        expect(modified.ageMinutes, equals(200));
        expect(modified.type, equals(original.type));
        expect(modified.messageId, equals(original.messageId));
        expect(original.hopTtl, equals(50)); // Original unchanged
      });
    });

    group('toString', () {
      test('includes all important fields', () {
        final header = StandardHeader(
          version: 1,
          type: MessageType.dataEncrypted,
          flags: PacketFlags(mesh: true),
          hopTtl: 50,
          messageId: 0xDEADBEEF,
          securityMode: SecurityMode.symmetric,
          payloadLength: 1024,
          ageMinutes: 60,
        );

        final str = header.toString();
        expect(str, contains('v1'));
        expect(str, contains('dataEncrypted'));
        expect(str, contains('50'));
        expect(str, contains('deadbeef'));
        expect(str, contains('symmetric'));
        expect(str, contains('1024'));
        expect(str, contains('60'));
      });
    });
  });
}
