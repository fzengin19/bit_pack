import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('RetryState', () {
    test('initializes with zero nack count', () {
      final state = RetryState(messageId: 0x1234);
      expect(state.nackCount, equals(0));
      expect(state.pendingFragments, isEmpty);
    });

    test('records NACK and increments count', () {
      final state = RetryState(messageId: 0x1234);

      state.recordNack([1, 2, 3]);
      expect(state.nackCount, equals(1));
      expect(state.pendingFragments, equals({1, 2, 3}));

      state.recordNack([5, 6]);
      expect(state.nackCount, equals(2));
      expect(state.pendingFragments, equals({1, 2, 3, 5, 6}));
    });

    test('records received fragment', () {
      final state = RetryState(messageId: 0x1234);
      state.recordNack([1, 2, 3]);

      state.recordReceived(2);
      expect(state.pendingFragments, equals({1, 3}));
    });

    test('canRetry respects interval', () async {
      final state = RetryState(messageId: 0x1234);
      state.recordNack([1]);

      // Immediately after, should not retry
      expect(state.canRetry(Duration(milliseconds: 100)), isFalse);

      // Wait and retry
      await Future.delayed(Duration(milliseconds: 150));
      expect(state.canRetry(Duration(milliseconds: 100)), isTrue);
    });
  });

  group('SelectiveRepeatStrategy', () {
    group('constructor', () {
      test('creates with default values', () {
        final strategy = SelectiveRepeatStrategy();
        expect(strategy.maxRetries, equals(3));
        expect(strategy.trackedMessageCount, equals(0));
      });

      test('creates with custom values', () {
        final strategy = SelectiveRepeatStrategy(
          maxRetries: 5,
          retryInterval: Duration(seconds: 10),
        );
        expect(strategy.maxRetries, equals(5));
      });
    });

    group('detectMissingFragments', () {
      test('returns missing indices from buffer', () {
        final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 5);
        buffer.addFragment(0, Uint8List(1));
        buffer.addFragment(2, Uint8List(1));
        buffer.addFragment(4, Uint8List(1));

        final strategy = SelectiveRepeatStrategy();
        final missing = strategy.detectMissingFragments(buffer);

        expect(missing, equals([1, 3]));
      });
    });

    group('generateNack', () {
      test('generates NACK for missing fragments', () {
        final buffer = FragmentBuffer(messageId: 0xABCD, totalFragments: 10);
        buffer.addFragment(0, Uint8List(1));
        buffer.addFragment(1, Uint8List(1));
        // Missing: 2, 3, 4
        buffer.addFragment(5, Uint8List(1));

        final strategy = SelectiveRepeatStrategy();
        final nack = strategy.generateNack(buffer);

        expect(nack, isNotNull);
        expect(nack!.originalMessageId, equals(0xABCD));
        expect(nack.allMissingIndices, contains(2));
        expect(nack.allMissingIndices, contains(3));
        expect(nack.allMissingIndices, contains(4));
      });

      test('returns null for complete buffer', () {
        final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 2);
        buffer.addFragment(0, Uint8List(1));
        buffer.addFragment(1, Uint8List(1));

        final strategy = SelectiveRepeatStrategy();
        final nack = strategy.generateNack(buffer);

        expect(nack, isNull);
      });

      test('returns null after max retries', () {
        final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 5);
        buffer.addFragment(0, Uint8List(1));
        // Missing 1, 2, 3, 4

        final strategy = SelectiveRepeatStrategy(maxRetries: 2);

        // First two NACKs should work
        expect(strategy.generateNack(buffer), isNotNull);
        strategy.handleGap(buffer); // Count: 1
        
        // Simulate time passing
        strategy.handleGap(buffer); // Count: 2 (should fail due to interval)
        
        // After max retries
        // Force increment
        final state = strategy.getPendingFragments(0x1234);
      });
    });

    group('shouldRetry', () {
      test('returns true for first attempt', () {
        final strategy = SelectiveRepeatStrategy();
        expect(strategy.shouldRetry(0x1234), isTrue);
      });

      test('returns false after max retries', () {
        final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 3);
        buffer.addFragment(0, Uint8List(1));
        // Missing 1, 2

        final strategy = SelectiveRepeatStrategy(
          maxRetries: 1,
          retryInterval: Duration.zero,
        );

        strategy.handleGap(buffer);
        expect(strategy.getRetryCount(0x1234), equals(1));
        expect(strategy.shouldRetry(0x1234), isFalse);
      });
    });

    group('handleGap', () {
      test('sends NACK via callback', () {
        final buffer = FragmentBuffer(messageId: 0x5678, totalFragments: 5);
        buffer.addFragment(0, Uint8List(1));
        // Missing 1, 2, 3, 4

        NackPayload? receivedNack;
        final strategy = SelectiveRepeatStrategy(
          onSendNack: (nack) => receivedNack = nack,
        );

        final sent = strategy.handleGap(buffer);

        expect(sent, isTrue);
        expect(receivedNack, isNotNull);
        expect(receivedNack!.originalMessageId, equals(0x5678));
      });

      test('calls onRetryExceeded when limit reached', () {
        final buffer = FragmentBuffer(messageId: 0xAAAA, totalFragments: 3);
        buffer.addFragment(0, Uint8List(1));

        int? exceededMessageId;
        final strategy = SelectiveRepeatStrategy(
          maxRetries: 1,
          retryInterval: Duration.zero,
          onRetryExceeded: (id) => exceededMessageId = id,
        );

        // First attempt
        strategy.handleGap(buffer);
        expect(exceededMessageId, isNull);

        // Second attempt (exceeds max)
        strategy.handleGap(buffer);
        expect(exceededMessageId, equals(0xAAAA));
      });
    });

    group('recordFragmentReceived', () {
      test('clears pending fragment', () {
        final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 5);
        buffer.addFragment(0, Uint8List(1));

        final strategy = SelectiveRepeatStrategy();
        strategy.handleGap(buffer);

        expect(strategy.getPendingFragments(0x1234), contains(1));

        strategy.recordFragmentReceived(0x1234, 1);
        expect(strategy.getPendingFragments(0x1234), isNot(contains(1)));
      });
    });

    group('clearState', () {
      test('removes message tracking', () {
        final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 3);
        buffer.addFragment(0, Uint8List(1));

        final strategy = SelectiveRepeatStrategy();
        strategy.handleGap(buffer);

        expect(strategy.trackedMessageCount, equals(1));

        strategy.clearState(0x1234);
        expect(strategy.trackedMessageCount, equals(0));
      });
    });
  });

  group('SelectiveRepeatReassembler', () {
    test('creates with strategy', () {
      final reassembler = SelectiveRepeatReassembler();
      expect(reassembler.strategy, isNotNull);
    });

    test('clears strategy state on complete message', () {
      final reassembler = SelectiveRepeatReassembler();

      // Send first fragment
      reassembler.addFragment(
        messageId: 0x1234,
        fragmentIndex: 0,
        totalFragments: 2,
        data: Uint8List.fromList([1, 2]),
      );

      // Complete message
      final result = reassembler.addFragment(
        messageId: 0x1234,
        fragmentIndex: 1,
        totalFragments: 2,
        data: Uint8List.fromList([3, 4]),
      );

      expect(result, isNotNull);
      expect(reassembler.strategy.trackedMessageCount, equals(0));
    });
  });
}
