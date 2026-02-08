# Complete Firestore Data-Loading & Data-Creating Audit — iOS App

**Scope:** All navbar items (Dashboard, Vehicles, Scan, Analytics, Report) and menu features (Office Operations, Shuttle, Vacation Times, Work Timetable, Services, Admin Panel).  
**Date:** 2025-02-07.

---

## Summary: Collections Used

| Collection | READ (one-time) | READ (listener) | WRITE (set/update/add) | DELETE | Franchise-filtered? | Notes |
|------------|-----------------|-----------------|------------------------|--------|---------------------|-------|
| **araclar** | ✅ | ✅ | ✅ | ✅ | **Yes** | Vehicles; damage records embedded in doc |
| **servisler** | ✅ | — | ✅ | ✅ | **Yes** | Services |
| **iadeIslemleri** | ✅ | ✅ | ✅ | ✅ | **Yes** | Returns |
| **exitIslemleri** | ✅ | ✅ | ✅ | ✅ | **Yes** | Check-out operations |
| **activities** | ✅ | ✅ | ✅ | ✅ | **Yes** | Activity log |
| **servisFirmalari** | ✅ | ✅ | ✅ | ✅ | **Yes** | Service companies |
| **office_operations** | ✅ | ✅ | ✅ | ✅ | **Yes** | Office ops |
| **office_Return** | ✅ | ✅ | ✅ | ✅ | **Yes** | Office returns |
| **workSchedules** | ✅ | ✅ | ✅ | ✅ | **Yes** | Work timetable |
| **protocols** | ✅ | ✅ | ✅ | ✅ | **Yes** | Protocols |
| **vacationTimes** | ✅ | ✅ | ✅ | ✅ | **Yes** | Vacation times |
| **assistantCompanies** | ✅ | ✅ | ✅ | ✅ | **Yes** | Assistant companies |
| **shuttleSessions** | ✅ | — | ✅ | ✅ | **Yes*** | *Some views use raw `db.collection` |
| **shuttleEntries** | ✅ | ✅ | ✅ | ✅ | **Yes*** | *Same as above |
| **shuttleReports** | ✅ | — | ✅ | ✅ | **No (bug)** | Raw `Firestore.firestore().collection` in 2 places |
| **users** | ✅ | — | ✅ | — | **No** | User profile + FCM; system-wide |
| **notifications** | — | — | ✅ (addDocument) | — | **Yes** | Queued for Cloud Function; uses getCollectionReference |
| **userPresence** | — | ✅ | ✅ | — | **Yes** | Presence; uses getCollectionReference |
| **audit_logs** | ✅ | — | ✅ | — | **Yes** | Audit trail |
| **adminTestLogs** | ✅ | — | ✅ | — | **No (bug)** | Raw `db.collection` in AdminPanelView |
| **adminTests** | — | — | ✅ | ✅ | **No (bug)** | Raw `db.collection` in AdminPanelView; test docs |
| **demo_environments** | — | — | — | — | N/A | Used only as parent path for demo subcollections |

**Not used in app code:** `raporGecmisi`, `fcmTokens` (rules only; FCM stored in `users` doc).

---

## 1. By Feature (Nav + Menu)

### Dashboard
- **Reads:** All data is from ViewModel (no direct Firestore in Dashboard UI).
- **Sources:** `AracViewModel` loads/observes: `araclar`, `servisler`, `iadeIslemleri`, `exitIslemleri`, `activities`, `servisFirmalari`, `officeOperations`, `officeReturns`, `workSchedules`, `vacationTimes`, `assistantCompanies`.
- **Swift files:** `Models/DashboardView.swift`, `ContentView.swift` — no direct Firestore; `ViewModels/AracViewModel.swift` (orchestrates), `Firebase/FirebaseService.swift` (actual calls).

