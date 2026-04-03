# Franchise-Scoped Migration Runbook

Default Zurich mapping for legacy/orphan data: `franchiseId = "ch"`.

## 1) Preflight
- Take full backup (Firestore export + Storage rsync + local repo archive).
- Deploy compatibility app build and Cloud Functions first.
- Deploy transitional `firestore.rules` and `storage.rules`.

## 2) Mevcut uygulama davranışı (2026-04)

- Domain Firestore verisi **yalnızca** `franchises/{franchiseId}/{collection}` altında okunur/yazılır.
- Kök koleksiyona **çift yazma** ve **legacy okuma fallback** kaldırıldı.
- `FirebaseService.configureMigration(...)` yalnızca gölge tarih tercihi için kullanılabilir: `preferShadowTimestamps`.
- Kök (legacy) doküman sayısı kontrolü: `node scripts/check_legacy_root_counts.mjs` (Admin SDK / service account gerekir).
- Kökte veri varsa: `node scripts/backfill_firestore_scoped.js --dry-run` sonra `node scripts/backfill_firestore_scoped.js` (detay: `franchise-migration-map.json`).

## 3) Firestore Backfill
- Dry run:
  - `node scripts/backfill_firestore_scoped.js --dry-run`
- Execute:
  - `node scripts/backfill_firestore_scoped.js`
- Verify:
  - `node scripts/verify_scoped_parity.js`

## 4) Storage Backfill
- Execute:
  - `BUCKET_NAME=<your_bucket> DEFAULT_FRANCHISE_ID=ch bash scripts/backfill_storage_scoped.sh`
- Verify report:
  - `scripts/storage-backfill-report.txt`

## 5) Monitoring Checklist
- Notification and email queue processing status is healthy.
- No duplicate outgoing emails.
- Return PDF attachments are delivered.
- Vehicle CRUD, return, exit, damage flows remain functional.
- Scoped and legacy counts are equal in parity report.

## 6) Rollback
- Uygulama artık migration flag’leri ile kök koleksiyona dönmez; Firestore export + önceki app sürümü ile geri dönüş planlanır.
- Keep backfilled scoped data untouched.
- Re-run parity scripts after fix.
