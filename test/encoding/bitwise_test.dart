import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/encoding/bitwise.dart';

void main() {
  group('Bitwise - Single Bit Operations', () {
    test('setBit sets bit at position', () {
      expect(Bitwise.setBit(0x00, 0), equals(0x01));
      expect(Bitwise.setBit(0x00, 7), equals(0x80));
      expect(Bitwise.setBit(0x01, 7), equals(0x81));
    });

    test('clearBit clears bit at position', () {
      expect(Bitwise.clearBit(0xFF, 0), equals(0xFE));
      expect(Bitwise.clearBit(0xFF, 7), equals(0x7F));
      expect(Bitwise.clearBit(0x80, 7), equals(0x00));
    });

    test('toggleBit toggles bit at position', () {
      expect(Bitwise.toggleBit(0x00, 0), equals(0x01));
      expect(Bitwise.toggleBit(0x01, 0), equals(0x00));
      expect(Bitwise.toggleBit(0x80, 7), equals(0x00));
    });

    test('getBit returns correct bit value', () {
      expect(Bitwise.getBit(0x01, 0), isTrue);
      expect(Bitwise.getBit(0x01, 1), isFalse);
      expect(Bitwise.getBit(0x80, 7), isTrue);
      expect(Bitwise.getBit(0x80, 6), isFalse);
    });

    test('writeBit sets or clears bit', () {
      expect(Bitwise.writeBit(0x00, 0, true), equals(0x01));
      expect(Bitwise.writeBit(0xFF, 0, false), equals(0xFE));
    });
  });

  group('Bitwise - Bit Range Operations', () {
    test('extractBits extracts correct range', () {
      // 0b11010110, extract bits 2-5 (4 bits starting at bit 2)
      expect(Bitwise.extractBits(0xD6, 2, 4), equals(0x05)); // 0b0101

      // Extract lower nibble
      expect(Bitwise.extractBits(0xAB, 0, 4), equals(0x0B));

      // Extract upper nibble
      expect(Bitwise.extractBits(0xAB, 4, 4), equals(0x0A));
    });

    test('insertBits inserts at correct position', () {
      // Insert 0b1010 at bits 2-5 into 0b11110000
      expect(Bitwise.insertBits(0xF0, 0x0A, 2, 4), equals(0xE8)); // 0b11101000
    });

    test('mask creates correct bitmask', () {
      expect(Bitwise.mask(1), equals(0x01));
      expect(Bitwise.mask(4), equals(0x0F));
      expect(Bitwise.mask(8), equals(0xFF));
      expect(Bitwise.mask(16), equals(0xFFFF));
    });
  });

  group('Bitwise - Multi-field Packing', () {
    test('pack combines values LSB first', () {
      // Pack [3, 5, 1, 1] with widths [3, 3, 1, 1]
      // Result: 1_1_101_011 = 0b11101011 = 0xEB
      final packed = Bitwise.pack([3, 5, 1, 1], [3, 3, 1, 1]);
      expect(packed, equals(0xEB));
    });

    test('unpack extracts values LSB first', () {
      final values = Bitwise.unpack(0xEB, [3, 3, 1, 1]);
      expect(values, equals([3, 5, 1, 1]));
    });

    test('packMsbFirst combines values MSB first', () {
      // Pack [3, 5] with widths [3, 3] -> 011_101 = 0b00011101 = 0x1D
      final packed = Bitwise.packMsbFirst([3, 5], [3, 3]);
      expect(packed, equals(0x1D));
    });

    test('unpackMsbFirst extracts values MSB first', () {
      final values = Bitwise.unpackMsbFirst(0x1D, [3, 3]);
      expect(values, equals([3, 5]));
    });

    test('pack and unpack are inverse operations', () {
      final original = [7, 31, 3, 1];
      final widths = [3, 5, 2, 1];

      final packed = Bitwise.pack(original, widths);
      final unpacked = Bitwise.unpack(packed, widths);

      expect(unpacked, equals(original));
    });
  });

  group('Bitwise - Byte Operations', () {
    test('highNibble extracts upper 4 bits', () {
      expect(Bitwise.highNibble(0xAB), equals(0x0A));
      expect(Bitwise.highNibble(0xF0), equals(0x0F));
    });

    test('lowNibble extracts lower 4 bits', () {
      expect(Bitwise.lowNibble(0xAB), equals(0x0B));
      expect(Bitwise.lowNibble(0x0F), equals(0x0F));
    });

    test('combineNibbles creates byte', () {
      expect(Bitwise.combineNibbles(0x0A, 0x0B), equals(0xAB));
      expect(Bitwise.combineNibbles(0xFF, 0xFF), equals(0xFF)); // Masked
    });

    test('highByte16 and lowByte16 extract bytes', () {
      expect(Bitwise.highByte16(0xABCD), equals(0xAB));
      expect(Bitwise.lowByte16(0xABCD), equals(0xCD));
    });

    test('combine16BE creates 16-bit value', () {
      expect(Bitwise.combine16BE(0xAB, 0xCD), equals(0xABCD));
    });

    test('combine32BE creates 32-bit value', () {
      expect(Bitwise.combine32BE(0x12, 0x34, 0x56, 0x78), equals(0x12345678));
    });
  });

  group('Bitwise - Bit Counting', () {
    test('popCount returns number of set bits', () {
      expect(Bitwise.popCount(0), equals(0));
      expect(Bitwise.popCount(1), equals(1));
      expect(Bitwise.popCount(0xFF), equals(8));
      expect(Bitwise.popCount(0x55), equals(4)); // 0b01010101
    });

    test('highestBit returns position of highest set bit', () {
      expect(Bitwise.highestBit(0), equals(-1));
      expect(Bitwise.highestBit(1), equals(0));
      expect(Bitwise.highestBit(0x80), equals(7));
      expect(Bitwise.highestBit(0xFF), equals(7));
    });

    test('lowestBit returns position of lowest set bit', () {
      expect(Bitwise.lowestBit(0), equals(-1));
      expect(Bitwise.lowestBit(1), equals(0));
      expect(Bitwise.lowestBit(0x80), equals(7));
      expect(Bitwise.lowestBit(0x10), equals(4));
    });
  });

  group('Bitwise - Byte Array Operations', () {
    test('read16BE reads big-endian 16-bit', () {
      final bytes = Uint8List.fromList([0xAB, 0xCD]);
      expect(Bitwise.read16BE(bytes, 0), equals(0xABCD));
    });

    test('read16LE reads little-endian 16-bit', () {
      final bytes = Uint8List.fromList([0xCD, 0xAB]);
      expect(Bitwise.read16LE(bytes, 0), equals(0xABCD));
    });

    test('read32BE reads big-endian 32-bit', () {
      final bytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
      expect(Bitwise.read32BE(bytes, 0), equals(0x12345678));
    });

    test('read32LE reads little-endian 32-bit', () {
      final bytes = Uint8List.fromList([0x78, 0x56, 0x34, 0x12]);
      expect(Bitwise.read32LE(bytes, 0), equals(0x12345678));
    });

    test('write16BE writes big-endian 16-bit', () {
      final bytes = Uint8List(2);
      Bitwise.write16BE(bytes, 0, 0xABCD);
      expect(bytes, equals([0xAB, 0xCD]));
    });

    test('write16LE writes little-endian 16-bit', () {
      final bytes = Uint8List(2);
      Bitwise.write16LE(bytes, 0, 0xABCD);
      expect(bytes, equals([0xCD, 0xAB]));
    });

    test('write32BE writes big-endian 32-bit', () {
      final bytes = Uint8List(4);
      Bitwise.write32BE(bytes, 0, 0x12345678);
      expect(bytes, equals([0x12, 0x34, 0x56, 0x78]));
    });

    test('write32LE writes little-endian 32-bit', () {
      final bytes = Uint8List(4);
      Bitwise.write32LE(bytes, 0, 0x12345678);
      expect(bytes, equals([0x78, 0x56, 0x34, 0x12]));
    });

    test('read and write are inverse operations', () {
      final original16 = 0xABCD;
      final original32 = 0x12345678;

      final buf16 = Uint8List(2);
      Bitwise.write16BE(buf16, 0, original16);
      expect(Bitwise.read16BE(buf16, 0), equals(original16));

      final buf32 = Uint8List(4);
      Bitwise.write32BE(buf32, 0, original32);
      expect(Bitwise.read32BE(buf32, 0), equals(original32));
    });
  });

  group('PacketFlags', () {
    test('default constructor creates empty flags', () {
      final flags = PacketFlags();
      expect(flags.mesh, isFalse);
      expect(flags.ackRequired, isFalse);
      expect(flags.encrypted, isFalse);
      expect(flags.compressed, isFalse);
      expect(flags.urgent, isFalse);
      expect(flags.isFragment, isFalse);
      expect(flags.moreFragments, isFalse);
    });

    test('toCompactBytes encodes for compact mode', () {
      final flags = PacketFlags(
        mesh: true,
        ackRequired: true,
        encrypted: true,
        compressed: true,
        urgent: true,
      );

      final (byte0, byte1) = flags.toCompactBytes();

      // Byte 0: bits 2-0 = [MESH, ACK, ENC] = 0b111 = 0x07
      expect(byte0, equals(0x07));

      // Byte 1: bits 7-6 = [COMP, URG] = 0b11000000 = 0xC0
      expect(byte1, equals(0xC0));
    });

    test('fromCompactBytes decodes compact mode', () {
      final flags = PacketFlags.fromCompactBytes(0x07, 0xC0);

      expect(flags.mesh, isTrue);
      expect(flags.ackRequired, isTrue);
      expect(flags.encrypted, isTrue);
      expect(flags.compressed, isTrue);
      expect(flags.urgent, isTrue);
      expect(flags.isFragment, isFalse); // Not supported in compact
    });

    test('toStandardByte encodes for standard mode', () {
      final flags = PacketFlags(
        mesh: true, // bit 7
        ackRequired: true, // bit 6
        encrypted: true, // bit 5
        compressed: true, // bit 4
        urgent: true, // bit 3
        isFragment: true, // bit 2
        moreFragments: true, // bit 1
      );

      final byte = flags.toStandardByte();
      // 0b11111110 = 0xFE
      expect(byte, equals(0xFE));
    });

    test('fromStandardByte decodes standard mode', () {
      final flags = PacketFlags.fromStandardByte(0xFE);

      expect(flags.mesh, isTrue);
      expect(flags.ackRequired, isTrue);
      expect(flags.encrypted, isTrue);
      expect(flags.compressed, isTrue);
      expect(flags.urgent, isTrue);
      expect(flags.isFragment, isTrue);
      expect(flags.moreFragments, isTrue);
    });

    test('compact encode/decode roundtrip', () {
      final original = PacketFlags(mesh: true, encrypted: true, urgent: true);

      final (byte0, byte1) = original.toCompactBytes();
      final decoded = PacketFlags.fromCompactBytes(byte0, byte1);

      expect(decoded.mesh, equals(original.mesh));
      expect(decoded.encrypted, equals(original.encrypted));
      expect(decoded.urgent, equals(original.urgent));
    });

    test('standard encode/decode roundtrip', () {
      final original = PacketFlags(
        mesh: true,
        isFragment: true,
        moreFragments: true,
      );

      final byte = original.toStandardByte();
      final decoded = PacketFlags.fromStandardByte(byte);

      expect(decoded, equals(original));
    });

    test('copyWith creates modified copy', () {
      final original = PacketFlags(mesh: true);
      final modified = original.copyWith(encrypted: true);

      expect(original.mesh, isTrue);
      expect(original.encrypted, isFalse);
      expect(modified.mesh, isTrue);
      expect(modified.encrypted, isTrue);
    });

    test('equality works correctly', () {
      final flags1 = PacketFlags(mesh: true, urgent: true);
      final flags2 = PacketFlags(mesh: true, urgent: true);
      final flags3 = PacketFlags(mesh: true);

      expect(flags1, equals(flags2));
      expect(flags1, isNot(equals(flags3)));
    });

    test('toString shows active flags', () {
      final flags = PacketFlags(mesh: true, urgent: true);
      final str = flags.toString();

      expect(str, contains('MESH'));
      expect(str, contains('URG'));
      expect(str, isNot(contains('ENC')));
    });
  });
}
