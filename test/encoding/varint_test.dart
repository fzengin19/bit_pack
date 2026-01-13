import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/encoding/varint.dart';

void main() {
  group('VarInt', () {
    group('encodedLength', () {
      test('1 byte for values 0-127', () {
        expect(VarInt.encodedLength(0), equals(1));
        expect(VarInt.encodedLength(127), equals(1));
      });

      test('2 bytes for values 128-16383', () {
        expect(VarInt.encodedLength(128), equals(2));
        expect(VarInt.encodedLength(16383), equals(2));
      });

      test('3 bytes for values 16384-2097151', () {
        expect(VarInt.encodedLength(16384), equals(3));
        expect(VarInt.encodedLength(2097151), equals(3));
      });

      test('4 bytes for values 2097152-268435455', () {
        expect(VarInt.encodedLength(2097152), equals(4));
        expect(VarInt.encodedLength(268435455), equals(4));
      });

      test('5 bytes for larger values', () {
        expect(VarInt.encodedLength(268435456), equals(5));
      });

      test('throws on negative values', () {
        expect(() => VarInt.encodedLength(-1), throwsA(isA<ArgumentError>()));
      });
    });

    group('encode', () {
      test('encodes 0 to single byte', () {
        final encoded = VarInt.encode(0);
        expect(encoded, equals([0x00]));
      });

      test('encodes 127 to single byte', () {
        final encoded = VarInt.encode(127);
        expect(encoded, equals([0x7F]));
      });

      test('encodes 128 to two bytes', () {
        final encoded = VarInt.encode(128);
        expect(encoded.length, equals(2));
        expect(encoded[0] & 0x80, isNot(0)); // Continuation bit set
      });

      test('encodes 300 correctly', () {
        // 300 = 0x12C = 0b100101100
        // Split into 7-bit groups: 0000010 0101100
        // With continuation: 10101100 00000010 = [0xAC, 0x02]
        final encoded = VarInt.encode(300);
        expect(encoded, equals([0xAC, 0x02]));
      });

      test('encodes 16383 to two bytes', () {
        final encoded = VarInt.encode(16383);
        expect(encoded.length, equals(2));
        expect(encoded, equals([0xFF, 0x7F]));
      });

      test('throws on negative values', () {
        expect(() => VarInt.encode(-1), throwsA(isA<ArgumentError>()));
      });
    });

    group('decode', () {
      test('decodes single byte', () {
        final (value, bytesRead) = VarInt.decode(Uint8List.fromList([0x00]));
        expect(value, equals(0));
        expect(bytesRead, equals(1));
      });

      test('decodes 127', () {
        final (value, bytesRead) = VarInt.decode(Uint8List.fromList([0x7F]));
        expect(value, equals(127));
        expect(bytesRead, equals(1));
      });

      test('decodes 300', () {
        final (value, bytesRead) = VarInt.decode(
          Uint8List.fromList([0xAC, 0x02]),
        );
        expect(value, equals(300));
        expect(bytesRead, equals(2));
      });

      test('decodes from offset', () {
        final data = Uint8List.fromList([0xFF, 0xAC, 0x02, 0xFF]);
        final (value, bytesRead) = VarInt.decode(data, 1);
        expect(value, equals(300));
        expect(bytesRead, equals(2));
      });

      test('throws on truncated data', () {
        final data = Uint8List.fromList([
          0x80,
        ]); // Continuation set but no next byte
        expect(() => VarInt.decode(data), throwsA(isA<Exception>()));
      });

      test('throws on empty data', () {
        expect(() => VarInt.decode(Uint8List(0)), throwsA(isA<Exception>()));
      });
    });

    group('write', () {
      test('writes to buffer at offset', () {
        final buffer = Uint8List(10);
        final bytesWritten = VarInt.write(buffer, 2, 300);

        expect(bytesWritten, equals(2));
        expect(buffer[2], equals(0xAC));
        expect(buffer[3], equals(0x02));
      });
    });

    group('read', () {
      test('reads from ByteData', () {
        final bytes = Uint8List.fromList([0xAC, 0x02]);
        final data = ByteData.view(bytes.buffer);

        final (value, bytesRead) = VarInt.read(data, 0);
        expect(value, equals(300));
        expect(bytesRead, equals(2));
      });
    });

    group('roundtrip', () {
      test('encode then decode preserves value', () {
        final testValues = [
          0,
          1,
          127,
          128,
          255,
          300,
          16383,
          16384,
          100000,
          268435455,
        ];

        for (final original in testValues) {
          final encoded = VarInt.encode(original);
          final (decoded, _) = VarInt.decode(encoded);
          expect(
            decoded,
            equals(original),
            reason: 'Failed for value $original',
          );
        }
      });
    });

    group('ZigZag encoding', () {
      test('zigZagEncode maps correctly', () {
        expect(VarInt.zigZagEncode(0), equals(0));
        expect(VarInt.zigZagEncode(-1), equals(1));
        expect(VarInt.zigZagEncode(1), equals(2));
        expect(VarInt.zigZagEncode(-2), equals(3));
        expect(VarInt.zigZagEncode(2), equals(4));
      });

      test('zigZagDecode reverses encoding', () {
        expect(VarInt.zigZagDecode(0), equals(0));
        expect(VarInt.zigZagDecode(1), equals(-1));
        expect(VarInt.zigZagDecode(2), equals(1));
        expect(VarInt.zigZagDecode(3), equals(-2));
        expect(VarInt.zigZagDecode(4), equals(2));
      });

      test('encodeSigned and decodeSigned roundtrip', () {
        final testValues = [0, 1, -1, 127, -128, 1000, -1000];

        for (final original in testValues) {
          final encoded = VarInt.encodeSigned(original);
          final (decoded, _) = VarInt.decodeSigned(encoded);
          expect(
            decoded,
            equals(original),
            reason: 'Failed for value $original',
          );
        }
      });

      test('small negative numbers use fewer bytes', () {
        // -1 encoded with ZigZag = 1, which is 1 byte
        final encoded = VarInt.encodeSigned(-1);
        expect(encoded.length, equals(1));

        // -64 encoded with ZigZag = 127, still 1 byte
        final encoded64 = VarInt.encodeSigned(-64);
        expect(encoded64.length, equals(1));
      });
    });
  });
}
