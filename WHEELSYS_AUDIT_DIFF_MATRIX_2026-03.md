# Wheelsys Audit Diff Matrix (Old Audit vs Current State)

Source audit: `Downloads/firebase-schema-audit.pdf`

Status labels:
- `OPEN`: still valid and unresolved.
- `PARTIAL`: partially addressed but not fully closed.
- `CLOSED`: resolved in current repo state.

| # | Audit Finding | Audit Priority | Current Status | Evidence | Action |
|---|---|---|---|---|---|
| 1 | Apple epoch date encoding in `office_operations` and `vacationTimes` | High | OPEN | `FIREBASE_DATA_SCHEMA.md`, `FirebaseService.swift` date handling | Keep guardrails now, migrate to Timestamp in phased rollout |
| 2 | Damage records nested in `araclar.hasarKayitlari` | High | OPEN | `FIREBASE_DATA_SCHEMA.md` vehicle schema | Plan top-level `hasarKayitlari` migration with dual-write |
| 3 | Shuttle duplication (`shuttleSessions.entries` + `shuttleEntries`) | Medium | OPEN | `FIREBASE_DATA_SCHEMA.md` shuttle sections | Remove embedded array in phased migration |
| 4 | Missing indexes for returns/check-outs | Medium | PARTIAL -> CLOSED in code changes | `firestore.indexes.json` now includes `iadeIslemleri` and `exitIslemleri` composite indexes | Deploy indexes and verify no runtime index errors |
| 5 | No soft-delete pattern consistency | Medium | OPEN | Mixed behavior in codebase; no global `isDeleted` standard | Add soft-delete strategy as P2 schema hardening |
| 6 | `raporGecmisi` not franchise-filtered | Low | CLOSED | `firestore.rules` contains `match /raporGecmisi/{raporId}` with franchise access checks | Keep documentation aligned |
| 7 | `notifications` has no TTL/expiry | Low | PARTIAL | Cleanup jobs exist for some artifacts, but no strict `expiresAt` standard for all notifications docs | Add explicit `expiresAt` + scheduled purge |
| 8 | UUID case inconsistency (`assistantCompanies`) | Low | OPEN | `FIREBASE_DATA_SCHEMA.md` and existing behavior | Canonical casing migration with compatibility mapping |

## Additional Wheelsys-Relevant Delta

### Old assumption
- `confirmation_no` could be treated as protocol-only reservation field.

### Current business clarification
- `confirmation_no` maps to RES domain key across checkout/checkin/damage lifecycle.
- It must not be modeled as protocol-only.

### Implemented direction
- Added secure Cloud Function endpoint for Wheelsys pre-check-in updates.
- Endpoint resolves by `confirmation_no` with deterministic strategy and writes additive `araclar.lastCheckIn`.
