## BitPack – Mevcut Durum & Tutarsızlık Raporu (Snapshot)

**Tarih**: 2026-01-14  
**Amaç**: Bu dosya, yeni bir sohbet açıldığında yalnızca bunu okuyarak projeyi yeniden “kapsamlı” şekilde anlamaya yetecek bir durum fotoğrafı üretmek için yazıldı.  

---

## 0) Kısa Özet (TL;DR)

- **Ürün fikri (plan)**: Afet/internet kesintisinde BLE üzerinden **P2P mesh** iletişim için **byte-level optimize** ikili protokol kütüphanesi. BLE 4.2’yi dışlamadan çalışmak kritik.
- **Kod durumu**: `lib/` ve `test/` altında planın neredeyse tüm modülleri mevcut (header’lar, payload’lar, CRC, varint/BCD/GPS, crypto, fragmentation, selective repeat, mesh/backoff, benchmark).
- **Test durumu**: `flutter test` çalıştırıldı → **All tests passed**.
- **En kritik tutarsızlık/riskler (özet)**:
  - **MeshController compact paketleri yanlış ele alıyor**: Compact header geldiğinde `messageId` **0’a indirgeniyor** → duplicate/backoff/cache ciddi şekilde bozuluyor.
  - **RelayPolicy sadece Standard’ı relayediyor**: Compact header’da MESH biti olmasına rağmen compact relay yok (planla çelişiyor).
  - **Relative Age TTL mantığı relay’de doğru uygulanmıyor**: `currentAgeMinutes` / local-hold-time güncellemesi mesh akışında kullanılmıyor.
  - `PacketBuilder` auto-mode seçimi **standard-only type** / fragment flag’leri gibi kriterleri hesaba katmıyor → bazı kombinasyonlarda compact seçip patlayabilir.
  - `Packet.decode` bazı message type’ları (özellikle `nack`) **packet-level** decode etmiyor.
  - **MessageId üretimi iki farklı strateji** (factory’ler timestamp mask, builder time-window+random) → collision riski tutarsız.
  - **CRC “zorunlu” gibi tanımlanmış** ama `Packet.encode(includeCrc)` default `false` → protokol disiplininde belirsizlik.

---

## 1) Plan (IMPLEMENTATION_PLAN.md) – Ürün Fikri ve Temel Teknik Kararlar

- **Problem**: BLE 4.2’de efektif payload **20 byte** (MTU 23 – overhead). BLE 5+ DLE ile ~244 byte. Afette eski cihazları dışlamak kabul edilemez.
- **Çözüm**: Dual-mode protokol:
  - **COMPACT MODE**: 4 byte header + ultra kompakt payload’lar (SOS gibi).
  - **STANDARD MODE**: Daha büyük header + payload length + crypto + fragmentation + **relative age TTL**.
  - **EXTENDED**: Büyük veriler için fragmentasyon.
- **TTL stratejisi**:
  - Compact: hop-count TTL (4-bit).
  - Standard: hop-count + **ageMinutes (relative age)**; saat senkronu gerektirmeden “mesaj eskidi mi” kararı.
- **Ekler**: CRC-8, anti-collision MessageId, relay/backoff, selective repeat (NACK).

---

## 2) Repo – Modül Haritası (lib/src)

Bu snapshot’ta `lib/` tarafında görülen ana dosyalar:

- **Core**
  - `lib/src/core/constants.dart`
  - `lib/src/core/types.dart`
  - `lib/src/core/exceptions.dart`
- **Encoding**
  - `lib/src/encoding/bitwise.dart` (Bitwise + PacketFlags)
  - `lib/src/encoding/crc8.dart`
  - `lib/src/encoding/varint.dart`
  - `lib/src/encoding/bcd.dart`
  - `lib/src/encoding/gps.dart`
  - `lib/src/encoding/international_bcd.dart`
- **Protocol**
  - Header: `lib/src/protocol/header/compact_header.dart`, `standard_header.dart`, `header_factory.dart`
  - Payload: `lib/src/protocol/payload/{payload.dart,sos_payload.dart,location_payload.dart,text_payload.dart,ack_payload.dart,nack_payload.dart}`
  - Packet: `lib/src/protocol/packet.dart`, `packet_builder.dart`
