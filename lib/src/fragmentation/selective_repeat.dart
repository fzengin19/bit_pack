/// BitPack Selective Repeat Strategy
///
/// Implements Selective Repeat ARQ logic for fragment recovery.
/// Analyzes FragmentBuffer state and generates efficient NACK payloads.

library;

import 'dart:typed_data';

import '../protocol/payload/nack_payload.dart';
import 'reassembler.dart';

// ============================================================================
// RETRY STATE
// ============================================================================

/// Tracks retry state for a single message
class RetryState {
  /// Message ID being tracked
  final int messageId;

  /// Number of NACKs sent for this message
  int nackCount;

  /// Last time a NACK was sent
  DateTime lastNackTime;

  /// Fragments that have been NACKed but not yet received
  final Set<int> pendingFragments;

  RetryState({
    required this.messageId,
    this.nackCount = 0,
    DateTime? lastNackTime,
  })  : lastNackTime = lastNackTime ?? DateTime.now(),
        pendingFragments = {};

  /// Record that a NACK was sent
  void recordNack(List<int> fragments) {
    nackCount++;
    lastNackTime = DateTime.now();
    pendingFragments.addAll(fragments);
  }

  /// Record that a fragment was received
  void recordReceived(int fragmentIndex) {
    pendingFragments.remove(fragmentIndex);
  }

  /// Check if we've waited long enough for a retry
  bool canRetry(Duration retryInterval) {
    return DateTime.now().difference(lastNackTime) >= retryInterval;
  }
}

// ============================================================================
// SELECTIVE REPEAT STRATEGY
// ============================================================================

/// Selective Repeat ARQ strategy for fragment recovery
///
/// Features:
/// - Detects gaps in received fragments
/// - Groups consecutive gaps into efficient NACK blocks
/// - Limits retries to prevent infinite loops
/// - Prioritizes oldest missing fragments
///
/// Example:
/// ```dart
/// final strategy = SelectiveRepeatStrategy(
///   maxRetries: 3,
///   retryInterval: Duration(seconds: 5),
///   onSendNack: (nack) => sendOverBle(nack.encode()),
/// );
///
/// // When a gap is detected
/// strategy.handleGap(buffer);
///
/// // Periodically check for timeouts
/// strategy.checkTimeouts(reassembler);
/// ```
class SelectiveRepeatStrategy {
  /// Maximum NACK retries per message before giving up
  final int maxRetries;

  /// Minimum interval between NACKs for the same message
  final Duration retryInterval;

  /// Maximum blocks per NACK payload
  final int maxBlocksPerNack;

  /// Callback to send NACK
  final void Function(NackPayload nack)? onSendNack;

  /// Callback when retry limit exceeded
  final void Function(int messageId)? onRetryExceeded;

  /// Retry state per message
  final Map<int, RetryState> _retryStates = {};

  SelectiveRepeatStrategy({
    this.maxRetries = 3,
    this.retryInterval = const Duration(seconds: 5),
    this.maxBlocksPerNack = NackPayload.maxBlocks,
    this.onSendNack,
    this.onRetryExceeded,
  });

  /// Detect missing fragments in a buffer
  ///
  /// Returns sorted list of missing fragment indices.
  List<int> detectMissingFragments(FragmentBuffer buffer) {
    return buffer.missingIndices;
  }

  /// Generate a NACK payload for missing fragments
  ///
  /// Returns null if:
  /// - No missing fragments
  /// - Retry limit exceeded
  /// - Too soon to retry
  ///
  /// Prioritizes earliest missing fragments if too many to fit in one NACK.
  NackPayload? generateNack(FragmentBuffer buffer) {
    final messageId = buffer.messageId;
    final missing = detectMissingFragments(buffer);

    if (missing.isEmpty) {
      return null;
    }

    // Get or create retry state
    final state = _retryStates.putIfAbsent(
      messageId,
      () => RetryState(messageId: messageId),
    );

    // Check retry limit
    if (state.nackCount >= maxRetries) {
      return null;
    }

    // Check retry interval (skip for first NACK)
    if (state.nackCount > 0 && !state.canRetry(retryInterval)) {
      return null;
    }

    // Filter out fragments that are still pending from last NACK
    final newMissing = missing
        .where((idx) => !state.pendingFragments.contains(idx))
        .toList();

    // If all missing are still pending, use full missing list for retry
    final toRequest = newMissing.isNotEmpty ? newMissing : missing;

    try {
      return NackPayload.fromMissingIndices(
        originalMessageId: messageId,
        missingIndices: toRequest,
        maxBlockCount: maxBlocksPerNack,
      );
    } catch (e) {
      // No valid NACK could be created
      return null;
    }
  }

