import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bit_pack/bit_pack.dart';
import 'package:test/test.dart';

// ============================================================================
// REALWORLD E2E STRESS TEST
// ============================================================================

/// Deterministic realworld-style E2E simulation that exercises:
/// - Compact CRC-8 + Standard CRC-32
/// - Mesh relay/backoff/cancel/duplicate handling
/// - Fragmentation + selective-repeat NACK + reassembly
/// - Crypto primitives (PBKDF2 + AES-GCM) with tamper checks
/// - Basic performance metrics (ops/sec, throughput)
void main() {
  test('realworld_e2e_stress', () async {
    final perfMode = Platform.environment['BITPACK_PERF'] == '1';
    final seed = int.tryParse(Platform.environment['BITPACK_SEED'] ?? '') ?? 42;
    final rng = Random(seed);

    // Keep default runs fast/non-flaky; heavy perf mode is opt-in.
    final iterations = perfMode ? 20000 : 2000;
    final cryptoIterations = perfMode ? 5 : 1;

    final metrics = _Metrics(seed: seed, perfMode: perfMode);

    // Phase A: Compact SOS mesh broadcast with duplicates + CRC drop.
    await _phaseA_compactMesh(
      rng: rng,
      metrics: metrics,
      ttl: 3,
    );

    // Phase B: Standard relay backoff cancel + Standard CRC-32 drop.
    await _phaseB_standardCancel(
      rng: rng,
      metrics: metrics,
    );

    // Phase C: Fragmentation + NACK + reassembly (including corrupted fragment).
    await _phaseC_fragmentationSelectiveRepeat(
      rng: rng,
      metrics: metrics,
    );

    // Phase D: Crypto (PBKDF2 + AES-GCM) + tamper + CRC gating demonstration.
    await _phaseD_cryptoEnvelope(
      rng: rng,
      metrics: metrics,
      iterations: cryptoIterations,
    );

    // Performance micro-benchmarks (non-authoritative).
    _perf_basic(
      metrics: metrics,
      iterations: iterations,
    );

    metrics.printSummary();

    // Extremely loose sanity checks (avoid flakiness).
    expect(metrics.compactCrcDrops, greaterThanOrEqualTo(1));
    expect(metrics.standardCrcDrops, greaterThanOrEqualTo(1));
    expect(metrics.meshDuplicatesObserved, greaterThanOrEqualTo(1));
    expect(metrics.meshCancelledRelaysObserved, greaterThanOrEqualTo(1));
    expect(metrics.fragmentNacksSent, greaterThanOrEqualTo(1));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

// ============================================================================
// PHASE A: COMPACT MESH (SOS) + CRC DROP + DUPLICATES
// ============================================================================

Future<void> _phaseA_compactMesh({
  required Random rng,
  required _Metrics metrics,
  required int ttl,
}) async {
  final net = _SimNetwork(
    rng: rng,
    metrics: metrics,
    dropProbability: 0.0,
    duplicateProbability: 0.0,
    corruptProbability: 0.0,
  );

  // Line topology: A -> B -> C -> D
  net.addNode('A', relayDelayMs: 0);
  net.addNode('B', relayDelayMs: 0);
  net.addNode('C', relayDelayMs: 0);
  net.addNode('D', relayDelayMs: 0);

  net.connectBidirectional('A', 'B');
  net.connectBidirectional('B', 'C');
  net.connectBidirectional('C', 'D');

  // Origin: Compact SOS with small TTL to force multi-hop, deterministic id.
  final origin = Packet.sos(
    sosType: SosType.needRescue,
    latitude: 41.0,
    longitude: 28.0,
    messageId: 0xBEEF,
  );

  final originHeader = origin.header as CompactHeader;
  final originWithTtl = Packet(
    header: originHeader.copyWith(ttl: ttl),
    payload: origin.payload,
  );

  // Send once (normal).
  await net.injectFromOrigin('A', originWithTtl);

  // Send duplicate of same bytes to B (should be treated as duplicate).
  final duplicateBytes = originWithTtl.encode();
  await net.deliverBytes(from: 'A', to: 'B', bytes: duplicateBytes);

  // Corrupt and send to C (should be dropped by CRC-8 before decode).
  final corrupted = Uint8List.fromList(duplicateBytes);
  _flipOneByteInPlace(corrupted, preferLastByte: true);
  await net.deliverBytes(from: 'B', to: 'C', bytes: corrupted);

  // Update metrics from observed events.
  metrics.meshDuplicatesObserved += net
      .node('B')
      .events
      .whereType<PacketReceivedEvent>()
      .where((e) => !e.isNew)
      .length;

  // Assertions: D should have received at least one new packet (multi-hop).
  final d = net.node('D');
  final receivedAtD = d.events.whereType<PacketReceivedEvent>().toList();
  expect(receivedAtD.where((e) => e.isNew).length, greaterThanOrEqualTo(1));

  // TTL should be decremented hop-by-hop; the packet that reaches D must have ttl < origin ttl.
  final firstNewAtD =
      receivedAtD.firstWhere((e) => e.isNew).packet.header as CompactHeader;
  expect(firstNewAtD.ttl, lessThan(ttl));

  net.dispose();
}

// ============================================================================
// PHASE B: STANDARD CANCEL (BACKOFF) + CRC-32 DROP
// ============================================================================

Future<void> _phaseB_standardCancel({
  required Random rng,
  required _Metrics metrics,
}) async {
  final net = _SimNetwork(
    rng: rng,
    metrics: metrics,
    dropProbability: 0.0,
    duplicateProbability: 0.0,
    corruptProbability: 0.0,
  );

  // A -> B only; we focus on B cancelling its own pending relay.
  net.addNode('A', relayDelayMs: 0);
  net.addNode('B', relayDelayMs: 30); // must be > 0 to allow cancel window
  net.connectBidirectional('A', 'B');

  final packet = PacketBuilder()
      .text('Standard cancel test', senderId: 'nodeA', recipientId: null)
      .standard()
      .mesh(true)
      .ttl(10)
      .messageId(0x12345678)
      .build();

  final bytes = packet.encode();

  // Deliver once to B (will schedule relay with delay).
  final deliver1 = net.deliverBytes(from: 'A', to: 'B', bytes: bytes);

  // While B is waiting in backoff, deliver duplicate to trigger cancel.
  await Future.delayed(const Duration(milliseconds: 5));
  await net.deliverBytes(from: 'A', to: 'B', bytes: bytes);

  await deliver1;

  // Verify cancel event observed at B.
  final b = net.node('B');
  final cancelled = b.events.whereType<RelayCancelledEvent>().toList();
  expect(cancelled.length, greaterThanOrEqualTo(1));
  metrics.meshCancelledRelaysObserved += cancelled.length;

  // Standard CRC-32 drop: corrupt and ensure decode is rejected.
  final corrupted = Uint8List.fromList(bytes);
  _flipOneByteInPlace(corrupted, preferLastByte: true); // hit CRC-32 bytes
  await net.deliverBytes(from: 'A', to: 'B', bytes: corrupted);
  expect(metrics.standardCrcDrops, greaterThanOrEqualTo(1));

  net.dispose();
}

// ============================================================================
// PHASE C: FRAGMENTATION + NACK + REASSEMBLY (INCLUDING CORRUPTION)
// ============================================================================

Future<void> _phaseC_fragmentationSelectiveRepeat({
  required Random rng,
  required _Metrics metrics,
}) async {
  // Build a large Standard payload and fragment it into Standard *fragment packets*.
  //
  // IMPORTANT: With packet-level CRC-32 enforcement, a corrupted fragment must be
  // rejected by Packet.decode (fail-fast) and never reach the reassembly buffer.
  final largeText = List.filled(8000, 'A').join(); // upper-ish bound
  final payload =
      TextPayload(text: largeText, senderId: 'sender', recipientId: null);
  final payloadBytes = payload.encode();

  final messageId = 0xCAFEBABE;
  const ttl = 20;

  // Intentionally small MTU to force many fragments.
  final mtu = 64;
  final fragmenter = Fragmenter(mtu: mtu);
  final fragmentPackets = fragmenter.fragmentWithHeaders(
    payload: payloadBytes,
    messageId: messageId,
    messageType: payload.type,
    ttl: ttl,
  );
  expect(fragmentPackets.length, greaterThan(1));

  final totalFragments = fragmentPackets.length;
  final buffer =
      FragmentBuffer(messageId: messageId, totalFragments: totalFragments);
  final strategy = SelectiveRepeatStrategy(
    maxRetries: 3,
    retryInterval: const Duration(milliseconds: 0),
    onSendNack: (_) {},
  );

  final packetReassembler = PacketFragmentReassembler();
  Packet? full;

  // Deliver fragment *packets* out-of-order with one missing and one corrupted on-wire.
  final indices = List<int>.generate(totalFragments, (i) => i)..shuffle(rng);

  // Pick one missing and one corrupt (distinct).
  final missingIndex = indices.first;
  final corruptIndex = indices.length > 1 ? indices[1] : indices.first;

  for (final i in indices) {
    if (i == missingIndex) continue; // drop

    final delivered = Uint8List.fromList(fragmentPackets[i]);
    if (i == corruptIndex) {
      // Any byte flip must be rejected by CRC-32 at Packet.decode.
      _flipOneByteInPlace(delivered, preferLastByte: true);
    }

    Packet decoded;
    try {
      decoded = Packet.decode(delivered);
    } catch (e) {
      // CRC fail-fast: corrupted fragment never reaches buffers.
      metrics.standardCrcDrops++;
      continue;
    }

    expect(decoded.header, isA<StandardHeader>());
    expect(decoded.header.flags.isFragment, isTrue);
    expect(decoded.payload, isA<RawPayload>());

    final raw = decoded.payload as RawPayload;
    final fragHeader = FragmentHeader.decode(raw.bytes, 0);
    final chunk = raw.bytes.sublist(FragmentHeader.sizeInBytes);

    buffer.addFragment(fragHeader.fragmentIndex, Uint8List.fromList(chunk));
    full = packetReassembler.addFragmentPacket(decoded) ?? full;
  }

  // At this point we should have a gap -> NACK.
  final nack1 = strategy.generateNack(buffer);
  expect(nack1, isNotNull);
  metrics.fragmentNacksSent++;
  final missingRequested = nack1!.allMissingIndices;
  expect(missingRequested, contains(missingIndex));
  // Corrupted fragment was dropped by CRC, so it should also be requested.
  if (corruptIndex != missingIndex) {
    expect(missingRequested, contains(corruptIndex));
  }

  // Sender re-sends missing fragments (clean packets).
  for (final idx in missingRequested) {
    final decoded = Packet.decode(fragmentPackets[idx]);
    final raw = decoded.payload as RawPayload;
    final fragHeader = FragmentHeader.decode(raw.bytes, 0);
    final chunk = raw.bytes.sublist(FragmentHeader.sizeInBytes);

    buffer.addFragment(fragHeader.fragmentIndex, Uint8List.fromList(chunk));
    full = packetReassembler.addFragmentPacket(decoded) ?? full;
  }

  // Now complete and must decode cleanly (corrupted fragment never entered).
  expect(buffer.isComplete, isTrue);
  expect(full, isNotNull);
  expect(full!.type, equals(MessageType.textShort));
  expect(full!.payload, equals(payload));
}

// ============================================================================
// PHASE D: CRYPTO ENVELOPE (CRC GATING + AUTH TAG)
// ============================================================================

Future<void> _phaseD_cryptoEnvelope({
  required Random rng,
  required _Metrics metrics,
  required int iterations,
}) async {
  // We model the desired "zarf+mühür" pattern at byte level:
  // [headerBytes][ciphertextBytes][crc32]
  // CRC-32 is checked before attempting AES-GCM decrypt.

  int decryptAttempts = 0;

  for (int i = 0; i < iterations; i++) {
    final header = StandardHeader(
      type: MessageType.dataEncrypted,
      flags: PacketFlags(mesh: false, encrypted: true),
      hopTtl: 10,
      messageId: 0x90000000 + i,
      securityMode: SecurityMode.symmetric,
      payloadLength: 0, // not used here
      ageMinutes: 0,
    );
    final headerBytes = header.encode();

    final salt = KeyDerivation.generateSalt();
    final key = await KeyDerivation.deriveKey(
      password: 'shared-secret',
      salt: salt,
      keyLength: 16,
      iterations: 10000,
    );

    final plaintext = Uint8List.fromList(utf8.encode('secret-payload-$i'));
    final ciphertext = await AesGcmCipher.encryptWithHeader(
      plaintext: plaintext,
      key: key,
      header: headerBytes,
    );

    final envelope = _EncryptedEnvelope(
      headerBytes: headerBytes,
      ciphertext: ciphertext,
    );

    // 1) Random corruption => CRC fails => decrypt not attempted.
    final corrupted = envelope.toBytes();
    _flipOneByteInPlace(corrupted, preferLastByte: true);
    try {
      _EncryptedEnvelope.parseAndVerify(corrupted);
      fail('Expected CRC mismatch');
    } catch (_) {
      metrics.standardCrcDrops++;
    }

    // 2) Malicious/tamper with recomputed CRC => CRC passes but AES-GCM must fail.
    final tampered = envelope.toBytes();
    // Flip a byte in ciphertext area (not CRC) and recompute CRC to keep envelope "sealed".
    final tamperedEnvelope = _EncryptedEnvelope.parseAndVerify(tampered);
    final tamperedCipher = Uint8List.fromList(tamperedEnvelope.ciphertext);
    _flipOneByteInPlace(tamperedCipher, preferLastByte: false);
    final rewrapped = _EncryptedEnvelope(
      headerBytes: tamperedEnvelope.headerBytes,
      ciphertext: tamperedCipher,
    ).toBytes();

    final verified = _EncryptedEnvelope.parseAndVerify(rewrapped);
    try {
      decryptAttempts++;
      await AesGcmCipher.decryptWithHeader(
        ciphertext: verified.ciphertext,
        key: key,
        header: verified.headerBytes,
      );
      fail('Expected AuthenticationException');
    } on AuthenticationException {
      // expected
    }
  }

  expect(decryptAttempts, equals(iterations));
}

// ============================================================================
// PERF (BASIC, NON-AUTHORITATIVE)
// ============================================================================

void _perf_basic({
  required _Metrics metrics,
  required int iterations,
}) {
  // Compact encode+decode (cold encode: new packet each time).
  final swCompact = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final p = Packet.sos(
      sosType: SosType.needRescue,
      latitude: 41.0,
      longitude: 28.0,
      messageId: i & 0xFFFF,
    );
    final bytes = p.encode();
    Packet.decode(bytes);
  }
  swCompact.stop();
  metrics.compactOpsPerSec =
      iterations / (swCompact.elapsedMicroseconds / 1000000);

  // Standard encode+decode (cold encode).
  final swStandard = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    final payload = TextPayload(text: 'Hello-$i', senderId: 's', recipientId: null);
    final header = StandardHeader(
      type: payload.type,
      flags: PacketFlags(mesh: false),
      hopTtl: 10,
      messageId: i,
      securityMode: SecurityMode.none,
      payloadLength: payload.sizeInBytes,
      ageMinutes: 0,
    );
    final p = Packet(header: header, payload: payload);
    final bytes = p.encode();
    Packet.decode(bytes);
  }
  swStandard.stop();
  metrics.standardOpsPerSec =
      iterations / (swStandard.elapsedMicroseconds / 1000000);
}

// ============================================================================
// SIMULATION HARNESS (MESH)
// ============================================================================

class _SimNetwork {
  final Random rng;
  final _Metrics metrics;
  final double dropProbability;
  final double duplicateProbability;
  final double corruptProbability;

  final Map<String, _SimNode> _nodes = {};
  final Map<String, Set<String>> _adj = {};

  _SimNetwork({
    required this.rng,
    required this.metrics,
    required this.dropProbability,
    required this.duplicateProbability,
    required this.corruptProbability,
  });

  void addNode(String id, {required int relayDelayMs}) {
    final node = _SimNode(
      id: id,
      relayDelayMs: relayDelayMs,
      onBroadcast: (packet) async {
        await broadcastPacket(from: id, packet: packet);
      },
    );
    _nodes[id] = node;
    _adj.putIfAbsent(id, () => <String>{});
  }

  _SimNode node(String id) => _nodes[id]!;

  void connectBidirectional(String a, String b) {
    _adj.putIfAbsent(a, () => <String>{}).add(b);
    _adj.putIfAbsent(b, () => <String>{}).add(a);
  }

  Future<void> injectFromOrigin(String originId, Packet packet) async {
    await broadcastBytes(from: originId, bytes: packet.encode());
  }

  Future<void> broadcastPacket({required String from, required Packet packet}) async {
    await broadcastBytes(from: from, bytes: packet.encode());
  }

  Future<void> broadcastBytes({required String from, required Uint8List bytes}) async {
    final neighbors = _adj[from]?.toList() ?? const <String>[];
    for (final to in neighbors) {
      await deliverBytes(from: from, to: to, bytes: bytes);
    }
  }

  Future<void> deliverBytes({
    required String from,
    required String to,
    required Uint8List bytes,
  }) async {
    // Drop?
    if (dropProbability > 0 && rng.nextDouble() < dropProbability) {
      return;
    }

    // Duplicate?
    final duplicates = <Uint8List>[bytes];
    if (duplicateProbability > 0 && rng.nextDouble() < duplicateProbability) {
      duplicates.add(Uint8List.fromList(bytes));
    }

    for (final original in duplicates) {
      // Corrupt?
      Uint8List delivered = original;
      if (corruptProbability > 0 && rng.nextDouble() < corruptProbability) {
        delivered = Uint8List.fromList(original);
        _flipOneByteInPlace(delivered, preferLastByte: true);
      }

      try {
        final packet = Packet.decode(delivered);
        await _nodes[to]!.mesh.handleIncomingPacket(packet, fromPeerId: from);
      } on CrcMismatchException {
        if (_looksCompact(delivered)) {
          metrics.compactCrcDrops++;
        } else {
          metrics.standardCrcDrops++;
        }
      } catch (_) {
        // Any other decode error: count as drop (but not CRC-specific).
      }
    }
  }

  bool _looksCompact(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    return HeaderFactory.detectMode(bytes[0]) == PacketMode.compact;
  }

  void dispose() {
    for (final n in _nodes.values) {
      n.mesh.dispose();
    }
  }
}

class _SimNode {
  final String id;
  final MeshController mesh;
  final List<MeshEvent> events = [];

  _SimNode({
    required this.id,
    required int relayDelayMs,
    required Future<void> Function(Packet packet) onBroadcast,
  }) : mesh = MeshController(
          cache: MessageCache(),
          policy: RelayPolicy(),
          backoff: RelayBackoff(
            baseDelayMs: relayDelayMs,
            maxDelayMs: relayDelayMs,
            jitterPercent: 0,
            hopMultiplier: 1.0,
            random: Random(1),
          ),
          onBroadcast: onBroadcast,
        ) {
    mesh.events.listen(events.add);
  }
}

// ============================================================================
// ENCRYPTED ENVELOPE (BYTE-LEVEL) FOR PHASE D
// ============================================================================

class _EncryptedEnvelope {
  final Uint8List headerBytes;
  final Uint8List ciphertext;

  _EncryptedEnvelope({
    required this.headerBytes,
    required this.ciphertext,
  });

  Uint8List toBytes() {
    final totalLen = headerBytes.length + ciphertext.length + 4;
    final out = Uint8List(totalLen);
    out.setRange(0, headerBytes.length, headerBytes);
    out.setRange(headerBytes.length, headerBytes.length + ciphertext.length, ciphertext);
    final crc = Crc32.compute(out.sublist(0, totalLen - 4));
    Bitwise.write32BE(out, totalLen - 4, crc);
    return out;
  }

  static _EncryptedEnvelope parseAndVerify(Uint8List bytes) {
    if (bytes.length < StandardHeader.headerSizeInBytes + 4) {
      throw const FormatException('Envelope too short');
    }
    final actual = Bitwise.read32BE(bytes, bytes.length - 4);
    final expected = Crc32.compute(bytes.sublist(0, bytes.length - 4));
    if (actual != expected) {
      throw CrcMismatchException(expected: expected, actual: actual);
    }

    // We only need the header bytes as AAD and ciphertext; header parsing is optional here.
    final headerBytes = bytes.sublist(0, StandardHeader.headerSizeInBytes);
    final ciphertext = bytes.sublist(StandardHeader.headerSizeInBytes, bytes.length - 4);
    return _EncryptedEnvelope(headerBytes: headerBytes, ciphertext: ciphertext);
  }
}

// ============================================================================
// UTIL + METRICS
// ============================================================================

class _Metrics {
  final int seed;
  final bool perfMode;

  int compactCrcDrops = 0;
  int standardCrcDrops = 0;
  int meshDuplicatesObserved = 0;
  int meshCancelledRelaysObserved = 0;
  int fragmentNacksSent = 0;

  double compactOpsPerSec = 0;
  double standardOpsPerSec = 0;

  _Metrics({required this.seed, required this.perfMode});

  void printSummary() {
    // Keep prints concise: 1 block at end.
    // ignore: avoid_print
    print('=== BitPack Realworld E2E Stress Summary ===');
    // ignore: avoid_print
    print('seed=$seed perfMode=$perfMode');
    // ignore: avoid_print
    print('compactCrcDrops=$compactCrcDrops standardCrcDrops=$standardCrcDrops');
    // ignore: avoid_print
    print('meshDuplicatesObserved=$meshDuplicatesObserved meshCancelledRelaysObserved=$meshCancelledRelaysObserved');
    // ignore: avoid_print
    print('fragmentNacksSent=$fragmentNacksSent');
    // ignore: avoid_print
    print('compactOpsPerSec=${compactOpsPerSec.toStringAsFixed(0)} standardOpsPerSec=${standardOpsPerSec.toStringAsFixed(0)}');
    // ignore: avoid_print
    print('===========================================');
  }
}

void _flipOneByteInPlace(Uint8List bytes, {required bool preferLastByte}) {
  if (bytes.isEmpty) return;
  final idx = preferLastByte ? bytes.length - 1 : max(0, bytes.length ~/ 2);
  bytes[idx] ^= 0xFF;
}

