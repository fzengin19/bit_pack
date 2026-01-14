/// BitPack Relay Policy
///
/// Decides whether a packet should be relayed and prepares it for relay.

library;

import '../protocol/header/standard_header.dart';
import '../protocol/packet.dart';
import 'message_cache.dart';

// ============================================================================
// RELAY POLICY
// ============================================================================

/// Policy for deciding whether to relay packets in mesh network
///
/// A packet should be relayed if:
/// 1. TTL > 0 (has remaining hops)
/// 2. MESH flag is set
/// 3. Not seen before (or not relayed to target peer)
/// 4. Not expired (age < max age)
///
/// Example:
/// ```dart
/// final policy = RelayPolicy();
///
/// if (policy.shouldRelay(packet, cache)) {
///   final prepared = policy.prepareForRelay(packet);
///   broadcast(prepared);
/// }
/// ```
class RelayPolicy {
  /// Maximum message age in minutes (default: 24 hours)
  final int maxAgeMinutes;

  /// My own device ID (to avoid relaying own messages)
  final int? myDeviceId;

  RelayPolicy({
    this.maxAgeMinutes = 1440, // 24 hours
    this.myDeviceId,
  });

  /// Check if packet should be relayed
  ///
  /// [packet] The packet to check
  /// [cache] Message cache for duplicate detection
  /// [targetPeerId] Optional specific peer to relay to
  bool shouldRelay(
    Packet packet,
    MessageCache cache, {
    String? targetPeerId,
  }) {
    final header = packet.header;

    // Only Standard Mode supports mesh relay
    if (header is! StandardHeader) {
      return false;
    }

    // 1. MESH flag must be set
    if (!header.flags.mesh) {
      return false;
    }

    // 2. TTL must be > 0
    if (header.hopTtl <= 0) {
      return false;
    }

    // 3. Message must not be expired
    if (header.ageMinutes >= maxAgeMinutes) {
      return false;
    }

    // 4. Must not be already seen (unless relaying to new peer)
    final messageId = header.messageId;
    if (targetPeerId != null) {
      // Check if already relayed to this specific peer
      if (cache.wasRelayedTo(messageId, targetPeerId)) {
        return false;
      }
    } else {
      // General check - have we processed this message?
      if (cache.hasSeen(messageId)) {
        return false;
      }
    }

    return true;
  }

  /// Prepare packet for relay
  ///
  /// - Decrements TTL
  /// - Updates age (if significantly delayed)
  ///
  /// Returns a new packet ready for relay.
  Packet prepareForRelay(Packet packet, {int additionalAgeMinutes = 0}) {
    final header = packet.header;

    if (header is! StandardHeader) {
      throw UnsupportedError('Only StandardHeader supports relay');
    }

    // Create new header with decremented TTL
    final newHeader = StandardHeader(
      type: header.type,
      flags: header.flags,
      hopTtl: header.hopTtl - 1,
      messageId: header.messageId,
      securityMode: header.securityMode,
      payloadLength: header.payloadLength,
      ageMinutes: header.ageMinutes + additionalAgeMinutes,
    );

    // Create new packet with updated header
    return Packet(
      header: newHeader,
      payload: packet.payload,
    );
  }

  /// Calculate priority for relay ordering
  ///
  /// Higher priority = should relay sooner
  /// Priority factors:
  /// - Urgent flag: +100
  /// - Lower TTL (closer to expiry): +10 per remaining hop
  /// - SOS message type: +200
  int calculatePriority(Packet packet) {
    final header = packet.header;
    if (header is! StandardHeader) return 0;

    int priority = 0;

    // Urgent messages get high priority
    if (header.flags.urgent) {
      priority += 100;
    }

    // Lower TTL = higher priority (about to expire)
    priority += (15 - header.hopTtl) * 10;

    // SOS messages get highest priority
    if (header.type.index <= 3) {
      // SOS types are 0-3
      priority += 200;
    }

    return priority;
  }

  @override
  String toString() {
    return 'RelayPolicy(maxAge: ${maxAgeMinutes}min)';
  }
}