- **Crypto**
  - `lib/src/crypto/key_derivation.dart` (PBKDF2 + isolate)
  - `lib/src/crypto/aes_gcm.dart`
  - `lib/src/crypto/challenge.dart`
- **Fragmentation**
  - `lib/src/fragmentation/fragment_header.dart`
  - `lib/src/fragmentation/fragmenter.dart`
  - `lib/src/fragmentation/reassembler.dart`
  - `lib/src/fragmentation/selective_repeat.dart`
- **Mesh**
  - `lib/src/mesh/message_cache.dart`
  - `lib/src/mesh/relay_policy.dart`
  - `lib/src/mesh/relay_backoff.dart`
  - `lib/src/mesh/mesh_controller.dart`
  - `lib/src/mesh/message_id_generator.dart`
  - `lib/src/mesh/peer_registry.dart`
- **Benchmark**
  - `lib/src/benchmark/benchmark_suite.dart`

---

## 3) Kodun “Gerçek Protokol Spec”i (planla karşılaştırmalı)

### 3.1 Compact Header (4 byte)

- **Gerçek**: `CompactHeader` 4 byte, mode bit 0.
- Byte 0: `[MODE=0][TYPE:4][FLAGS:3]` (flags: MESH/ACK_REQ/ENCRYPTED)
- Byte 1: `[TTL:4][COMPRESSED/URGENT:2][RESERVED:2]`
- Byte 2-3: `messageId` (16-bit, BE)

### 3.2 Standard Header (11 byte)

- **Gerçek**: `StandardHeader` **11 byte** (testler 11 bekliyor).
- Alanlar: mode/version/type + flags + hopTtl + messageId(32) + secMode+payloadLen(13) + ageMinutes(16).
- **Not**: `standard_header.dart` içinde bazı yorumlar hâlâ “10 bytes” diyor; bu dokümantasyon hatası.

### 3.3 CRC-8 (Compact)

- `crc8.dart` CRC-8-CCITT (poly 0x07, init 0x00).
- `Packet.encode(includeCrc: true)` ile header+payload sonuna 1 byte CRC ekleniyor.
- `Packet.decode(bytes, hasCrc: true)` CRC doğrulayıp CRC byte’ını strip ediyor.

> Plan/konstantlar CRC’yi compact için “zorunlu” gibi konumlandırıyor; fakat API’de default `includeCrc=false`.

### 3.4 Payload’lar

- `SosPayload` **15 byte** (compact hedefi).
- `LocationPayload` **8 byte** (GPS) veya **12 byte** (altitude+accuracy).
- `TextPayload` değişken uzunluk: `flags` + opsiyonel sender/recipient + UTF-8 text.
- `AckPayload` compact: 3 byte, standard: 5+ byte (opsiyonel reason).
- `NackPayload` block-mask (3B block) ile missing fragment indekslerini verimli taşır.

---

## 4) Test & Doğrulama Sonuçları

### 4.1 Test çalıştırma

- Komut: `flutter test`
- Sonuç: **All tests passed**

### 4.2 Testlerin doğruladığı ana şeyler

- Standard header’ın **11 byte** olduğu.
- CRC-8’in bilinen test vektörü (“123456789” → `0xF4`).
- SOS payload bit/field yerleşimi ve 15 byte olduğu.
- FragmentHeader encode/decode ve fragment/reassembly roundtrip.
- AES-GCM: nonce+cipher+tag formatı, AAD doğrulaması, wrong key/tamper’da AuthenticationException.
- KeyDerivation: PBKDF2 parametre doğrulamaları + isolate ile aynı sonuç.

---

## 5) Tutarsızlıklar / Eksikler / Riskler (tam liste)

### 5.1 Kritik (çalışma anında ciddi davranış hatası)

- **(K1) MeshController compact mesajları `messageId=0` gibi ele alıyor**
  - **Nerede**: `lib/src/mesh/mesh_controller.dart`
  - **Ne oluyor**: header standard değilse `messageId = 0`. Bu yüzden:
    - Duplicate detection: ilk compact paket cache’e `0` olarak yazılır; sonraki compact paketlerin çoğu **duplicate** sayılıp drop edilebilir.
    - Backoff cancel: tüm compact paketler “aynı mesaj” gibi birbirini iptal eder.
  - **Etkisi**: Compact (özellikle SOS) akışında mesh kontrolü kullanılırsa davranış ciddi şekilde bozulur.

