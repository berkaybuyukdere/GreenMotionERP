# Firebase / Uygulama Remediation — Ustalık Planı (Mart 2026)

Bu belge, CTO şema denetimi (DOC-SCHEMA-2026-02) ve repodaki **gerçek kod yolları** üzerinden hazırlanmıştır. Hedef: veriyi bilinçli biçimde korumak, geri dönüşü mümkün tutmak ve franchise / mobil / Cloud Functions tutarlılığını artırmak.

**İlgili envanter:** `FIREBASE_SCHEMA_AS_IS_2026-03.md`, `FIREBASE_REMEDIATION_ROADMAP_2026-03.md`, `WHEELSYS_API_CONTRACT_2026-03.md`

---

## 1. Mevcut sistem analizi (profesyonel özet)

### 1.1 İstemci (iOS)

- **UI katmanı:** SwiftUI; operasyonel akışlar `AracViewModel`, ofis/shuttle için ayrı view’lar ve `FirebaseService.shared`.
- **Araç ve hasar:** `Arac` modeli `hasarKayitlari` dizisini **araç dokümanı içinde** taşır; tüm hasar CRUD ve raporlar (`RaporView`, `AnalyticsDashboardView`, `AracViewModel`) bu varsayıma göre **flatten** ederek çalışır.
- **Firebase erişimi:** `FirebaseService` hem **düz** koleksiyonları (`araclar`, …) hem **`franchises/{id}/…` scoped** yolu destekler (`readQueryWithFallback`, `writeDictionaryDocument`). Bu, migrasyon ve kurallar için **çift gerçeklik** yaratır; planın her fazında “hangi path yazılıyor?” sorusu netleştirilmelidir.

### 1.2 Tarih kodlaması (kritik bulgu)

- **Firestore `Timestamp`:** Çoğu operasyonel koleksiyon (çıkış, iade, shuttle entry timestamp’leri vb.).
- **Apple epoch `Double` (2001-01-01):** `office_operations.date` ve `vacationTimes` (`startDate`, `endDate`, `createdAt`) — kayıt sırasında `FirebaseService.saveOfficeOperation` / `saveVacationTime` ve ilgili modeller bu formata kilitlemiş; web uyumluluğu gerekçesi kod içinde açıkça yazıyor.
- **ISO string:** `protocols` tarih alanları.

**Risk:** Harici tüketici (Node/Python/Wheelsys tarafı script) bu alanları Unix saniye sanırsa tarihler **yaklaşık 31 yıl** kayar.

### 1.3 Shuttle

- `ShuttleManager.addCustomerEntry`: **atomik batch** ile hem `shuttleEntries` dokümanı oluşturuluyor hem `shuttleSessions` üzerinde `entries` dizisine `arrayUnion` yapılıyor; `totalCustomers` artırılıyor.
- UI tarafında `listenToTodayEntries` “WORKAROUND” ile ağırlıklı olarak **session içi `entries`** kullanıyor — denetimdeki **çift kaynak** ve **sınırsız büyüme** riski doğrulanmış durumda.

### 1.4 Bildirimler

- `NotificationManager` `notifications` koleksiyonuna doküman ekliyor; Cloud Function tetikleyip FCM gönderiyor.
- **`expiresAt` / TTL** veya sistematik temizlik repoda **standart değil** — maliyet ve liste büyümesi riski.

### 1.5 Silme ve denetim

- `aracSil` araç dokümanını **silme** üzerine kurulu; aktivite logu var ancak **şema düzeyinde tutarlı `isDeleted`** yok — denetim “soft delete” beklentisiyle uyumsuz.

### 1.6 Kimlik (UUID)

- `FIREBASE_SCHEMA_AS_IS` ve kod tabanına göre **`assistantCompanies`** doküman kimliği tarihsel olarak **lowercase**; diğer birçok koleksiyon **uppercase** UUID ile hizalı — case-sensitive karşılaştırmalarda **sessiz lookup hatası**.

### 1.7 Sorgu altyapısı

- `firestore.indexes.json` içinde `iadeIslemleri` / `exitIslemleri` için franchise + tarih sıralı **composite index** tanımlı (P0 kapanışı).
- `raporGecmisi` için kurallarda `hasFranchiseReadAccess` kullanımı mevcut; denetimdeki “dokümantasyon / liste eksikliği” **kısmen** adreslenmiş sayılır, yine de **rules deploy özeti** ve `hasFranchiseReadAccess` iç mantığı regression için doğrulanmalıdır.

### 1.8 Cloud Functions

- `wheelsysPreCheckIn`: Wheelsys’ten gelen pre-check-in; araç çözümlemesi, idempotency, `checkInKayitlari` + `lastCheckIn` yazımı (iOS ile uyum için güncel).
- Bildirim işleme ve idempotency `_functionLocks` altında.

