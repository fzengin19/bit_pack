## BitPack – Sohbet Snapshot (2026-01-14)

Bu dosya, bu sohbetin sonunda gelinen noktayı “tek başına okununca” yeni bir sohbeti hızlıca başlatmaya yetecek şekilde özetler.

---

### 0) TL;DR (Ne oldu?)

- **Kritik bug’lar kapatıldı**: Compact `messageId=0` hatası, compact relay eksikliği, relay akışının fiilen çalışmaması, Standard age/local-hold-time relay güncellemesi, builder auto-mode hataları, NACK decode eksikliği vb.
- **Packet-level integrity eklendi/sertleştirildi**:
  - **Compact**: CRC-8 **zorunlu**
  - **Standard**: CRC-32/IEEE (Ethernet) **zorunlu** (4 byte, big-endian)
- **API sadeleştirildi**: `Packet.encode()` / `Packet.decode()` artık CRC’yi otomatik yönetiyor; `includeCrc` / `hasCrc` parametreleri kaldırıldı.
- **Realworld tek akış stres testi eklendi**: `/test/realworld/realworld_e2e_stress_test.dart`
- **Test durumu**: `flutter test` **yeşil** (bu snapshot yazılmadan hemen önce çalıştırıldı).

---

### 1) Kilit kararlar (Spec / davranış)

- **Wire format**
  - **Compact**: `[CompactHeader(4)] + [Payload] + [CRC-8(1)]`
  - **Standard**: `[StandardHeader(11)] + [Payload] + [CRC-32(4)]`
- **CRC kapsamı**
  - CRC, **CRC alanı hariç tüm byte’lar** üzerinde hesaplanır.
- **CRC endianness**
  - Standard CRC-32: paketin sonuna **big-endian** (`Bitwise.write32BE`) yazılır.
- **Decode akışı**
  - `Packet.decode(bytes)` önce **mode**’u ilk byte’tan tespit eder, sonra ilgili CRC’yi doğrular, CRC’yi strip eder, ardından header/payload parse eder.
  - CRC mismatch → `CrcMismatchException` (veya üst seviye exception).

---

### 2) Bilinçli “breaking change” listesi (Public API)

Bu değişiklikler “paket geliştirme aşamasında” olduğu için bilinçli olarak kırıcı yapıldı.

- **`Packet.encode()`**
  - Eski: `encode({bool includeCrc = false})`
  - Yeni: `encode()` → Compact/Standard için CRC’yi otomatik ekler.
- **`Packet.decode()`**
  - Eski: `decode(bytes, {bool hasCrc = false})`
  - Yeni: `decode(bytes)` → CRC’yi otomatik doğrular/strip eder.
- **`Packet.header` tipi**
  - Eski: `Object`
  - Yeni: `PacketHeader`
- **`Packet.crc` alanı**
  - Kaldırıldı (CRC artık wire’da her zaman var; Packet state’inde saklanmıyor).
- **`RelayPolicy` imzaları**
  - Eski: `shouldRelay(Packet, MessageCache, {targetPeerId})` / `prepareForRelay(Packet, {additionalAgeMinutes})`
  - Yeni: `shouldRelay(Packet)` / `prepareForRelay(Packet)`

---

### 3) Mesh düzeltmeleri (K1/K2/K3 + akış bug’ı)

#### 3.1 MeshController – Compact messageId=0 kaldırıldı

- **Dosya**: `lib/src/mesh/mesh_controller.dart`
- Artık `messageId = packet.header.messageId` kullanılıyor (compact/standard ayrımı yok).

#### 3.2 Relay akışı düzeltildi (seen/relay sırası)

Önceden `markSeen` → `shouldRelay(cache.hasSeen)` şeklinde relay fiilen ölüyordu. Şimdi:

- `if (cache.hasSeen(messageId)) drop`
- `cache.markSeen(messageId)`
- `policy.shouldRelay(packet)` true ise relay schedule

#### 3.3 RelayPolicy – Compact relay eklendi + Standard age doğru güncelleniyor

- **Dosya**: `lib/src/mesh/relay_policy.dart`
- Compact: `decrementTtl()` ile TTL azaltarak relay.
- Standard: `StandardHeader.prepareForRelay()` kullanılır → `ageMinutes = currentAgeMinutes` (local-hold-time dahil).
- Priority “SOS type index <= 3” gibi hack’ler kaldırıldı; açık kontrol var: `type == MessageType.sosBeacon`.

---

### 4) PacketBuilder auto-mode iyileştirmesi (Y2)

