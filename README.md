<p align="center">
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License"/>
  <img src="https://img.shields.io/badge/Version-2.0.0-blue?style=for-the-badge" alt="Version"/>
  <img src="https://img.shields.io/badge/BLE-4.0+-purple?style=for-the-badge&logo=bluetooth&logoColor=white" alt="BLE 4.0+"/>
</p>

# 🔗 BitPack

**A safety-critical, bandwidth-efficient binary protocol for off-grid mesh networking over BLE 4.0+**

> *When infrastructure fails, communication shouldn't.*

BitPack is a pure Dart library designed for the **Echo Project** — a disaster communication app that enables peer-to-peer mesh networking when cellular and internet infrastructure is unavailable. Every byte counts when lives are on the line.

---

## 🎯 Why BitPack?

### The Problem

Modern BLE devices (especially BLE 4.0/4.2) have severe bandwidth limitations. The default MTU is just **20 bytes**. Most messaging protocols waste precious bytes on verbose headers, making them unsuitable for emergency communication over constrained networks.

### The Solution

BitPack implements a **dual-mode protocol** optimized for real-world BLE constraints:

| Feature | Compact Mode | Standard Mode |
|---------|:------------:|:-------------:|
| **Target** | BLE 4.0/4.2 (20-byte MTU) | BLE 5.0+ (244-byte MTU) |
| **Header Size** | 4 bytes | 11 bytes |
| **Message ID** | 16-bit | 32-bit |
| **Max Hops** | 15 | 255 |
| **Integrity** | CRC-8 | CRC-32 (IEEE 802.3) |
| **Max Payload** | 15 bytes | ~8 KB |
| **Encryption** | ❌ | AES-GCM ✅ |
| **Use Case** | SOS beacons, Keep-Alive | Text messages, Files |

### Key Features

- 🛡️ **Fail-Fast Integrity** — Every packet has a CRC trailer. Corrupt data is dropped *before* decoding.
- 📡 **Built-in Mesh Networking** — Flood routing with loop prevention and smart relay backoff.
- 🔐 **Military-Grade Encryption** — AES-128/256-GCM with PBKDF2 key derivation.
- 📦 **Automatic Fragmentation** — Large payloads are split and reassembled transparently.
- 🌍 **GPS Encoding** — 7-decimal precision coordinates in just 8 bytes.
- 📞 **Phone Number Compression** — BCD encoding for minimal overhead.

---

## 📦 Installation

Add BitPack to your `pubspec.yaml`:

```yaml
dependencies:
  bit_pack:
    git:
      url: https://github.com/fzengin19/bit_pack.git
      ref: v2.0.0
```

Then run:

```bash
flutter pub get
# or for pure Dart projects:
dart pub get
```

---

## 🚀 Quick Start

### Example 1: Creating an SOS Beacon (Compact Mode)

Send an emergency SOS that fits in a single BLE 4.0 packet (20 bytes total):

```dart
import 'package:bit_pack/bit_pack.dart';

// Create an SOS beacon with GPS coordinates
final packet = Packet.sos(
  sosType: SosType.needRescue,
  latitude: 41.0082,          // Istanbul coordinates
  longitude: 28.9784,
  phoneNumber: '+905331234567',
  altitude: 120,              // meters
  batteryPercent: 45,
  peopleCount: 3,
  hasInjured: true,
);

// Encode to bytes (20 bytes with CRC-8)
final bytes = packet.encode();
print('SOS Packet: ${bytes.length} bytes'); // Output: 20 bytes

// Send via BLE
await bleAdapter.broadcast(bytes);
```

### Example 2: Sending a Text Message (Standard Mode)

Send encrypted text messages with larger payloads:

