/// Packet - Complete Protocol Packet
///
/// Combines header and payload into a complete packet for transmission.
/// Handles encoding/decoding of the full packet structure.

library;

import 'dart:typed_data';

import '../core/constants.dart';
import '../core/exceptions.dart';
import '../core/types.dart';
import '../encoding/bitwise.dart';
import '../encoding/crc8.dart';
import '../encoding/crc32.dart';
import 'header/compact_header.dart';
import 'header/header_factory.dart';
import 'header/packet_header.dart';
import 'header/standard_header.dart';
import 'payload/payload.dart';
import 'payload/sos_payload.dart';
import 'payload/location_payload.dart';
import 'payload/text_payload.dart';
import 'payload/ack_payload.dart';
import 'payload/nack_payload.dart';
import 'payload/raw_payload.dart';
import 'payload/text_location_payload.dart';
import 'payload/challenge_payload.dart';
import '../mesh/message_id_generator.dart';

/// Complete packet (header + payload)
class Packet {
  /// Header (compact or standard)
  final PacketHeader header;

  /// Payload data
  final Payload payload;

  /// Raw encoded bytes (cached)
  Uint8List? _encoded;

  /// Create a packet from header and payload
  Packet({required this.header, required this.payload});

  /// Get packet mode
  PacketMode get mode {
    return header.mode;
  }

  /// Get message type from header
  MessageType get type {
    return header.type;
  }

  /// Get message ID from header
  int get messageId {
    return header.messageId;
  }

  /// Check if compact packet fits in BLE 4.2 MTU (20 bytes).
  /// Wire format for compact is: header (4) + payload + CRC-8 (1)
  bool get fitsCompact {
    if (mode != PacketMode.compact) return false;
    return kCompactHeaderSize + payload.sizeInBytes + kCrcSize <=
        kBle42MaxPayload;
  }

  /// Total packet size in bytes
  int get sizeInBytes {
    final headerSize = header.sizeInBytes;
    final payloadSize = payload.sizeInBytes;
    final integritySize = mode == PacketMode.compact ? kCrcSize : 4;
    return headerSize + payloadSize + integritySize;
  }

  /// Encode packet to bytes
  Uint8List encode() {
    if (_encoded != null) return _encoded!;

    // Encode header
    final headerBytes = header.encode();

    // Encode payload
    final payloadBytes = payload.encode();

    final integritySize = mode == PacketMode.compact ? kCrcSize : 4;

    // Combine
    final size = headerBytes.length + payloadBytes.length + integritySize;

    final buffer = Uint8List(size);
    buffer.setRange(0, headerBytes.length, headerBytes);
    buffer.setRange(
      headerBytes.length,
      headerBytes.length + payloadBytes.length,
      payloadBytes,
    );

    // Append integrity trailer
    if (mode == PacketMode.compact) {
      // CRC-8 over header+payload
      final crcValue = Crc8.compute(buffer.sublist(0, size - 1));
      buffer[size - 1] = crcValue;
    } else {
      // CRC-32/IEEE over header+payload (including ciphertext+tag if encrypted)
      final crcValue = Crc32.compute(buffer.sublist(0, size - 4));
      Bitwise.write32BE(buffer, size - 4, crcValue);
    }

    _encoded = buffer;
    return _encoded!;
  }