### Vehicles (Araçlar)
- **Read:** `araclar` — one-time: `loadAraclar`; listener: `observeAraclar`.
- **Write:** `araclar` — `saveArac`, `updateArac` (setData); damage is embedded in vehicle doc (no subcollection).
- **Delete:** `araclar` — `deleteArac`; cascade: `CascadeDeleteManager` deletes vehicle + related `servisler`, `iadeIslemleri`, `activities`.
- **Subcollections / nested:** None. `hasarKayitlari` is an **embedded array** in each `araclar` document (see `Models/Arac.swift`).
- **Swift files:** `Firebase/FirebaseService.swift`, `ViewModels/AracViewModel.swift`, `Utilities/CascadeDeleteManager.swift`, `Utilities/OptimizedRealtimeManager.swift` (listener), `Views/AdminPanelView.swift` (tests).

### Scan (Plaka / damage scan)
- **Read/Write:** Same as Vehicles (scan adds/updates vehicle or damage; damage stored in `araclar.hasarKayitlari`).
- **Swift files:** `ViewModels/AracViewModel.swift`, `Firebase/FirebaseService.swift`; Views use ViewModel only.

### Analytics
- **Read:** No direct Firestore in `AnalyticsDashboardView`; uses `AracViewModel` published data (araclar, officeOperations, etc.).
- **Swift files:** `Views/AnalyticsDashboardView.swift` (no Firestore), `ViewModels/AracViewModel.swift`.

### Report (Rapor)
- **Read:** `shuttleEntries` — one-time in `RaporView` (count for selected month) via `getCollectionReference("shuttleEntries").getDocuments`.
- **Swift files:** `Views/RaporView.swift` (getCollectionReference — franchise-aware).

### Office Operations
- **Read:** `office_operations` — one-time: `loadOfficeOperations`; listener: `observeOfficeOperations`.
- **Write:** `office_operations` — `saveOfficeOperation`, `updateOfficeOperation` (setData).
- **Delete:** `office_operations` — `deleteOfficeOperation`.
- **Swift files:** `Firebase/FirebaseService.swift`, `ViewModels/AracViewModel.swift`, `Views/AdminPanelView.swift` (tests), `Utilities/CascadeDeleteManager.swift`, `Utilities/OptimizedRealtimeManager.swift`.

### Shuttle
- **Read:**  
  - `shuttleSessions` — one-time: `ShuttleManager.initializeSession` (active session), `ShuttleMainView` (list), `GenerateShuttleReportView` (sessions for report), `ShuttleSessionDetailView` (delete path uses raw `db.collection("shuttleSessions")`).  
  - `shuttleEntries` — one-time: `ShuttleManager.generateDailyReport`, `DailyShuttleReportView`, `EditDailyShuttleReportView`, `RaporView`; listener: `DailyShuttleReportView` (`shuttleListener`).
- **Write:**  
  - `shuttleSessions` — `ShuttleManager.startDailySession`, `endDailySession`; `ShuttleSessionDetailView` delete (raw collection).  
  - `shuttleEntries` — `ShuttleManager.addCustomerEntry`, `DailyShuttleReportView` (batch add/delete), `EditDailyShuttleReportView` (batch set/delete).  
  - `activities` — `ShuttleManager.logActivity` (addDocument).
- **Delete:**  
  - `shuttleSessions` — `ShuttleSessionDetailView` (raw `Firestore.firestore().collection("shuttleSessions").document(sessionId).delete()`).  
  - `shuttleEntries` — `DailyShuttleReportView` (batch delete), `ShuttleSessionDetailView` (raw collection, entries by sessionId).
- **Swift files:** `Utilities/ShuttleManager.swift`, `Views/ShuttleMainView.swift`, `Views/ShuttleSessionDetailView.swift`, `Views/DailyShuttleReportView.swift`, `Views/EditDailyShuttleReportView.swift`, `Views/GenerateShuttleReportView.swift`, `Views/RaporView.swift`.

### Vacation Times
- **Read:** `vacationTimes` — one-time: `loadVacationTimes`; listener: `observeVacationTimes`.
- **Write:** `vacationTimes` — `saveVacationTime` (setData).
- **Delete:** `vacationTimes` — `deleteVacationTime`.
- **Swift files:** `Firebase/FirebaseService.swift`, `ViewModels/AracViewModel.swift`, `Views/AdminPanelView.swift` (tests).

