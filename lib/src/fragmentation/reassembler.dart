/// BitPack Reassembler
///
/// Reassembles fragmented packets back into complete messages.
/// Handles out-of-order fragment arrival and timeout cleanup.

library;

import 'dart:typed_data';

import '../core/exceptions.dart';
import 'fragment_header.dart';

// ============================================================================
// FRAGMENT BUFFER
// ============================================================================

/// Buffer for collecting fragments of a single message
class FragmentBuffer {
  /// Message ID being reassembled
  final int messageId;

  /// Total number of fragments expected
  final int totalFragments;

  /// When this buffer was created
  final DateTime createdAt;

  /// Received fragments (key: fragment index, value: fragment data)
  final Map<int, Uint8List> fragments = {};

  /// Last activity time (used for timeout)
  DateTime lastActivity;

  FragmentBuffer({
    required this.messageId,
    required this.totalFragments,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastActivity = createdAt ?? DateTime.now();

  /// Check if all fragments have been received
  bool get isComplete => fragments.length == totalFragments;

  /// Number of fragments received
  int get receivedCount => fragments.length;

  /// Number of fragments still missing
  int get missingCount => totalFragments - fragments.length;

  /// Get list of missing fragment indices
  List<int> get missingIndices {
    final missing = <int>[];
    for (int i = 0; i < totalFragments; i++) {
      if (!fragments.containsKey(i)) {
        missing.add(i);
      }
    }
    return missing;
  }

  /// Check if we have all fragments from 0 to [upTo] (exclusive)
  bool hasAllUpTo(int upTo) {
    for (int i = 0; i < upTo; i++) {
      if (!fragments.containsKey(i)) return false;
    }
    return true;
  }

  /// Add a fragment to the buffer
  ///
  /// Returns true if this was a new fragment, false if duplicate.
  bool addFragment(int index, Uint8List data) {
    if (fragments.containsKey(index)) {
      return false; // Duplicate
    }
    fragments[index] = data;
    lastActivity = DateTime.now();
    return true;
  }

  /// Reassemble all fragments into complete data
  ///
  /// Throws [MissingFragmentException] if not all fragments received.
  Uint8List reassemble() {
    if (!isComplete) {
      final missing = missingIndices;
      throw MissingFragmentException(
        messageId: messageId,
        fragmentIndex: missing.first,
      );
    }

    // Calculate total size
    int totalSize = 0;
    for (int i = 0; i < totalFragments; i++) {
      totalSize += fragments[i]!.length;
    }

    // Combine fragments in order
    final result = Uint8List(totalSize);
    int offset = 0;
    for (int i = 0; i < totalFragments; i++) {
      final fragment = fragments[i]!;
      result.setRange(offset, offset + fragment.length, fragment);
      offset += fragment.length;
    }

    return result;
  }

  @override
  String toString() {
    return 'FragmentBuffer(msgId: 0x${messageId.toRadixString(16)}, '
        '${fragments.length}/$totalFragments)';
  }
}

// ============================================================================
// REASSEMBLER
// ============================================================================

/// Reassembles fragmented packets
///
/// Example:
/// ```dart
/// final reassembler = Reassembler(timeout: Duration(minutes: 5));
///
/// // As fragments arrive
/// final result = reassembler.addFragment(
///   messageId: msg.messageId,
///   fragmentIndex: fragHeader.fragmentIndex,
///   totalFragments: fragHeader.totalFragments,
///   data: fragmentPayload,
/// );
///
/// if (result != null) {
///   // Complete message reassembled
///   handleComplete(result);
/// }
///
/// // Periodically cleanup
/// reassembler.cleanup();
/// ```
class Reassembler {
  /// Active fragment buffers (key: message ID)
  final Map<int, FragmentBuffer> _buffers = {};

  /// Timeout for incomplete reassembly
  final Duration timeout;

  /// Maximum number of concurrent reassembly buffers
  final int maxBuffers;

  /// Callback when a buffer times out (optional, for NACK support)
  final void Function(FragmentBuffer buffer)? onTimeout;

  Reassembler({
    this.timeout = const Duration(minutes: 5),
    this.maxBuffers = 100,
    this.onTimeout,
  });

  /// Number of active reassembly buffers
  int get activeBufferCount => _buffers.length;

  /// Add a fragment and attempt reassembly
  ///
  /// [messageId] Original message ID (from packet header)
  /// [fragmentIndex] Index of this fragment (from FragmentHeader)
  /// [totalFragments] Total fragments expected (from FragmentHeader)
  /// [data] Fragment payload bytes
  ///
  /// Returns complete reassembled data if all fragments received,
  /// null if still waiting for more fragments.
  ///
  /// Throws [FragmentationException] on errors.
  Uint8List? addFragment({
    required int messageId,
    required int fragmentIndex,
    required int totalFragments,
    required Uint8List data,
  }) {
    // Validate
    if (fragmentIndex < 0 || fragmentIndex >= totalFragments) {
      throw FragmentationException(
        'Invalid fragment index: $fragmentIndex (total: $totalFragments)',
      );
    }

    // Get or create buffer
    final buffer = _buffers.putIfAbsent(
      messageId,
      () => _createBuffer(messageId, totalFragments),
    );

    // Verify total fragments matches
    if (buffer.totalFragments != totalFragments) {
      throw FragmentationException(
        'Fragment count mismatch for message 0x${messageId.toRadixString(16)}: '
        'expected ${buffer.totalFragments}, got $totalFragments',
      );
    }

    // Add fragment
    buffer.addFragment(fragmentIndex, data);

    // Check if complete
    if (buffer.isComplete) {
      _buffers.remove(messageId);
      return buffer.reassemble();
    }

    return null;
  }

  /// Add fragment from a FragmentHeader
  ///
  /// Convenience method that extracts info from FragmentHeader.
  Uint8List? addFragmentWithHeader({
    required int messageId,
    required FragmentHeader header,
    required Uint8List data,
  }) {
    return addFragment(
      messageId: messageId,
      fragmentIndex: header.fragmentIndex,
      totalFragments: header.totalFragments,
      data: data,
    );
  }

  /// Check if a message is being reassembled
  bool hasBuffer(int messageId) => _buffers.containsKey(messageId);

  /// Get reassembly progress for a message
  ///
  /// Returns null if no buffer exists for the message.
  ({int received, int total})? getProgress(int messageId) {
    final buffer = _buffers[messageId];
    if (buffer == null) return null;
    return (received: buffer.receivedCount, total: buffer.totalFragments);
  }

  /// Clean up expired buffers
  ///
  /// Should be called periodically (e.g., every 30 seconds).
  /// Returns number of buffers removed.
  int cleanup() {
    final now = DateTime.now();
    final expired = <int>[];

    for (final entry in _buffers.entries) {
      if (now.difference(entry.value.createdAt) > timeout) {
        expired.add(entry.key);
        onTimeout?.call(entry.value);
      }
    }

    for (final messageId in expired) {
      _buffers.remove(messageId);
    }

    return expired.length;
  }

  /// Force remove a buffer (e.g., on permanent failure)
  void removeBuffer(int messageId) {
    _buffers.remove(messageId);
  }

  /// Clear all buffers
  void clear() {
    _buffers.clear();
  }

  /// Create a new buffer, evicting oldest if at capacity
  FragmentBuffer _createBuffer(int messageId, int totalFragments) {
    // Evict oldest if at capacity
    if (_buffers.length >= maxBuffers) {
      _evictOldest();
    }

    return FragmentBuffer(
      messageId: messageId,
      totalFragments: totalFragments,
    );
  }

  /// Evict the oldest buffer
  void _evictOldest() {
    if (_buffers.isEmpty) return;

    int? oldest;
    DateTime? oldestTime;

    for (final entry in _buffers.entries) {
      if (oldest == null || entry.value.createdAt.isBefore(oldestTime!)) {
        oldest = entry.key;
        oldestTime = entry.value.createdAt;
      }
    }

    if (oldest != null) {
      final buffer = _buffers.remove(oldest);
      if (buffer != null) {
        onTimeout?.call(buffer);
      }
    }
  }

  @override
  String toString() {
    return 'Reassembler(buffers: ${_buffers.length}, timeout: $timeout)';
  }
}