```dart
import 'package:bit_pack/bit_pack.dart';

// Generate salt and derive encryption key
final salt = KeyDerivation.generateSalt();
final key = await KeyDerivation.deriveKey(
  password: 'rescue_team_alpha',
  salt: salt,
  keyLength: 16, // AES-128
);

// Create a text message packet using PacketBuilder
final packet = PacketBuilder()
  .type(MessageType.textShort)
  .standard()  // Force standard mode for encryption
  .mesh(true)
  .encrypted(true)
  .security(SecurityMode.symmetric)
  .payload(TextPayload.broadcast(
    'Supplies arriving at checkpoint B in 30 minutes',
    senderId: 'rescue_team_01',
  ))
  .build();

// Encrypt the payload with header as AAD
final encryptedPayload = await AesGcmCipher.encryptWithHeader(
  plaintext: packet.payload.encode(),
  key: key,
  header: packet.header.encode(),
);

print('Encrypted message ready for transmission');
```

### Example 3: Setting Up Mesh Controller

Create a mesh network that automatically relays and deduplicates packets:

```dart
import 'dart:async';
import 'package:bit_pack/bit_pack.dart';

// Initialize mesh controller
final mesh = MeshController(
  defaultTtl: 15,
  onBroadcast: (packet) async {
    // This callback is called when a packet should be transmitted
    await bleAdapter.broadcast(packet.encode());
  },
);

// Listen to mesh events
mesh.events.listen((event) {
  if (event is PacketReceivedEvent) {
    if (event.isNew) {
      print('📨 New packet: ${event.packet.header.type}');
      handlePacket(event.packet);
    } else {
      print('🔄 Duplicate ignored');
    }
  } else if (event is PacketRelayedEvent) {
    print('📡 Relayed: msgId=${event.packet.header.messageId}');
  } else if (event is RelayCancelledEvent) {
    print('⏹️ Relay cancelled: ${event.messageId}');
  }
});

// Handle incoming BLE data
void onBleReceive(Uint8List bytes) {
  try {
    final packet = Packet.decode(bytes);
    mesh.handleIncomingPacket(packet);
  } on CrcMismatchException catch (e) {
    print('❌ Corrupt packet dropped: $e');
  }
}

// Originate a new message
await mesh.broadcast(myPacket);

// Cleanup expired cache entries periodically
Timer.periodic(Duration(minutes: 5), (_) => mesh.cleanup());
```

---

## 🏗️ Protocol Architecture

### Compact Mode Packet Structure (20 bytes)

Optimized for BLE 4.0/4.2 with 20-byte MTU:

```
┌─────────────────────────────────────────────────────────────┐
│                      HEADER (4 bytes)                       │
├──────────────┬──────────────┬───────────────────────────────┤
│    Byte 0    │    Byte 1    │         Bytes 2-3             │
├──────────────┼──────────────┼───────────────────────────────┤
│ MODE    [1b] │ TTL     [4b] │                               │
│ TYPE    [4b] │ FLAGS   [2b] │      MESSAGE_ID (16-bit)      │
│ FLAGS   [3b] │ RSVD    [2b] │                               │
├──────────────┴──────────────┴───────────────────────────────┤
│                      PAYLOAD (15 bytes)                     │
├─────────────────────────────────────────────────────────────┤
│                       CRC-8 (1 byte)                        │
└─────────────────────────────────────────────────────────────┘
```

### Standard Mode Packet Structure

For BLE 5.0+ with extended MTU (up to 244 bytes):

```
┌───────────────────────────────────────────────────────────┐
│                     HEADER (11 bytes)                     │
├───────────────────────────────────────────────────────────┤
│ Byte 0:     MODE [1b] + VERSION [1b] + TYPE [6b]          │
│ Byte 1:     FLAGS [8b]                                    │
│ Byte 2:     HOP_TTL [8b]                                  │
│ Bytes 3-6:  MESSAGE_ID [32b]                              │
│ Byte 7:     SECURITY_MODE [3b] + PAYLOAD_LEN_HIGH [5b]    │
│ Byte 8:     PAYLOAD_LEN_LOW [8b]                          │
│ Bytes 9-10: AGE_MINUTES [16b] (relative timestamp)        │
├───────────────────────────────────────────────────────────┤
│                PAYLOAD (variable, max ~8 KB)              │
├───────────────────────────────────────────────────────────┤
│                      CRC-32 (4 bytes)                     │
└───────────────────────────────────────────────────────────┘
```

