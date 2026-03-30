## Remediation Smoke Tests (No-Corruption)

Bu checklist, audit bulgularını giderirken **işlemlerin bozulmadığını** ve **verinin kaymadığını** hızlıca doğrulamak içindir.

### Önkoşullar
- **Staging** üzerinde aynı build + aynı functions sürümü
- En az 1 franchise (örn. `CH`) ve 1 test kullanıcı
- En az 1 araç (hasar + check-out/check-in + return verisi olan)
- En az 1 `office_operations` ve 1 `vacationTimes` kaydı (eski Apple epoch Double formatlı)
- En az 1 `shuttleSession` (embedded `entries` içeren) + top-level `shuttleEntries`

---

## 1) Date Encoding (office_operations / vacationTimes)

### 1.1 Office Operations
- **Create**: yeni office operation oluştur → listeye dön.
- **Verify UI**: tarih, oluşturduğun gün/saat ile tutarlı.
- **Update**: amount/notes değiştir → listeye dön.
- **Verify**: tarih değişmedi, kayıt doğru gün/saatte.

**Backend kontrol (log/console):**
- Okuma decode path: `dateTs` varsa ondan, yoksa legacy `date` Double/Timestamp’tan.
- Eğer migration sonrası `dateTs` yazılıyorsa, legacy `date` alanı ile **aynı** UTC anı göstermeli.

### 1.2 Vacation Times
- **Create**: yeni vacation time oluştur.
- **Verify UI**: start/end günleri doğru.
- **Restart app**: tekrar aç, listeyi kontrol et.
- **Verify**: tarih kayması yok.

**Backfill doğrulaması (örneklem):**
- 20 dokümanda `startDate/endDate/createdAt` legacy → `*Ts` dönüşümü sonrası:
  - \(|newTs - legacyConverted|\) < 1 saniye

---

## 2) Shuttle Duplication (entries -> shuttleEntries canonical)

### 2.1 Session start/end
- Session başlat, 2 kez customer entry ekle (pickup/dropoff).
- Günlük rapor ekranında toplamlar doğru mu?

### 2.2 Canonical read
- Session detay ekranında entry listesi **top-level `shuttleEntries`** ile tutarlı mı?
- Embedded `shuttleSessions.entries` alanı boş olsa bile UI doğru çalışıyor mu?

---

## 3) Notifications TTL (expiresAt)

### 3.1 Enqueue
- Hasar ekle / iade / exit gibi bir olay tetikle → notification dokümanı oluşuyor mu?
- Dokümanda `expiresAt` mevcut mu?

### 3.2 Scheduled purge
- `expiresAt < now` olan test dokümanları oluştur (staging).
- Scheduled job çalışınca siliniyor mu? (log + Firestore count)

---

## 4) Soft Delete (araclar)

### 4.1 Delete flow
- Bir aracı “sil” (soft delete) → listeden kaybolmalı.
- Admin/rapor ekranlarında silinen araç varsayılan listelerde görünmemeli.

### 4.2 Restore (opsiyonel)
- `isDeleted=false` yapınca tekrar görünmeli (debug/admin only).

---

## 5) Nested Damage Migration (dual-write / dual-read)

### 5.1 Dual-write
- Yeni hasar ekle:
  - Araç dokümanındaki `hasarKayitlari[]` artmalı
  - Yeni top-level `hasarKayitlari` koleksiyonunda da kayıt oluşmalı

### 5.2 Dual-read
- Rapor/analytics ekranı:
  - new-model aktifken totals doğru
  - fallback modda legacy totals doğru

---

## 6) Wheelsys Pre-Check-In

### 6.1 Endpoint happy path
- `wheelsysPreCheckIn` POST gönder:
  - `checkInKayitlari` append ve `lastCheckIn` update beklenir.
- iOS araç detayında check-in kayıtları görünmeli.

### 6.2 Idempotency
- Aynı payload ile tekrar POST → `202 already_processed`.

---

## İzleme / Metrikler (minimum)
- Date migration:
  - `docs_processed`, `docs_written`, `mismatch_count`
- Shuttle:
  - `entries_written_top_level`, `embedded_write_disabled_count`
- Notifications:
  - `queued`, `purged`
- Soft delete:
  - `soft_deleted`, `hard_deleted` (0 olmalı, admin cleanup hariç)