### Work Timetable
- **Read:** `workSchedules` — one-time: `loadWorkSchedules`; listener: `observeWorkSchedules`.
- **Write:** `workSchedules` — `saveWorkSchedule` / `updateWorkSchedule` (setData).
- **Delete:** `workSchedules` — `deleteWorkSchedule`.
- **Swift files:** `Firebase/FirebaseService.swift`, `ViewModels/AracViewModel.swift`.

### Services (Servisler + Servis Firmaları)
- **Read:**  
  - `servisler` — one-time: `loadServisler`.  
  - `servisFirmalari` — one-time: `loadServisFirmalari`; listener: `observeServisFirmalari` (via OptimizedRealtimeManager / FirebaseService).
- **Write:**  
  - `servisler` — `saveServis`, `deleteServis`.  
  - `servisFirmalari` — `saveServisFirmasi`, `updateServisFirmasi`, `deleteServisFirmasi`.
- **Swift files:** `Firebase/FirebaseService.swift`, `ViewModels/AracViewModel.swift`, `Utilities/CascadeDeleteManager.swift`, `Utilities/OptimizedRealtimeManager.swift`, `Views/AdminPanelView.swift` (tests).

### Admin Panel
- **Read:**  
  - `araclar`, `iadeIslemleri`, `office_operations`, `vacationTimes`, `exitIslemleri` — limit(1) tests via `getCollectionReference`.  
  - `adminTestLogs` — raw `db.collection("adminTestLogs")` (with/without orderBy) for export.
- **Write:**  
  - `adminTestLogs` — `getCollectionReference("adminTestLogs").document(logId).setData`.  
  - `adminTests` — raw `db.collection("adminTests").document(...).setData` (then delete); `exitIslemleri`, `iadeIslemleri`, `office_operations` test writes (mixed getCollectionReference and raw `db.collection`).
- **Listener:** Raw `db.collection("araclar").limit(to: 1).addSnapshotListener` for test.
- **Swift files:** `Views/AdminPanelView.swift` (contains its own `getCollectionReference` and raw `db.collection` usage).

---

## 2. FirebaseService.swift — All Firestore Operations

| Method | Collection | Operation | Type |
|--------|------------|-----------|------|
| loadAraclar | araclar | getDocuments | Read |
| saveArac | araclar | setData | Write |
| updateArac | araclar | setData | Write |
| deleteArac | araclar | delete | Delete |
| loadServisler | servisler | getDocuments | Read |
| saveServis | servisler | setData | Write |
| deleteServis | servisler | delete | Delete |
| loadIadeIslemleri | iadeIslemleri | getDocuments | Read |
| saveIadeIslemi | iadeIslemleri | setData | Write |
| deleteIadeIslemi | iadeIslemleri | delete | Delete |
| loadExitIslemleri | exitIslemleri | getDocuments | Read |
| saveExitIslemi | exitIslemleri | setData | Write |
| deleteExitIslemi | exitIslemleri | delete | Delete |
| observeExitIslemleri | exitIslemleri | addSnapshotListener | Listener |
| migrateExitOperationsCreatedAt | exitIslemleri | getDocuments + batch updateData | Read + Write |
| loadActivities | activities | getDocuments | Read |
| saveActivity | activities | setData | Write |
| deleteActivity | activities | delete | Delete |
| observeIadeIslemleri | iadeIslemleri | addSnapshotListener | Listener |
| observeAraclar | araclar | addSnapshotListener | Listener |
| loadServisFirmalari | servisFirmalari | getDocuments | Read |
| saveServisFirmasi | servisFirmalari | setData | Write |
| updateServisFirmasi | servisFirmalari | setData | Write |
| deleteServisFirmasi | servisFirmalari | delete | Delete |
| saveOfficeOperation | office_operations | setData | Write |
| loadOfficeOperations | office_operations | getDocuments | Read |
| observeOfficeOperations | office_operations | addSnapshotListener | Listener |
| updateOfficeOperation | office_operations | setData | Write |
| deleteOfficeOperation | office_operations | delete | Delete |
| saveOfficeReturn | office_Return | setData | Write |
| loadOfficeReturns | office_Return | getDocuments | Read |
| observeOfficeReturns | office_Return | addSnapshotListener | Listener |
| updateOfficeReturn | office_Return | setData | Write |
| deleteOfficeReturn | office_Return | delete | Delete |
| saveWorkSchedule | workSchedules | setData | Write |
| loadWorkSchedules | workSchedules | getDocuments | Read |
| observeWorkSchedules | workSchedules | addSnapshotListener | Listener |
| deleteWorkSchedule | workSchedules | delete | Delete |
| loadProtocols | protocols | getDocuments | Read |
| saveProtocol | protocols | setData | Write |
| updateProtocol | protocols | setData | Write |
| deleteProtocol | protocols | delete | Delete |
| observeProtocols | protocols | addSnapshotListener | Listener |
| saveVacationTime | vacationTimes | setData | Write |
| loadVacationTimes | vacationTimes | getDocuments | Read |
| observeVacationTimes | vacationTimes | addSnapshotListener | Listener |
| deleteVacationTime | vacationTimes | delete | Delete |
| loadAssistantCompanies | assistantCompanies | getDocuments | Read |
| saveAssistantCompany | assistantCompanies | setData | Write |
| deleteAssistantCompany | assistantCompanies | delete | Delete |
| observeAssistantCompanies | assistantCompanies | addSnapshotListener | Listener |