---

## 2. Planlama ilkeleri

1. **Önce ölç, sonra kes:** Prod’a migrasyon öncesi örneklem + staging.
2. **Tek yönlü gerçek kaynak:** Her faz için “canonical field” ve geçiş süresince **dual-read** veya **shadow field** tercih edilir; çift yazım kısa tutulur.
3. **Geri dönüş:** Özellikle tarih ve hasar migrasyonunda önceki field’ları silmeden **deprecated** bırakma seçeneği.
4. **Franchise:** Tüm batch script’lerde `franchiseId` ve hem flat hem scoped path kontrolü.
5. **Uygulama sözleşmesi:** Her faz sonunda iOS smoke test listesi + (mümkünse) otomasyon.

---

## 3. Fazlar (önerilen sıra ve bağımlılık)

Aşağıdaki sıra **risk / bağımlılık** optimizasyonudur: düşük veri riskinden yüksek migrasyon maliyetine.

### Faz A — “Hazırlık ve gözlemlenebilirlik” (1–3 gün takvim, paralel işler)

| Görev | Çıktı |
|--------|--------|
| Prod/staging **Firestore export** veya anlık yedek prosedürü | Rollback öncesi taban |
| Index’lerin Console’da **BUILD** durumu | `iadeIslemleri` / `exitIslemleri` sorgularında “index required” yok |
| Basit **Dashboard** (opsiyonel): Wheelsys endpoint 4xx/5xx oranları, fonksiyon log filtreleri | P1’de alerting temeli |
| Doküman: “Hangi koleksiyonlar flat, hangisi `franchises/`?” tek tabloda | Sonraki fazların scope’u netleşir |

**Veri riski:** Yok (okuma / süreç).

---

### Faz B — P1: Tarih birliği (`office_operations`, `vacationTimes`)

**Problem:** Apple epoch; entegrasyon ve web/JS tarafında yanlış yorumlama.

**Strateji (önerilen — en güvenlisi):**

1. **Okuma katmanı (hemen):** Tek bir yardımcı modül (iOS: `DateEncoding` veya `FirebaseService` içinde) — field adına veya magnitude’a göre **auto-detect**: &lt; `2e9` ise 2001 referanslı saniye olarak decode, aksi halde Unix veya Timestamp. Bu, migrasyon bitene kadar **çift format** ile güvenli okuma sağlar.
2. **Yazma katmanı:** Yeni kayıtlar için **Firestore `Timestamp`** veya **UTC ISO string** (tek standart seçin); web ile mutabakat şart.
3. **Veri migrasyonu (batch):**
   - Script: her doküman için `date` / `startDate` / `endDate` / `createdAt` oku → `*_v2` veya doğrudan yeni alana Timestamp yaz → doğrulama örneklemi (% oranı) → uygulama cutover → (isteğe bağlı) eski Double alanını kaldırma **ayrı release**.

**Etkilenen dosyalar (tipik):** `FirebaseService.swift` (`saveOfficeOperation`, `loadOfficeOperations`, vacation load/save), `OfficeOperation.swift`, `VacationTime` modeli ve kodlayıcılar, varsa web consumer.

**Kabul kriterleri:**

- Staging’de örnek dokümanlar migrasyon öncesi/sonrası **aynı takvim gününde** görünür.
- iOS ofis ve izin ekranları tarihleri bozmaz.
- İdempotent migrasyon: aynı script ikinci kez çalışınca no-op veya güvenli.

**Veri riski:** Orta — yanlış formül çift migrasyonu felakettir; **shadow field + validate** ile sınırlandırılmalı.

---

### Faz C — P1: Bildirim yaşam döngüsü (`notifications`)

**Problem:** Süresiz büyüme; maliyet.

**Strateji:**

1. Yeni dokümanlara **`expiresAt: Timestamp`** (ör. oluşturma + 7 gün) ve isteğe bağlı `processedAt`.
2. Cloud Scheduler + Function: `expiresAt < now` olanları sil veya arşiv koleksiyonuna taşı.
3. `NotificationManager` yazarken `expiresAt` set et.

**Kabul kriterleri:** Eski dokümanlar için tek seferlik backfill (isteğe bağlı) veya sadece yeni akış; fonksiyon metriklerinde silinen adet görünür.

**Veri riski:** Düşük (iş kuyruğu verisi).

---

### Faz D — P1: UUID normalizasyonu (`assistantCompanies` ve referanslar)

**Strateji:**

