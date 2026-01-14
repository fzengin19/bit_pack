/// BitPack Message Cache
///
/// LRU cache for duplicate message detection in mesh networks.
/// Tracks seen messages and relay history to prevent broadcast storms.

library;

import 'dart:collection';

// ============================================================================
// CACHE ENTRY
// ============================================================================

/// Entry in the message cache
class MessageCacheEntry {
  /// When this message was first seen
  final DateTime firstSeen;

  /// When this entry was last accessed
  DateTime lastAccess;

  /// Peers this message was relayed to
  final Set<String> relayedTo;

  MessageCacheEntry({
    DateTime? firstSeen,
  })  : firstSeen = firstSeen ?? DateTime.now(),
        lastAccess = firstSeen ?? DateTime.now(),
        relayedTo = {};

  /// Update last access time
  void touch() {
    lastAccess = DateTime.now();
  }

  /// Check if entry has expired
  bool isExpired(Duration ttl) {
    return DateTime.now().difference(firstSeen) > ttl;
  }
}

// ============================================================================
// MESSAGE CACHE
// ============================================================================

/// LRU cache for tracking seen messages
///
/// Used for:
/// - Duplicate detection (don't process same message twice)
/// - Relay tracking (don't relay to same peer twice)
/// - Broadcast storm prevention
///
/// Example:
/// ```dart
/// final cache = MessageCache(
///   maxSize: 10000,
///   ttl: Duration(hours: 24),
/// );
///
/// if (!cache.hasSeen(messageId)) {
///   cache.markSeen(messageId);
///   processMessage(packet);
/// }
/// ```
class MessageCache {
  /// Maximum number of entries to keep
  final int maxSize;

  /// Time-to-live for entries
  final Duration ttl;

  /// Cache storage (LinkedHashMap for LRU ordering)
  final LinkedHashMap<int, MessageCacheEntry> _cache = LinkedHashMap();

  /// Statistics
  int _hits = 0;
  int _misses = 0;

  MessageCache({
    this.maxSize = 10000,
    this.ttl = const Duration(hours: 24),
  });

  /// Number of entries in cache
  int get size => _cache.length;

  /// Cache hit count
  int get hits => _hits;

  /// Cache miss count
  int get misses => _misses;

  /// Hit ratio (0.0 to 1.0)
  double get hitRatio {
    final total = _hits + _misses;
    return total > 0 ? _hits / total : 0.0;
  }

  /// Check if message was seen before
  ///
  /// Returns true if message ID is in cache and not expired.
  bool hasSeen(int messageId) {
    final entry = _cache[messageId];

    if (entry == null) {
      _misses++;
      return false;
    }

    // Check expiry
    if (entry.isExpired(ttl)) {
      _cache.remove(messageId);
      _misses++;
      return false;
    }

    // Update LRU order
    entry.touch();
    _cache.remove(messageId);
    _cache[messageId] = entry;

    _hits++;
    return true;
  }

  /// Mark message as seen
  ///
  /// If already seen, just updates the access time.
  void markSeen(int messageId) {
    if (_cache.containsKey(messageId)) {
      final entry = _cache[messageId]!;
      entry.touch();
      // Move to end (most recently used)
      _cache.remove(messageId);
      _cache[messageId] = entry;
      return;
    }

    // Evict oldest if at capacity
    _evictIfNeeded();

    _cache[messageId] = MessageCacheEntry();
  }

  /// Get set of peer IDs this message was relayed to
  ///
  /// Returns empty set if message not in cache.
  Set<String> getRelayedTo(int messageId) {
    final entry = _cache[messageId];
    if (entry == null || entry.isExpired(ttl)) {
      return {};
    }
    return Set.unmodifiable(entry.relayedTo);
  }

  /// Mark message as relayed to a specific peer
  ///
  /// Creates entry if not exists.
  void markRelayedTo(int messageId, String peerId) {
    if (!_cache.containsKey(messageId)) {
      markSeen(messageId);
    }

    final entry = _cache[messageId]!;
    entry.relayedTo.add(peerId);
    entry.touch();
  }

  /// Check if message was already relayed to a specific peer
  bool wasRelayedTo(int messageId, String peerId) {
    final entry = _cache[messageId];
    if (entry == null || entry.isExpired(ttl)) {
      return false;
    }
    return entry.relayedTo.contains(peerId);
  }

  /// Get entry for a message (for inspection)
  MessageCacheEntry? getEntry(int messageId) {
    final entry = _cache[messageId];
    if (entry == null || entry.isExpired(ttl)) {
      return null;
    }
    return entry;
  }

  /// Remove a specific message from cache
  bool remove(int messageId) {
    return _cache.remove(messageId) != null;
  }

  /// Clean up expired entries
  ///
  /// Returns number of entries removed.
  int cleanup() {
    final expiredIds = <int>[];

    for (final entry in _cache.entries) {
      if (entry.value.isExpired(ttl)) {
        expiredIds.add(entry.key);
      }
    }

    for (final id in expiredIds) {
      _cache.remove(id);
    }

    return expiredIds.length;
  }

  /// Clear all entries
  void clear() {
    _cache.clear();
    _hits = 0;
    _misses = 0;
  }

  /// Evict oldest entries if at capacity
  void _evictIfNeeded() {
    while (_cache.length >= maxSize) {
      // LinkedHashMap iterates in insertion order
      // First key is the oldest
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
  }

  @override
  String toString() {
    return 'MessageCache(size: $size/$maxSize, hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%)';
  }
}
