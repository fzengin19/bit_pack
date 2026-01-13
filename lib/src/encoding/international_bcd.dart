/// International BCD Phone Number Encoding
///
/// Variable-length BCD encoding with country code support.
/// Supports both domestic (implicit +90) and international formats.
///
/// Header byte format:
/// - Bit 7: INT (0=domestic, 1=international)
/// - Bits 6-3: LENGTH (BCD pair count, 1-15)
/// - Bits 2-0: COUNTRY_CODE shortcut (if international)
///
/// Country code shortcuts:
///   001: +1 (USA/Canada)
///   010: +44 (UK)
///   011: +49 (Germany)
///   100: +33 (France)
///   101: +39 (Italy)
///   110: +90 (Turkey)
///   111: Custom (next 2 bytes contain BCD country code)

library;

import 'dart:typed_data';

import '../core/exceptions.dart';
import '../core/types.dart';

/// International BCD phone number encoder
class InternationalBcd {
  InternationalBcd._(); // Prevent instantiation

  /// Country code shortcuts (3 bits)
  static const Map<int, String> _countryShortcuts = {
    0x1: '1', // USA/Canada
    0x2: '44', // UK
    0x3: '49', // Germany
    0x4: '33', // France
    0x5: '39', // Italy
    0x6: '90', // Turkey
    0x7: 'custom', // Custom country code in next 2 bytes
  };

  /// Reverse lookup: country code to shortcut
  static const Map<String, int> _shortcutLookup = {
    '1': 0x1,
    '44': 0x2,
    '49': 0x3,
    '33': 0x4,
    '39': 0x5,
    '90': 0x6,
  };

  /// Maximum encoded size (header + country + 15 BCD pairs)
  static const int maxEncodedSize = 18;

  /// Padding nibble
  static const int _padding = 0x0F;

  /// Encode phone number to compact international BCD format
  ///
  /// [phoneNumber] Phone number string (may include + and country code)
  /// [isDomestic] If true, assumes +90 (Turkey) and encodes last digits only
  ///
  /// Returns encoded bytes (1-18 bytes)
  static Uint8List encode(String phoneNumber, {bool? isDomestic}) {
    // Remove all non-digit characters except +
    final hasPlus = phoneNumber.startsWith('+');
    var digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // Determine if domestic or international
    isDomestic ??= !hasPlus;

    if (isDomestic) {
      return _encodeDomestic(digits);
    } else {
      return _encodeInternational(digits);
    }
  }

  /// Encode using CountryCode enum
  static Uint8List encodeWithCountry(String localNumber, CountryCode country) {
    final fullNumber = '${country.prefix}$localNumber';
    return encode(fullNumber, isDomestic: false);
  }

  /// Encode domestic number (implicit +90)
  static Uint8List _encodeDomestic(String digits) {
    // Take last 10 digits for Turkey mobile numbers
    if (digits.length > 10) {
      digits = digits.substring(digits.length - 10);
    }

    final bcdPairs = (digits.length + 1) ~/ 2;
    final result = Uint8List(1 + bcdPairs);

    // Header: INT=0, LENGTH=bcdPairs, reserved=0
    result[0] = (bcdPairs & 0x0F) << 3;

    // BCD encode digits
    _writeBcd(result, 1, digits);

    return result;
  }

  /// Encode international number
  static Uint8List _encodeInternational(String digits) {
    // Try to find a country code shortcut
    int countryShortcut = 0;
    String countryCode = '';
    String remaining = digits;

    // Check known country codes (sorted by length descending for proper matching)
    for (final code in ['44', '49', '33', '39', '90', '1']) {
      if (digits.startsWith(code)) {
        countryShortcut = _shortcutLookup[code]!;
        countryCode = code;
        remaining = digits.substring(code.length);
        break;
      }
    }

    // If no shortcut found, use custom format
    if (countryShortcut == 0) {
      countryShortcut = 0x7; // Custom
      // Extract country code (1-4 digits, we'll use first 3)
      if (digits.length >= 3) {
        countryCode = digits.substring(0, 3);
        remaining = digits.substring(3);
      } else {
        countryCode = digits;
        remaining = '';
      }
    }

    final bcdPairs = (remaining.length + 1) ~/ 2;
    final isCustom = countryShortcut == 0x7;
    final countryBytes = isCustom ? 2 : 0;

    final result = Uint8List(1 + countryBytes + bcdPairs);

    // Header: INT=1, LENGTH=bcdPairs, COUNTRY=shortcut
    result[0] = 0x80 | ((bcdPairs & 0x0F) << 3) | (countryShortcut & 0x07);

    int offset = 1;

    // Write custom country code if needed
    if (isCustom) {
      _writeBcd(result, offset, countryCode.padRight(4, 'F'));
      offset += 2;
    }

    // Write remaining digits
    if (remaining.isNotEmpty) {
      _writeBcd(result, offset, remaining);
    }

    return result;
  }