1. **Read path:** ID karşılaştırması öncesi `uppercased()` / tek canonical string — hızlı ve geri alınabilir.
2. **Migrasyon:** Doküman ID’sini değiştirmek **kırıcı** olabilir; tercih: yeni doküman ID’si uppercase, eski için **alias map** koleksiyonu veya tek seferlik script + tüm `assistantCompanyId` referanslarını güncelle (envanter çıkarılmalı).

**Kabul kriterleri:** Firma seçici ve raporlarda “kayıt bulunamadı” regression’u yok.

**Veri riski:** Orta (ID rename); önce **read normalize** en güvenli adımdır.

---

### Faz E — P2: Shuttle çift yazımın kapatılması

**Strateji:**

1. **Yeni yazımlar:** `shuttleSessions` üzerinde **`entries` arrayUnion’ı kaldır**; sadece `shuttleEntries` + `totalCustomers` güncellemesi (batch atomik kalır).
2. **Okuma:** `ShuttleSessionDetailView` / `listenToTodayEntries` **top-level `shuttleEntries` where sessionId == …** (index zaten var) — workaround kaldırılır.
3. **Eski session’lar:** İsteğe bağlı tek seferlik “entries dizisini yoksay” veya temizlik script’i.

**Kabul kriterleri:** Aynı session için entry sayısı `shuttleEntries` ile tutarlı; doküman boyutu büyüme hızı düşer.

**Veri riski:** Düşük–orta (UI sorgu değişimi index gerektirebilir — mevcut index’lerle doğrulanmalı).

---

### Faz F — P2: Soft delete (özellikle `araclar`)

**Strateji:**

1. Şema: `isDeleted: bool`, `deletedAt`, `deletedBy` (isteğe bağlı).
2. `aracSil`: önce **update** (flag), sonra arka plan job ile storage/Firestore cleanup veya “retention policy” ile silme.
3. **Tüm liste sorgularına** `whereField("isDeleted", isEqualTo: false)` veya client-side filtre (tercihen server-side).

**Kabul kriterleri:** Admin ve raporlarda silinmiş araçlar politika ile uyumlu; aktivite logu korunur.

**Veri riski:** Orta (unutulan query “hayalet” kayıt gösterir).

---

### Faz G — P2: Hasar kayıtlarının top-level koleksiyona taşınması

**En ağır faz.** Önerilen yol roadmap ile aynı:

1. **Dual-write:** `hasarKayitlari` koleksiyonuna yeni kayıt + araç altında mevcut davranışı sürdür (geçici).
2. **Shadow-read karşılaştırma:** Rapor örneklemeleri.
3. **Cutover:** Okuma `hasarKayitlari` koleksiyonundan; araç dokümanında sadece özet veya boş dizi.
4. **Disk / contention:** Büyük filo ve foto URL listeleri için asıl gerekçe burada.

**Kabul kriterleri:** Rapor ve araç detayında hasar sayıları eşleşir; eşzamanlı iki kullanıcı senaryosu test edilir.

**Veri riski:** Yüksek — en sona ve en fazla test kaynağına bırakılmalı.

---

## 4. Özet matris: Madde × Durum × Plan fazı

| Denetim maddesi | Şu an repoda | Hedef faz | Veri riski |
|-----------------|--------------|-----------|------------|
| Apple epoch | Kod ve dokümantasyonla doğrulandı | B | Orta |
| Nested hasar | Tüm hasar akışı buna bağlı | G | Yüksek |
| Shuttle duplicate | `ShuttleManager` batch ile doğrulandı | E | Düşük–orta |
| iade/exit index | `firestore.indexes.json` | A (verify) | Yok |
| Soft delete | Hard delete | F | Orta |
| raporGecmisi rules | Kurallarda franchise helper | A (verify) | Düşük |
| notifications TTL | Yok | C | Düşük |
| UUID casing | Şema notu | D | Orta |

---

## 5. Önerilen ekip ve süre (kabaca)

- **Backend / Functions + migrasyon script:** Faz B, C, G’de kritik  
- **iOS:** Faz B, D, E, F, G read/write path  
- **QA:** Her faz için smoke + geri dönüş senaryosu  
- **Süre:** P1 (B+C+D) tipik 2–4 hafta (web mutabakatına göre); P2 (E+F+G) 4–12 hafta (G ayrı proje gibi ele alınmalı)

---

## 6. Bu planı “onay” için kullanma

1. Ürün ve uyumluluk: **tarih migrasyonu** için web/entegrasyon onayı.  
2. Yasal / denetim: **soft delete** ve saklama süresi.  
3. Teknik: Faz sırası ve **G’yi bağımsız release** olarak ayırma.

Bu belge canlı dokümandır; her faz kapanınca “As-Is” şema özeti ve bu plan birlikte güncellenmelidir.
