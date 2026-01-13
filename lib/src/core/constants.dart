/// BitPack Protocol Constants
///
/// This file contains all magic numbers, limits, and protocol-specific
/// constants used throughout the BitPack mesh networking library.

library;

// ============================================================================
// PROTOCOL VERSION
// ============================================================================

/// Current protocol version (2 bits in header, max value 3)
const int kProtocolVersion = 0;

/// Protocol magic string for ZK verification challenge block
const String kChallengeMagic = 'BITPACK\x00';

// ============================================================================
// HEADER SIZES
// ============================================================================

/// Compact header size in bytes (BLE 4.2 compatible)
const int kCompactHeaderSize = 4;

/// Standard header size in bytes (BLE 5.0+)
const int kStandardHeaderSize = 11;

/// Fragment header extension size in bytes
const int kFragmentHeaderSize = 3;

// ============================================================================
// MTU LIMITS
// ============================================================================

/// BLE 4.2 maximum payload (23 MTU - 3 L2CAP/ATT overhead)
const int kBle42MaxPayload = 20;

/// BLE 5.0+ maximum payload with DLE
const int kBle50MaxPayload = 244;

/// WiFi Direct typical payload
const int kWifiDirectMaxPayload = 1350;

/// Default MTU for fragmentation calculations
const int kDefaultMtu = kBle50MaxPayload;

// ============================================================================
// TTL LIMITS
// ============================================================================

/// Maximum hop count for Compact Mode (4 bits)
const int kCompactMaxHops = 15;

/// Maximum hop count for Standard Mode (8 bits)
const int kStandardMaxHops = 255;

/// Default hop TTL for new messages
const int kDefaultHopTtl = 15;

/// Maximum age in minutes for Standard Mode (24 hours)
const int kMaxAgeMinutes = 1440;

/// Maximum age value that fits in 16 bits (~45 days)
const int kMaxAgeMinutesAbsolute = 65535;

// ============================================================================
// MESSAGE ID
// ============================================================================

/// Maximum 16-bit message ID (Compact Mode)
const int kMaxMessageId16 = 0xFFFF;

/// Maximum 32-bit message ID (Standard Mode)
const int kMaxMessageId32 = 0xFFFFFFFF;

// ============================================================================
// PAYLOAD LIMITS
// ============================================================================

/// Maximum payload length (13 bits in Standard header)
const int kMaxPayloadLength = 8191;

/// Compact SOS payload size (excluding header)
const int kCompactSosPayloadSize = 15;

/// Compact SOS with CRC total size
const int kCompactSosTotalSize = 20; // 4 header + 15 payload + 1 CRC

// ============================================================================
// FRAGMENTATION
// ============================================================================

/// Maximum fragment index (12 bits)
const int kMaxFragmentIndex = 4095;

/// Maximum total fragments (12 bits)
const int kMaxTotalFragments = 4096;

/// Maximum message size with fragmentation (~1MB)
const int kMaxFragmentedMessageSize = kMaxTotalFragments * kBle50MaxPayload;

// ============================================================================
// GPS ENCODING
// ============================================================================

/// Fixed-point precision for GPS coordinates (7 decimal places)
const int kGpsPrecision = 10000000;

/// Minimum latitude value
const double kMinLatitude = -90.0;

/// Maximum latitude value
const double kMaxLatitude = 90.0;

/// Minimum longitude value
const double kMinLongitude = -180.0;

/// Maximum longitude value
const double kMaxLongitude = 180.0;

// ============================================================================
// ALTITUDE & BATTERY (Compact SOS)
// ============================================================================

/// Maximum altitude in meters (12 bits)
const int kMaxAltitude = 4095;

/// Battery level precision (4 bits, 0-15 mapped to 0-100%)
const int kMaxBatteryLevel = 15;

// ============================================================================
// CRC-8
// ============================================================================

/// CRC-8-CCITT polynomial
const int kCrc8Polynomial = 0x07;

/// CRC-8 initial value
const int kCrc8InitialValue = 0x00;

// ============================================================================
// PBKDF2 KEY DERIVATION
// ============================================================================

/// Default PBKDF2 iteration count (balance security vs. mobile performance)
const int kPbkdf2DefaultIterations = 10000;

/// Minimum PBKDF2 iterations
const int kPbkdf2MinIterations = 5000;

/// Maximum PBKDF2 iterations
const int kPbkdf2MaxIterations = 100000;

/// AES-128 key length in bytes
const int kAes128KeyLength = 16;

/// AES-256 key length in bytes
const int kAes256KeyLength = 32;

/// AES-GCM nonce length in bytes
const int kAesGcmNonceLength = 12;

/// AES-GCM auth tag length in bytes
const int kAesGcmTagLength = 16;

/// Salt length for key derivation
const int kSaltLength = 16;

// ============================================================================
// MESSAGE CACHE
// ============================================================================

/// Default maximum entries in message cache
const int kDefaultMessageCacheSize = 10000;

/// Default message cache TTL (24 hours)
const Duration kDefaultMessageCacheTtl = Duration(hours: 24);

// ============================================================================
// BACKOFF ALGORITHM
// ============================================================================

/// Base delay for exponential backoff (milliseconds)
const int kBackoffBaseDelayMs = 50;

/// Maximum delay for exponential backoff (milliseconds)
const int kBackoffMaxDelayMs = 2000;

/// Jitter percentage for backoff randomization
const double kBackoffJitterPercent = 0.2;

/// Hop multiplier for exponential backoff
const double kBackoffHopMultiplier = 1.5;

// ============================================================================
// REASSEMBLY
// ============================================================================

/// Default fragment reassembly timeout
const Duration kDefaultReassemblyTimeout = Duration(minutes: 5);

/// Maximum reassembly buffer lifetime (3x timeout)
const int kReassemblyBufferLifetimeMultiplier = 3;
