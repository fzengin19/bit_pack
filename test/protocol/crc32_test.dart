import 'dart:convert';
import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('CRC-32/IEEE', () {
    test('"123456789" test vector', () {
      final bytes = Uint8List.fromList(utf8.encode('123456789'));
      final crc = Crc32.compute(bytes);
      expect(crc, equals(0xCBF43926));
    });
  });
}

