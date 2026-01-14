# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