All use `getCollectionReference(...)` (franchise/demo-aware).

---

## 3. AracViewModel.swift — Data Operations

No direct Firestore calls. All operations go through `FirebaseService` or (for shuttle) `ShuttleManager`:

- Loads: `loadAraclar`, `servisleriYukle`, `iadeleriYukle`, `exitleriYukle`, `activitiesYukle`, `servisFirmalariYukle`, `assistantCompaniesYukle`, `officeOperationsYukle`, `officeReturnsYukle`, `vacationTimesYukle`, `workSchedulesYukle`.
- Listeners: set up in `setupRealtimeListeners()` (iadeIslemleri, exitIslemleri, assistantCompanies, araclar, officeOperations, officeReturns, workSchedules, vacationTimes).
- Writes: vehicle, damage, service, return, exit, office operation/return, service company, assistant company, work schedule, vacation time, activity — all via `firebaseService` or cascade.
- **Nested data:** Fixes missing `aracId` in `hasarKayitlari` when applying `observeAraclar` (damage is embedded in `araclar` doc).

---

## 4. Views/ — Direct Firestore Access

| File | Collections | Operations | Uses getCollectionReference? |
|------|-------------|------------|------------------------------|
| AdminPanelView | araclar, iadeIslemleri, office_operations, vacationTimes, exitIslemleri, adminTestLogs, adminTests | getDocuments, setData, updateData, delete, addSnapshotListener | Partially: tests use getCollectionReference for most; **adminTestLogs** and **adminTests** and one **araclar** listener use raw `db.collection` |
| DailyShuttleReportView | shuttleEntries | getDocuments, addSnapshotListener, batch setData/deleteDocument | Yes |
| EditDailyShuttleReportView | shuttleEntries | batch setData/deleteDocument | Yes |
| GenerateShuttleReportView | shuttleSessions, **shuttleReports** | getDocuments, **addDocument** (report metadata) | **No** for shuttleReports: `Firestore.firestore().collection("shuttleReports")` |
| NotificationManager | **users**, **notifications** | users: setData (FCM), getDocuments; notifications: addDocument | users: raw `db.collection("users")`; notifications: getCollectionReference |
| RaporView | shuttleEntries | getDocuments | Yes |
| ShuttleMainView | shuttleSessions | getDocuments | Yes |
| ShuttleReportsView | **shuttleReports** | getDocuments, delete | **No**: raw `Firestore.firestore().collection("shuttleReports")` |
| ShuttleSessionDetailView | **shuttleEntries**, **shuttleSessions** | getDocuments, delete (session + entries) | **No**: raw `Firestore.firestore().collection("shuttleEntries")` and `.collection("shuttleSessions")` |

---

## 5. Other Swift Files — Firestore

