/// GPS Fixed-Point Coordinate Encoding
///
/// Encodes GPS coordinates (latitude/longitude) as fixed-point integers
/// for compact binary transmission.
///
/// Precision: 7 decimal places (1.11cm at equator) using 32-bit integers
/// - Latitude: -90.0 to +90.0 → -900000000 to +900000000 (fits int32)
/// - Longitude: -180.0 to +180.0 → -1800000000 to +1800000000 (fits int32)
///
/// Total size: 8 bytes (4 lat + 4 lon)

library;

import 'dart:typed_data';

import '../core/constants.dart';
import '../core/exceptions.dart';

/// GPS coordinate encoder using fixed-point representation
class Gps {
  Gps._(); // Prevent instantiation

  /// Precision multiplier (10^7 = 7 decimal places)
  static const int precision = kGpsPrecision; // 10000000

  /// Minimum latitude (-90°)
  static const double minLatitude = kMinLatitude;

  /// Maximum latitude (+90°)
  static const double maxLatitude = kMaxLatitude;

  /// Minimum longitude (-180°)
  static const double minLongitude = kMinLongitude;

  /// Maximum longitude (+180°)
  static const double maxLongitude = kMaxLongitude;

  /// Encoded size for coordinates (lat + lon)
  static const int encodedSize = 8; // 4 + 4 bytes

  /// Encode latitude to fixed-point int32
  ///
  /// [lat] Latitude in degrees (-90 to +90)
  /// Returns fixed-point integer representation
  static int encodeLatitude(double lat) {
    if (lat < minLatitude || lat > maxLatitude) {
      throw ArgumentError(
        'Latitude must be between $minLatitude and $maxLatitude, got $lat',
      );
    }
    return (lat * precision).round();
  }

  /// Encode longitude to fixed-point int32
  ///
  /// [lon] Longitude in degrees (-180 to +180)
  /// Returns fixed-point integer representation
  static int encodeLongitude(double lon) {
    if (lon < minLongitude || lon > maxLongitude) {
      throw ArgumentError(
        'Longitude must be between $minLongitude and $maxLongitude, got $lon',
      );
    }
    return (lon * precision).round();
  }

  /// Decode fixed-point latitude to double
  ///
  /// [fixed] Fixed-point integer representation
  /// Returns latitude in degrees
  static double decodeLatitude(int fixed) {
    return fixed / precision;
  }

  /// Decode fixed-point longitude to double
  ///
  /// [fixed] Fixed-point integer representation
  /// Returns longitude in degrees
  static double decodeLongitude(int fixed) {
    return fixed / precision;
  }

  /// Encode coordinates to 8 bytes (big-endian)
  ///
  /// [lat] Latitude in degrees
  /// [lon] Longitude in degrees
  /// Returns Uint8List with encoded coordinates
  static Uint8List encode(double lat, double lon) {
    final result = Uint8List(encodedSize);
    write(result, 0, lat, lon);
    return result;
  }

  /// Write encoded coordinates to buffer
  ///
  /// [buffer] Destination buffer
  /// [offset] Starting offset
  /// [lat] Latitude in degrees
  /// [lon] Longitude in degrees
  /// Returns number of bytes written (always 8)
  static int write(Uint8List buffer, int offset, double lat, double lon) {
    final latFixed = encodeLatitude(lat);
    final lonFixed = encodeLongitude(lon);

    // Write latitude as signed 32-bit big-endian
    final data = ByteData.view(buffer.buffer, buffer.offsetInBytes);
    data.setInt32(offset, latFixed, Endian.big);
    data.setInt32(offset + 4, lonFixed, Endian.big);

    return encodedSize;
  }

  /// Decode coordinates from bytes
  ///
  /// [encoded] Encoded bytes (8 bytes)
  /// [offset] Starting offset (default 0)
  /// Returns tuple of (latitude, longitude)
  static (double lat, double lon) decode(Uint8List encoded, [int offset = 0]) {
    if (offset + encodedSize > encoded.length) {
      throw DecodingException(
        'GPS decode: insufficient data, need $encodedSize bytes at offset $offset',
        offset: offset,
      );
    }

    final data = ByteData.view(encoded.buffer, encoded.offsetInBytes);
    final latFixed = data.getInt32(offset, Endian.big);
    final lonFixed = data.getInt32(offset + 4, Endian.big);

    return (decodeLatitude(latFixed), decodeLongitude(lonFixed));
  }

  /// Read coordinates from buffer
  ///
  /// Alias for [decode] for API consistency
  static (double lat, double lon) read(Uint8List buffer, int offset) {
    return decode(buffer, offset);
  }

  /// Calculate distance between two points (Haversine formula)
  ///
  /// [lat1], [lon1] First point coordinates
  /// [lat2], [lon2] Second point coordinates
  /// Returns distance in meters
  static double distance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = _sin2(dLat / 2) + _cos(lat1) * _cos(lat2) * _sin2(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));

    return earthRadius * c;
  }

  /// Check if coordinates are valid
  static bool isValidLatitude(double lat) {
    return lat >= minLatitude && lat <= maxLatitude;
  }

  /// Check if coordinates are valid
  static bool isValidLongitude(double lon) {
    return lon >= minLongitude && lon <= maxLongitude;
  }

  /// Check if both coordinates are valid
  static bool isValid(double lat, double lon) {
    return isValidLatitude(lat) && isValidLongitude(lon);
  }

  // Math helpers for distance calculation
  static double _toRadians(double deg) => deg * 0.017453292519943295;
  static double _sin2(double x) {
    final s = _sin(x);
    return s * s;
  }

  // Import math functions directly to avoid dart:math import issues
  static double _sin(double x) {
    // Taylor series approximation for sin
    x = x % (2 * 3.141592653589793);
    if (x > 3.141592653589793) x -= 2 * 3.141592653589793;
    if (x < -3.141592653589793) x += 2 * 3.141592653589793;
    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  static double _cos(double x) {
    return _sin(x + 3.141592653589793 / 2);
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  static double _atan2(double y, double x) {
    // Simplified atan2 approximation
    if (x > 0) return _atan(y / x);
    if (x < 0 && y >= 0) return _atan(y / x) + 3.141592653589793;
    if (x < 0 && y < 0) return _atan(y / x) - 3.141592653589793;
    if (x == 0 && y > 0) return 3.141592653589793 / 2;
    if (x == 0 && y < 0) return -3.141592653589793 / 2;
    return 0;
  }

  static double _atan(double x) {
    // Taylor series approximation for atan
    if (x.abs() > 1) {
      return (x > 0 ? 1 : -1) * 3.141592653589793 / 2 - _atan(1 / x);
    }
    double result = x;
    double term = x;
    for (int i = 1; i <= 20; i++) {
      term *= -x * x * (2 * i - 1) / (2 * i + 1);
      result += term / (2 * i + 1);
    }
    return result;
  }
}