  /// Decode packet from bytes
  factory Packet.decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw DecodingException('Packet.decode: empty input');
    }

    // Detect mode from first byte
    final mode = HeaderFactory.detectMode(bytes[0]);

    // Verify and strip integrity trailer
    if (mode == PacketMode.compact) {
      if (bytes.length < kCompactHeaderSize + kCrcSize) {
        throw DecodingException('Packet.decode: too short for Compact+CRC');
      }
      final actual = bytes[bytes.length - 1];
      final expected = Crc8.compute(bytes.sublist(0, bytes.length - 1));
      if (actual != expected) {
        throw CrcMismatchException(expected: expected, actual: actual);
      }
      bytes = bytes.sublist(0, bytes.length - 1);
    } else {
      if (bytes.length < kStandardHeaderSize + 4) {
        throw DecodingException('Packet.decode: too short for Standard+CRC32');
      }
      final actual = Bitwise.read32BE(bytes, bytes.length - 4);
      final expected = Crc32.compute(bytes.sublist(0, bytes.length - 4));
      if (actual != expected) {
        throw CrcMismatchException(expected: expected, actual: actual);
      }
      bytes = bytes.sublist(0, bytes.length - 4);
    }

    // Decode header
    final headerSize = HeaderFactory.getHeaderSize(bytes[0]);

    if (bytes.length < headerSize) {
      throw DecodingException(
        'Packet.decode: insufficient data for header, expected $headerSize, got ${bytes.length}',
      );
    }

    final PacketHeader header = mode == PacketMode.compact
        ? CompactHeader.decode(bytes)
        : StandardHeader.decode(bytes);

    // Get message type
    final messageType = header.type;

    // Extract payload bytes
    final payloadBytes = bytes.sublist(headerSize);

    // Decode payload based on type.
    //
    // Fragment packets carry partial data: do NOT attempt to parse as a typed
    // payload. We still want CRC fail-fast at Packet.decode level, so we return
    // RawPayload here and let the fragmentation layer handle reassembly.
    final payload = header.flags.isFragment
        ? RawPayload(type: messageType, bytes: payloadBytes)
        : _decodePayload(messageType, payloadBytes, mode);

    return Packet(header: header, payload: payload);
  }

  /// Decode payload based on message type
  static Payload _decodePayload(
    MessageType type,
    Uint8List bytes,
    PacketMode mode,
  ) {
    switch (type) {
      case MessageType.sosBeacon:
        return SosPayload.decode(bytes);

      case MessageType.location:
        // Try extended first, fall back to compact
        final extended = bytes.length >= LocationPayload.extendedSize;
        return LocationPayload.decode(bytes, extended: extended);

      case MessageType.textShort:
      case MessageType.textExtended:
        return TextPayload.decode(bytes);

      case MessageType.sosAck:
      case MessageType.dataAck:
        return AckPayload.decode(bytes, compact: mode == PacketMode.compact);

      case MessageType.nack:
        return NackPayload.decode(bytes);

      case MessageType.textLocation:
        return TextLocationPayload.decode(bytes);

      case MessageType.challenge:
        return ChallengePayload.decode(bytes);

      default:
        // Return text payload as fallback for unknown types
        if (bytes.isNotEmpty) {
          try {
            return TextPayload.decode(bytes);
          } catch (_) {
            // Fall through
          }
        }
        throw DecodingException('Unknown message type: ${type.name}');
    }
  }

  /// Create a compact SOS packet
  factory Packet.sos({
    required SosType sosType,
    required double latitude,
    required double longitude,
    String? phoneNumber,
    int? altitude,
    int? batteryPercent,
    int peopleCount = 1,
    bool hasInjured = false,
    bool isTrapped = false,
    int? messageId,
  }) {
    final payload = SosPayload(
      sosType: sosType,
      latitude: latitude,
      longitude: longitude,
      phoneNumber: phoneNumber,
      altitude: altitude,
      batteryPercent: batteryPercent,
      peopleCount: peopleCount,
      hasInjured: hasInjured,
      isTrapped: isTrapped,
    );

    final header = CompactHeader(
      type: MessageType.sosBeacon,
      flags: PacketFlags(mesh: true, urgent: true),
      messageId: messageId ?? MessageIdGenerator.generate(),
    );

    return Packet(header: header, payload: payload);
  }

  /// Create a location packet
  factory Packet.location({
    required double latitude,
    required double longitude,
    int? altitude,
    int? accuracy,
    bool compact = true,
    int? messageId,
  }) {
    final payload = LocationPayload(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      accuracy: accuracy,
    );

    if (compact) {
      final header = CompactHeader(
        type: MessageType.location,
        flags: PacketFlags(mesh: true),
        messageId: messageId ?? MessageIdGenerator.generate(),
      );
      return Packet(header: header, payload: payload);
    } else {
      final header = StandardHeader(
        type: MessageType.location,
        flags: PacketFlags(mesh: true),
        messageId: messageId ?? MessageIdGenerator.generate32(),
        payloadLength: payload.sizeInBytes,
      );
      return Packet(header: header, payload: payload);
    }
  }

  /// Create a text message packet
  factory Packet.text({
    required String text,
    String? senderId,
    String? recipientId,
    bool ackRequired = false,
    int? messageId,
  }) {
    final payload = TextPayload(
      text: text,
      senderId: senderId,
      recipientId: recipientId,
    );

    final header = StandardHeader(
      type: MessageType.textShort,
      flags: PacketFlags(mesh: true, ackRequired: ackRequired),
      messageId: messageId ?? MessageIdGenerator.generate32(),
      payloadLength: payload.sizeInBytes,
    );

    return Packet(header: header, payload: payload);
  }

  /// Create an ACK packet
  factory Packet.ack({
    required int originalMessageId,
    AckStatus status = AckStatus.received,
    bool compact = true,
    int? messageId,
  }) {
    final payload = AckPayload(
      originalMessageId: originalMessageId,
      status: status,
      isCompact: compact,
    );

    if (compact) {
      final header = CompactHeader(
        type: MessageType.sosAck,
        flags: PacketFlags(),
        messageId: messageId ?? MessageIdGenerator.generate(),
      );
      return Packet(header: header, payload: payload);
    } else {
      final header = StandardHeader(
        type: MessageType.dataAck,
        flags: PacketFlags(),
        messageId: messageId ?? MessageIdGenerator.generate32(),
        payloadLength: payload.sizeInBytes,
      );
      return Packet(header: header, payload: payload);
    }
  }

  @override
  String toString() {
    return 'Packet(mode: ${mode.name}, type: ${type.name}, '
        'msgId: 0x${messageId.toRadixString(16)}, '
        'size: $sizeInBytes bytes, '
        'payload: ${payload.runtimeType})';
  }
}
