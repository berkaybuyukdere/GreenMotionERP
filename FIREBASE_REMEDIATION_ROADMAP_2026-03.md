# Firebase Remediation Roadmap (P0 / P1 / P2)

**Detaylı faz planı, kod analizi ve kabul kriterleri:** `FIREBASE_REMEDIATION_MASTER_PLAN_2026-03.md`

## Objective
- Close high/medium audit risks without breaking existing production behavior.
- Keep rollout reversible.

## P0 (Immediate, no-break)

1. Wheelsys secure endpoint live
   - Implemented: `functions/index.js` -> `wheelsysPreCheckIn`.
   - Add env secrets in production:
     - `WHEELSYS_API_KEY`
     - `WHEELSYS_HMAC_SECRET` (recommended)

2. RES/confirmation handling standard
   - Canonical business meaning documented: `confirmation_no` is RES lifecycle key.
   - Do not scope it to protocols-only semantics.

3. Return/checkout query reliability
   - Composite indexes added in `firestore.indexes.json` for:
     - `iadeIslemleri(franchiseId, iadeTarihi)`
     - `exitIslemleri(franchiseId, exitTarihi)`
     - `exitIslemleri(franchiseId, createdAt)`

4. Backward-compatible vehicle check-in snapshot
   - Implemented additive field: `araclar.lastCheckIn`.
   - `Arac` model updated with optional decode support.

## P1 (Stability + consistency)

1. Date encoding guardrail package
   - Add shared conversion helpers in web/iOS/backend:
     - Firestore Timestamp <-> JS Date
     - Apple epoch Double <-> Date
   - Add integration tests to block accidental unix/apple mixups.

2. Notifications lifecycle hardening
   - Add `expiresAt` to notification docs.
   - Add scheduled cleanup for expired notifications.

3. assistantCompanies casing harmonization
   - Introduce canonical ID normalization map.
   - Add compatibility read fallback during transition.

4. Wheelsys observability
   - Dashboard metrics:
     - success/duplicate/not-found/ambiguous/validation failures.
   - Alerting on spikes in `404` or `409`.

## P2 (Structural migration, controlled)

1. Damage normalization
   - Migrate `araclar.hasarKayitlari[]` -> top-level `hasarKayitlari`.
   - Steps:
     - dual-write
     - shadow-read compare
     - cutover reads
     - remove legacy nested writes

2. Shuttle model de-duplication
   - Stop persisting `shuttleSessions.entries`.
   - Use only `shuttleEntries` + denormalized `totalCustomers`.

3. Soft-delete standardization
   - Add `isDeleted` and `deletedAt/deletedBy` for core collections.
   - Update queries to filter active documents.

## Rollout Strategy

1. Staging deploy
   - Deploy functions + indexes.
   - Run integration tests with Wheelsys-like payloads.

2. Canary franchise
   - Enable endpoint traffic for one franchise.
   - Monitor error distribution and latency.

3. Full rollout
   - Expand to all franchise traffic.
   - Keep rollback switch for endpoint if anomaly detected.

4. Post-rollout verification
   - Compare pre/post data consistency:
     - reservation resolution success
     - mileage/fuel monotonic checks
     - franchise boundary integrity

## Rollback Notes
- Endpoint rollback: redeploy previous function revision.
- Data rollback: not required for additive fields; merge writes preserve legacy schema.
- Index rollback: harmless to keep; no destructive action needed.
