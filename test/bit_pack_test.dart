// Test entry point for BitPack library
// Individual test files are in test/encoding/ and test/protocol/

import 'package:test/test.dart';

import 'encoding/crc8_test.dart' as crc8_test;
import 'encoding/bitwise_test.dart' as bitwise_test;
import 'protocol/compact_header_test.dart' as compact_header_test;
import 'protocol/standard_header_test.dart' as standard_header_test;
import 'protocol/header_factory_test.dart' as header_factory_test;

void main() {
  group('Encoding', () {
    crc8_test.main();
    bitwise_test.main();
  });

  group('Protocol', () {
    compact_header_test.main();
    standard_header_test.main();
    header_factory_test.main();
  });
}
