/// BitPack Protocol Exceptions
///
/// Custom exception classes for error handling in the BitPack mesh protocol.

library;

// ============================================================================
// BASE EXCEPTION
// ============================================================================

/// Base exception for all BitPack protocol errors
abstract class BitPackException implements Exception {
  /// Human-readable error message
  final String message;

  /// Optional underlying cause
  final Object? cause;

  const BitPackException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return '$runtimeType: $message (caused by: $cause)';
    }
    return '$runtimeType: $message';
  }
}

// ============================================================================
// ENCODING EXCEPTIONS
// ============================================================================

/// Exception thrown when encoding data fails
class EncodingException extends BitPackException {
  const EncodingException(super.message, [super.cause]);
}

/// Exception thrown when decoding data fails
class DecodingException extends BitPackException {
  /// Byte offset where the error occurred (if applicable)
  final int? offset;

  DecodingException(String message, {this.offset, Object? cause})
    : super(message, cause);

  @override
  String toString() {
    final offsetInfo = offset != null ? ' at offset $offset' : '';
    if (cause != null) {
      return 'DecodingException: $message$offsetInfo (caused by: $cause)';
    }
    return 'DecodingException: $message$offsetInfo';
  }
}

/// Exception thrown when CRC verification fails
class CrcMismatchException extends DecodingException {
  /// Expected CRC value
  final int expected;

  /// Actual CRC value found in data
  final int actual;

  CrcMismatchException({required this.expected, required this.actual})
    : super(
        'CRC mismatch: expected 0x${expected.toRadixString(16)}, '
        'got 0x${actual.toRadixString(16)}',
      );
}

// ============================================================================
// HEADER EXCEPTIONS
// ============================================================================

/// Exception thrown when header parsing fails
class InvalidHeaderException extends DecodingException {
  InvalidHeaderException(super.message, {super.offset, super.cause});
}

/// Exception thrown when header size is insufficient
class InsufficientHeaderException extends InvalidHeaderException {
  /// Expected header size
  final int expected;

  /// Actual data size
  final int actual;

  InsufficientHeaderException({required this.expected, required this.actual})
    : super('Insufficient header data: expected $expected bytes, got $actual');
}

/// Exception thrown when packet mode bit is invalid
class InvalidModeException extends InvalidHeaderException {
  final int mode;

  InvalidModeException(this.mode)
    : super('Invalid packet mode: $mode (expected 0 or 1)');
}

// ============================================================================
// PAYLOAD EXCEPTIONS
// ============================================================================

/// Exception thrown when payload is invalid or corrupted
class InvalidPayloadException extends DecodingException {
  InvalidPayloadException(super.message, {super.offset, super.cause});
}

/// Exception thrown when payload exceeds maximum size
class PayloadTooLargeException extends EncodingException {
  /// Maximum allowed size
  final int maxSize;

  /// Actual payload size
  final int actualSize;

  PayloadTooLargeException({required this.maxSize, required this.actualSize})
    : super('Payload too large: $actualSize bytes exceeds maximum $maxSize');
}

// ============================================================================
// FRAGMENTATION EXCEPTIONS
// ============================================================================

/// Exception thrown during fragmentation/reassembly
class FragmentationException extends BitPackException {
  const FragmentationException(super.message, [super.cause]);
}

/// Exception thrown when fragment is missing during reassembly
class MissingFragmentException extends FragmentationException {
  /// Message ID being reassembled
  final int messageId;

  /// Missing fragment index
  final int fragmentIndex;

  MissingFragmentException({
    required this.messageId,
    required this.fragmentIndex,
  }) : super(
         'Missing fragment $fragmentIndex for message 0x${messageId.toRadixString(16)}',
       );
}

/// Exception thrown when reassembly times out
class ReassemblyTimeoutException extends FragmentationException {
  /// Message ID that timed out
  final int messageId;

  /// Number of fragments received
  final int receivedCount;

  /// Total expected fragments
  final int totalCount;

  ReassemblyTimeoutException({
    required this.messageId,
    required this.receivedCount,
    required this.totalCount,
  }) : super(
         'Reassembly timeout for message 0x${messageId.toRadixString(16)}: '
         'received $receivedCount of $totalCount fragments',
       );
}

// ============================================================================
// CRYPTO EXCEPTIONS
// ============================================================================

/// Exception thrown when cryptographic operation fails
class CryptoException extends BitPackException {
  const CryptoException(super.message, [super.cause]);
}

/// Exception thrown when key derivation fails
class KeyDerivationException extends CryptoException {
  const KeyDerivationException(super.message, [super.cause]);
}

/// Exception thrown when decryption fails (wrong key or corrupted data)
class DecryptionException extends CryptoException {
  const DecryptionException(super.message, [super.cause]);
}

/// Exception thrown when authentication tag verification fails
class AuthenticationException extends CryptoException {
  const AuthenticationException()
    : super('Authentication failed: invalid auth tag');
}

/// Exception thrown when challenge block verification fails
class ChallengeVerificationException extends CryptoException {
  const ChallengeVerificationException()
    : super('Challenge verification failed: incorrect shared secret');
}

// ============================================================================
// TTL EXCEPTIONS
// ============================================================================

/// Exception thrown when message has expired
class MessageExpiredException extends BitPackException {
  /// Message ID
  final int messageId;

  /// Reason for expiration
  final String reason;

  MessageExpiredException({required this.messageId, required this.reason})
    : super('Message 0x${messageId.toRadixString(16)} expired: $reason');
}

/// Exception thrown when hop TTL reaches zero
class HopLimitReachedException extends MessageExpiredException {
  HopLimitReachedException({required super.messageId})
    : super(reason: 'hop limit reached');
}

/// Exception thrown when age TTL exceeds maximum
class AgeLimitReachedException extends MessageExpiredException {
  /// Message age in minutes
  final int ageMinutes;

  /// Maximum allowed age in minutes
  final int maxAgeMinutes;

  AgeLimitReachedException({
    required super.messageId,
    required this.ageMinutes,
    required this.maxAgeMinutes,
  }) : super(reason: 'age $ageMinutes minutes exceeds max $maxAgeMinutes');
}

// ============================================================================
// MESH EXCEPTIONS
// ============================================================================

/// Exception thrown during mesh relay operations
class MeshException extends BitPackException {
  const MeshException(super.message, [super.cause]);
}

/// Exception thrown when duplicate message is detected
class DuplicateMessageException extends MeshException {
  /// Message ID
  final int messageId;

  DuplicateMessageException(this.messageId)
    : super('Duplicate message: 0x${messageId.toRadixString(16)}');
}

/// Exception thrown when message cache is full
class CacheFullException extends MeshException {
  /// Current cache size
  final int currentSize;

  /// Maximum cache size
  final int maxSize;

  CacheFullException({required this.currentSize, required this.maxSize})
    : super('Message cache full: $currentSize entries (max $maxSize)');
}
