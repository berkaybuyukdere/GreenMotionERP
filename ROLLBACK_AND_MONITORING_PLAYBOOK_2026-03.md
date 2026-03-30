## Rollback & Monitoring Playbook (No-Corruption)

Bu doküman, migration adımlarında sorun görülürse **downtime olmadan** geri dönüş (rollback) ve doğrulama (monitoring) için hızlı referanstır.

### Ortak prensipler
- **Geri dönüş “flag ile” yapılır**: Shadow alanlar / yeni koleksiyonlar silinmez.
- **Önce okuma davranışını geri al** (read preference), sonra yazma davranışını (dual-write vs).
- **Her rollback sonrası**: iOS smoke test + Cloud Functions log kontrolü + örneklem bazlı veri karşılaştırması.

---

## 1) iOS / Firestore data path flags (UserDefaults)

Bu flag’ler `FirebaseService.configureMigration(...)` üzerinden runtime değiştirilebilir.

### Core routing
- `migration.scoped.reads.enabled`
  - **Amaç**: Read path scoped `/franchises/{id}/...` mı, legacy root mu?
  - **Rollback**: `false` (legacy root’a dön)
- `migration.scoped.writes.enabled`
  - **Amaç**: Write path scoped mı?
  - **Rollback**: `false` (legacy root’a yaz)
- `migration.dual.write.enabled`
  - **Amaç**: Scoped + legacy **aynı anda** yaz (dual-write)
  - **Rollback**: `false` (tek target’a dön)
- `migration.read.fallback.legacy.enabled`
  - **Amaç**: Scoped read başarısızsa legacy read fallback
  - **Rollback**: `true` (fail-safe açık)

### Date cutover (Apple epoch shadow timestamps)
- `migration.date.prefer.shadow.timestamps.enabled`
  - **Amaç**: Okumada `*Ts` shadow alanları **öncelik** olsun.
  - **Rollback**: `false` (legacy Double/Timestamp alanlarını kullan)

### Shuttle embedded yazımı
- `migration.shuttle.disable.embedded.entries.write`
  - **Amaç**: `shuttleSessions.entries` arrayUnion yazımını kapat.
  - **Rollback**: `false` (embedded yazımı geri aç)
  - **Not**: Canonical read top-level `shuttleEntries` olacak şekilde tasarlandı; embedded’i geri açmak sadece “geçici uyum” içindir.

---

## 2) Cloud Functions rollback

### Notifications TTL cleanup
- `cleanupExpiredNotifications` scheduled job
  - **Rollback**: Deploy’den kaldırmak yerine ilk etapta job’u “no-op” yap veya schedule’ı kapat (ops kararı).
  - **Risk**: Yanlış query filtreleri ile erken silme. Bu yüzden sadece `expiresAt < now` silinir; `expiresAt` olmayan dokümanlar etkilenmez.

---

## 3) Monitoring / Verification checklist

### Date migration
- **Metrikler**:
  - backfill çıktısı: `processed`, `updated` (script log JSON)
  - mismatch: örneklem 20 dokümanda `legacyConverted` vs `*Ts` delta < 1s
- **UI**:
  - Office Operations: gün/saat kayması yok
  - Vacation Times: start/end kayması yok

### Shuttle
- **UI**:
  - Session detail entry listesi: top-level `shuttleEntries` ile tutarlı
  - Total customers: beklenen count
- **Backend**:
  - embedded `shuttleSessions.entries` büyümesi durmalı

### Notifications TTL
- **Firestore**:
  - yeni notification dokümanlarında `expiresAt` set edilmiş olmalı
- **Functions log**:
  - `Expired notifications deleted: N` trendi beklenen

### Soft delete (araclar)
- **UI**:
  - “silinen” araç listelerde görünmemeli
- **Firestore**:
  - `isDeleted=true`, `deletedAt`, `deletedBy` set edilmiş olmalı

### Damage migration
- **Dual-write**:
  - yeni hasar ekle/güncelle/sil → hem nested hem `hasarKayitlari` top-level tutarlı
- **Rapor/Analytics**:
  - `RaporView` ve `AnalyticsDashboardView` top-level kaynak doluysa onu tercih eder

---

## 4) “Acil durum” rollback akışı (önerilen sıra)

1. **Read preference rollback**:
   - `migration.date.prefer.shadow.timestamps.enabled = false`
   - `migration.read.fallback.legacy.enabled = true`
2. **Write rollback**:
   - `migration.dual.write.enabled = false`
   - gerekiyorsa `migration.scoped.writes.enabled = false`
3. **Shuttle rollback**:
   - `migration.shuttle.disable.embedded.entries.write = false` (sadece gerekirse)
4. **Functions rollback**:
   - TTL cleanup job’u no-op / kapalı
5. **Doğrulama**:
   - `REMEDIATION_SMOKE_TESTS_2026-03.md` tam tur

