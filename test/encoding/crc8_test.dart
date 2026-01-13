import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bit_pack/src/encoding/crc8.dart';

void main() {
  group('CRC-8-CCITT', () {
    test('lookup table has 256 entries', () {
      expect(Crc8.table.length, equals(256));
    });

    test('compute returns 0 for empty data', () {
      final result = Crc8.compute(Uint8List(0));
      expect(result, equals(0));
    });

    test('compute returns correct CRC for known data', () {
      // Test vector: "123456789" -> CRC-8-CCITT = 0xF4
      final data = Uint8List.fromList([
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0x37,
        0x38,
        0x39,
      ]);
      final crc = Crc8.compute(data);
      expect(crc, equals(0xF4));
    });

    test('compute returns consistent results', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final crc1 = Crc8.compute(data);
      final crc2 = Crc8.compute(data);
      expect(crc1, equals(crc2));
    });

    test('computeRange calculates CRC for partial data', () {
      final data = Uint8List.fromList([0xAA, 0x01, 0x02, 0x03, 0xBB]);
      final fullCrc = Crc8.compute(Uint8List.fromList([0x01, 0x02, 0x03]));
      final rangeCrc = Crc8.computeRange(data, 1, 3);
      expect(rangeCrc, equals(fullCrc));
    });

    test('update continues CRC calculation', () {
      final data1 = Uint8List.fromList([0x01, 0x02]);
      final data2 = Uint8List.fromList([0x03, 0x04]);
      final combined = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

      final combinedCrc = Crc8.compute(combined);
      var incrementalCrc = Crc8.compute(data1);
      incrementalCrc = Crc8.update(incrementalCrc, data2);

      expect(incrementalCrc, equals(combinedCrc));
    });

    test('updateByte updates CRC with single byte', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final fullCrc = Crc8.compute(data);

      var crc = 0;
      crc = Crc8.updateByte(crc, 0x01);
      crc = Crc8.updateByte(crc, 0x02);
      crc = Crc8.updateByte(crc, 0x03);

      expect(crc, equals(fullCrc));
    });

    test('appendCrc adds CRC byte to data', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final withCrc = Crc8.appendCrc(data);

      expect(withCrc.length, equals(data.length + 1));
      expect(withCrc.sublist(0, 3), equals(data));

      final expectedCrc = Crc8.compute(data);
      expect(withCrc[3], equals(expectedCrc));
    });

    test('appendCrcInPlace writes CRC to buffer', () {
      final buffer = Uint8List(5);
      buffer[0] = 0x01;
      buffer[1] = 0x02;
      buffer[2] = 0x03;
      buffer[3] = 0x04;
      // buffer[4] will be CRC

      Crc8.appendCrcInPlace(buffer, 4);

      final expectedCrc = Crc8.compute(
        Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
      );
      expect(buffer[4], equals(expectedCrc));
    });

    test('verify returns true for valid CRC', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final withCrc = Crc8.appendCrc(data);

      expect(Crc8.verify(withCrc), isTrue);
    });

    test('verify returns false for invalid CRC', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final withCrc = Crc8.appendCrc(data);
      withCrc[3] = (withCrc[3] + 1) & 0xFF; // Corrupt CRC

      expect(Crc8.verify(withCrc), isFalse);
    });

    test('verify returns false for empty data', () {
      expect(Crc8.verify(Uint8List(0)), isFalse);
    });

    test('verifyOrThrow throws on invalid CRC', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final withCrc = Crc8.appendCrc(data);
      withCrc[3] = (withCrc[3] + 1) & 0xFF; // Corrupt CRC

      expect(() => Crc8.verifyOrThrow(withCrc), throwsA(isA<Exception>()));
    });

    test('stripCrc removes and verifies CRC', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final withCrc = Crc8.appendCrc(data);
      final stripped = Crc8.stripCrc(withCrc);

      expect(stripped, equals(data));
    });

    test('stripCrc throws on invalid CRC when verify=true', () {
      final corrupted = Uint8List.fromList([0x01, 0x02, 0x03, 0xFF]);
      expect(() => Crc8.stripCrc(corrupted), throwsA(isA<Exception>()));
    });

    test('stripCrc does not throw when verify=false', () {
      final corrupted = Uint8List.fromList([0x01, 0x02, 0x03, 0xFF]);
      final stripped = Crc8.stripCrc(corrupted, verify: false);
      expect(stripped, equals(Uint8List.fromList([0x01, 0x02, 0x03])));
    });

    test('19-byte SOS packet CRC calculation', () {
      // Simulate a 19-byte SOS packet (4 header + 15 payload)
      final packet = Uint8List(19);
      for (int i = 0; i < 19; i++) {
        packet[i] = i;
      }

      final crc = Crc8.compute(packet);
      expect(crc, inInclusiveRange(0, 255));

      // Append and verify
      final withCrc = Crc8.appendCrc(packet);
      expect(withCrc.length, equals(20)); // BLE 4.2 MTU exactly
      expect(Crc8.verify(withCrc), isTrue);
    });
  });
}
