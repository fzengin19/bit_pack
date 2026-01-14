import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

void main() {
  group('Fragmenter', () {
    group('constructor', () {
      test('creates with default MTU', () {
        final fragmenter = Fragmenter();
        expect(fragmenter.mtu, equals(244));
      });

      test('creates with custom MTU', () {
        final fragmenter = Fragmenter(mtu: 100);
        expect(fragmenter.mtu, equals(100));
      });

      test('throws on MTU below minimum', () {
        expect(
          () => Fragmenter(mtu: 10),
          throwsA(isA<FragmentationException>()),
        );
      });

      test('allows minimum MTU', () {
        final fragmenter = Fragmenter(mtu: 20);
        expect(fragmenter.mtu, equals(20));
      });
    });

    group('needsFragmentation', () {
      test('returns false for data smaller than MTU', () {
        final fragmenter = Fragmenter(mtu: 100);
        final data = Uint8List(50);
        expect(fragmenter.needsFragmentation(data), isFalse);
      });

      test('returns false for data equal to MTU', () {
        final fragmenter = Fragmenter(mtu: 100);
        final data = Uint8List(100);
        expect(fragmenter.needsFragmentation(data), isFalse);
      });

      test('returns true for data larger than MTU', () {
        final fragmenter = Fragmenter(mtu: 100);
        final data = Uint8List(101);
        expect(fragmenter.needsFragmentation(data), isTrue);
      });
    });

    group('fragmentCount', () {
      test('returns 1 for data within MTU', () {
        final fragmenter = Fragmenter(mtu: 100);
        expect(fragmenter.fragmentCount(50), equals(1));
        expect(fragmenter.fragmentCount(100), equals(1));
      });

      test('calculates correct count for larger data', () {
        final fragmenter = Fragmenter(mtu: 100);
        // Note: data <= MTU returns 1 (no fragmentation needed)
        // Payload per fragment = MTU - 3 (fragment header) = 97
        expect(fragmenter.fragmentCount(100), equals(1)); // Fits in MTU
        expect(fragmenter.fragmentCount(101), equals(2)); // Needs 2 fragments
        expect(fragmenter.fragmentCount(194), equals(2)); // 97 + 97 = 194
        expect(fragmenter.fragmentCount(195), equals(3)); // 97 + 97 + 1 = 195
      });
    });

    group('fragment', () {
      test('returns single item for small data', () {
        final fragmenter = Fragmenter(mtu: 100);
        final data = Uint8List.fromList(List.generate(50, (i) => i));

        final fragments = fragmenter.fragment(data, 0x1234);
        expect(fragments.length, equals(1));
        expect(fragments[0], equals(data));
      });

      test('splits large data into fragments', () {
        final fragmenter = Fragmenter(mtu: 50);
        final data = Uint8List.fromList(List.generate(100, (i) => i));

        final fragments = fragmenter.fragment(data, 0x1234);
        expect(fragments.length, greaterThan(1));

        // Each fragment should be <= MTU
        for (final fragment in fragments) {
          expect(fragment.length, lessThanOrEqualTo(50));
        }
      });

      test('fragments can be reassembled', () {
        final fragmenter = Fragmenter(mtu: 50);
        final data = Uint8List.fromList(List.generate(150, (i) => i));

        final fragments = fragmenter.fragment(data, 0xABCD);

        // Manually reassemble (skip fragment headers)
        final reassembled = <int>[];
        for (final fragment in fragments) {
          // First 3 bytes are fragment header
          reassembled.addAll(fragment.sublist(FragmentHeader.sizeInBytes));
        }

        expect(Uint8List.fromList(reassembled), equals(data));
      });

      test('each fragment has valid header', () {
        final fragmenter = Fragmenter(mtu: 50);
        final data = Uint8List.fromList(List.generate(200, (i) => i));

        final fragments = fragmenter.fragment(data, 0x5678);

        for (int i = 0; i < fragments.length; i++) {
          final header = FragmentHeader.decode(fragments[i]);
          expect(header.fragmentIndex, equals(i));
          expect(header.totalFragments, equals(fragments.length));
        }
      });

      test('throws on data too large', () {
        final fragmenter = Fragmenter(mtu: 50);
        // Would need > 4096 fragments
        // payloadPerFragment = 50 - 3 = 47
        // 4096 * 47 = 192512 bytes max
        final hugeData = Uint8List(200000);

        expect(
          () => fragmenter.fragment(hugeData, 0x1234),
          throwsA(isA<FragmentationException>()),
        );
      });
    });

    group('properties', () {
      test('maxPayloadWithoutFragmentation equals MTU', () {
        final fragmenter = Fragmenter(mtu: 244);
        expect(fragmenter.maxPayloadWithoutFragmentation, equals(244));
      });

      test('maxPayloadPerFragment accounts for header', () {
        final fragmenter = Fragmenter(mtu: 244);
        expect(fragmenter.maxPayloadPerFragment, equals(241)); // 244 - 3
      });
    });

    group('fragmentWithHeaders (Standard packets)', () {
      test('single packet includes CRC-32 and decodes', () {
        final fragmenter = Fragmenter(mtu: 64);
        final payload = TextPayload(text: 'Hello', senderId: 's', recipientId: null);
        final payloadBytes = payload.encode();

        final packets = fragmenter.fragmentWithHeaders(
          payload: payloadBytes,
          messageId: 0x12345678,
          messageType: payload.type,
          ttl: 10,
        );

        expect(packets.length, equals(1));
        expect(packets[0].length, lessThanOrEqualTo(64));

        final decoded = Packet.decode(packets[0]);
        expect(decoded.header, isA<StandardHeader>());
        expect(decoded.header.flags.isFragment, isFalse);
        expect(decoded.payload, equals(payload));
      });

      test('fragment packets include CRC-32 and decode to RawPayload', () {
        final fragmenter = Fragmenter(mtu: 32); // force many fragments
        final payload = Uint8List.fromList(List.generate(200, (i) => i & 0xFF));

        final packets = fragmenter.fragmentWithHeaders(
          payload: payload,
          messageId: 0xCAFEBABE,
          messageType: MessageType.textShort,
          ttl: 20,
        );

        expect(packets.length, greaterThan(1));
        for (final p in packets) {
          expect(p.length, lessThanOrEqualTo(32));
          final decoded = Packet.decode(p);
          expect(decoded.header, isA<StandardHeader>());
          expect(decoded.header.flags.isFragment, isTrue);
          expect(decoded.payload, isA<RawPayload>());
        }
      });

      test('corrupted fragment fails fast at Packet.decode (CRC mismatch)', () {
        final fragmenter = Fragmenter(mtu: 32);
        final payload = Uint8List.fromList(List.generate(200, (i) => i & 0xFF));

        final packets = fragmenter.fragmentWithHeaders(
          payload: payload,
          messageId: 0xDEADBEEF,
          messageType: MessageType.textShort,
          ttl: 20,
        );
        expect(packets.length, greaterThan(1));

        final corrupted = Uint8List.fromList(packets[0]);
        // Flip a byte near the end to likely hit CRC trailer.
        corrupted[corrupted.length - 1] ^= 0xFF;

        expect(
          () => Packet.decode(corrupted),
          throwsA(isA<CrcMismatchException>()),
        );
      });

      test('reassembles to full Packet (typed) from fragment packets', () {
        final fragmenter = Fragmenter(mtu: 48);
        final payload = TextPayload(text: 'X' * 1000, senderId: 's', recipientId: null);
        final payloadBytes = payload.encode();

        final packets = fragmenter.fragmentWithHeaders(
          payload: payloadBytes,
          messageId: 0xA1B2C3D4,
          messageType: payload.type,
          ttl: 20,
        );
        expect(packets.length, greaterThan(1));

        final reassembler = PacketFragmentReassembler();
        Packet? full;
        for (final bytes in packets) {
          final frag = Packet.decode(bytes);
          full = reassembler.addFragmentPacket(frag) ?? full;
        }

        expect(full, isNotNull);
        expect(full!.header, isA<StandardHeader>());
        expect(full!.header.flags.isFragment, isFalse);
        expect(full!.payload, equals(payload));
      });
    });
  });

  group('Reassembler', () {
    group('constructor', () {
      test('creates with default values', () {
        final reassembler = Reassembler();
        expect(reassembler.activeBufferCount, equals(0));
      });

      test('creates with custom timeout', () {
        final reassembler = Reassembler(timeout: Duration(seconds: 30));
        expect(reassembler.activeBufferCount, equals(0));
      });
    });

    group('addFragment', () {
      test('returns null for incomplete message', () {
        final reassembler = Reassembler();

        final result = reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 0,
          totalFragments: 3,
          data: Uint8List.fromList([1, 2, 3]),
        );

        expect(result, isNull);
        expect(reassembler.activeBufferCount, equals(1));
      });

      test('returns data when all fragments received', () {
        final reassembler = Reassembler();

        // Add fragments in order
        reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 0,
          totalFragments: 3,
          data: Uint8List.fromList([1, 2, 3]),
        );

        reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 1,
          totalFragments: 3,
          data: Uint8List.fromList([4, 5, 6]),
        );

        final result = reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 2,
          totalFragments: 3,
          data: Uint8List.fromList([7, 8, 9]),
        );

        expect(result, isNotNull);
        expect(result, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])));
        expect(reassembler.activeBufferCount, equals(0)); // Buffer removed
      });

      test('handles out-of-order fragments', () {
        final reassembler = Reassembler();

        // Add fragments out of order
        reassembler.addFragment(
          messageId: 0x5678,
          fragmentIndex: 2,
          totalFragments: 3,
          data: Uint8List.fromList([7, 8, 9]),
        );

        reassembler.addFragment(
          messageId: 0x5678,
          fragmentIndex: 0,
          totalFragments: 3,
          data: Uint8List.fromList([1, 2, 3]),
        );

        final result = reassembler.addFragment(
          messageId: 0x5678,
          fragmentIndex: 1,
          totalFragments: 3,
          data: Uint8List.fromList([4, 5, 6]),
        );

        expect(result, isNotNull);
        expect(result, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])));
      });

      test('handles multiple concurrent messages', () {
        final reassembler = Reassembler();

        // Message A fragment 0
        reassembler.addFragment(
          messageId: 0xAAAA,
          fragmentIndex: 0,
          totalFragments: 2,
          data: Uint8List.fromList([0xA0]),
        );

        // Message B fragment 0
        reassembler.addFragment(
          messageId: 0xBBBB,
          fragmentIndex: 0,
          totalFragments: 2,
          data: Uint8List.fromList([0xB0]),
        );

        expect(reassembler.activeBufferCount, equals(2));

        // Complete message A
        final resultA = reassembler.addFragment(
          messageId: 0xAAAA,
          fragmentIndex: 1,
          totalFragments: 2,
          data: Uint8List.fromList([0xA1]),
        );

        expect(resultA, equals(Uint8List.fromList([0xA0, 0xA1])));
        expect(reassembler.activeBufferCount, equals(1));

        // Complete message B
        final resultB = reassembler.addFragment(
          messageId: 0xBBBB,
          fragmentIndex: 1,
          totalFragments: 2,
          data: Uint8List.fromList([0xB1]),
        );

        expect(resultB, equals(Uint8List.fromList([0xB0, 0xB1])));
        expect(reassembler.activeBufferCount, equals(0));
      });

      test('throws on invalid fragment index', () {
        final reassembler = Reassembler();

        expect(
          () => reassembler.addFragment(
            messageId: 0x1234,
            fragmentIndex: 5,
            totalFragments: 3,
            data: Uint8List(5),
          ),
          throwsA(isA<FragmentationException>()),
        );
      });

      test('throws on fragment count mismatch', () {
        final reassembler = Reassembler();

        reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 0,
          totalFragments: 5,
          data: Uint8List(5),
        );

        expect(
          () => reassembler.addFragment(
            messageId: 0x1234,
            fragmentIndex: 1,
            totalFragments: 10, // Mismatch!
            data: Uint8List(5),
          ),
          throwsA(isA<FragmentationException>()),
        );
      });
    });

    group('getProgress', () {
      test('returns null for unknown message', () {
        final reassembler = Reassembler();
        expect(reassembler.getProgress(0x9999), isNull);
      });

      test('returns correct progress', () {
        final reassembler = Reassembler();

        reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 0,
          totalFragments: 5,
          data: Uint8List(10),
        );

        reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 2,
          totalFragments: 5,
          data: Uint8List(10),
        );

        final progress = reassembler.getProgress(0x1234);
        expect(progress, isNotNull);
        expect(progress!.received, equals(2));
        expect(progress.total, equals(5));
      });
    });

    group('cleanup', () {
      test('removes expired buffers', () async {
        final reassembler = Reassembler(
          timeout: Duration(milliseconds: 50),
        );

        reassembler.addFragment(
          messageId: 0x1234,
          fragmentIndex: 0,
          totalFragments: 5,
          data: Uint8List(10),
        );

        expect(reassembler.activeBufferCount, equals(1));

        // Wait for timeout
        await Future.delayed(Duration(milliseconds: 100));

        final removed = reassembler.cleanup();
        expect(removed, equals(1));
        expect(reassembler.activeBufferCount, equals(0));
      });
    });

    group('clear', () {
      test('removes all buffers', () {
        final reassembler = Reassembler();

        reassembler.addFragment(
          messageId: 0x1111,
          fragmentIndex: 0,
          totalFragments: 2,
          data: Uint8List(5),
        );

        reassembler.addFragment(
          messageId: 0x2222,
          fragmentIndex: 0,
          totalFragments: 2,
          data: Uint8List(5),
        );

        expect(reassembler.activeBufferCount, equals(2));

        reassembler.clear();
        expect(reassembler.activeBufferCount, equals(0));
      });
    });
  });

  group('FragmentBuffer', () {
    test('tracks received fragments', () {
      final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 5);

      expect(buffer.receivedCount, equals(0));
      expect(buffer.missingCount, equals(5));

      buffer.addFragment(0, Uint8List.fromList([1]));
      expect(buffer.receivedCount, equals(1));
      expect(buffer.missingCount, equals(4));

      buffer.addFragment(2, Uint8List.fromList([3]));
      expect(buffer.receivedCount, equals(2));
      expect(buffer.missingCount, equals(3));
    });

    test('identifies missing indices', () {
      final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 5);
      buffer.addFragment(0, Uint8List(1));
      buffer.addFragment(2, Uint8List(1));
      buffer.addFragment(4, Uint8List(1));

      expect(buffer.missingIndices, equals([1, 3]));
    });

    test('hasAllUpTo works correctly', () {
      final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 5);
      buffer.addFragment(0, Uint8List(1));
      buffer.addFragment(1, Uint8List(1));
      buffer.addFragment(3, Uint8List(1));

      expect(buffer.hasAllUpTo(2), isTrue);
      expect(buffer.hasAllUpTo(3), isFalse); // Missing index 2
    });

    test('isComplete when all fragments received', () {
      final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 3);

      expect(buffer.isComplete, isFalse);

      buffer.addFragment(0, Uint8List(1));
      buffer.addFragment(1, Uint8List(1));
      expect(buffer.isComplete, isFalse);

      buffer.addFragment(2, Uint8List(1));
      expect(buffer.isComplete, isTrue);
    });

    test('reassemble combines fragments in order', () {
      final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 3);
      buffer.addFragment(2, Uint8List.fromList([7, 8, 9]));
      buffer.addFragment(0, Uint8List.fromList([1, 2, 3]));
      buffer.addFragment(1, Uint8List.fromList([4, 5, 6]));

      final result = buffer.reassemble();
      expect(result, equals(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])));
    });

    test('reassemble throws if incomplete', () {
      final buffer = FragmentBuffer(messageId: 0x1234, totalFragments: 3);
      buffer.addFragment(0, Uint8List(1));

      expect(
        () => buffer.reassemble(),
        throwsA(isA<MissingFragmentException>()),
      );
    });
  });

  group('Integration: Fragmenter + Reassembler', () {
    test('roundtrip fragmentation and reassembly', () {
      final fragmenter = Fragmenter(mtu: 50);
      final reassembler = Reassembler();

      // Original data
      final original = Uint8List.fromList(
        List.generate(200, (i) => i % 256),
      );

      // Fragment
      final fragments = fragmenter.fragment(original, 0xABCD);
      expect(fragments.length, greaterThan(1));

      // Reassemble
      Uint8List? result;
      for (int i = 0; i < fragments.length; i++) {
        final header = FragmentHeader.decode(fragments[i]);
        final data = fragments[i].sublist(FragmentHeader.sizeInBytes);

        result = reassembler.addFragment(
          messageId: 0xABCD,
          fragmentIndex: header.fragmentIndex,
          totalFragments: header.totalFragments,
          data: data,
        );
      }

      expect(result, isNotNull);
      expect(result, equals(original));
    });

    test('roundtrip with out-of-order delivery', () {
      final fragmenter = Fragmenter(mtu: 30);
      final reassembler = Reassembler();

      final original = Uint8List.fromList(List.generate(100, (i) => i));
      final fragments = fragmenter.fragment(original, 0x9999);

      // Shuffle fragments
      final shuffled = List<Uint8List>.from(fragments)..shuffle();

      Uint8List? result;
      for (final fragment in shuffled) {
        final header = FragmentHeader.decode(fragment);
        final data = fragment.sublist(FragmentHeader.sizeInBytes);

        result = reassembler.addFragment(
          messageId: 0x9999,
          fragmentIndex: header.fragmentIndex,
          totalFragments: header.totalFragments,
          data: data,
        );
      }

      expect(result, isNotNull);
      expect(result, equals(original));
    });
  });
}
