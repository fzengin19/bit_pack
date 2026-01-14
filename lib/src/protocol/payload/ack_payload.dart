/// ACK Payload
///
/// Acknowledgment payload for confirming message receipt.
/// Used with ack_required flag in headers.
///
/// Layout:
/// ```
/// BYTES 0-3:  ORIGINAL_MESSAGE_ID (32 bits for standard, 16 bits for compact)
/// BYTE 4:     ACK_STATUS
///             Bits 7-4: Reserved
///             Bits 3-0: Status code
/// [BYTES 5-N]: Optional data (status-dependent)
/// ```
///
/// Status codes:
/// - 0x0: RECEIVED (message received successfully)
/// - 0x1: DELIVERED (message delivered to recipient)
/// - 0x2: READ (message read by recipient)
/// - 0x3: FAILED (delivery failed)
/// - 0x4: REJECTED (message rejected)
/// - 0x5: RELAYED (message relayed to next hop)

library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../core/types.dart';
import 'payload.dart';

/// ACK status codes
enum AckStatus {
  /// Message received by node
  received(0x0),

  /// Message delivered to final recipient
  delivered(0x1),

  /// Message read by recipient
  read(0x2),

  /// Delivery failed
  failed(0x3),

  /// Message rejected
  rejected(0x4),

  /// Message relayed to next hop
  relayed(0x5);

  final int code;

  const AckStatus(this.code);

  /// Create from status code
  static AckStatus fromCode(int code) {
    for (final status in AckStatus.values) {
      if (status.code == code) return status;
    }
    return AckStatus.received;
  }
}

/// Acknowledgment payload
class AckPayload extends Payload {
  /// Compact ACK size (for 16-bit message ID)
  static const int compactSize = 3;

  /// Standard ACK size (for 32-bit message ID)
  static const int standardSize = 5;

  /// Original message ID being acknowledged
  final int originalMessageId;

  /// ACK status
  final AckStatus status;

  /// Whether this is a compact ACK (16-bit message ID)
  final bool isCompact;

  /// Optional failure reason (for failed/rejected status)
  final String? reason;

  /// Create a new ACK payload
  AckPayload({
    required this.originalMessageId,
    this.status = AckStatus.received,
    this.isCompact = false,
    this.reason,
  }) {
    // Validate message ID range
    if (isCompact && (originalMessageId < 0 || originalMessageId > 0xFFFF)) {
      throw ArgumentError(
        'Compact ACK message ID must be 0-65535, got $originalMessageId',
      );
    }
    if (!isCompact &&
        (originalMessageId < 0 || originalMessageId > 0xFFFFFFFF)) {
      throw ArgumentError(
        'Standard ACK message ID must be 0-4294967295, got $originalMessageId',
      );
    }
  }

  /// Create a "received" ACK
  factory AckPayload.received(int messageId, {bool compact = false}) {
    return AckPayload(
      originalMessageId: messageId,
      status: AckStatus.received,
      isCompact: compact,
    );
  }

  /// Create a "delivered" ACK
  factory AckPayload.delivered(int messageId, {bool compact = false}) {
    return AckPayload(
      originalMessageId: messageId,
      status: AckStatus.delivered,
      isCompact: compact,
    );
  }

  /// Create a "relayed" ACK
  factory AckPayload.relayed(int messageId, {bool compact = false}) {
    return AckPayload(
      originalMessageId: messageId,
      status: AckStatus.relayed,
      isCompact: compact,
    );
  }

  /// Create a "failed" ACK
  factory AckPayload.failed(
    int messageId, {
    String? reason,
    bool compact = false,
  }) {
    return AckPayload(
      originalMessageId: messageId,
      status: AckStatus.failed,
      isCompact: compact,
      reason: reason,
    );
  }

  @override
  MessageType get type => MessageType.sosAck;

  @override
  int get sizeInBytes {
    int size = isCompact ? compactSize : standardSize;
    if (reason != null) {
      size += 1 + utf8.encode(reason!).length; // Length byte + UTF-8
    }
    return size;
  }

  @override
  Uint8List encode() {
    final buffer = Uint8List(sizeInBytes);
    final data = ByteData.view(buffer.buffer);
    int offset = 0;

    // MESSAGE_ID
    if (isCompact) {
      data.setUint16(offset, originalMessageId, Endian.big);
      offset += 2;
    } else {
      data.setUint32(offset, originalMessageId, Endian.big);
      offset += 4;
    }

    // STATUS
    buffer[offset++] = status.code & 0x0F;

    // REASON (optional)
    if (reason != null) {
      final reasonBytes = utf8.encode(reason!);
      buffer[offset++] = reasonBytes.length.clamp(0, 255);
      buffer.setRange(
        offset,
        offset + reasonBytes.length.clamp(0, 255),
        reasonBytes,
      );
    }

    return buffer;
  }

  /// Decode ACK payload from bytes
  factory AckPayload.decode(Uint8List bytes, {bool compact = false}) {
    final minSize = compact ? compactSize : standardSize;

    if (bytes.length < minSize) {
      throw DecodingException(
        'AckPayload: insufficient data, expected $minSize, got ${bytes.length}',
      );
    }

    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    int offset = 0;

    // MESSAGE_ID
    int messageId;
    if (compact) {
      messageId = data.getUint16(offset, Endian.big);
      offset += 2;
    } else {
      messageId = data.getUint32(offset, Endian.big);
      offset += 4;
    }

    // STATUS
    final statusCode = bytes[offset++] & 0x0F;
    final status = AckStatus.fromCode(statusCode);

    // REASON (optional)
    String? reason;
    if (offset < bytes.length) {
      final reasonLen = bytes[offset++];
      if (offset + reasonLen <= bytes.length) {
        reason = utf8.decode(bytes.sublist(offset, offset + reasonLen));
      }
    }

    return AckPayload(
      originalMessageId: messageId,
      status: status,
      isCompact: compact,
      reason: reason,
    );
  }

  @override
  AckPayload copy() {
    return AckPayload(
      originalMessageId: originalMessageId,
      status: status,
      isCompact: isCompact,
      reason: reason,
    );
  }

  @override
  String toString() {
    final mode = isCompact ? 'compact' : 'standard';
    final reasonStr = reason != null ? ', reason: $reason' : '';
    return 'AckPayload($mode, msgId: 0x${originalMessageId.toRadixString(16)}, '
        'status: ${status.name}$reasonStr)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AckPayload &&
        other.originalMessageId == originalMessageId &&
        other.status == status &&
        other.isCompact == isCompact &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(originalMessageId, status, isCompact, reason);
}
