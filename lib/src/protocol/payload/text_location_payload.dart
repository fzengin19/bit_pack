/// Text Location Payload (0x1C)
///
/// Hybrid payload combining GPS coordinates and text message.
/// Optimized for low-bandwidth by avoiding delimiters.
///
/// Layout:
/// [LAT: 4 bytes (fixed-point)][LON: 4 bytes (fixed-point)][TEXT: Variable (UTF-8)]

library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/types.dart';
import '../../encoding/gps.dart';
import 'payload.dart';

/// Hybrid payload with fixed-point GPS and text
class TextLocationPayload extends Payload with GeoPayload {
  @override
  final double latitude;

  @override
  final double longitude;

  /// Text message content
  final String text;

  @override
  final int? altitude = null; // Altitude not supported in this compact format

  /// Create a text location payload
  TextLocationPayload({
    required this.latitude,
    required this.longitude,
    required this.text,
  }) {
    // Validate coordinates
    if (!Gps.isValid(latitude, longitude)) {
      throw ArgumentError('Invalid coordinates: $latitude, $longitude');
    }
  }

  @override
  MessageType get type => MessageType.textLocation;

  @override
  int get sizeInBytes {
    return Gps.encodedSize + utf8.encode(text).length;
  }

  @override
  Uint8List encode() {
    final textBytes = utf8.encode(text);
    final size = Gps.encodedSize + textBytes.length;
    final buffer = Uint8List(size);

    // Write GPS (0-8)
    Gps.write(buffer, 0, latitude, longitude);

    // Write Text (8-end)
    buffer.setRange(Gps.encodedSize, size, textBytes);

    return buffer;
  }

  /// Decode from bytes
  factory TextLocationPayload.decode(Uint8List bytes) {
    if (bytes.length < Gps.encodedSize) {
      throw ArgumentError(
        'TextLocationPayload too short: ${bytes.length} bytes (min ${Gps.encodedSize})',
      );
    }

    // Decode GPS
    final (lat, lon) = Gps.read(bytes, 0);

    // Decode Text
    final textBytes = bytes.sublist(Gps.encodedSize);
    final text = utf8.decode(textBytes);

    return TextLocationPayload(latitude: lat, longitude: lon, text: text);
  }

  @override
  Payload copy() {
    return TextLocationPayload(
      latitude: latitude,
      longitude: longitude,
      text: text,
    );
  }

  @override
  String toString() {
    return 'TextLocationPayload('
        'lat: $latitude, '
        'lon: $longitude, '
        'text: "$text")';
  }
}
