# Firebase Schema As-Is (March 2026)

This document reflects current repository reality across:
- `firestore.rules`
- `firestore.indexes.json`
- `AracHasarKayit/Firebase/FirebaseService.swift`
- `functions/index.js`

## 1) Data Isolation and Franchise Model

### 1.1 Access model
- Primary isolation key: `franchiseId` on domain documents.
- Rules helper functions enforce:
  - read: `hasFranchiseReadAccess()`
  - write: `hasFranchiseWriteAccess()`
  - delete: `hasFranchiseDeleteAccess()`
- `superadmin` bypasses franchise filtering.

### 1.2 Collection path models
- **Flat model (active):** `/{collection}/{docId}` with `franchiseId` field.
- **Scoped model (transitional):** `/franchises/{franchiseId}/{collection}/{docId}`.
- **Demo legacy model:** `/demo_{collection}/{docId}`.

## 2) Collection Inventory (Current)

### 2.1 Franchise-filtered collections (core)
- `araclar`
- `activities`
- `servisler`
- `servisFirmalari`
- `iadeIslemleri`
- `exitIslemleri`
- `office_operations`
- `office_Return`
- `shuttleEntries`
- `shuttleSessions`
- `shuttleReports`
- `workSchedules`
- `vacationTimes`
- `assistantCompanies`
- `protocols`
- `audit_logs`
- `raporGecmisi`
- `trafficFines`
- `bankingTransactions`
- `additionalSales`
- `semesInvoices`

### 2.2 Global/shared collections
- `users`
- `userPresence` (legacy; iOS app no longer writes; optional backend cleanup only)
- `notifications`
- `franchises`
- `plateFormats`
- `protocolTemplates`
- `accidentCodes`

## 3) Encoding Conventions (Current)

### 3.1 Date/time encodings
- **Firestore Timestamp:** majority of collections.
- **Apple epoch TimeInterval (Double):**
  - `office_operations.date`
  - `vacationTimes.startDate`
  - `vacationTimes.endDate`
  - `vacationTimes.createdAt`
- **ISO string:**
  - `protocols.createdAt`
  - `protocols.updatedAt`
  - `protocols.checkInDate`
  - `protocols.checkOutDate`

### 3.2 ID conventions
- Uppercase UUID dominates (`araclar`, `activities`, `iadeIslemleri`, `exitIslemleri`).
- `assistantCompanies` historically uses lowercase UUID as document id.
- Auto IDs used in some collections (`shuttleEntries`, `shuttleSessions`, `protocols`).

## 4) Known Structural Realities

- `araclar.hasarKayitlari` is still nested array model.
- `shuttleSessions.entries` duplicates `shuttleEntries` top-level records.
- `office_operations` and `vacationTimes` still use Apple epoch doubles.

## 5) Wheelsys-Related Current State

- Cloud Function endpoint implemented: `wheelsysPreCheckIn` in `functions/index.js`.
- Input contract accepted:
  - `confirmation_no`
  - `fuel`
  - `mileage`
  - optional: `event_time`, `source_event_id`, `customer_name`
- Match strategy:
  1. `exitIslemleri.resKodu`
  2. `protocols.reservationNumber`
- Update target:
  - `araclar.lastCheckIn` (additive merge update)
- Security:
  - API key required (`WHEELSYS_API_KEY`)
  - optional HMAC signature (`WHEELSYS_HMAC_SECRET`)
  - idempotency lock in `_functionLocks`

## 6) Composite Indexes (Current)

### Present before this implementation
- `activities` (multiple query combos)
- `assistantCompanies`
- `shuttleEntries`
- `shuttleSessions`
- `shuttleReports`
- `audit_logs`
- `protocols`
- `vacationTimes`
- `semesInvoices`

### Added in this implementation
- `iadeIslemleri`: `franchiseId ASC`, `iadeTarihi DESC`
- `exitIslemleri`: `franchiseId ASC`, `exitTarihi DESC`
- `exitIslemleri`: `franchiseId ASC`, `createdAt DESC`

## 7) Implementation Notes

- `Arac` model now includes optional `lastCheckIn` snapshot:
  - `timestamp`, `km`, `fuelLevel`, `reservationNumber`, `checkedInBy`, `customerName`
- Change is backward-compatible:
  - old documents decode safely without `lastCheckIn`
  - writes use merge and do not remove existing fields
