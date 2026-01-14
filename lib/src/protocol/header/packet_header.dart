/// Packet Header Abstraction
///
/// Common interface implemented by both Compact and Standard headers.
library;

import 'dart:typed_data';

import '../../core/types.dart';
import '../../encoding/bitwise.dart';

/// Common interface for all packet headers.
abstract class PacketHeader {
  /// Packet mode (compact or standard)
  PacketMode get mode;

  /// Message type
  MessageType get type;

  /// Packet flags
  PacketFlags get flags;

  /// Hop TTL (compact: 4-bit, standard: 8-bit)
  int get ttl;

  /// Message ID (compact: 16-bit, standard: 32-bit)
  int get messageId;

  /// Header size in bytes
  int get sizeInBytes;

  /// Whether this message is expired (TTL and/or age based)
  bool get isExpired;

  /// Encode header to bytes.
  Uint8List encode();
}