- **(K2) RelayPolicy sadece StandardHeader için çalışıyor (compact relay yok)**
  - **Nerede**: `lib/src/mesh/relay_policy.dart`
  - **Ne oluyor**: Compact header için `shouldRelay=false`. Plan ise compact header’da MESH biti tanımlıyor ve compact TTL decrement ile relay senaryosu anlatıyor.
  - **Etkisi**: BLE 4.2 cihazların “mesh relay” kapasitesi pratikte devre dışı.

- **(K3) Relative Age TTL (local hold time) relay akışında doğru uygulanmıyor**
  - **Nerede**: `lib/src/protocol/header/standard_header.dart` (destek var), `lib/src/mesh/relay_policy.dart` / `mesh_controller.dart` (kullanım yok).
  - **Ne oluyor**:
    - `StandardHeader.decode()` → `markReceived()` çağırıyor.
    - Ama relay sırasında `header.currentAgeMinutes` / `header.prepareForRelay()` yerine genelde `ageMinutes` kopyalanıyor.
  - **Etkisi**: Planın “her relay node bekletme süresini age’e ekler” garantisi zayıflıyor.

### 5.2 Yüksek (API/protokol tutarsızlığı, ileride bug çıkarma riski)

- **(Y1) StandardHeader byte-size yorumları yanlış (10 yazıyor ama gerçek 11)**
  - **Nerede**: `lib/src/protocol/header/standard_header.dart`, `lib/src/core/types.dart`
  - **Etkisi**: Dokümantasyon/spec okuyan kişi yanlış implementasyon yapabilir.

- **(Y2) PacketBuilder auto-mode seçimi standard-only type’ı hesaba katmıyor**
  - **Nerede**: `lib/src/protocol/packet_builder.dart`
  - **Ne oluyor**: `_determineMode()` type.requiresStandardMode/fragment gibi kriterleri dikkate almıyor.
  - **Etkisi**: `.type(MessageType.handshakeInit)` gibi bir kullanım + küçük payload → compact seçebilir; sonra `CompactHeader` ctor içinde `ArgumentError` ile patlar.

- **(Y3) Packet.decode bazı message type’ları çözmüyor (özellikle NACK)**
  - **Nerede**: `lib/src/protocol/packet.dart` (`_decodePayload`)
  - **Ne oluyor**: `MessageType.nack` için case yok → default branch → text parse fallback ya da exception.
  - **Etkisi**: NACK paketlerini “paket olarak” almak zorlaşır.

- **(Y4) HeaderFactory.createAuto payload size kontrolü CRC varsayımıyla tam hizalı değil**
  - **Nerede**: `lib/src/protocol/header/header_factory.dart`
  - **Detay**: `payloadLength > kBle42MaxPayload - kCompactHeaderSize` eşiği **16**’ya izin verir; fakat CRC “zorunlu” varsayılırsa compact max payload **15** olmalı (`kCompactMaxPayload`).
  - **Etkisi**: edge-case’te yanlışlıkla compact seçip BLE 4.2 MTU aşımı yaşatabilir.

- **(Y5) Packet.crc alanı pratikte kullanılmıyor**
  - **Nerede**: `lib/src/protocol/packet.dart`
  - **Detay**: `encode(includeCrc:true)` CRC hesaplayıp ekliyor ama `Packet.crc` set edilmiyor; `decode(hasCrc:true)` doğruluyor ama packet içinde CRC saklamıyor.
  - **Etkisi**: API yüzeyi “crc var” gibi ama gerçek kullanım yok; kafa karıştırır.

- **(Y6) MessageId üretimi iki ayrı strateji**
  - **Nerede**:
    - Modern: `lib/src/mesh/message_id_generator.dart` (time-window + random)
    - Factory’ler: `lib/src/protocol/packet.dart` (timestamp & mask)
  - **Etkisi**: collision direnci hedefi tutarsızlaşır (özellikle compact 16-bit).

