/// BitPack Peer Registry
///
/// Tracks BLE peers in mesh network for connection management and analytics.

library;

// ============================================================================
// PEER INFO
// ============================================================================

/// Information about a discovered peer
class PeerInfo {
  /// Unique peer identifier (BLE address or custom ID)
  final String peerId;

  /// When this peer was first discovered
  final DateTime firstSeen;

  /// When this peer was last seen
  DateTime lastSeen;

  /// Last known RSSI (signal strength)
  int? rssi;

  /// Number of messages received from this peer
  int messageCount;

  /// Number of messages relayed to this peer
  int relayCount;

  /// Custom metadata
  final Map<String, dynamic> metadata;

  PeerInfo({
    required this.peerId,
    DateTime? firstSeen,
    DateTime? lastSeen,
    this.rssi,
    this.messageCount = 0,
    this.relayCount = 0,
    Map<String, dynamic>? metadata,
  })  : firstSeen = firstSeen ?? DateTime.now(),
        lastSeen = lastSeen ?? DateTime.now(),
        metadata = metadata ?? {};

  /// Update last seen timestamp
  void touch() {
    lastSeen = DateTime.now();
  }

  /// Duration since first seen
  Duration get age => DateTime.now().difference(firstSeen);

  /// Duration since last seen
  Duration get idleTime => DateTime.now().difference(lastSeen);

  /// Check if peer is considered active
  bool isActive(Duration threshold) {
    return idleTime <= threshold;
  }

  /// Check if peer has good signal strength
  bool get hasGoodSignal => rssi != null && rssi! >= -70;

  /// Signal quality category
  String get signalQuality {
    if (rssi == null) return 'unknown';
    if (rssi! >= -50) return 'excellent';
    if (rssi! >= -70) return 'good';
    if (rssi! >= -85) return 'fair';
    return 'poor';
  }

  @override
  String toString() {
    return 'PeerInfo($peerId, msgs: $messageCount, rssi: $rssi, '
        'idle: ${idleTime.inSeconds}s)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PeerInfo && other.peerId == peerId;
  }

  @override
  int get hashCode => peerId.hashCode;
}

// ============================================================================
// PEER REGISTRY
// ============================================================================

/// Registry for tracking BLE peers in mesh network
///
/// Provides:
/// - Peer discovery tracking
/// - Signal strength monitoring
/// - Message counting
/// - Active peer filtering
///
/// Example:
/// ```dart
/// final registry = PeerRegistry();
///
/// // When a peer is discovered
/// registry.register('AA:BB:CC:DD:EE:FF', rssi: -65);
///
/// // When a message is received
/// registry.recordMessage('AA:BB:CC:DD:EE:FF', messageId);
///
/// // Get active peers for relay
/// final activePeers = registry.getActivePeers(Duration(minutes: 5));
/// ```
class PeerRegistry {
  /// Maximum number of peers to track
  final int maxPeers;

  /// Maximum number of message IDs to track (prevents memory leak)
  final int maxTrackedMessages;

  /// Default activity threshold
  final Duration activityThreshold;

  /// Registered peers
  final Map<String, PeerInfo> _peers = {};

  /// Message ID to peer mapping (for deduplication)
  final Map<int, Set<String>> _messagesSeen = {};

  /// Queue of message IDs for LRU eviction
  final List<int> _messageIdQueue = [];

  PeerRegistry({
    this.maxPeers = 1000,
    this.maxTrackedMessages = 10000,
    this.activityThreshold = const Duration(minutes: 10),
  });

  /// Number of registered peers
  int get peerCount => _peers.length;

  /// All peer IDs
  Iterable<String> get peerIds => _peers.keys;

  /// All peer info
  Iterable<PeerInfo> get peers => _peers.values;

  /// Register or update a peer
  ///
  /// Returns the peer info (created or updated).
  PeerInfo register(String peerId, {int? rssi}) {
    final existing = _peers[peerId];

    if (existing != null) {
      existing.touch();
      if (rssi != null) existing.rssi = rssi;
      return existing;
    }

    // Evict oldest peer if at capacity
    if (_peers.length >= maxPeers) {
      _evictOldest();
    }

    final peer = PeerInfo(peerId: peerId, rssi: rssi);
    _peers[peerId] = peer;
    return peer;
  }

