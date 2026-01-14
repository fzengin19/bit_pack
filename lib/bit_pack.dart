/// BitPack - Binary Protocol for P2P Mesh Networking
///
/// A byte-optimized binary protocol library for offline emergency
/// communication over BLE 4.2/5.0 mesh networks.
///
/// ## Features
/// - Dual-mode headers (Compact for BLE 4.2, Standard for BLE 5.0+)
/// - Ultra-compact SOS payload (19 bytes total with header)
/// - Relative time-based TTL (no clock sync required)
/// - CRC-8 checksum for packet integrity
/// - VarInt and BCD encoding for space efficiency
/// - AES-GCM encryption with PBKDF2 key derivation
/// - Mesh relay with duplicate detection and backoff
///
/// ## Example
/// ```dart
/// import 'package:bit_pack/bit_pack.dart';
///
/// // Create an SOS packet
/// final packet = Packet.sos(
///   sosType: SosType.needRescue,
///   latitude: 41.0082,
///   longitude: 28.9784,
///   phoneNumber: '+905331234567',
/// );
///
/// final encoded = packet.encode(includeCrc: true);
/// print('Packet: ${encoded.length} bytes'); // 20 bytes
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

// Protocol - Payloads
export 'src/protocol/payload/payload.dart';
export 'src/protocol/payload/sos_payload.dart';
export 'src/protocol/payload/location_payload.dart';
export 'src/protocol/payload/text_payload.dart';
export 'src/protocol/payload/ack_payload.dart';
export 'src/protocol/payload/nack_payload.dart';

// Protocol - Packet
export 'src/protocol/packet.dart';

// Crypto
export 'src/crypto/key_derivation.dart';
export 'src/crypto/aes_gcm.dart';
export 'src/crypto/challenge.dart';

// Fragmentation
export 'src/fragmentation/fragment_header.dart';
export 'src/fragmentation/fragmenter.dart';
export 'src/fragmentation/reassembler.dart';
export 'src/fragmentation/selective_repeat.dart';