- **Dosya**: `lib/src/protocol/packet_builder.dart`
- Auto seçim artık şunları dikkate alıyor:
  - `MessageType.requiresStandardMode`
  - `SecurityMode != none` / `_encrypted`
  - fragment flag’leri (`_fragment`, `_moreFragments`)
  - TTL > 15
  - payload `kCompactMaxPayload` sınırını aşarsa standard

---

### 5) Decode geliştirmeleri + MessageId tutarlılığı (Y3/Y6)

- **NACK decode eklendi**
  - **Dosya**: `lib/src/protocol/packet.dart`
  - `_decodePayload` içinde `MessageType.nack` → `NackPayload.decode(...)`
- **Factory’lerde ID tekilleştirildi**
  - `Packet.sos/location/text/ack` artık `MessageIdGenerator.generate()` / `generate32()` kullanıyor (DateTime mask kaldırıldı).

---

### 6) CRC-32 implementasyonu (Standard)

- **Dosya**: `lib/src/encoding/crc32.dart`
- **Algoritma**: CRC-32/IEEE (Ethernet)
  - Reflected poly: `0xEDB88320`
  - Init: `0xFFFFFFFF`
  - XorOut: `0xFFFFFFFF`
  - Test vektörü: `"123456789" -> 0xCBF43926`
- **Test**: `test/protocol/crc32_test.dart`

---

### 7) Realworld E2E stress testi (tek akış)

- **Dosya**: `test/realworld/realworld_e2e_stress_test.dart`
- **Amaç**: Tek bir test akışında en zor senaryoları deterministik simüle etmek:
  - Compact CRC-8 drop + duplicate
  - Standard CRC-32 drop + backoff cancel
  - Transport fragmentation (`Fragmenter.fragment`) + out-of-order + missing + corrupted fragment
  - NACK üretimi (`SelectiveRepeatStrategy`) + resend + reassemble + `Packet.decode`
  - Crypto primitives: PBKDF2 + AES-GCM tamper (CRC gating konseptini byte-level “envelope” ile gösterir)
  - Basit perf metrikleri (ops/sec)

#### Çalıştırma

```bash
flutter test -r expanded test/realworld/realworld_e2e_stress_test.dart
```

Heavy perf modu (opsiyonel):

```bash
BITPACK_PERF=1 flutter test -r expanded test/realworld/realworld_e2e_stress_test.dart
```

Seed sabitleme:

```bash
BITPACK_SEED=123 flutter test -r expanded test/realworld/realworld_e2e_stress_test.dart
```

Not: NACK payload’ın kapasitesi sınırlı (`maxBlocks=8`, block başına 12 fragment) → full retransmission senaryosu test içinde **birden fazla NACK’e bölünerek** simüle edilir.

---

### 8) Test/Doğrulama durumu

- **Komut**: `flutter test`
- **Sonuç**: Bu snapshot yazılmadan hemen önce **exit code 0** ile tamamlandı (tüm suite yeşil).

---

### 9) Bilinen sınırlar / sonraki olası adımlar

- **`Fragmenter.fragmentWithHeaders(...)` tutarlılık notu**:
  - Bu metot Standard header’lı fragment “paketleri” üretirken şu an CRC-32 trailer eklemiyor.
  - Yeni “Standard CRC-32 always” kuralıyla tutarlılık için ya güncellenmeli ya da bu metot “Packet.decode ile decode edilemez (internal/transport)” diye net dokümante edilmeli.
- **Şifrelemenin Packet formatına tam entegrasyonu**:
  - Crypto modülü (PBKDF2 + AES-GCM) var, ama `Packet` içinde “encrypted payload wire formatı” ayrı bir tasarım adımı.
  - Realworld testte “packet-level CRC gating + AES-GCM” konsepti byte-level envelope ile gösterildi.
- **Ek güvence katmanları (istersen)**:
  - Decoder fuzzing/property-based testler (random bytes → “crash yok, düzgün exception”)
  - Uzun süreli çok düğümlü soak test (dakikalar/saatler)
  - Fragment taşıma stratejisinin gerçek BLE/WiFi simülasyonu (jitter/drop pattern’leri)

---

### 10) Yeni sohbette hızlı başlangıç (nereden devam edelim?)

- **Protokol çekirdeği**: `lib/src/protocol/packet.dart`
- **CRC’ler**: `lib/src/encoding/crc8.dart`, `lib/src/encoding/crc32.dart`
- **Mesh**: `lib/src/mesh/mesh_controller.dart`, `lib/src/mesh/relay_policy.dart`, `lib/src/mesh/relay_backoff.dart`
- **Fragment + NACK**: `lib/src/fragmentation/fragmenter.dart`, `lib/src/fragmentation/reassembler.dart`, `lib/src/fragmentation/selective_repeat.dart`
- **Realworld test**: `test/realworld/realworld_e2e_stress_test.dart`