### SOS Payload Structure (15 bytes)

Ultra-compact emergency payload:

```
┌────────────────────────────────────────────────────────────┐
│  Byte 0:      SOS_STATUS                                   │
│               ├── SOS Type [3b]     (needRescue, injured)  │
│               ├── People Count [3b] (0-7 people)           │
│               ├── Has Injured [1b]                         │
│               └── Is Trapped [1b]                          │
├────────────────────────────────────────────────────────────┤
│  Bytes 1-4:   LATITUDE  (fixed-point int32, 7 decimals)    │
│  Bytes 5-8:   LONGITUDE (fixed-point int32, 7 decimals)    │
├────────────────────────────────────────────────────────────┤
│  Bytes 9-12:  PHONE NUMBER (BCD encoded, last 8 digits)    │
├────────────────────────────────────────────────────────────┤
│  Bytes 13-14: ALTITUDE [12b] (0-4095m)                     │
│               BATTERY  [4b]  (0-15 → 0-100%)               │
└────────────────────────────────────────────────────────────┘
```

---

## 🔐 Security

BitPack implements defense-in-depth security:

| Layer | Mechanism | Purpose |
|-------|-----------|---------|
| **Integrity** | CRC-8 / CRC-32 | Detect transmission errors |
| **Authentication** | AES-GCM Auth Tag | Verify packet authenticity |
| **Encryption** | AES-128/256-GCM | Protect payload confidentiality |
| **Key Derivation** | PBKDF2 | Derive keys from shared secrets |
| **Header Protection** | AAD | Prevent header tampering |

### Encryption Example

```dart
// Encrypt with header as AAD (Additional Authenticated Data)
final encrypted = await AesGcmCipher.encryptWithHeader(
  plaintext: payload,
  key: derivedKey,
  header: headerBytes,  // Header is authenticated, not encrypted
);

// Output: nonce (12B) + ciphertext + auth_tag (16B)
```

---

## 📡 Mesh Networking

### Features

- **Flood Routing**: Messages propagate across all reachable nodes
- **Loop Prevention**: Message cache prevents infinite forwarding loops
- **Exponential Backoff**: Randomized delays prevent broadcast storms
- **TTL Control**: Hop-based (Compact) and time-based (Standard) expiration
- **Duplicate Detection**: 24-hour message cache with configurable size

### How It Works

```
   [Node A] ──broadcast──▶ [Node B] ──relay──▶ [Node C]
       │                      │                    │
       └──────────────────────┴────────────────────┘
                    Mesh Network
```

1. **Receive**: Node receives packet via BLE
2. **Verify**: CRC check (fail-fast on corruption)  
3. **Deduplicate**: Check message cache
4. **Process**: Deliver to application if new
5. **Relay**: Schedule relay with backoff delay
6. **Decrement TTL**: Reduce hop count before forwarding

---

## 🗺️ Roadmap

### v1.0.0
- ✅ Dual-mode protocol (Compact/Standard)
- ✅ CRC-8 and CRC-32 integrity
- ✅ AES-GCM encryption with PBKDF2
- ✅ Mesh controller with flood routing
- ✅ Automatic fragmentation/reassembly
- ✅ Selective Repeat ARQ

### v1.1.0
- ✅ Hybrid Payloads (TextLocation)
- ✅ Secure Challenges (ChallengePayload)
- ✅ PacketBuilder fluent API

### v2.0.0 (Current)
- ✅ **Identity Support** — senderId/recipientId for TextLocationPayload and ChallengePayload
- ✅ **Forward Compatibility** — Unknown MessageTypes return RawPayload
- ✅ **UTF-8 Fix** — Turkish and emoji support in AckPayload

### v2.1.0 (Planned)
- 🔜 **File Transfer** — Binary data chunks with resume support
- 🔜 **Wi-Fi Direct Handover** — Seamless transition for large transfers
- 🔜 **Compression** — Optional payload compression
- 🔜 **Group Keys** — Multi-party encryption support

---

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <i>Developed for the Echo Project — Off-grid communication when it matters most.</i>
</p>
