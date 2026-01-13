/// Payload Base Class
///
/// Abstract interface for all payload types in the BitPack protocol.
/// Each payload has a specific MessageType and can be encoded/decoded.

library;

import 'dart:typed_data';

import '../../core/types.dart';

/// Abstract base class for all payload types
abstract class Payload {
  /// Get the message type for this payload
  MessageType get type;

  /// Get the encoded size in bytes
  int get sizeInBytes;

  /// Encode payload to bytes
  Uint8List encode();

  /// Create a copy of this payload
  Payload copy();
}

/// Mixin for payloads that support compact mode (BLE 4.2)
mixin CompactPayload on Payload {
  /// Maximum size for compact mode (16 bytes = 20 MTU - 4 header)
  static const int maxCompactSize = 16;

  /// Check if this payload fits in compact mode
  bool get fitsCompactMode => sizeInBytes <= maxCompactSize;
}

/// Mixin for payloads that include GPS coordinates
mixin GeoPayload on Payload {
  /// Latitude in degrees (-90 to +90)
  double get latitude;

  /// Longitude in degrees (-180 to +180)
  double get longitude;

  /// Optional altitude in meters
  int? get altitude;
}
