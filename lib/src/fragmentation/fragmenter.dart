/// BitPack Fragmenter
///
/// Splits large packets into MTU-sized fragments for transmission
/// over bandwidth-limited connections like BLE.
///
/// Each fragment contains:
/// - Original packet header (with FRAGMENT flag set)
/// - Fragment header (3 bytes: index + total)
/// - Portion of original payload

library;

import 'dart:typed_data';

import '../core/constants.dart';
import '../core/exceptions.dart';
import '../core/types.dart';
import '../encoding/bitwise.dart';
import '../protocol/header/standard_header.dart';
import 'fragment_header.dart';

// ============================================================================
// FRAGMENTER
// ============================================================================

/// Splits large packets into MTU-sized fragments
///
/// Example:
/// ```dart
/// final fragmenter = Fragmenter(mtu: 244); // BLE 5.0
///
/// if (fragmenter.needsFragmentation(packetBytes)) {
///   final fragments = fragmenter.fragment(packetBytes, messageId);
///   for (final fragment in fragments) {
///     sendOverBle(fragment);
///   }
/// }
/// ```
class Fragmenter {
  /// Maximum Transmission Unit in bytes
  final int mtu;

  /// Minimum MTU (header + fragment header + at least 1 byte payload)
  static const int minMtu = kBle42MaxPayload;

  /// Default MTU for BLE 5.0+
  static const int defaultMtu = 244;

  /// BLE 4.2 MTU
  static const int ble42Mtu = kBle42MaxPayload;

  /// Create a fragmenter with specified MTU
  ///
  /// [mtu] Maximum bytes per fragment (default: 244 for BLE 5.0)
  Fragmenter({this.mtu = defaultMtu}) {
    if (mtu < minMtu) {
      throw FragmentationException(
        'MTU must be at least $minMtu bytes, got $mtu',
      );
    }
  }

  /// Check if data needs fragmentation
  bool needsFragmentation(Uint8List data) => data.length > mtu;

  /// Calculate number of fragments needed for given data size
  int fragmentCount(int dataSize) {
    if (dataSize <= mtu) return 1;

    // Each fragment has overhead: fragment header (3 bytes)
    // First fragment uses original header, subsequent use minimal header
    final payloadPerFragment = mtu - FragmentHeader.sizeInBytes;
    if (payloadPerFragment <= 0) {
      throw FragmentationException(
        'MTU too small for fragmentation: $mtu bytes',
      );
    }

    return (dataSize / payloadPerFragment).ceil();
  }

  /// Fragment a packet into MTU-sized pieces
  ///
  /// [data] Original packet bytes (header + payload)
  /// [messageId] Message ID for fragment tracking
  ///
  /// Returns list of fragment byte arrays, each <= MTU size.
  /// Each fragment includes a FragmentHeader.
  ///
  /// Throws [FragmentationException] if data cannot be fragmented.
  List<Uint8List> fragment(Uint8List data, int messageId) {
    if (data.length <= mtu) {
      // No fragmentation needed
      return [data];
    }

    // Calculate payload per fragment
    // We need space for fragment header in each fragment
    final payloadPerFragment = mtu - FragmentHeader.sizeInBytes;
    if (payloadPerFragment <= 0) {
      throw FragmentationException(
        'MTU too small for fragmentation overhead: $mtu bytes',
      );
    }

    final totalFragments = (data.length / payloadPerFragment).ceil();
    if (totalFragments > FragmentHeader.maxTotalFragments) {
      throw FragmentationException(
        'Data too large: needs $totalFragments fragments, max is ${FragmentHeader.maxTotalFragments}',
      );
    }

    final fragments = <Uint8List>[];

    for (int i = 0; i < totalFragments; i++) {
      final start = i * payloadPerFragment;
      final end = (start + payloadPerFragment).clamp(0, data.length);
      final chunkSize = end - start;

      // Create fragment header
      final fragHeader = FragmentHeader(
        fragmentIndex: i,
        totalFragments: totalFragments,
      );
      final fragHeaderBytes = fragHeader.encode();

      // Build fragment: [fragment_header (3)] [payload_chunk]
      final fragment = Uint8List(FragmentHeader.sizeInBytes + chunkSize);
      fragment.setRange(0, FragmentHeader.sizeInBytes, fragHeaderBytes);
      fragment.setRange(FragmentHeader.sizeInBytes, fragment.length, 
          data.sublist(start, end));

      fragments.add(fragment);
    }

    return fragments;
  }

