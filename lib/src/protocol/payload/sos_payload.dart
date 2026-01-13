/// SOS Payload (15 bytes)
///
/// Ultra-compact emergency payload designed to fit in BLE 4.2 single packet.
/// Total packet size: 4 (header) + 15 (payload) = 19 bytes < 20 byte limit
///
/// Layout:
/// ```
/// BYTE 0:     SOS_STATUS
///             Bits 7-5: SOS Type (8 types)
///             Bits 4-2: People count (0-7)
///             Bit 1: Has injured
///             Bit 0: Is trapped
/// BYTES 1-4:  LATITUDE (fixed-point int32, lat * 10_000_000)
/// BYTES 5-8:  LONGITUDE (fixed-point int32, lon * 10_000_000)
/// BYTES 9-12: PHONE (BCD packed, last 8 digits)
/// BYTES 13-14: ALTITUDE (12 bits, 0-4095m) + BATTERY (4 bits, 0-15)
/// ```

library;

import 'dart:typed_data';

import '../../core/exceptions.dart';
import '../../core/types.dart';
import '../../encoding/bcd.dart';
import '../../encoding/gps.dart';
import 'payload.dart';

/// SOS emergency payload (15 bytes)
class SosPayload extends Payload with CompactPayload, GeoPayload {
  /// SOS payload size in bytes
  static const int payloadSize = 15;

  /// SOS type (need rescue, injured, trapped, safe, etc.)
  final SosType sosType;

  /// Number of people (0-7)
  final int peopleCount;

  /// Whether there are injured people
  final bool hasInjured;

  /// Whether someone is trapped
  final bool isTrapped;

  /// Latitude in degrees
  @override
  final double latitude;

  /// Longitude in degrees
  @override
  final double longitude;

  /// Phone number (last 8 digits for compact mode)
  final String? phoneNumber;

  /// Altitude in meters (0-4095)
  @override
  final int? altitude;

  /// Battery percentage (0-100, stored as 0-15)
  final int? batteryPercent;

  /// Create a new SOS payload
  SosPayload({
    required this.sosType,
    this.peopleCount = 1,
    this.hasInjured = false,
    this.isTrapped = false,
    required this.latitude,
    required this.longitude,
    this.phoneNumber,
    this.altitude,
    this.batteryPercent,
  }) {
    // Validate people count (3 bits = 0-7)
    if (peopleCount < 0 || peopleCount > 7) {
      throw ArgumentError('People count must be 0-7, got $peopleCount');
    }

    // Validate coordinates
    if (!Gps.isValid(latitude, longitude)) {
      throw ArgumentError('Invalid coordinates: ($latitude, $longitude)');
    }

    // Validate altitude (12 bits = 0-4095)
    if (altitude != null && (altitude! < 0 || altitude! > 4095)) {
      throw ArgumentError('Altitude must be 0-4095, got $altitude');
    }

    // Validate battery (0-100%)
    if (batteryPercent != null &&
        (batteryPercent! < 0 || batteryPercent! > 100)) {
      throw ArgumentError('Battery percent must be 0-100, got $batteryPercent');
    }
  }

  @override
  MessageType get type => MessageType.sosBeacon;

  @override
  int get sizeInBytes => payloadSize;

  /// Map battery percentage (0-100) to 4-bit value (0-15)
  int get _batteryEncoded {
    if (batteryPercent == null) return 0;
    return ((batteryPercent! * 15) / 100).round().clamp(0, 15);
  }

  /// Decode 4-bit battery value (0-15) to percentage (0-100)
  static int _decodeBattery(int encoded) {
    return ((encoded * 100) / 15).round().clamp(0, 100);
  }

