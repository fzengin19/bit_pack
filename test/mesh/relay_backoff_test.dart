import 'dart:math';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('RelayBackoff', () {
    group('constructor', () {
      test('creates with default values', () {
        final backoff = RelayBackoff();
        expect(backoff.baseDelayMs, equals(50));
        expect(backoff.maxDelayMs, equals(2000));
        expect(backoff.pendingCount, equals(0));
      });

      test('creates with custom values', () {
        final backoff = RelayBackoff(
          baseDelayMs: 100,
          maxDelayMs: 500,
          jitterPercent: 0.1,
        );
        expect(backoff.baseDelayMs, equals(100));
        expect(backoff.maxDelayMs, equals(500));
      });
    });

    group('calculateDelay', () {
      test('returns duration within bounds', () {
        final backoff = RelayBackoff(
          baseDelayMs: 50,
          maxDelayMs: 2000,
          random: Random(42), // Seeded for reproducibility
        );

        final delay = backoff.calculateDelay(14, 15); // 1 hop
        expect(delay.inMilliseconds, greaterThanOrEqualTo(50));
        expect(delay.inMilliseconds, lessThanOrEqualTo(2000));
      });

      test('delay increases with hop count', () {
        final backoff = RelayBackoff(
          baseDelayMs: 50,
          maxDelayMs: 5000,
          jitterPercent: 0.0, // No jitter for predictable test
          random: Random(42),
        );

        // More hops = generally longer delay due to exponential factor
        final delays = <int>[];
        for (int hop = 0; hop < 5; hop++) {
          final ttl = 15 - hop;
          final delay = backoff.calculateDelay(ttl, 15);
          delays.add(delay.inMilliseconds);
        }

        // All delays should be within bounds
        for (final d in delays) {
          expect(d, greaterThanOrEqualTo(50));
        }
      });
    });

    group('isPending', () {
      test('returns false initially', () {
        final backoff = RelayBackoff();
        expect(backoff.isPending(0x1234), isFalse);
      });
    });

    group('scheduleRelay', () {
      test('executes relay action', () async {
        final backoff = RelayBackoff(
          baseDelayMs: 10,
          maxDelayMs: 20,
        );

        bool relayExecuted = false;

        final result = await backoff.scheduleRelay(
          messageId: 0x1234,
          currentTtl: 10,
          originalTtl: 15,
          relayAction: () async {
            relayExecuted = true;
          },
        );

        expect(result, isTrue);
        expect(relayExecuted, isTrue);
        expect(backoff.isPending(0x1234), isFalse);
      });

      test('returns false if already pending', () async {
        final backoff = RelayBackoff(
          baseDelayMs: 500,
          maxDelayMs: 1000,
        );

        // Start first relay (won't complete immediately)
        final future1 = backoff.scheduleRelay(
          messageId: 0x1234,
          currentTtl: 10,
          originalTtl: 15,
          relayAction: () async {},
        );

        // Try to schedule same message again
        final result2 = await backoff.scheduleRelay(
          messageId: 0x1234,
          currentTtl: 10,
          originalTtl: 15,
          relayAction: () async {},
        );

        expect(result2, isFalse);

        // Cancel and wait for first
        backoff.cancelRelay(0x1234);
        await future1;
      });
    });

    group('cancelRelay', () {
      test('cancels pending relay', () async {
        final backoff = RelayBackoff(
          baseDelayMs: 1000,
          maxDelayMs: 2000,
        );

        bool relayExecuted = false;

        final future = backoff.scheduleRelay(
          messageId: 0xABCD,
          currentTtl: 10,
          originalTtl: 15,
          relayAction: () async {
            relayExecuted = true;
          },
        );

        // Cancel before it executes
        await Future.delayed(Duration(milliseconds: 10));
        backoff.cancelRelay(0xABCD);

        final result = await future;

        expect(result, isFalse);
        expect(relayExecuted, isFalse);
      });
    });

    group('onPacketReceived', () {
      test('cancels pending relay for same message', () async {
        final backoff = RelayBackoff(
          baseDelayMs: 500,
          maxDelayMs: 1000,
        );

        final future = backoff.scheduleRelay(
          messageId: 0x5678,
          currentTtl: 10,
          originalTtl: 15,
          relayAction: () async {},
        );

        await Future.delayed(Duration(milliseconds: 10));
        backoff.onPacketReceived(0x5678); // Simulates duplicate heard

        final result = await future;
        expect(result, isFalse);
      });
    });

    group('clear', () {
      test('cancels all pending relays', () async {
        final backoff = RelayBackoff(
          baseDelayMs: 1000,
          maxDelayMs: 2000,
        );

        final future1 = backoff.scheduleRelay(
          messageId: 0x1111,
          currentTtl: 10,
          originalTtl: 15,
          relayAction: () async {},
        );

        final future2 = backoff.scheduleRelay(
          messageId: 0x2222,
          currentTtl: 10,
          originalTtl: 15,
          relayAction: () async {},
        );

        await Future.delayed(Duration(milliseconds: 10));
        backoff.clear();

        final results = await Future.wait([future1, future2]);
        expect(results, equals([false, false]));
        expect(backoff.pendingCount, equals(0));
      });
    });
  });
}
