/// BitPack Benchmark Suite
///
/// Performance measurement tools for encoding, decoding, and crypto operations.

library;

import 'dart:typed_data';

import '../core/types.dart';
import '../encoding/crc8.dart';
import '../protocol/packet.dart';
import '../crypto/key_derivation.dart';
import '../crypto/aes_gcm.dart';

// ============================================================================
// BENCHMARK RESULT
// ============================================================================

/// Result of a single benchmark
class BenchmarkResult {
  /// Name of the benchmark
  final String name;

  /// Number of iterations run
  final int iterations;

  /// Total duration
  final Duration totalDuration;

  /// Duration per operation
  Duration get perOperation =>
      Duration(microseconds: totalDuration.inMicroseconds ~/ iterations);

  /// Operations per second
  double get opsPerSecond =>
      iterations / (totalDuration.inMicroseconds / 1000000);

  /// Throughput in bytes per second (if applicable)
  final int? bytesProcessed;

  double? get throughputMBps {
    if (bytesProcessed == null) return null;
    return bytesProcessed! / (totalDuration.inMicroseconds / 1000000) / (1024 * 1024);
  }

  BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.totalDuration,
    this.bytesProcessed,
  });

  @override
  String toString() {
    final ops = '${opsPerSecond.toStringAsFixed(0)} ops/sec';
    final perOp = '${perOperation.inMicroseconds}μs/op';
    final throughput = throughputMBps != null
        ? ', ${throughputMBps!.toStringAsFixed(2)} MB/s'
        : '';
    return '$name: $ops ($perOp$throughput)';
  }
}

// ============================================================================
// BENCHMARK SUITE
// ============================================================================

/// Performance benchmark suite for BitPack components
///
/// Example:
/// ```dart
/// final suite = BenchmarkSuite();
/// final results = await suite.runAll();
///
/// for (final result in results) {
///   print(result);
/// }
/// ```
class BenchmarkSuite {
  /// Default iterations for quick benchmarks
  final int quickIterations;

  /// Default iterations for full benchmarks
  final int fullIterations;

  BenchmarkSuite({
    this.quickIterations = 1000,
    this.fullIterations = 10000,
  });

  /// Run all benchmarks
  Future<List<BenchmarkResult>> runAll({bool quick = true}) async {
    final iterations = quick ? quickIterations : fullIterations;
    final results = <BenchmarkResult>[];

    results.add(benchmarkSosEncode(iterations));
    results.add(benchmarkSosDecode(iterations));
    results.add(benchmarkTextEncode(iterations));
    results.add(benchmarkTextDecode(iterations));
    results.add(benchmarkCrc8(iterations));
    results.add(await benchmarkPbkdf2(quick ? 10 : 50));
    results.add(await benchmarkAesGcm(iterations));

    return results;
  }

  /// Benchmark SOS packet encoding
  BenchmarkResult benchmarkSosEncode(int iterations) {
    final packet = Packet.sos(
      sosType: SosType.needRescue,
      latitude: 41.0082,
      longitude: 28.9784,
      phoneNumber: '5551234567',
    );

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      packet.encode();
    }
    stopwatch.stop();

    return BenchmarkResult(
      name: 'SOS Encode',
      iterations: iterations,
      totalDuration: stopwatch.elapsed,
      bytesProcessed: iterations * 20,
    );
  }

  /// Benchmark SOS packet decoding
  BenchmarkResult benchmarkSosDecode(int iterations) {
    final packet = Packet.sos(
      sosType: SosType.needRescue,
      latitude: 41.0082,
      longitude: 28.9784,
      phoneNumber: '5551234567',
    );
    final encoded = packet.encode();

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      Packet.decode(encoded);
    }
    stopwatch.stop();

    return BenchmarkResult(
      name: 'SOS Decode',
      iterations: iterations,
      totalDuration: stopwatch.elapsed,
      bytesProcessed: iterations * encoded.length,
    );
  }

  /// Benchmark text packet encoding
  BenchmarkResult benchmarkTextEncode(int iterations) {
    final packet = Packet.text(
      text: 'Hello, this is a test message for benchmarking purposes!',
      senderId: 'user123',
    );

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      packet.encode();
    }
    stopwatch.stop();

    return BenchmarkResult(
      name: 'Text Encode',
      iterations: iterations,
      totalDuration: stopwatch.elapsed,
      bytesProcessed: iterations * packet.sizeInBytes,
    );
  }

  /// Benchmark text packet decoding
  BenchmarkResult benchmarkTextDecode(int iterations) {
    final packet = Packet.text(
      text: 'Hello, this is a test message for benchmarking purposes!',
      senderId: 'user123',
    );
    final encoded = packet.encode();

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      Packet.decode(encoded);
    }
    stopwatch.stop();

    return BenchmarkResult(
      name: 'Text Decode',
      iterations: iterations,
      totalDuration: stopwatch.elapsed,
      bytesProcessed: iterations * encoded.length,
    );
  }

  /// Benchmark CRC-8 computation
  BenchmarkResult benchmarkCrc8(int iterations) {
    final data = Uint8List.fromList(List.generate(100, (i) => i));

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      Crc8.compute(data);
    }
    stopwatch.stop();

    return BenchmarkResult(
      name: 'CRC-8',
      iterations: iterations,
      totalDuration: stopwatch.elapsed,
      bytesProcessed: iterations * data.length,
    );
  }

  /// Benchmark PBKDF2 key derivation
  Future<BenchmarkResult> benchmarkPbkdf2(int iterations) async {
    final salt = KeyDerivation.generateSalt();
    const password = 'benchmark-password-12345';

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await KeyDerivation.deriveKey(
        password: password,
        salt: salt,
        iterations: 10000,
      );
    }
    stopwatch.stop();

    return BenchmarkResult(
      name: 'PBKDF2 (10K iter)',
      iterations: iterations,
      totalDuration: stopwatch.elapsed,
    );
  }

  /// Benchmark AES-GCM encryption/decryption
  Future<BenchmarkResult> benchmarkAesGcm(int iterations) async {
    final key = Uint8List.fromList(List.generate(16, (i) => i));
    final plaintext = Uint8List.fromList(
      List.generate(64, (i) => i),
    );

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final encrypted = await AesGcmCipher.encrypt(
        plaintext: plaintext,
        key: key,
      );
      await AesGcmCipher.decrypt(
        ciphertext: encrypted,
        key: key,
      );
    }
    stopwatch.stop();

    return BenchmarkResult(
      name: 'AES-GCM roundtrip',
      iterations: iterations,
      totalDuration: stopwatch.elapsed,
      bytesProcessed: iterations * plaintext.length * 2,
    );
  }

  /// Print benchmark results summary
  void printSummary(List<BenchmarkResult> results) {
    print('=== BitPack Benchmark Results ===');
    print('');
    for (final result in results) {
      print(result);
    }
    print('');
    print('================================');
  }
}
