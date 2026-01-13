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
import 'header/compact_header.dart';
import 'header/header_factory.dart';
import 'header/standard_header.dart';
import 'payload/payload.dart';
import 'payload/sos_payload.dart';
import 'payload/location_payload.dart';
import 'payload/text_payload.dart';
import 'payload/ack_payload.dart';

/// Complete packet (header + payload)
class Packet {
  /// Header (compact or standard)
  final Object header;

  /// Payload data
  final Payload payload;

  /// CRC-8 checksum (for compact SOS packets)
  final int? crc;

  /// Raw encoded bytes (cached)
  Uint8List? _encoded;

  /// Create a packet from header and payload
  Packet({required this.header, required this.payload, this.crc}) {
    // Validate header type
    if (header is! CompactHeader && header is! StandardHeader) {
      throw ArgumentError('Header must be CompactHeader or StandardHeader');
    }
  }

  /// Get packet mode
  PacketMode get mode {
    if (header is CompactHeader) return PacketMode.compact;
    return PacketMode.standard;
  }

  /// Get message type from header
  MessageType get type {
    if (header is CompactHeader) return (header as CompactHeader).type;
    return (header as StandardHeader).type;
  }

  /// Get message ID from header
  int get messageId {
    if (header is CompactHeader) return (header as CompactHeader).messageId;
    return (header as StandardHeader).messageId;
  }

  /// Check if packet fits in BLE 4.2 MTU (20 bytes)
  bool get fitsCompact {
    final headerSize = header is CompactHeader
        ? kCompactHeaderSize
        : kStandardHeaderSize;
    return headerSize + payload.sizeInBytes <= kBle42MaxPayload;
  }

  /// Total packet size in bytes
  int get sizeInBytes {
    final headerSize = header is CompactHeader
        ? kCompactHeaderSize
        : kStandardHeaderSize;
    int size = headerSize + payload.sizeInBytes;
    if (crc != null) size += 1;
    return size;
  }

  /// Encode packet to bytes
  Uint8List encode({bool includeCrc = false}) {
    if (_encoded != null && !includeCrc) return _encoded!;

    // Encode header
    final headerBytes = header is CompactHeader
        ? (header as CompactHeader).encode()
        : (header as StandardHeader).encode();

    // Encode payload
    final payloadBytes = payload.encode();

    // Combine
    int size = headerBytes.length + payloadBytes.length;
    if (includeCrc) size += 1;

    final buffer = Uint8List(size);
    buffer.setRange(0, headerBytes.length, headerBytes);
    buffer.setRange(
      headerBytes.length,
      headerBytes.length + payloadBytes.length,
      payloadBytes,
    );

    // Add CRC if requested
    if (includeCrc) {
      final crcValue = Crc8.compute(buffer.sublist(0, size - 1));
      buffer[size - 1] = crcValue;
    }

    if (!includeCrc) _encoded = buffer;
    return buffer;
  }

  /// Decode packet from bytes
  factory Packet.decode(Uint8List bytes, {bool hasCrc = false}) {
    if (bytes.isEmpty) {
      throw DecodingException('Packet.decode: empty input');
    }

    // Verify CRC if present
    if (hasCrc) {
      if (bytes.length < 2) {
        throw DecodingException('Packet.decode: too short for CRC');
      }
      final actualCrc = bytes[bytes.length - 1];
      final expectedCrc = Crc8.compute(bytes.sublist(0, bytes.length - 1));
      if (actualCrc != expectedCrc) {
        throw CrcMismatchException(expected: expectedCrc, actual: actualCrc);
      }
      // Remove CRC byte for decoding
      bytes = bytes.sublist(0, bytes.length - 1);
    }

    // Decode header
    final mode = HeaderFactory.detectMode(bytes[0]);
    final headerSize = HeaderFactory.getHeaderSize(bytes[0]);

    if (bytes.length < headerSize) {
      throw DecodingException(
        'Packet.decode: insufficient data for header, expected $headerSize, got ${bytes.length}',
      );
    }

    Object header;
    if (mode == PacketMode.compact) {
      header = CompactHeader.decode(bytes);
    } else {
      header = StandardHeader.decode(bytes);
    }

    // Get message type
    final messageType = mode == PacketMode.compact
        ? (header as CompactHeader).type
        : (header as StandardHeader).type;

    // Extract payload bytes
    final payloadBytes = bytes.sublist(headerSize);

    // Decode payload based on type
    final payload = _decodePayload(messageType, payloadBytes, mode);

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
      messageId: messageId ?? DateTime.now().millisecondsSinceEpoch & 0xFFFF,
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
        messageId: messageId ?? DateTime.now().millisecondsSinceEpoch & 0xFFFF,
      );
      return Packet(header: header, payload: payload);
    } else {
      final header = StandardHeader(
        type: MessageType.location,
        flags: PacketFlags(mesh: true),
        messageId:
            messageId ?? DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF,
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
      messageId:
          messageId ?? DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF,
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
        messageId: messageId ?? DateTime.now().millisecondsSinceEpoch & 0xFFFF,
      );
      return Packet(header: header, payload: payload);
    } else {
      final header = StandardHeader(
        type: MessageType.dataAck,
        flags: PacketFlags(),
        messageId:
            messageId ?? DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF,
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
