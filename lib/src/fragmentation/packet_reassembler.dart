/// Packet Fragment Reassembler
///
/// Reassembles Standard-mode fragment packets (each with its own CRC-32) into a
/// complete Standard packet, then returns a fully decoded `Packet`.
library;

import 'dart:typed_data';

import '../core/exceptions.dart';
import '../encoding/bitwise.dart';
import '../encoding/crc32.dart';
import '../protocol/header/standard_header.dart';
import '../protocol/packet.dart';
import '../protocol/payload/raw_payload.dart';
import 'fragment_header.dart';

class PacketFragmentReassembler {
  final Map<int, _PacketFragBuffer> _buffers = {};

  /// Add a decoded fragment `Packet`.
  ///
  /// Expectations:
  /// - `fragment.header` is `StandardHeader`
  /// - `fragment.header.flags.isFragment == true`
  /// - `fragment.payload` is `RawPayload` whose bytes are `[FragmentHeader][chunk]`
  ///
  /// Returns the fully reassembled and decoded `Packet` when complete, otherwise null.
  Packet? addFragmentPacket(Packet fragment) {
    final header = fragment.header;
    if (header is! StandardHeader) {
      throw FragmentationException(
        'PacketFragmentReassembler: expected StandardHeader, got ${header.runtimeType}',
      );
    }
    if (!header.flags.isFragment) {
      throw FragmentationException(
        'PacketFragmentReassembler: packet is not marked as fragment',
      );
    }

    final payload = fragment.payload;
    if (payload is! RawPayload) {
      throw FragmentationException(
        'PacketFragmentReassembler: expected RawPayload, got ${payload.runtimeType}',
      );
    }
    if (payload.bytes.length < FragmentHeader.sizeInBytes) {
      throw FragmentationException(
        'PacketFragmentReassembler: fragment payload too short for FragmentHeader',
      );
    }

    final fragHeader = FragmentHeader.decode(payload.bytes, 0);
    final chunk = payload.bytes.sublist(FragmentHeader.sizeInBytes);

    final buffer = _buffers.putIfAbsent(
      header.messageId,
      () => _PacketFragBuffer(
        messageId: header.messageId,
        totalFragments: fragHeader.totalFragments,
        baseHeader: header,
      ),
    );

    // Total count must match.
    if (buffer.totalFragments != fragHeader.totalFragments) {
      throw FragmentationException(
        'PacketFragmentReassembler: fragment count mismatch for message '
        '0x${header.messageId.toRadixString(16)}: '
        'expected ${buffer.totalFragments}, got ${fragHeader.totalFragments}',
      );
    }

    // Add chunk (idempotent for duplicates).
    buffer.addChunk(fragHeader.fragmentIndex, chunk);

    if (!buffer.isComplete) return null;

    // Completed: build full Standard packet bytes and decode into typed Packet.
    _buffers.remove(header.messageId);
    final payloadBytes = buffer.reassemblePayload();

    // Clear fragmentation flags for the reassembled (logical) packet.
    final flags = buffer.baseHeader.flags.copyWith(
      isFragment: false,
      moreFragments: false,
    );

    final fullHeader = StandardHeader(
      version: buffer.baseHeader.version,
      type: buffer.baseHeader.type,
      flags: flags,
      hopTtl: buffer.baseHeader.hopTtl,
      messageId: buffer.baseHeader.messageId,
      securityMode: buffer.baseHeader.securityMode,
      payloadLength: payloadBytes.length,
      ageMinutes: buffer.baseHeader.ageMinutes,
    );

    const int crc32Size = 4;
    final size =
        StandardHeader.headerSizeInBytes + payloadBytes.length + crc32Size;
    final bytes = Uint8List(size);
    bytes.setRange(0, StandardHeader.headerSizeInBytes, fullHeader.encode());
    bytes.setRange(
      StandardHeader.headerSizeInBytes,
      StandardHeader.headerSizeInBytes + payloadBytes.length,
      payloadBytes,
    );
    final crc = Crc32.compute(bytes.sublist(0, size - crc32Size));
    Bitwise.write32BE(bytes, size - crc32Size, crc);

    return Packet.decode(bytes);
  }

  /// Clear all in-flight reassemblies.
  void clear() => _buffers.clear();

  /// Current number of in-flight messages being reassembled.
  int get activeCount => _buffers.length;
}

class _PacketFragBuffer {
  final int messageId;
  final int totalFragments;
  final StandardHeader baseHeader;

  final Map<int, Uint8List> chunks = {};

  _PacketFragBuffer({
    required this.messageId,
    required this.totalFragments,
    required this.baseHeader,
  });

  bool get isComplete => chunks.length == totalFragments;

  void addChunk(int index, Uint8List bytes) {
    chunks.putIfAbsent(index, () => Uint8List.fromList(bytes));
  }

  Uint8List reassemblePayload() {
    if (!isComplete) {
      throw MissingFragmentException(messageId: messageId, fragmentIndex: 0);
    }

    int total = 0;
    for (int i = 0; i < totalFragments; i++) {
      final c = chunks[i];
      if (c == null) {
        throw MissingFragmentException(messageId: messageId, fragmentIndex: i);
      }
      total += c.length;
    }

    final out = Uint8List(total);
    int offset = 0;
    for (int i = 0; i < totalFragments; i++) {
      final c = chunks[i]!;
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    return out;
  }
}

