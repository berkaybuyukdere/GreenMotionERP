# Production Security and Architecture Redesign

This document defines a production-safe redesign for the iOS + Firebase platform without breaking the active mail and operations flows.

## 1) Target Architecture (Text Diagram)

```text
iOS App (SwiftUI)
  ├─ Presentation (Views)
  ├─ Application (ViewModels / UseCases)
  ├─ Domain (Entities + Policies)
  ├─ Data (Repositories)
  └─ Infra (Firebase adapters, cache, logging, crypto)
          |
          v
Firebase
  ├─ Auth (UID, custom claims, App Check)
  ├─ Firestore (tenant-scoped domain data)
  ├─ Storage (tenant-scoped objects only)
  ├─ Cloud Functions (trusted backend side-effects)
  └─ Scheduler (cleanup, retries, monitoring)
```

## 2) Security Boundaries

```text
Client trust: LOW
Cloud Functions trust: HIGH
Firestore/Storage rules: ENFORCE tenant + role
Secrets: NEVER on client, NEVER readable by tenant users
```

## 3) Folder Structure (Swift)

```text
AracHasarKayit/
  App/
    AracHasarKayitApp.swift
    AppDelegate.swift
  Presentation/
    Features/
      Damage/
      Return/
      Exit/
      OfficeOps/
      Admin/
    Shared/
  Application/
    UseCases/
    Coordinators/
  Domain/
    Models/
    Repositories/
    Policies/
  Data/
    Repositories/
    DTO/
    Mappers/
  Infrastructure/
    Firebase/
    Network/
    Logging/
    Security/
  Support/
    Localization/
    Extensions/
```

## 4) Dependency Injection Strategy

- Replace direct `.shared` usage with protocol-driven constructors.
- Keep singletons only for cross-cutting adapters (`Logger`, `CrashReporter`) behind protocols.
- Introduce a composition root in `AracHasarKayitApp`:
  - `AppContainer` builds repositories/services once.
  - ViewModels receive dependencies via init.
- Test builds swap concrete Firebase adapters with in-memory fakes.

## 5) Repository Segmentation

- `VehicleRepository`
- `DamageRepository`
- `ReturnRepository`
- `CheckoutRepository`
- `OfficeOperationRepository`
- `NotificationRepository`
- `UserRepository`
- `MarketingCampaignRepository`
- `StorageRepository`
- `EmailQueueRepository`

Each repository:
- handles one aggregate
- owns mapping between Firestore DTO and domain model
- never leaks raw Firestore documents to UI.

## 6) Secret Management

- SMTP credentials are backend-owned.
- Preferred runtime source:
  - Google Secret Manager / Firebase Functions secrets
  - env variables (`SMTP_PASSWORD`, `SMTP_PASSWORD_{FRANCHISE}`)
- Firestore SMTP docs may keep non-secret metadata (host, port, senderName, senderEmail).
- Password should be removed from client-visible schema during migration.

## 7) Secure Firestore Rules Model

Core policy:
- user reads own profile
- superadmin can manage all users
- no cross-user tenant-wide user document reads
- SMTP config restricted to superadmin only

## 8) Secure Storage Rules Model

Core policy:
- all tenant files stored under `franchises/{franchiseId}/...`
- checks `request.auth.uid` membership in same franchise
- superadmin bypass for ops
- legacy root paths read-only during migration, then disabled

## 9) Network Policy Layer

Define a centralized `NetworkPolicy`:

```text
NetworkPolicy
  ├─ RetryPolicy (exp backoff + jitter)
  ├─ TimeoutPolicy (per operation class)
  ├─ ConnectivityGate (NWPathMonitor)
  ├─ OfflineQueue (idempotent commands)
  └─ ConflictPolicy (merge/version checks)
```

## 10) Logging Strategy

- No raw token logs (APNS/FCM), no raw notification payloads.
- Redact sensitive values:
  - `abcd...wxyz` format
- `DEBUG` builds keep minimal diagnostic logs.
- production logs: structured, low-noise, no PII.

## 11) Migration Strategy (No-Downtime)

1. **Dual-read / dual-write window** (already partially used)
2. Move writes to scoped-only
3. Backfill old documents/objects
4. Verify health metrics:
   - queue depth
   - failed sends
   - cross-tenant access denied
5. Disable legacy write paths
6. Disable legacy reads after retention period

## 12) Backend Scalability Pattern

- Keep side effects in Cloud Functions:
  - Push dispatch
  - Email dispatch
  - cleanup jobs
  - migration jobs
- Use idempotency locks (`_functionLocks`) for dedupe.
- Introduce DLQ for permanently failed email/notification jobs:
  - `deadLetterQueue/{id}`
  - include `reason`, `attemptCount`, `lastError`, `payloadRef`.

## 13) Test Strategy Expansion

- Unit tests:
  - repositories
  - use cases
  - rules validation helpers
- Integration tests:
  - Firebase emulator for rules
  - email queue processing
  - migration scripts
- Contract tests:
  - DTO schema compatibility

## 14) Immediate Production Priorities

P0:
- tenant isolation rules enforced
- SMTP secrets removed from client defaults
- token/payload log redaction
- cloud function token resolution server-side

P1:
- users_public / users_private split
- full DI and repository decomposition of `FirebaseService`
- outbox + DLQ dashboards in admin panel