  /// Record that a message was received from a peer
  void recordMessage(String peerId, int messageId) {
    final peer = _peers[peerId];
    if (peer != null) {
      peer.messageCount++;
      peer.touch();
    }

    // Track message source with LRU eviction
    if (!_messagesSeen.containsKey(messageId)) {
      // Evict oldest message IDs if at capacity
      while (_messageIdQueue.length >= maxTrackedMessages) {
        final oldestId = _messageIdQueue.removeAt(0);
        _messagesSeen.remove(oldestId);
      }
      _messageIdQueue.add(messageId);
    }
    _messagesSeen.putIfAbsent(messageId, () => {}).add(peerId);
  }

  /// Record that a message was relayed to a peer
  void recordRelay(String peerId, int messageId) {
    final peer = _peers[peerId];
    if (peer != null) {
      peer.relayCount++;
      peer.touch();
    }
  }

  /// Get peers who have seen a specific message
  Set<String> getPeersWithMessage(int messageId) {
    return _messagesSeen[messageId] ?? {};
  }

  /// Get info for a specific peer
  PeerInfo? get(String peerId) => _peers[peerId];

  /// Check if peer is registered
  bool contains(String peerId) => _peers.containsKey(peerId);

  /// Get all active peers
  List<PeerInfo> getActivePeers([Duration? threshold]) {
    threshold ??= activityThreshold;
    return _peers.values.where((p) => p.isActive(threshold!)).toList();
  }

  /// Get peers sorted by signal strength (best first)
  List<PeerInfo> getPeersBySignal() {
    final withRssi = _peers.values.where((p) => p.rssi != null).toList();
    withRssi.sort((a, b) => (b.rssi ?? -100).compareTo(a.rssi ?? -100));
    return withRssi;
  }

  /// Get peers sorted by message count (most active first)
  List<PeerInfo> getPeersByActivity() {
    final sorted = _peers.values.toList();
    sorted.sort((a, b) => b.messageCount.compareTo(a.messageCount));
    return sorted;
  }

  /// Remove a specific peer
  bool remove(String peerId) {
    return _peers.remove(peerId) != null;
  }

  /// Remove inactive peers
  ///
  /// Returns number of peers removed.
  int cleanup([Duration? threshold]) {
    threshold ??= activityThreshold;
    final toRemove = <String>[];

    for (final peer in _peers.values) {
      if (!peer.isActive(threshold)) {
        toRemove.add(peer.peerId);
      }
    }

    for (final id in toRemove) {
      _peers.remove(id);
    }

    // Also cleanup old message tracking
    _cleanupMessageTracking();

    return toRemove.length;
  }

  /// Clear all peers
  void clear() {
    _peers.clear();
    _messagesSeen.clear();
    _messageIdQueue.clear();
  }

  /// Evict the oldest (least recently seen) peer
  void _evictOldest() {
    if (_peers.isEmpty) return;

    String? oldest;
    DateTime? oldestTime;

    for (final entry in _peers.entries) {
      if (oldestTime == null || entry.value.lastSeen.isBefore(oldestTime)) {
        oldest = entry.key;
        oldestTime = entry.value.lastSeen;
      }
    }

    if (oldest != null) {
      _peers.remove(oldest);
    }
  }

  /// Cleanup message tracking (keep only recent entries)
  void _cleanupMessageTracking() {
    // Keep only messages from active peers
    final activePeerIds = getActivePeers().map((p) => p.peerId).toSet();

    _messagesSeen.removeWhere((_, peers) {
      peers.retainWhere(activePeerIds.contains);
      return peers.isEmpty;
    });
  }

  /// Get statistics
  Map<String, dynamic> get stats => {
        'totalPeers': peerCount,
        'activePeers': getActivePeers().length,
        'totalMessages': _peers.values.fold(0, (s, p) => s + p.messageCount),
        'avgRssi': _calculateAvgRssi(),
      };

  double? _calculateAvgRssi() {
    final withRssi = _peers.values.where((p) => p.rssi != null).toList();
    if (withRssi.isEmpty) return null;
    final sum = withRssi.fold(0, (s, p) => s + (p.rssi ?? 0));
    return sum / withRssi.length;
  }

  @override
  String toString() {
    return 'PeerRegistry(peers: $peerCount, active: ${getActivePeers().length})';
  }
}