| File | Collections | Operations | Franchise-aware? |
|------|-------------|------------|------------------|
| AuthenticationManager | users | getDocument, getDocuments, setData | No (users is global) |
| ShuttleManager | shuttleSessions, shuttleEntries, activities | getDocuments, setData, updateData, addDocument | Yes (getCollectionReference) |
| CascadeDeleteManager | araclar, servisler, activities, iadeIslemleri, office_operations, servisFirmalari | getDocuments, delete, setData, updateData | Yes |
| PaginatedActivitiesManager | activities | getDocuments, addSnapshotListener | Yes |
| UserPresenceManager | userPresence | addSnapshotListener, setData | Yes |
| AuditTrailManager | audit_logs | setData, getDocuments | Yes |
| OptimizedRealtimeManager | araclar, iadeIslemleri, office_operations, activities, servisFirmalari | addSnapshotListener; batch setData/deleteDocument (generic) | Yes |

---

## 6. Subcollections / Nested Reads

- **hasarKayitlari:** Not a subcollection. It is an **array field** inside each `araclar` document. Read/write by loading/updating the vehicle document only. No `araclar/{id}/hasarKayitlari` in code.
- **shuttleReports:** Treated as a top-level collection; no subcollections under it in this audit.
- **demo_environments/{userId}/{collectionName}:** Used as path for demo users only (inside `getCollectionReference`), not as a “content” collection.

---

## 7. Collections You Asked About

- **raporGecmisi:** Referenced in `firestore.rules` only; **not used** in the iOS app.
- **shuttleReports:** Used in `GenerateShuttleReportView` (addDocument) and `ShuttleReportsView` (getDocuments, delete) via **raw** `Firestore.firestore().collection("shuttleReports")` — **not franchise-filtered** (bug for multi-franchise/demo).
- **notifications:** Used in `NotificationManager` — `getCollectionReference("notifications").addDocument` (franchise-aware). Queue for Cloud Function.
- **fcmTokens:** In `firestore.rules` only. App stores FCM in **users** doc: `db.collection("users").document(userId).setData(["fcmToken": token, ...], merge: true)`.
- **userPresence:** Used in `UserPresenceManager` — listener and setData via `getCollectionReference("userPresence")` (franchise-aware).
- **adminTests:** Used in `AdminPanelView` — raw `db.collection("adminTests")` for write test + delete. **Not franchise-filtered.**
- **adminTestLogs:** Used in `AdminPanelView` — write via `getCollectionReference("adminTestLogs")`; read/export via raw `db.collection("adminTestLogs")`. **Read path not franchise-filtered.**

---

## 8. Production vs System/User Collections

**Should be franchise-filtered (production data):**  
araclar, servisler, iadeIslemleri, exitIslemleri, activities, servisFirmalari, office_operations, office_Return, workSchedules, protocols, vacationTimes, assistantCompanies, shuttleSessions, shuttleEntries, shuttleReports, notifications (queue per env), userPresence (per env), audit_logs.

**Should NOT be franchise-filtered (system/user):**  
users (profiles + FCM by uid).

**Admin/diagnostic (decide by policy):**  
adminTests, adminTestLogs — currently raw `db.collection` in places; if they should be per-franchise, they need to use `getCollectionReference` everywhere.

---

## 9. Issues to Fix

1. **shuttleReports**  
   - `GenerateShuttleReportView`: save report metadata with `getCollectionReference("shuttleReports")` (or equivalent) instead of `Firestore.firestore().collection("shuttleReports")`.  
   - `ShuttleReportsView`: load and delete using the same franchise-aware reference.

2. **ShuttleSessionDetailView**  
   - Replace `Firestore.firestore().collection("shuttleSessions")` and `.collection("shuttleEntries")` with `getCollectionReference("shuttleSessions")` and `getCollectionReference("shuttleEntries")` (and pass/inject FirebaseService or a helper that uses demo/production logic).

3. **AdminPanelView**  
   - Use `getCollectionReference("adminTestLogs")` for export (read) so demo/production is consistent.  
   - Use `getCollectionReference("adminTests")` for write/delete if admin tests should be per-franchise; otherwise document that they are global.

4. **NotificationManager — users**  
   - Intentional: `users` is global for FCM and profile. No change needed for franchise filtering of users.

---

**End of audit.**
