/// BitPack Packet Builder
///
/// Fluent API for building packets with automatic mode selection.

library;

import '../core/constants.dart';
import '../core/types.dart';
import '../encoding/bitwise.dart';
import '../mesh/message_id_generator.dart';
import 'header/compact_header.dart';
import 'header/packet_header.dart';
import 'header/standard_header.dart';
import 'packet.dart';
import 'payload/payload.dart';
import 'payload/text_payload.dart';
import 'payload/location_payload.dart';

// ============================================================================
// PACKET BUILDER
// ============================================================================

/// Fluent builder for creating BitPack packets
///
/// Provides chainable API for configuring packet properties.
/// Automatically selects appropriate mode based on payload size.
///
/// Example:
/// ```dart
/// final packet = PacketBuilder()
///   .type(MessageType.textShort)
///   .mesh(true)
///   .ttl(10)
///   .urgent(true)
///   .payload(TextPayload(text: 'Hello mesh!'))
///   .build();
/// ```
class PacketBuilder {
  MessageType? _type;
  PacketMode? _mode;
  int? _messageId;
  int _ttl = 15;
  SecurityMode _securityMode = SecurityMode.none;

  // Flags
  bool _mesh = true;
  bool _ackRequired = false;
  bool _encrypted = false;
  bool _compressed = false;
  bool _urgent = false;
  bool _fragment = false;
  bool _moreFragments = false;

  // Payload
  Payload? _payload;

  // Age (for standard mode)
  int _ageMinutes = 0;

  /// Set message type
  PacketBuilder type(MessageType type) {
    _type = type;
    return this;
  }

  /// Set packet mode explicitly
  PacketBuilder mode(PacketMode mode) {
    _mode = mode;
    return this;
  }

  /// Force compact mode
  PacketBuilder compact() {
    _mode = PacketMode.compact;
    return this;
  }

  /// Force standard mode
  PacketBuilder standard() {
    _mode = PacketMode.standard;
    return this;
  }

  /// Set message ID (auto-generated if not set)
  PacketBuilder messageId(int id) {
    _messageId = id;
    return this;
  }

  /// Set TTL (hop count)
  PacketBuilder ttl(int ttl) {
    _ttl = ttl;
    return this;
  }

  /// Set security mode
  PacketBuilder security(SecurityMode mode) {
    _securityMode = mode;
    if (mode != SecurityMode.none) {
      _encrypted = true;
    }
    return this;
  }

  /// Enable mesh relay
  PacketBuilder mesh([bool enabled = true]) {
    _mesh = enabled;
    return this;
  }

  /// Request acknowledgment
  PacketBuilder ackRequired([bool required = true]) {
    _ackRequired = required;
    return this;
  }

  /// Mark as encrypted
  PacketBuilder encrypted([bool encrypted = true]) {
    _encrypted = encrypted;
    return this;
  }

  /// Mark as compressed
  PacketBuilder compressed([bool compressed = true]) {
    _compressed = compressed;
    return this;
  }

  /// Mark as urgent
  PacketBuilder urgent([bool urgent = true]) {
    _urgent = urgent;
    return this;
  }

  /// Mark as fragment
  PacketBuilder fragment([bool fragment = true]) {
    _fragment = fragment;
    return this;
  }

  /// Mark as having more fragments
  PacketBuilder moreFragments([bool more = true]) {
    _moreFragments = more;
    return this;
  }

  /// Set age in minutes (standard mode only)
  PacketBuilder age(int minutes) {
    _ageMinutes = minutes;
    return this;
  }

  /// Set payload
  PacketBuilder payload(Payload payload) {
    _payload = payload;
    return this;
  }

  /// Set text payload
  PacketBuilder text(String text, {String? senderId, String? recipientId}) {
    _payload = TextPayload(
      text: text,
      senderId: senderId,
      recipientId: recipientId,
    );
    _type ??= MessageType.textShort;
    return this;
  }

  /// Set location payload
  PacketBuilder location(double lat, double lon, {int? altitude}) {
    _payload = LocationPayload(
      latitude: lat,
      longitude: lon,
      altitude: altitude,
    );
    _type ??= MessageType.location;
    return this;
  }

  /// Build the flags
  PacketFlags _buildFlags() {
    return PacketFlags(
      mesh: _mesh,
      ackRequired: _ackRequired,
      encrypted: _encrypted,
      compressed: _compressed,
      urgent: _urgent,
      isFragment: _fragment,
      moreFragments: _moreFragments,
    );
  }

  /// Determine best mode for this packet
  PacketMode _determineMode() {
    if (_mode != null) return _mode!;

    final messageType = _type ?? _payload?.type;

    // Force standard if:
    // - Standard-only message type
    // - Encrypted / SecurityMode enabled
    // - Fragmentation flags
    // - Payload too large for compact
    // - TTL > 15
    // - Age tracking needed
    if ((messageType?.requiresStandardMode ?? false) ||
        _securityMode != SecurityMode.none ||
        _encrypted ||
        _fragment ||
        _moreFragments ||
        _ageMinutes > 0 ||
        _ttl > 15) {
      return PacketMode.standard;
    }

    if (_payload != null) {
      // Compact max payload: 20 (MTU) - 4 (header) - 1 (CRC) = 15 bytes
      // CRC is mandatory for data integrity in mesh/emergency scenarios
      if (_payload!.sizeInBytes > kCompactMaxPayload) {
        return PacketMode.standard;
      }
    }

    return PacketMode.compact;
  }

  /// Build the packet
  ///
  /// Throws [StateError] if required fields are not set.
  Packet build() {
    if (_payload == null) {
      throw StateError('PacketBuilder: payload is required');
    }

    final messageType = _type ?? _payload!.type;
    final mode = _determineMode();
    final flags = _buildFlags();

    PacketHeader header;
    if (mode == PacketMode.compact) {
      header = CompactHeader(
        type: messageType,
        flags: flags,
        messageId: _messageId ?? MessageIdGenerator.generate(),
        ttl: _ttl.clamp(0, 15),
      );
    } else {
      header = StandardHeader(
        type: messageType,
        flags: flags,
        hopTtl: _ttl.clamp(0, 255),
        messageId: _messageId ?? MessageIdGenerator.generate32(),
        securityMode: _securityMode,
        payloadLength: _payload!.sizeInBytes,
        ageMinutes: _ageMinutes,
      );
    }

    return Packet(header: header, payload: _payload!);
  }

  /// Reset builder to initial state
  void reset() {
    _type = null;
    _mode = null;
    _messageId = null;
    _ttl = 15;
    _securityMode = SecurityMode.none;
    _mesh = true;
    _ackRequired = false;
    _encrypted = false;
    _compressed = false;
    _urgent = false;
    _fragment = false;
    _moreFragments = false;
    _payload = null;
    _ageMinutes = 0;
  }

  @override
  String toString() {
    return 'PacketBuilder(type: $_type, mode: ${_determineMode()}, '
        'payload: ${_payload?.runtimeType})';
  }
}
