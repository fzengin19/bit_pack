# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-01-15

### Added

- **Identity Support**: `TextLocationPayload` and `ChallengePayload` now support `senderId` and `recipientId`.
- **FLAGS Byte**: New payloads use FLAGS at Offset 0 (Bit 7 = Sender, Bit 6 = Recipient).
- **Forward Compatibility**: Unknown `MessageType` returns `RawPayload` instead of throwing.

### Fixed

- **UTF-8 Support**: `AckPayload` now uses `utf8.encode/decode` for Turkish and emoji characters.

### Breaking Changes

- `TextLocationPayload` binary layout changed (GPS moved from Offset 0 to dynamic offset).
- `ChallengePayload` binary layout changed (Salt moved from Offset 0 to dynamic offset).
- v1.x clients cannot decode v2.0 payloads.

## [1.1.0] - 2026-01-15

### Added

- **Protocol v1.1**: Native support for hybrid payloads to reduce overhead.
- **TextLocationPayload (0x1C)**: Combination of fixed-point GPS and UTF-8 text without delimiters.
- **ChallengePayload (0x1D)**: Structured binary format for security challenges (Salt + Question + Ciphertext).
- **PacketBuilder**: New fluent methods `textLocation()` and `challenge()`.

## [1.0.0] - 2026-01-14

### Added

- **Dual-mode protocol**: Compact (4B header, BLE 4.0+) and Standard (11B header, BLE 5.0+)
- **Packet types**: SOS beacon, location, text, ACK/NACK, ping/pong
- **Integrity**: CRC-8 (Compact) and CRC-32 IEEE 802.3 (Standard)
- **Encryption**: AES-128/256-GCM with PBKDF2 key derivation
- **Mesh networking**: MeshController with flood routing, duplicate detection, exponential backoff
- **Fragmentation**: Automatic packet splitting/reassembly with Selective Repeat ARQ
- **Encoding utilities**: GPS fixed-point, BCD phone numbers, VarInt