  @override
  Uint8List encode() {
    final buffer = Uint8List(payloadSize);

    // BYTE 0: SOS_STATUS
    // Bits 7-5: SOS Type (3 bits)
    // Bits 4-2: People count (3 bits)
    // Bit 1: Has injured
    // Bit 0: Is trapped
    buffer[0] =
        ((sosType.code & 0x07) << 5) |
        ((peopleCount & 0x07) << 2) |
        (hasInjured ? 0x02 : 0x00) |
        (isTrapped ? 0x01 : 0x00);

    // BYTES 1-4: LATITUDE (fixed-point, big-endian)
    final latFixed = Gps.encodeLatitude(latitude);
    final data = ByteData.view(buffer.buffer);
    data.setInt32(1, latFixed, Endian.big);

    // BYTES 5-8: LONGITUDE (fixed-point, big-endian)
    final lonFixed = Gps.encodeLongitude(longitude);
    data.setInt32(5, lonFixed, Endian.big);

    // BYTES 9-12: PHONE (BCD, last 8 digits)
    if (phoneNumber != null && phoneNumber!.isNotEmpty) {
      final phoneBcd = Bcd.encodeLastDigits(phoneNumber!, 8);
      buffer.setRange(9, 9 + phoneBcd.length.clamp(0, 4), phoneBcd);
    }

    // BYTES 13-14: ALTITUDE (12 bits) + BATTERY (4 bits)
    // Bits 15-4: Altitude (12 bits, 0-4095)
    // Bits 3-0: Battery (4 bits, 0-15)
    final alt = (altitude ?? 0).clamp(0, 4095);
    final bat = _batteryEncoded;
    final altBat = (alt << 4) | (bat & 0x0F);
    data.setUint16(13, altBat, Endian.big);

    return buffer;
  }

  /// Decode SOS payload from bytes
  factory SosPayload.decode(Uint8List bytes) {
    if (bytes.length < payloadSize) {
      throw DecodingException(
        'SosPayload: insufficient data, expected $payloadSize, got ${bytes.length}',
      );
    }

    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes);

    // BYTE 0: SOS_STATUS
    final status = bytes[0];
    final sosTypeCode = (status >> 5) & 0x07;
    final peopleCount = (status >> 2) & 0x07;
    final hasInjured = (status & 0x02) != 0;
    final isTrapped = (status & 0x01) != 0;

    // Parse SOS type
    SosType sosType;
    try {
      sosType = SosType.fromCode(sosTypeCode);
    } catch (_) {
      sosType = SosType.needRescue;
    }

    // BYTES 1-4: LATITUDE
    final latFixed = data.getInt32(1, Endian.big);
    final latitude = Gps.decodeLatitude(latFixed);

    // BYTES 5-8: LONGITUDE
    final lonFixed = data.getInt32(5, Endian.big);
    final longitude = Gps.decodeLongitude(lonFixed);

    // BYTES 9-12: PHONE
    final phoneBcd = bytes.sublist(9, 13);
    String? phoneNumber;
    try {
      final decoded = Bcd.decode(phoneBcd);
      if (decoded.isNotEmpty && decoded != '00000000') {
        phoneNumber = decoded;
      }
    } catch (_) {
      // Invalid BCD, ignore
    }

    // BYTES 13-14: ALTITUDE + BATTERY
    final altBat = data.getUint16(13, Endian.big);
    final altitude = (altBat >> 4) & 0x0FFF;
    final batteryEncoded = altBat & 0x0F;
    final batteryPercent = _decodeBattery(batteryEncoded);

    return SosPayload(
      sosType: sosType,
      peopleCount: peopleCount,
      hasInjured: hasInjured,
      isTrapped: isTrapped,
      latitude: latitude,
      longitude: longitude,
      phoneNumber: phoneNumber,
      altitude: altitude > 0 ? altitude : null,
      batteryPercent: batteryEncoded > 0 ? batteryPercent : null,
    );
  }

  @override
  SosPayload copy() {
    return SosPayload(
      sosType: sosType,
      peopleCount: peopleCount,
      hasInjured: hasInjured,
      isTrapped: isTrapped,
      latitude: latitude,
      longitude: longitude,
      phoneNumber: phoneNumber,
      altitude: altitude,
      batteryPercent: batteryPercent,
    );
  }

  @override
  String toString() {
    return 'SosPayload('
        'type: ${sosType.name}, '
        'people: $peopleCount, '
        'injured: $hasInjured, '
        'trapped: $isTrapped, '
        'lat: $latitude, '
        'lon: $longitude, '
        'phone: $phoneNumber, '
        'alt: $altitude, '
        'battery: $batteryPercent%)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SosPayload &&
        other.sosType == sosType &&
        other.peopleCount == peopleCount &&
        other.hasInjured == hasInjured &&
        other.isTrapped == isTrapped &&
        (other.latitude - latitude).abs() < 0.0000001 &&
        (other.longitude - longitude).abs() < 0.0000001 &&
        other.phoneNumber == phoneNumber &&
        other.altitude == altitude &&
        other.batteryPercent == batteryPercent;
  }

  @override
  int get hashCode => Object.hash(
    sosType,
    peopleCount,
    hasInjured,
    isTrapped,
    latitude.toStringAsFixed(6),
    longitude.toStringAsFixed(6),
    phoneNumber,
    altitude,
    batteryPercent,
  );
}