  /// Write BCD-encoded digits to buffer
  static void _writeBcd(Uint8List buffer, int offset, String digits) {
    // Pad with F if odd length
    var padded = digits;
    if (padded.length.isOdd) {
      padded = padded + 'F';
    }

    for (int i = 0; i < padded.length; i += 2) {
      final high = padded[i] == 'F' ? _padding : int.parse(padded[i]);
      final low = padded[i + 1] == 'F' ? _padding : int.parse(padded[i + 1]);
      buffer[offset + (i ~/ 2)] = (high << 4) | low;
    }
  }

  /// Decode international BCD to phone number string
  ///
  /// [encoded] Encoded bytes
  /// Returns phone number with + prefix
  static String decode(Uint8List encoded) {
    if (encoded.isEmpty) {
      throw DecodingException('InternationalBcd: empty input');
    }

    final header = encoded[0];
    final isInternational = (header & 0x80) != 0;
    final bcdPairs = (header >> 3) & 0x0F;
    final countryShortcut = header & 0x07;

    final buffer = StringBuffer('+');
    int offset = 1;

    if (isInternational) {
      if (countryShortcut == 0x7) {
        // Custom country code in next 2 bytes
        if (encoded.length < 3) {
          throw DecodingException(
            'InternationalBcd: missing custom country code bytes',
          );
        }
        final countryDigits = _readBcd(encoded, offset, 2);
        buffer.write(countryDigits.replaceAll('F', ''));
        offset += 2;
      } else if (_countryShortcuts.containsKey(countryShortcut)) {
        buffer.write(_countryShortcuts[countryShortcut]!);
      }
    } else {
      // Domestic = +90 (Turkey)
      buffer.write('90');
    }

    // Read remaining phone digits
    if (bcdPairs > 0 && offset < encoded.length) {
      final remaining = _readBcd(encoded, offset, bcdPairs);
      buffer.write(remaining);
    }

    return buffer.toString();
  }

  /// Read BCD digits from buffer
  static String _readBcd(Uint8List buffer, int offset, int byteCount) {
    final result = StringBuffer();

    for (int i = 0; i < byteCount && offset + i < buffer.length; i++) {
      final byte = buffer[offset + i];
      final high = (byte >> 4) & 0x0F;
      final low = byte & 0x0F;

      if (high <= 9) {
        result.write(high);
      } else if (high == _padding) {
        result.write('F'); // Preserve for country code parsing
      }

      if (low <= 9) {
        result.write(low);
      } else if (low == _padding) {
        // Stop at padding
        break;
      }
    }

    return result.toString().replaceAll('F', '');
  }

  /// Get the country code from encoded data
  ///
  /// Returns CountryCode enum if recognized, null otherwise
  static CountryCode? getCountryCode(Uint8List encoded) {
    if (encoded.isEmpty) return null;

    final header = encoded[0];
    final isInternational = (header & 0x80) != 0;
    final countryShortcut = header & 0x07;

    if (!isInternational) {
      return CountryCode.turkey; // Domestic = Turkey
    }

    switch (countryShortcut) {
      case 0x1:
        return CountryCode.usaCanada;
      case 0x2:
        return CountryCode.uk;
      case 0x3:
        return CountryCode.germany;
      case 0x4:
        return CountryCode.france;
      case 0x5:
        return CountryCode.italy;
      case 0x6:
        return CountryCode.turkey;
      default:
        return null; // Custom or unknown
    }
  }

  /// Calculate encoded size for a phone number
  static int encodedSize(String phoneNumber, {bool isDomestic = true}) {
    final encoded = encode(phoneNumber, isDomestic: isDomestic);
    return encoded.length;
  }
}
