/// BitPack Relay Policy
///
/// Decides whether a packet should be relayed and prepares it for relay.

library;

import '../core/types.dart';
import '../protocol/header/compact_header.dart';
import '../protocol/header/standard_header.dart';
import '../protocol/packet.dart';

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
  bool shouldRelay(Packet packet) {
    final header = packet.header;

    // 1. MESH flag must be set
    if (!header.flags.mesh) return false;

    // 2. TTL must be > 0
    if (header.ttl <= 0) return false;

    // 3. Must not be expired (age-based applies to Standard)
    if (header is StandardHeader) {
      if (header.currentAgeMinutes >= maxAgeMinutes) return false;
      if (header.isExpired) return false;
    } else {
      if (header.isExpired) return false;
    }

    return true;
  }

  /// Prepare packet for relay
  ///
  /// - Decrements TTL
  /// - Updates age (if significantly delayed)
  ///
  /// Returns a new packet ready for relay.
  Packet prepareForRelay(Packet packet) {
    final header = packet.header;

    if (header is CompactHeader) {
      final newHeader = header.decrementTtl();
      return Packet(
        header: newHeader,
        payload: packet.payload,
      );
    }

    if (header is StandardHeader) {
      final newHeader = header.prepareForRelay();
      return Packet(
        header: newHeader,
        payload: packet.payload,
      );
    }

    throw UnsupportedError('Unsupported header type: ${header.runtimeType}');
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
    int priority = 0;

    // Urgent messages get high priority
    if (header.flags.urgent) {
      priority += 100;
    }

    // Lower TTL = higher priority (about to expire)
    final ttlForPriority = header.ttl.clamp(0, 15);
    priority += (15 - ttlForPriority) * 10;

    // SOS messages get highest priority
    if (header.type == MessageType.sosBeacon) {
      priority += 200;
    }

    return priority;
  }

  @override
  String toString() {
    return 'RelayPolicy(maxAge: ${maxAgeMinutes}min)';
  }
}
