/// BitPack Mesh Controller
///
/// Integrates all mesh components for coordinated packet handling.
/// Provides high-level API for mesh networking operations.

library;

import 'dart:async';

import '../protocol/packet.dart';
import '../protocol/header/standard_header.dart';
import 'message_cache.dart';
import 'relay_backoff.dart';
import 'relay_policy.dart';

// ============================================================================
// MESH EVENTS
// ============================================================================

/// Event emitted by mesh controller
abstract class MeshEvent {}

/// Packet received for local processing
class PacketReceivedEvent extends MeshEvent {
  final Packet packet;
  final bool isNew;

  PacketReceivedEvent(this.packet, {this.isNew = true});
}

/// Packet was relayed
class PacketRelayedEvent extends MeshEvent {
  final Packet packet;

  PacketRelayedEvent(this.packet);
}

/// Relay was cancelled (duplicate heard)
class RelayCancelledEvent extends MeshEvent {
  final int messageId;

  RelayCancelledEvent(this.messageId);
}

/// Retry limit exceeded
class RetryExceededEvent extends MeshEvent {
  final int messageId;

  RetryExceededEvent(this.messageId);
}

// ============================================================================
// MESH CONTROLLER
// ============================================================================

/// Controller for mesh network operations
///
/// Coordinates message caching, relay policy, and backoff timing.
///
/// Example:
/// ```dart
/// final mesh = MeshController(
///   onBroadcast: (packet) async => bleAdapter.broadcast(packet.encode()),
/// );
///
/// // Handle incoming packet
/// bleAdapter.onReceive = (bytes) {
///   final packet = Packet.decode(bytes);
///   mesh.handleIncomingPacket(packet);
/// };
///
/// // Send new message
/// await mesh.broadcast(myPacket);
/// ```
class MeshController {
  /// Message cache for duplicate detection
  final MessageCache cache;

  /// Relay policy
  final RelayPolicy policy;

  /// Backoff controller
  final RelayBackoff backoff;

  /// Default TTL for new messages
  final int defaultTtl;

  /// Callback to broadcast packet
  final Future<void> Function(Packet packet)? onBroadcast;

  /// Event stream controller
  final StreamController<MeshEvent> _eventController =
      StreamController<MeshEvent>.broadcast();

  /// Statistics
  int _receivedCount = 0;
  int _relayedCount = 0;
  int _droppedCount = 0;

  MeshController({
    MessageCache? cache,
    RelayPolicy? policy,
    RelayBackoff? backoff,
    this.defaultTtl = 15,
    this.onBroadcast,
  })  : cache = cache ?? MessageCache(),
        policy = policy ?? RelayPolicy(),
        backoff = backoff ?? RelayBackoff();

  /// Stream of mesh events
  Stream<MeshEvent> get events => _eventController.stream;

  /// Total packets received
  int get receivedCount => _receivedCount;

  /// Total packets relayed
  int get relayedCount => _relayedCount;

  /// Total packets dropped (duplicates)
  int get droppedCount => _droppedCount;

  /// Handle incoming packet from mesh network
  ///
  /// - Checks for duplicates
  /// - Schedules relay if appropriate
  /// - Emits events for processing
  Future<void> handleIncomingPacket(Packet packet, {String? fromPeerId}) async {
    _receivedCount++;

    final header = packet.header;
    final messageId = header is StandardHeader ? header.messageId : 0;

    // Notify backoff system (may cancel pending relay)
    backoff.onPacketReceived(messageId);

    // Check for duplicate
    if (cache.hasSeen(messageId)) {
      _droppedCount++;
      _eventController.add(PacketReceivedEvent(packet, isNew: false));
      return;
    }

    // Mark as seen
    cache.markSeen(messageId);

    // Emit event for local processing
    _eventController.add(PacketReceivedEvent(packet, isNew: true));

    // Check if should relay
    if (header is StandardHeader && policy.shouldRelay(packet, cache)) {
      await _scheduleRelay(packet, fromPeerId);
    }
  }

  /// Broadcast a packet to the mesh network
  ///
  /// Call this for originating new messages.
  Future<void> broadcast(Packet packet) async {
    final header = packet.header;
    final messageId = header is StandardHeader ? header.messageId : 0;

    // Mark as seen (prevent echo)
    cache.markSeen(messageId);

    // Broadcast immediately (no backoff for originated messages)
    if (onBroadcast != null) {
      await onBroadcast!(packet);
    }
  }

  /// Schedule relay with backoff
  Future<void> _scheduleRelay(Packet packet, String? fromPeerId) async {
    final header = packet.header as StandardHeader;
    final messageId = header.messageId;

    // Mark relay source
    if (fromPeerId != null) {
      cache.markRelayedTo(messageId, fromPeerId);
    }

    // Prepare packet for relay
    final prepared = policy.prepareForRelay(packet);

    // Schedule with backoff
    final relayed = await backoff.scheduleRelay(
      messageId: messageId,
      currentTtl: header.hopTtl,
      originalTtl: defaultTtl,
      relayAction: () async {
        if (onBroadcast != null) {
          await onBroadcast!(prepared);
        }
      },
    );

    if (relayed) {
      _relayedCount++;
      _eventController.add(PacketRelayedEvent(prepared));
    } else {
      _eventController.add(RelayCancelledEvent(messageId));
    }
  }

  /// Cleanup expired cache entries
  int cleanup() {
    return cache.cleanup();
  }

  /// Cancel all pending relays
  void cancelAllRelays() {
    backoff.cancelAll();
  }

  /// Clear all state
  void clear() {
    cache.clear();
    backoff.clear();
    _receivedCount = 0;
    _relayedCount = 0;
    _droppedCount = 0;
  }

  /// Dispose resources
  void dispose() {
    backoff.clear();
    _eventController.close();
  }

  @override
  String toString() {
    return 'MeshController(received: $_receivedCount, relayed: $_relayedCount, '
        'dropped: $_droppedCount, cache: ${cache.size})';
  }
}