  /// Fragment raw payload data with a new header for each fragment
  ///
  /// Creates proper packet structure for each fragment with:
  /// - Standard header (with FRAGMENT + MORE_FRAGMENTS flags)
  /// - Fragment header
  /// - Payload chunk
  ///
  /// [payload] Raw payload bytes to fragment
  /// [messageId] Message ID for all fragments
  /// [messageType] Type of the original message
  /// [ttl] Time-to-live hop count
  ///
  /// Returns list of complete fragment packets.
  List<Uint8List> fragmentWithHeaders({
    required Uint8List payload,
    required int messageId,
    required MessageType messageType,
    int ttl = 10,
  }) {
    // Calculate available payload per fragment
    // Standard header (11) + Fragment header (3) = 14 bytes overhead
    const headerOverhead = StandardHeader.sizeInBytes + FragmentHeader.sizeInBytes;
    final payloadPerFragment = mtu - headerOverhead;

    if (payloadPerFragment <= 0) {
      throw FragmentationException(
        'MTU too small for headers: need > $headerOverhead bytes, got $mtu',
      );
    }

    final totalFragments = (payload.length / payloadPerFragment).ceil();
    if (totalFragments > FragmentHeader.maxTotalFragments) {
      throw FragmentationException(
        'Payload too large: needs $totalFragments fragments',
      );
    }

    // If no fragmentation needed, return single packet without fragment header
    if (totalFragments <= 1) {
      final header = StandardHeader(
        type: messageType,
        flags: PacketFlags(),
        hopTtl: ttl,
        messageId: messageId,
        securityMode: SecurityMode.none,
        payloadLength: payload.length,
        ageMinutes: 0,
      );

      final packet = Uint8List(StandardHeader.sizeInBytes + payload.length);
      packet.setRange(0, StandardHeader.sizeInBytes, header.encode());
      packet.setRange(StandardHeader.sizeInBytes, packet.length, payload);
      return [packet];
    }

    final fragments = <Uint8List>[];

    for (int i = 0; i < totalFragments; i++) {
      final start = i * payloadPerFragment;
      final end = (start + payloadPerFragment).clamp(0, payload.length);
      final chunk = payload.sublist(start, end);

      final isLast = (i == totalFragments - 1);

      // Create header with fragment flags
      final flags = PacketFlags(
        isFragment: true,
        moreFragments: !isLast,
      );

      final header = StandardHeader(
        type: messageType,
        flags: flags,
        hopTtl: ttl,
        messageId: messageId,
        securityMode: SecurityMode.none,
        payloadLength: chunk.length,
        ageMinutes: 0,
      );

      // Create fragment header
      final fragHeader = FragmentHeader(
        fragmentIndex: i,
        totalFragments: totalFragments,
      );

      // Build complete fragment packet
      final fragmentSize = StandardHeader.sizeInBytes + 
          FragmentHeader.sizeInBytes + chunk.length;
      final fragment = Uint8List(fragmentSize);

      int offset = 0;
      fragment.setRange(offset, offset + StandardHeader.sizeInBytes, header.encode());
      offset += StandardHeader.sizeInBytes;


      fragment.setRange(offset, offset + FragmentHeader.sizeInBytes, fragHeader.encode());
      offset += FragmentHeader.sizeInBytes;

      fragment.setRange(offset, fragment.length, chunk);

      fragments.add(fragment);
    }

    return fragments;
  }

  /// Calculate maximum payload size that fits in a single MTU
  int get maxPayloadWithoutFragmentation => mtu;

  /// Calculate maximum payload size per fragment (with fragmentation overhead)
  int get maxPayloadPerFragment => mtu - FragmentHeader.sizeInBytes;

  @override
  String toString() => 'Fragmenter(mtu: $mtu)';
}
