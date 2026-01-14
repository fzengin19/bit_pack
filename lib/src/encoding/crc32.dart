/// CRC-32/IEEE (Ethernet) implementation
///
/// Parameters:
/// - Polynomial (reflected): 0xEDB88320
/// - Init: 0xFFFFFFFF
/// - XorOut: 0xFFFFFFFF
/// - Reflect In/Out: true
///
/// Test vector:
/// - "123456789" -> 0xCBF43926
library;

import 'dart:typed_data';

class Crc32 {
  Crc32._();

  static final Uint32List _table = _makeTable();

  static Uint32List _makeTable() {
    final table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }

  /// Compute CRC-32/IEEE over [data].
  static int compute(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

