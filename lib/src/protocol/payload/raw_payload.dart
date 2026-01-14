/// Raw Payload
///
/// Carries uninterpreted bytes for cases where payload decoding is not meaningful
/// or should be deferred (e.g., Standard-mode fragment packets that contain
/// partial data).
library;

import 'dart:typed_data';

import '../../core/types.dart';
import 'payload.dart';

/// A payload that wraps raw bytes without parsing.
class RawPayload extends Payload {
  @override
  final MessageType type;

  /// Raw payload bytes (immutable snapshot).
  final Uint8List bytes;

  RawPayload({required this.type, required Uint8List bytes})
      : bytes = Uint8List.fromList(bytes);

  @override
  int get sizeInBytes => bytes.length;

  @override
  Uint8List encode() => Uint8List.fromList(bytes);

  @override
  RawPayload copy() => RawPayload(type: type, bytes: bytes);

  @override
  String toString() => 'RawPayload(type: ${type.name}, bytes: ${bytes.length})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RawPayload) return false;
    if (other.type != type) return false;
    if (other.bytes.length != bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    // Cheap-ish rolling hash; good enough for tests/debug.
    int h = type.hashCode;
    for (final b in bytes) {
      h = 0x1fffffff & (h + b);
      h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
      h ^= (h >> 6);
    }
    h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
    h ^= (h >> 11);
    h = 0x1fffffff & (h + ((0x00003fff & h) << 15));
    return h;
  }
}

