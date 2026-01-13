/// BitPack - Binary Protocol for P2P Mesh Networking
///
/// A byte-optimized binary protocol library for offline emergency
/// communication over BLE 4.2/5.0 mesh networks.
///
/// ## Features
/// - Dual-mode headers (Compact for BLE 4.2, Standard for BLE 5.0+)
/// - Ultra-compact SOS payload (19 bytes total with header)
/// - Relative time-based TTL (no clock sync required)
/// - CRC-8 checksum for integrity verification
/// - VarInt and BCD encoding for space efficiency
/// - AES-GCM encryption with PBKDF2 key derivation
/// - Mesh relay with duplicate detection and backoff
///
/// ## Example
/// ```dart
/// import 'package:bit_pack/bit_pack.dart';
///
/// // Create an SOS packet
/// final header = CompactHeader(
///   type: MessageType.sosBeacon,
///   flags: PacketFlags(mesh: true, urgent: true),
///   messageId: 0x1234,
/// );
///
/// final encoded = header.encode();
/// print('Header: ${encoded.length} bytes'); // 4 bytes
/// ```

library bit_pack;

// Core
export 'src/core/constants.dart';
export 'src/core/types.dart';
export 'src/core/exceptions.dart';

// Encoding
export 'src/encoding/bitwise.dart';
export 'src/encoding/crc8.dart';
export 'src/encoding/varint.dart';
export 'src/encoding/bcd.dart';
export 'src/encoding/gps.dart';
export 'src/encoding/international_bcd.dart';

// Protocol - Headers
export 'src/protocol/header/compact_header.dart';
export 'src/protocol/header/standard_header.dart';
export 'src/protocol/header/header_factory.dart';
