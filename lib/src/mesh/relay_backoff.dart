/// BitPack Relay Backoff
///
/// Broadcast storm prevention using randomized exponential backoff.
/// Prevents all mesh nodes from relaying simultaneously.

library;

import 'dart:async';
import 'dart:math';

// ============================================================================
// RELAY BACKOFF
// ============================================================================

/// Broadcast storm prevention with randomized exponential backoff
///
/// When a packet is received for relay:
/// 1. Calculate random delay based on hop count
/// 2. Wait for the delay
/// 3. If duplicate heard during wait, cancel relay
/// 4. Otherwise, relay the packet
///
/// Example:
/// ```dart
/// final backoff = RelayBackoff();
///
/// // Schedule relay with backoff
/// final relayed = await backoff.scheduleRelay(
///   messageId: packet.header.messageId,
///   currentTtl: packet.header.ttl,
///   originalTtl: 15,
///   relayAction: () async => broadcast(packet),
/// );
///
/// // When duplicate heard
/// backoff.cancelRelay(messageId);
/// ```
class RelayBackoff {
  /// Base delay in milliseconds
  final int baseDelayMs;

  /// Maximum delay in milliseconds
  final int maxDelayMs;

  /// Jitter percentage (0.0 to 1.0)
  final double jitterPercent;

  /// Multiplier per hop
  final double hopMultiplier;

  /// Random number generator
  final Random _random;

  /// Messages currently scheduled for relay
  final Set<int> _pendingRelays = {};

  /// Messages that should be cancelled
  final Set<int> _cancelledRelays = {};

  /// Active timers for pending relays
  final Map<int, Completer<void>> _pendingCompleters = {};

  RelayBackoff({
    this.baseDelayMs = 50,
    this.maxDelayMs = 2000,
    this.jitterPercent = 0.2,
    this.hopMultiplier = 1.5,
    Random? random,
  }) : _random = random ?? Random();

  /// Number of pending relay operations
  int get pendingCount => _pendingRelays.length;

  /// Check if a message is pending relay
  bool isPending(int messageId) => _pendingRelays.contains(messageId);

  /// Calculate backoff delay based on TTL
  ///
  /// Higher hop count (further from origin) = shorter delay
  /// This gives priority to nodes closer to destination.
  Duration calculateDelay(int currentTtl, int originalTtl) {
    // Hop count = how many times this message has been relayed
    final hopCount = originalTtl - currentTtl;

    // Exponential increase with hop count
    final baseMs = baseDelayMs * pow(hopMultiplier, hopCount);

    // Random selection within range [baseDelayMs, baseMs]
    final range = baseMs.toInt().clamp(baseDelayMs, maxDelayMs);
    final delayMs = baseDelayMs + _random.nextInt(range - baseDelayMs + 1);

    // Add jitter (±jitterPercent)
    final jitterRange = delayMs * jitterPercent;
    final jitter = (jitterRange * (_random.nextDouble() * 2 - 1)).toInt();
    final finalDelayMs = (delayMs + jitter).clamp(baseDelayMs, maxDelayMs);

    return Duration(milliseconds: finalDelayMs);
  }

  /// Schedule relay with backoff delay
  ///
  /// Returns true if relay was executed, false if cancelled.
  ///
  /// [messageId] Unique message identifier
  /// [currentTtl] Current TTL of the packet
  /// [originalTtl] Original TTL (max hops)
  /// [relayAction] Async action to execute for relay
  Future<bool> scheduleRelay({
    required int messageId,
    required int currentTtl,
    required int originalTtl,
    required Future<void> Function() relayAction,
  }) async {
    // Already scheduled
    if (_pendingRelays.contains(messageId)) {
      return false;
    }

    _pendingRelays.add(messageId);
    final completer = Completer<void>();
    _pendingCompleters[messageId] = completer;

    final delay = calculateDelay(currentTtl, originalTtl);

    // Wait with possibility of early cancellation
    bool cancelled = false;
    await Future.any([
      Future.delayed(delay),
      completer.future.then((_) => cancelled = true),
    ]);

    // Check if cancelled (duplicate heard during wait)
    if (cancelled || _cancelledRelays.contains(messageId)) {
      _cancelledRelays.remove(messageId);
      _pendingRelays.remove(messageId);
      _pendingCompleters.remove(messageId);
      return false;
    }

    // Execute relay
    try {
      await relayAction();
    } finally {
      _pendingRelays.remove(messageId);
      _pendingCompleters.remove(messageId);
    }

    return true;
  }

  /// Cancel a pending relay
  ///
  /// Call this when a duplicate is heard during the backoff period.
  void cancelRelay(int messageId) {
    if (_pendingRelays.contains(messageId)) {
      _cancelledRelays.add(messageId);

      // Complete the pending completer to wake up the waiter
      final completer = _pendingCompleters[messageId];
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// Handle incoming packet (may cancel pending relays)
  ///
  /// Call this for every received packet to detect duplicates.
  void onPacketReceived(int messageId) {
    cancelRelay(messageId);
  }

  /// Cancel all pending relays
  void cancelAll() {
    for (final messageId in List.from(_pendingRelays)) {
      cancelRelay(messageId);
    }
  }

  /// Clear all state
  void clear() {
    cancelAll();
    _pendingRelays.clear();
    _cancelledRelays.clear();
    _pendingCompleters.clear();
  }

  @override
  String toString() {
    return 'RelayBackoff(pending: $pendingCount, base: ${baseDelayMs}ms, max: ${maxDelayMs}ms)';
  }
}