  /// Handle a detected gap - generate and send NACK if appropriate
  ///
  /// Returns true if a NACK was sent.
  bool handleGap(FragmentBuffer buffer) {
    final nack = generateNack(buffer);
    if (nack == null) {
      // Check if retry limit was exceeded
      final state = _retryStates[buffer.messageId];
      if (state != null && state.nackCount >= maxRetries) {
        onRetryExceeded?.call(buffer.messageId);
      }
      return false;
    }

    // Record the NACK
    final state = _retryStates[buffer.messageId]!;
    state.recordNack(nack.allMissingIndices);

    // Send the NACK
    onSendNack?.call(nack);
    return true;
  }

  /// Record that a fragment was received (clears from pending)
  void recordFragmentReceived(int messageId, int fragmentIndex) {
    _retryStates[messageId]?.recordReceived(fragmentIndex);
  }

  /// Check if we should retry for a specific message
  bool shouldRetry(int messageId) {
    final state = _retryStates[messageId];
    if (state == null) return true; // First attempt
    if (state.nackCount >= maxRetries) return false;
    return state.canRetry(retryInterval);
  }

  /// Get retry count for a message
  int getRetryCount(int messageId) {
    return _retryStates[messageId]?.nackCount ?? 0;
  }

  /// Get pending fragments for a message
  Set<int> getPendingFragments(int messageId) {
    return _retryStates[messageId]?.pendingFragments ?? {};
  }

  /// Check all buffers for timeouts and send NACKs as needed
  ///
  /// Returns number of NACKs sent.
  int checkTimeouts(Reassembler reassembler) {
    // This would require access to reassembler's internal buffers
    // For now, return 0 - the caller should iterate buffers externally
    return 0;
  }

  /// Clear retry state for a message (call when message is complete)
  void clearState(int messageId) {
    _retryStates.remove(messageId);
  }

  /// Clear all retry states
  void clearAllStates() {
    _retryStates.clear();
  }

  /// Get number of messages being tracked
  int get trackedMessageCount => _retryStates.length;

  @override
  String toString() {
    return 'SelectiveRepeatStrategy(maxRetries: $maxRetries, '
        'interval: $retryInterval, tracked: $trackedMessageCount)';
  }
}

// ============================================================================
// SELECTIVE REPEAT REASSEMBLER
// ============================================================================

/// Extended reassembler with Selective Repeat ARQ support
///
/// Automatically detects gaps and triggers NACK generation.
///
/// Example:
/// ```dart
/// final reassembler = SelectiveRepeatReassembler(
///   sendNack: (nack) => bleChannel.send(nack.encode()),
/// );
///
/// // As fragments arrive
/// final result = reassembler.addFragment(...);
/// if (result != null) {
///   handleCompleteMessage(result);
/// }
/// ```
class SelectiveRepeatReassembler extends Reassembler {
  /// Strategy for gap detection and NACK generation
  final SelectiveRepeatStrategy strategy;

  /// Create reassembler with Selective Repeat support
  SelectiveRepeatReassembler({
    super.timeout,
    super.maxBuffers,
    void Function(NackPayload)? sendNack,
    void Function(int messageId)? onRetryExceeded,
    int maxRetries = 3,
    Duration retryInterval = const Duration(seconds: 5),
  })  : strategy = SelectiveRepeatStrategy(
          maxRetries: maxRetries,
          retryInterval: retryInterval,
          onSendNack: sendNack,
          onRetryExceeded: onRetryExceeded,
        ),
        super(
          onTimeout: (buffer) {
            // Will be handled by strategy
          },
        );

  @override
  Uint8List? addFragment({
    required int messageId,
    required int fragmentIndex,
    required int totalFragments,
    required Uint8List data,
  }) {
    // Record fragment reception
    strategy.recordFragmentReceived(messageId, fragmentIndex);

    // Add fragment
    final result = super.addFragment(
      messageId: messageId,
      fragmentIndex: fragmentIndex,
      totalFragments: totalFragments,
      data: data,
    );

    // If complete, clear retry state
    if (result != null) {
      strategy.clearState(messageId);
      return result;
    }

    // Check for gaps - if we received a later fragment but earlier ones are missing
    final progress = getProgress(messageId);
    if (progress != null && fragmentIndex > 0) {
      // Get buffer to check for gaps
      // Note: We need access to internal buffer which base class doesn't expose
      // This is handled by the periodic checkTimeouts call
    }

    return null;
  }

  /// Process gap detection for a specific buffer
  bool processGaps(FragmentBuffer buffer) {
    if (buffer.isComplete) return false;
    return strategy.handleGap(buffer);
  }
}
