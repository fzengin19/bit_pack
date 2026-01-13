/// Location Payload
///
/// GPS location sharing payload with optional altitude and accuracy.
/// Supports both compact (8 bytes) and extended (12+ bytes) modes.
///
/// Compact Layout (8 bytes):
/// ```
/// BYTES 0-3: LATITUDE (fixed-point int32)
/// BYTES 4-7: LONGITUDE (fixed-point int32)
/// ```
///
/// Extended Layout (12 bytes):
/// ```
/// BYTES 0-3:  LATITUDE (fixed-point int32)
/// BYTES 4-7:  LONGITUDE (fixed-point int32)
/// BYTES 8-9:  ALTITUDE (16 bits, signed, meters)
/// BYTES 10-11: ACCURACY (16 bits, 0-65535 meters)
/// ```

library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../core/types.dart';
import '../../encoding/gps.dart';
import 'payload.dart';

/// Location sharing payload
class LocationPayload extends Payload with CompactPayload, GeoPayload {
  /// Compact size (GPS only)
  static const int compactSize = 8;

  /// Extended size (GPS + altitude + accuracy)
  static const int extendedSize = 12;

  /// Latitude in degrees
  @override
  final double latitude;

  /// Longitude in degrees
  @override
  final double longitude;

  /// Altitude in meters (-32768 to 32767)
  @override
  final int? altitude;

  /// GPS accuracy in meters (0-65535)
  final int? accuracy;

  /// Timestamp when location was captured
  final DateTime? timestamp;

  /// Create a new location payload
  LocationPayload({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.timestamp,
  }) {
    // Validate coordinates
    if (!Gps.isValid(latitude, longitude)) {
      throw ArgumentError('Invalid coordinates: ($latitude, $longitude)');
    }

    // Validate altitude (signed 16-bit)
    if (altitude != null && (altitude! < -32768 || altitude! > 32767)) {
      throw ArgumentError('Altitude must be -32768 to 32767, got $altitude');
    }

    // Validate accuracy (unsigned 16-bit)
    if (accuracy != null && (accuracy! < 0 || accuracy! > 65535)) {
      throw ArgumentError('Accuracy must be 0-65535, got $accuracy');
    }
  }

  @override
  MessageType get type => MessageType.location;

  /// Check if this is extended mode (includes altitude/accuracy)
  bool get isExtended => altitude != null || accuracy != null;

  @override
  int get sizeInBytes => isExtended ? extendedSize : compactSize;

  @override
  Uint8List encode() {
    final size = sizeInBytes;
    final buffer = Uint8List(size);
    final data = ByteData.view(buffer.buffer);

    // BYTES 0-3: LATITUDE
    data.setInt32(0, Gps.encodeLatitude(latitude), Endian.big);

    // BYTES 4-7: LONGITUDE
    data.setInt32(4, Gps.encodeLongitude(longitude), Endian.big);

    if (isExtended) {
      // BYTES 8-9: ALTITUDE (signed 16-bit)
      data.setInt16(8, altitude ?? 0, Endian.big);

      // BYTES 10-11: ACCURACY (unsigned 16-bit)
      data.setUint16(10, accuracy ?? 0, Endian.big);
    }

    return buffer;
  }

  /// Decode location payload from bytes
  ///
  /// [extended] If true, expect extended format with altitude/accuracy
  factory LocationPayload.decode(Uint8List bytes, {bool extended = false}) {
    final expectedSize = extended ? extendedSize : compactSize;

    if (bytes.length < expectedSize) {
      throw DecodingException(
        'LocationPayload: insufficient data, expected $expectedSize, got ${bytes.length}',
      );
    }

    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes);

    // BYTES 0-3: LATITUDE
    final latFixed = data.getInt32(0, Endian.big);
    final latitude = Gps.decodeLatitude(latFixed);

    // BYTES 4-7: LONGITUDE
    final lonFixed = data.getInt32(4, Endian.big);
    final longitude = Gps.decodeLongitude(lonFixed);

    int? altitude;
    int? accuracy;

    if (extended && bytes.length >= extendedSize) {
      // BYTES 8-9: ALTITUDE
      final altValue = data.getInt16(8, Endian.big);
      if (altValue != 0) altitude = altValue;

      // BYTES 10-11: ACCURACY
      final accValue = data.getUint16(10, Endian.big);
      if (accValue != 0) accuracy = accValue;
    }

    return LocationPayload(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      accuracy: accuracy,
    );
  }

  @override
  LocationPayload copy() {
    return LocationPayload(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      accuracy: accuracy,
      timestamp: timestamp,
    );
  }

  @override
  String toString() {
    final parts = <String>['lat: $latitude', 'lon: $longitude'];
    if (altitude != null) parts.add('alt: ${altitude}m');
    if (accuracy != null) parts.add('acc: ${accuracy}m');
    return 'LocationPayload(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationPayload &&
        (other.latitude - latitude).abs() < 0.0000001 &&
        (other.longitude - longitude).abs() < 0.0000001 &&
        other.altitude == altitude &&
        other.accuracy == accuracy;
  }

  @override
  int get hashCode => Object.hash(
    latitude.toStringAsFixed(6),
    longitude.toStringAsFixed(6),
    altitude,
    accuracy,
  );
}
