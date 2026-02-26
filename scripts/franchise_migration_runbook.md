# Franchise-Scoped Migration Runbook

Default Zurich mapping for legacy/orphan data: `franchiseId = "ch"`.

## 1) Preflight
- Take full backup (Firestore export + Storage rsync + local repo archive).
- Deploy compatibility app build and Cloud Functions first.
- Deploy transitional `firestore.rules` and `storage.rules`.

## 2) Migration Flags (App-Side)

Flags are stored in `UserDefaults` and configured by `FirebaseService.configureMigration(...)`.

- `migration.scoped.reads.enabled`
- `migration.scoped.writes.enabled`
- `migration.dual.write.enabled`
- `migration.read.fallback.legacy.enabled`
- `migration.storage.scoped.writes.enabled`
- `migration.storage.dual.write.enabled`
- `migration.storage.read.fallback.legacy.enabled`

### Phase A (compatibility / safe start)
- scoped reads: `false`
- scoped writes: `false`
- dual write: `true`
- read fallback legacy: `true`
- storage scoped writes: `true`
- storage dual write: `true`
- storage read fallback legacy: `true`

### Phase B (read cutover)
- scoped reads: `true`
- scoped writes: `false`
- dual write: `true`
- read fallback legacy: `true`

### Phase C (write cutover)
- scoped reads: `true`
- scoped writes: `true`
- dual write: `false`
- read fallback legacy: `true`
- storage scoped writes: `true`
- storage dual write: `false`

### Phase D (finalize)
- scoped reads: `true`
- scoped writes: `true`
- dual write: `false`
- read fallback legacy: `false`
- storage read fallback legacy: `false`

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
- Immediate rollback:
  - scoped reads: `false`
  - scoped writes: `false`
  - dual write: `true`
  - read fallback legacy: `true`
- Keep backfilled scoped data untouched.
- Re-run parity scripts after fix, then re-enter cutover phases.
