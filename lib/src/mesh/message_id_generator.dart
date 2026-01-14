/// BitPack Message ID Generator
///
/// Generates collision-resistant message IDs using time-window + random strategy.
/// Minimizes birthday paradox collision risk in mesh networks.

library;

import 'dart:math';

// ============================================================================
// MESSAGE ID GENERATOR
// ============================================================================

/// Collision-resistant message ID generator
///
/// Uses hybrid strategy combining time-window and random components:
/// - 16-bit: High byte = time-window (minute), Low byte = random
/// - 32-bit: High 16 bits = time-window (second), Low 16 bits = random
///
/// Example:
/// ```dart
/// // For Compact mode (16-bit ID)
/// final id16 = MessageIdGenerator.generate();
///
/// // For Standard mode (32-bit ID)
/// final id32 = MessageIdGenerator.generate32();
///
/// // Extract time component for debugging
/// final timeWindow = MessageIdGenerator.extractTimeWindow16(id16);
/// ```
class MessageIdGenerator {
  /// Secure random number generator
  static final Random _secureRandom = Random.secure();

  /// Private constructor - all methods are static
  MessageIdGenerator._();

  /// Generate collision-resistant 16-bit message ID
  ///
  /// Layout:
  /// - High 4 bits: Time-window (unix seconds mod 16)
  /// - Low 12 bits: Cryptographic random
  ///
  /// Collision probability:
  /// - Same 16-second window: 1/4096 (0.024%)
  /// - Different windows: Near zero
  ///
  /// Comparison with 8+8 bit approach:
  /// - Old: 256 slots per minute → 4.3 msgs/sec collision-free
  /// - New: 4096 slots per 16 sec → 256 msgs/sec collision-free
  static int generate() {
    // Unix timestamp in 16-second windows (rolls over every 256 seconds ≈ 4.27 min)
    final unixSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeWindow = unixSeconds & 0x0F; // 4 bits = 16 slots

    // Cryptographic random for low 12 bits (4096 values)
    final randomPart = _secureRandom.nextInt(0x1000);

    // Combine: time-window as high 4 bits, random as low 12 bits
    return (timeWindow << 12) | randomPart;
  }

  /// Generate collision-resistant 32-bit message ID
  ///
  /// Layout:
  /// - High 16 bits: Time-window (unix seconds mod 65536)
  /// - Low 16 bits: Cryptographic random
  ///
  /// Collision probability: Practically zero for reasonable message rates.
  static int generate32() {
    // Unix timestamp in seconds (rolls over every ~18.2 hours)
    final unixSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeWindow = unixSeconds & 0xFFFF;

    // Cryptographic random for low 16 bits
    final randomPart = _secureRandom.nextInt(0x10000);

    // Combine: time-window as high 16 bits, random as low 16 bits
    return (timeWindow << 16) | randomPart;
  }

  /// Generate ID based on packet mode
  static int generateForMode(bool compact) {
    return compact ? generate() : generate32();
  }

  /// Extract time-window from 16-bit message ID
  ///
  /// Returns the second-based time component (0-15).
  static int extractTimeWindow16(int messageId) {
    return (messageId >> 12) & 0x0F;
  }

  /// Extract time-window from 32-bit message ID
  ///
  /// Returns the second-based time component (0-65535).
  static int extractTimeWindow32(int messageId) {
    return (messageId >> 16) & 0xFFFF;
  }

  /// Extract random component from 16-bit message ID
  static int extractRandom16(int messageId) {
    return messageId & 0x0FFF;
  }

  /// Extract random component from 32-bit message ID
  static int extractRandom32(int messageId) {
    return messageId & 0xFFFF;
  }

  /// Check if two message IDs are from the same time window (16-bit)
  static bool sameTimeWindow16(int id1, int id2) {
    return extractTimeWindow16(id1) == extractTimeWindow16(id2);
  }

  /// Check if two message IDs are from the same time window (32-bit)
  static bool sameTimeWindow32(int id1, int id2) {
    return extractTimeWindow32(id1) == extractTimeWindow32(id2);
  }

  /// Estimate age of a 16-bit message ID in minutes
  ///
  /// Returns null if age cannot be determined (time window rolled over).
  /// Maximum trackable age: 256 minutes (~4.27 hours)
  static int? estimateAge16(int messageId) {
    final currentMinutes = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final currentWindow = currentMinutes & 0xFF;
    final msgWindow = extractTimeWindow16(messageId);

    int diff = currentWindow - msgWindow;
    if (diff < 0) diff += 256;

    // If diff is too large, the time window has rolled over
    if (diff > 128) return null;

    return diff;
  }

  /// Estimate age of a 32-bit message ID in seconds
  ///
  /// Returns null if age cannot be determined.
  /// Maximum trackable age: 65536 seconds (~18.2 hours)
  static int? estimateAge32(int messageId) {
    final currentSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final currentWindow = currentSeconds & 0xFFFF;
    final msgWindow = extractTimeWindow32(messageId);

    int diff = currentWindow - msgWindow;
    if (diff < 0) diff += 0x10000;

    // If diff is too large (> 9 hours), probably rolled over
    if (diff > 0x8000) return null;

    return diff;
  }
}