- **(Y7) MessageIdGenerator.estimateAge16 yeni layout ile uyumsuz görünüyor**
  - **Nerede**: `lib/src/mesh/message_id_generator.dart`
  - **Detay**: `generate()` high 4 bit “seconds window”; `estimateAge16()` ise “minutes window & 0xFF” gibi davranıyor → konsept karışık.
  - **Etkisi**: Şu an testlenmiyor; kullanılırsa yanlış sonuç verebilir.

### 5.3 Orta/Düşük (mantık/dokümantasyon, iyileştirme fırsatları)

- **(O1) RelayPolicy.calculatePriority “SOS types 0-3” varsayımı problemli**
  - **Nerede**: `lib/src/mesh/relay_policy.dart`
  - **Detay**: `header.type.index <= 3` kontrolü `ping` gibi türleri de “SOS” sayabilir.
  - **Etkisi**: Relay önceliklendirme hatalı olabilir.

- **(O2) RelayPolicy.myDeviceId alanı var ama kullanılmıyor**
  - **Nerede**: `lib/src/mesh/relay_policy.dart`
  - **Plan**: “kendi mesajımı relaying etme” kuralı vardı.

- **(O3) SelectiveRepeatReassembler gap detection tam entegre değil**
  - **Nerede**: `lib/src/fragmentation/selective_repeat.dart`
  - **Detay**: Base `Reassembler` iç buffer’ları expose etmediği için otomatik gap detection sınırlı; `checkTimeouts` şimdilik stub.
  - **Etkisi**: “Selective repeat” altyapısı var ama tam otomatik akış eksik.

- **(O4) FragmentHeader max değerleri sabitlerde off-by-one**
  - **Nerede**:
    - `lib/src/core/constants.dart` → `kMaxTotalFragments = 4096`
    - `lib/src/fragmentation/fragment_header.dart` → `maxTotalFragments = 4095`
  - **Etkisi**: Küçük; ama tek bir “source of truth” olmalı.

- **(O5) Fragmenter.fragment(messageId) parametresi kullanılmıyor**
  - **Nerede**: `lib/src/fragmentation/fragmenter.dart`
  - **Etkisi**: API temizliği.

- **(O6) README / pubspec açıklamaları placeholder**
  - **Nerede**: `README.md`, `pubspec.yaml`
  - **Etkisi**: Yayın/publish hazırlığında düzenlenmeli.

---

## 6) Önerilen Fix Planı (önceliklendirilmiş)

- **P1 (kritik)**: `MeshController` compact header için gerçek `messageId`’yi kullanmalı (0’a düşürmemeli). Compact + standard için ortak messageId API’si/adapter düşünülebilir.
- **P2 (kritik/plan uyumu)**: `RelayPolicy` compact relay’i destekleyecek şekilde genişletilmeli (en azından TTL decrement + cache/duplicate kuralları).
- **P3 (plan uyumu)**: Standard relay’de age güncellemesi `StandardHeader.currentAgeMinutes`/`prepareForRelay()` ile doğru uygulanmalı.
- **P4**: `PacketBuilder` auto-mode seçimi `MessageType.requiresStandardMode`, fragment flag’leri vb. kriterlerle güçlendirilmeli (HeaderFactory.createAuto ile hizalanabilir).
- **P5**: `Packet.decode` içine `MessageType.nack` ve gerekiyorsa diğer kontrol mesajları eklenecek şekilde genişletilmeli.
- **P6**: Packet factory’leri `MessageIdGenerator` stratejisini kullanacak şekilde tekilleştirilmeli.
- **P7**: CRC’nin compact için “zorunlu mu opsiyonel mi” kararı netleştirilmeli (API default’u / dokümantasyon / HeaderFactory.createAuto eşiği buna göre hizalanmalı).
- **P8**: Dokümantasyon/yorum temizlikleri (11 byte header, vs.).

---

## 7) Reprodüksiyon / Komutlar

- **Tüm testler**:
  - `flutter test`

---

## 8) Notlar

- Bu snapshot, kodu ve testleri okuyarak çıkarılmıştır; testler başarılı olsa da yukarıdaki maddeler **plan hedefleriyle uyum** ve **ilerideki kullanım senaryoları** açısından önemlidir.

