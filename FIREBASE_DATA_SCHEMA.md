# Firebase Data Schema Documentation

> **Application:** GreenMotion Fleet Management System  
> **Platform:** iOS (SwiftUI) + Web (React)  
> **Database:** Cloud Firestore  
> **Storage:** Firebase Storage  
> **Last Updated:** February 2026

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Collection Reference](#2-collection-reference)
3. [Detailed Collection Schemas](#3-detailed-collection-schemas)
4. [Firebase Storage Paths](#4-firebase-storage-paths)
5. [Composite Indexes](#5-composite-indexes)
6. [Security Rules Summary](#6-security-rules-summary)
7. [Data Encoding Conventions](#7-data-encoding-conventions)
8. [Legacy → Scoped Migration](#8-legacy--scoped-migration)

---

## 1. Architecture Overview

### Data Isolation Layers

```
┌─────────────────────────────────────────────────────┐
│                   FIRESTORE                         │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  GLOBAL COLLECTIONS (no franchise filter)   │    │
│  │  users, userPresence, notifications,        │    │
│  │  franchises, plateFormats, protocolTemplates │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  FRANCHISE-FILTERED COLLECTIONS             │    │
│  │  Every document has: franchiseId: String     │    │
│  │  Query filter: WHERE franchiseId == "ch"     │    │
│  │  Superadmins bypass filter (see all data)    │    │
│  │                                              │    │
│  │  araclar, activities, servisler,             │    │
│  │  iadeIslemleri, exitIslemleri,               │    │
│  │  office_operations, office_Return,           │    │
│  │  shuttleEntries, shuttleSessions, ...        │    │
│  └─────────────────────────────────────────────┘    │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  DEMO COLLECTIONS                           │    │
│  │  Legacy: demo_{collectionName}              │    │
│  │  New: demo_environments/{userId}/{collection}│   │
│  └─────────────────────────────────────────────┘    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Franchise Filtering Logic

| User Type | Collection Path | Query Filter |
|-----------|----------------|--------------|
| Regular Production User | `{collectionName}` | `WHERE franchiseId == user.franchiseId` |
| Superadmin | `{collectionName}` | No filter (sees all franchises) |
| Legacy Demo (`demo@gmail.com`) | `demo_{collectionName}` | None |
| New Demo User | `demo_environments/{userId}/{collectionName}` | None |

---

## 2. Collection Reference

### Production Collections (Franchise-Filtered)

| # | Collection Name | Swift Model | Description |
|---|----------------|-------------|-------------|
| 1 | `araclar` | `Arac` | Vehicles with nested damage records |
| 2 | `activities` | `Activity` | Activity/audit log entries |
| 3 | `servisler` | `ServisKaydi` | Service records for vehicles |
| 4 | `servisFirmalari` | `ServisFirma` | Service company directory |
| 5 | `iadeIslemleri` | `IadeIslemi` | Customer return (check-in) operations |
| 6 | `exitIslemleri` | `ExitIslemi` | Check-out operations |
| 7 | `office_operations` | `OfficeOperation` | Office financial operations |
| 8 | `office_Return` | `OfficeReturn` | Office customer returns |
| 9 | `shuttleEntries` | `ShuttleEntry` | Individual shuttle pickup/dropoff entries |
| 10 | `shuttleSessions` | `ShuttleSession` | Daily shuttle driver sessions |
| 11 | `shuttleReports` | Dictionary | Generated shuttle report metadata |
| 12 | `workSchedules` | `WorkSchedule` | Employee work timetable |
| 13 | `vacationTimes` | `VacationTime` | Employee vacation periods |
| 14 | `assistantCompanies` | `AssistantCompany` | Assistant/insurance companies |
| 15 | `protocols` | `Protocol` | Rental protocols |
| 16 | `audit_logs` | `AuditLog` | System audit trail |

### Global Collections (Not Franchise-Filtered)

| # | Collection Name | Swift Model | Description |
|---|----------------|-------------|-------------|
| 17 | `users` | `UserProfile` | User profiles, roles, FCM tokens |
| 18 | `userPresence` | `UserPresence` | Real-time user online status |
| 19 | `notifications` | Dictionary | Push notification queue |
| 20 | `franchises` | — | Franchise configuration (superadmin only) |
| 21 | `plateFormats` | — | Country-specific license plate formats |
| 22 | `protocolTemplates` | — | Protocol templates (web app) |

### Admin/Diagnostic Collections

| # | Collection Name | Description |
|---|----------------|-------------|
| 23 | `adminTests` | Admin panel test documents (superadmin only) |
| 24 | `adminTestLogs` | Admin panel test result logs (superadmin only) |

### Web-Only Collections (Referenced in Rules)

| # | Collection Name | Description |
|---|----------------|-------------|
| 25 | `transactions` | ERP transactions |
| 26 | `customers` | ERP customer records |
| 27 | `accidents` | ERP accident records |
| 28 | `accidentCodes` | Accident type codes |
| 29 | `trafficFines` | Traffic fine records |
| 30 | `bankingTransactions` | Banking transaction records |
| 31 | `additionalSales` | Additional sales records |
| 32 | `semesInvoices` | SEMES invoice records |

---

## 3. Detailed Collection Schemas

### 3.1 `users` — User Profiles

**Document ID:** Firebase Auth UID  
**Swift Model:** `UserProfile`

```
users/{uid}
├── uid: String                    // Firebase Auth UID
├── email: String                  // User email address
├── firstName: String              // First name (default: "")
├── lastName: String               // Last name (default: "")
├── createdAt: Timestamp           // Account creation date
├── role: String                   // "superadmin" | "admin" | "manager" | "staff" | "shuttle" | "viewer"
├── countryCode: String            // Country code (default: "CH")
├── franchiseId: String            // Franchise identifier (default: "ch")
├── isDemoAccount: Bool            // Demo account flag (default: false)
├── isActive: Bool                 // Active status
├── parentUserId: String?          // Parent user ID (demo accounts only)
├── demoExpiresAt: Timestamp?      // Demo expiration date (demo accounts only)
├── fcmToken: String?              // FCM push notification token
└── lastTokenUpdate: Timestamp?    // Last FCM token update time
```

**Role Hierarchy:**
| Role | Access Level |
|------|-------------|
| `superadmin` | Full access, bypasses franchise filter, manages all franchises |
| `admin` | Franchise-level admin, manages users within franchise |
| `manager` | Operational management within franchise |
| `staff` | Standard operational access |
| `viewer` | Read-only access |

---

### 3.2 `araclar` — Vehicles

**Document ID:** UUID string  
**Swift Model:** `Arac`

```
araclar/{vehicleId}
├── id: String                     // UUID string
├── plaka: String                  // License plate (e.g., "ZH 123456")
├── marka: String                  // Brand (e.g., "Toyota")
├── model: String                  // Model (e.g., "Corolla")
├── kategori: String               // Category: "A", "B", "C", etc. (default: "A")
├── vignetteVar: Bool              // Has highway vignette
├── kayitTarihi: Timestamp         // Registration date
├── qrCode: String                 // QR code value (default: plaka)
├── spareKeyCount: Int             // Number of spare keys (default: 0)
├── headDocumentURL: String?       // Vehicle registration document URL
├── createdBy: String?             // Creator user UID
├── assistantCompanyName: String?  // Assigned assistant/insurance company name
├── assistantCompanyPhone: String? // Assigned assistant/insurance company phone
├── franchiseId: String            // Franchise ID (default: "ch")
│
└── hasarKayitlari: Array          // Nested damage records
    └── [index]
        ├── id: String             // UUID string
        ├── aracId: String         // Parent vehicle UUID
        ├── aracPlaka: String      // Vehicle plate
        ├── tarih: Timestamp       // Damage date
        ├── handoverTarihi: Timestamp // Handover date
        ├── resKodu: String        // Reservation code
        ├── km: Int                // Odometer reading (km)
        ├── fotograflar: [String]  // Array of photo URLs (Firebase Storage)
        ├── durum: String          // "inProgress" | "done"
        ├── status: String         // "inProgress" | "completed"
        ├── notlar: String         // Notes (default: "")
        └── createdBy: String?     // Creator user UID
```

---

### 3.3 `activities` — Activity Log

**Document ID:** UUID string  
**Swift Model:** `Activity`

```
activities/{activityId}
├── id: String                     // UUID string
├── tip: String                    // Activity type (see enum below)
├── aciklama: String               // Description text
├── tarih: Timestamp               // Activity date
├── aracPlaka: String?             // Related vehicle plate
├── detayliAciklama: String?       // Detailed description
├── kullaniciAdi: String?          // Username who performed action
├── kullaniciEmail: String?        // User email
├── officeOperationId: String?     // Related office operation UUID
└── franchiseId: String            // Franchise ID (default: "ch")
```

**Activity Types (`tip`):**
| Value | Description |
|-------|-------------|
| `Araç Eklendi` | Vehicle added |
| `Araç Silindi` | Vehicle deleted |
| `Hasar Eklendi` | Damage record added |
| `Hasar Silindi` | Damage record deleted |
| `Hasar Güncellendi` | Damage record updated |
| `Servis Eklendi` | Service record added |
| `İade Yapıldı` | Return completed |
| `Shuttle Pickup` | Shuttle pickup recorded |
| `Office Operation` | Office operation recorded |
| `Office Operation Deleted` | Office operation deleted |

---

### 3.4 `servisler` — Service Records

**Document ID:** UUID string  
**Swift Model:** `ServisKaydi`

```
servisler/{serviceId}
├── id: String                     // UUID string
├── aracId: String                 // Vehicle UUID
├── servisTuru: String             // Service type
├── aciklama: String               // Description
├── tarih: Timestamp               // Service date
├── ucret: Double                  // Cost amount (default: 0)
├── teslimTarihi: Timestamp?       // Expected delivery date
├── servisNedenleri: [String]      // Array of service reasons (default: [])
├── durum: String                  // Status (default: "Serviste")
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.5 `servisFirmalari` — Service Companies

**Document ID:** UUID string  
**Swift Model:** `ServisFirma`

```
servisFirmalari/{companyId}
├── id: String                     // UUID string
├── ad: String                     // Company name
├── telefon: String                // Phone number (default: "")
├── email: String                  // Email (default: "")
├── adres: String                  // Address (default: "")
├── notlar: String                 // Notes (default: "")
├── kayitTarihi: Timestamp         // Registration date
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.6 `iadeIslemleri` — Return (Check-In) Operations

**Document ID:** UUID string  
**Swift Model:** `IadeIslemi`

```
iadeIslemleri/{returnId}
├── id: String                     // UUID string
├── aracId: String                 // Vehicle UUID
├── aracPlaka: String              // Vehicle license plate
├── iadeTarihi: Timestamp          // Return date
├── fotograflar: [String]          // Array of photo URLs
├── notlar: String                 // Notes
├── status: String                 // "inProgress" | "completed" (default: "completed")
├── createdBy: String?             // Creator user UID
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.7 `exitIslemleri` — Check-Out Operations

**Document ID:** UUID string  
**Swift Model:** `ExitIslemi`

```
exitIslemleri/{exitId}
├── id: String                     // UUID string
├── aracId: String                 // Vehicle UUID
├── aracPlaka: String              // Vehicle license plate
├── exitTarihi: Timestamp          // Check-out date
├── createdAt: Timestamp           // Document creation date
├── fotograflar: [String]          // Array of photo URLs
├── notlar: String                 // Notes (default: "")
├── resKodu: String                // Reservation code (default: "")
├── status: String                 // "inProgress" | "completed" (default: "completed")
├── createdBy: String?             // Creator user UID
├── assistantCompanyName: String?  // Assistant company name
├── assistantCompanyPhone: String? // Assistant company phone
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.8 `office_operations` — Office Financial Operations

**Document ID:** UUID string or custom string  
**Swift Model:** `OfficeOperation`

> **Note:** Dates are stored as `TimeInterval` (seconds since January 1, 2001 — Apple's reference date) for web compatibility. NOT standard Firestore Timestamps.

```
office_operations/{operationId}
├── id: String                     // UUID string or custom ID
├── documentId: String?            // Firebase document ID (web compatibility)
├── type: String                   // Operation type (see enum below)
├── date: Double                   // TimeInterval since 2001-01-01
├── amount: Double                 // Monetary amount
├── photos: [String]               // Array of photo URLs (default: [])
├── notes: String                  // Notes (default: "")
├── isCompleted: Bool              // Completion status (default: false)
├── createdBy: String?             // Creator user UID
├── vehiclePlate: String?          // Related vehicle plate
│
│   // --- POS Fields (type: "posClosing") ---
├── posCount: Int?                 // Number of POS transactions
├── posAmounts: [Double]?          // Individual POS amounts
│
│   // --- Traffic Fine Fields (type: "trafficFine") ---
├── fineNumber: String?            // Fine reference number
├── fineType: String?              // Fine type/category
├── paymentStatus: String?         // Payment status (iOS: "paymentStatus", Web: "status")
│
│   // --- Banking Fields (type: "banking") ---
├── transactionNumber: String?     // Transaction reference number
├── bankName: String?              // Bank name
├── accountNumber: String?         // Account number
├── transactionType: String?       // Transaction type
├── referenceNumber: String?       // Reference number (iOS: "referenceNumber", Web: "resCode")
│
│   // --- Additional Sales Fields (type: "additionalSales") ---
├── productName: String?           // Product/service name
├── quantity: Double?              // Quantity sold
├── unitPrice: Double?             // Unit price
├── customerName: String?          // Customer name
├── invoiceNumber: String?         // Invoice number
│
└── franchiseId: String            // Franchise ID (default: "ch")
```

**Operation Types (`type`):**
| Value | Description |
|-------|-------------|
| `creditCard` | Credit card receipt |
| `posClosing` | POS daily closing |
| `fuelReceipt` | Fuel receipt |
| `washing` | Vehicle washing expense |
| `additionalSales` | Additional sales |
| `banking` | Banking transaction |
| `trafficFine` | Traffic fine |

---

### 3.9 `office_Return` — Office Customer Returns

**Document ID:** UUID string  
**Swift Model:** `OfficeReturn`

```
office_Return/{returnId}
├── id: String                     // UUID string
├── amount: Double                 // Return amount
├── reason: String                 // Return reason (see enum below)
├── date: Timestamp                // Return date
├── photos: [String]               // Array of photo URLs (default: [])
├── notes: String                  // Notes (default: "")
└── franchiseId: String            // Franchise ID (default: "ch")
```

**Return Reasons (`reason`):**
| Value | Description |
|-------|-------------|
| `vehicleReturn` | Vehicle return |
| `cancellation` | Reservation cancellation |
| `refund` | Refund |
| `damageClaim` | Damage claim |
| `other` | Other |

---

### 3.10 `shuttleEntries` — Shuttle Pickup/Dropoff Entries

**Document ID:** Auto-generated  
**Swift Model:** `ShuttleEntry`

```
shuttleEntries/{entryId}
├── id: String                     // Auto-generated document ID
├── customerCount: Int             // Number of customers
├── entryType: String              // "pickup" | "dropoff"
├── timestamp: Timestamp           // Entry time
├── driverName: String             // Driver display name
├── driverUID: String              // Driver Firebase Auth UID
├── sessionId: String              // Parent session document ID
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.11 `shuttleSessions` — Shuttle Driver Sessions

**Document ID:** Auto-generated  
**Swift Model:** `ShuttleSession`

```
shuttleSessions/{sessionId}
├── id: String                     // Auto-generated document ID
├── date: Timestamp                // Session date
├── driverName: String             // Driver display name
├── driverUID: String              // Driver Firebase Auth UID
├── entries: Array                 // Embedded ShuttleEntry objects
│   └── [index]
│       ├── customerCount: Int
│       ├── entryType: String
│       ├── timestamp: Timestamp
│       ├── driverName: String
│       ├── driverUID: String
│       └── sessionId: String
├── totalCustomers: Int            // Running total of customers
├── isActive: Bool                 // Session active/completed
├── startTime: Timestamp           // Session start time
├── endTime: Timestamp?            // Session end time (null if active)
└── franchiseId: String            // Franchise ID (default: "ch")
```

**Write Operations use:**
- `FieldValue.arrayUnion([entryData])` to append entries
- `FieldValue.increment(Int64(count))` to update totalCustomers

---

### 3.12 `shuttleReports` — Generated Shuttle Report Metadata

**Document ID:** Auto-generated  
**No Codable model** — stored as dictionary

```
shuttleReports/{reportId}
├── type: String                   // Report type
├── startDate: Timestamp           // Report period start
├── endDate: Timestamp             // Report period end
├── totalSessions: Int             // Total sessions in period
├── totalCustomers: Int            // Total customers in period
├── totalTrips: Int                // Total trips in period
├── generatedAt: Timestamp         // Report generation timestamp
├── pdfPath: String                // Firebase Storage path to PDF
└── franchiseId: String            // Franchise ID
```

---

### 3.13 `workSchedules` — Employee Work Timetable

**Document ID:** `{userId}_{weekStartTimestamp}`  
**Swift Model:** `WorkSchedule`

```
workSchedules/{scheduleId}
├── userId: String                 // Employee Firebase Auth UID
├── userName: String               // Employee display name
├── weekStartDate: Timestamp       // Monday of the week
├── schedules: Array               // Daily schedule entries
│   └── [index]
│       ├── dayOfWeek: Int         // 0=Monday, 1=Tuesday, ..., 6=Sunday
│       ├── startTime: String      // Format: "HH:mm" (e.g., "08:00")
│       ├── endTime: String        // Format: "HH:mm" (e.g., "17:00")
│       ├── isVacation: Bool       // Vacation day flag
│       └── shiftType: String      // "morning" | "afternoon" | "evening" | "fullDay"
├── createdAt: Timestamp           // Document creation date
├── updatedAt: Timestamp           // Last update date
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.14 `vacationTimes` — Employee Vacation Periods

**Document ID:** UUID string  
**Swift Model:** `VacationTime`

> **Note:** Dates stored as `TimeInterval` (seconds since January 1, 2001) for web compatibility.

```
vacationTimes/{vacationId}
├── id: String                     // UUID string
├── employeeName: String           // Employee name
├── startDate: Double              // TimeInterval since 2001-01-01
├── endDate: Double                // TimeInterval since 2001-01-01
├── isActive: Bool                 // Active status (default: true)
├── createdBy: String              // Creator email or user ID
├── createdAt: Double              // TimeInterval since 2001-01-01
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.15 `assistantCompanies` — Insurance/Assistant Companies

**Document ID:** Lowercase UUID string  
**Swift Model:** `AssistantCompany`

```
assistantCompanies/{companyId}
├── id: String                     // UUID string (lowercase)
├── name: String                   // Company name
├── phoneNumber: String            // Phone number
├── createdAt: Timestamp           // Creation date
├── createdBy: String?             // Creator user UID
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.16 `protocols` — Rental Protocols

**Document ID:** Auto-assigned by Firestore  
**Swift Model:** `Protocol`

> **Note:** All date fields are ISO 8601 strings, not Firestore Timestamps.

```
protocols/{protocolId}
├── id: String                     // Firestore document ID
├── protocolId: String             // Protocol identifier
├── protocolName: String           // Protocol name
├── protocolType: String           // Protocol type
├── templatePath: String           // Protocol template path
├── customerName: String           // Customer name
├── vehiclePlate: String           // Vehicle license plate
├── reservationNumber: String      // Reservation number
├── baseCost: String               // Base cost (string)
├── checkInDate: String            // ISO 8601 date string
├── checkOutDate: String           // ISO 8601 date string
├── fieldValues: String            // JSON-encoded field values
├── status: String                 // "DRAFT" | "PENDING" | "COMPLETE" | "OVERDUE" | "CANCELLED"
├── createdAt: String              // ISO 8601 date string
├── createdBy: String              // Creator user UID
├── updatedAt: String              // ISO 8601 date string
├── updatedBy: String              // Updater user UID
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.17 `audit_logs` — System Audit Trail

**Document ID:** UUID string  
**Swift Model:** `AuditLog`

```
audit_logs/{logId}
├── id: String                     // UUID string
├── timestamp: Timestamp           // Event timestamp
├── userId: String                 // Acting user UID
├── userName: String?              // Acting user name
├── action: String                 // "CREATED" | "UPDATED" | "DELETED" | "ACCESSED"
├── tableName: String              // Target collection name
├── recordId: String               // Target document ID
├── changes: Map                   // Changed fields
│   └── {fieldName}
│       ├── before: String?        // Previous value
│       └── after: String?         // New value
├── ipAddress: String?             // Client IP address
├── deviceInfo: String?            // Client device info
└── franchiseId: String            // Franchise ID (default: "ch")
```

---

### 3.18 `userPresence` — Real-Time User Status

**Document ID:** Firebase Auth UID  
**Swift Model:** `UserPresence`

```
userPresence/{userId}
├── id: String                     // Firebase Auth UID
├── displayName: String            // User display name
├── email: String                  // User email
├── status: String                 // "Online" | "Offline" | "Away"
└── lastSeen: Timestamp            // Last activity timestamp
```

---

### 3.19 `notifications` — Push Notification Queue

**Document ID:** Auto-generated  
**No Codable model**

```
notifications/{notificationId}
├── title: String                  // Notification title
├── body: String                   // Notification body text
├── timestamp: Timestamp           // Creation timestamp
├── userId: String?                // Target user UID (null = broadcast)
└── type: String?                  // Notification category
```

---

### 3.20 `raporGecmisi` — Report History

**Document ID:** UUID string  
**Swift Model:** `RaporGecmisi`

```
raporGecmisi/{reportId}
├── id: String                     // UUID string
├── tip: String                    // "Hasar Raporu" | "İade Raporu"
├── aracPlaka: String              // Vehicle plate
├── olusturulmaTarihi: Timestamp   // Creation date
├── pdfURL: String                 // PDF download URL
├── kullaniciEmail: String?        // Creator email
└── detaylar: String?              // Report details
```

---

## 4. Firebase Storage Paths

### Photo Storage

| Path Pattern | Content | Size Limit | Format |
|---|---|---|---|
| `hasar_fotograflari/{...}` | Damage photos | 10 MB | Images |
| `damages/{vehicleId}/{damageId}/{filename}` | Damage photos (alt path) | 10 MB | Images |
| `iade_fotograflari/{...}` | Return photos | 10 MB | Images |
| `exit_fotograflari/{...}` | Check-out photos | 10 MB | Images |
| `office_operations/{...}` | Office operation receipts | 10 MB | Images |
| `officeOperations/{operationId}/{...}` | Office operation receipts (alt) | 10 MB | Images |
| `office_Return/{returnId}/{filename}` | Office return photos | 10 MB | Images |
| `servis_fotograflari/{userId}/{serviceId}/{filename}` | Service photos | 5 MB | Images |

### Document Storage

| Path Pattern | Content | Size Limit | Format |
|---|---|---|---|
| `head_documents/{vehicleId}/{filename}` | Vehicle registration papers | 10 MB | Images, PDF |
| `pdf_exports/{userId}/{filename}` | Generated PDF reports | 10 MB | PDF |

### User Storage

| Path Pattern | Content | Size Limit | Format |
|---|---|---|---|
| `profile_photos/{userId}/{filename}` | User profile photos | 5 MB | Images |
| `temp/{userId}/{filename}` | Temporary uploads (24h TTL) | 10 MB | Any |

### Demo & Test Storage

| Path Pattern | Content | Size Limit | Format |
|---|---|---|---|
| `demo_environments/{userId}/{...}` | Demo user isolated storage | 10 MB | Images, PDF |
| `test/{...}` | Admin test files | 10 MB | Any |

### Web App Storage

| Path Pattern | Content |
|---|---|
| `protocolTemplates/{...}` | Protocol PDF templates |
| `cars/{carId}/{...}` | Vehicle photos (web) |
| `returns/{returnId}/{...}` | Return photos (web) |

---

## 5. Composite Indexes

Defined in `firestore.indexes.json`:

| Collection | Fields | Order |
|---|---|---|
| `activities` | `franchiseId` ASC, `tarih` DESC | Query: by franchise + date |
| `activities` | `franchiseId` ASC, `tip` ASC, `tarih` DESC | Query: by franchise + type + date |
| `activities` | `franchiseId` ASC, `aracPlaka` ASC, `tarih` DESC | Query: by franchise + vehicle + date |
| `assistantCompanies` | `franchiseId` ASC, `name` ASC | Query: by franchise + name sort |
| `shuttleEntries` | `franchiseId` ASC, `timestamp` ASC | Query: by franchise + time range |
| `shuttleSessions` | `franchiseId` ASC, `startTime` ASC | Query: by franchise + start time |
| `shuttleReports` | `franchiseId` ASC, `generatedAt` DESC | Query: by franchise + newest first |

---

## 6. Security Rules Summary

### Helper Functions

| Function | Purpose |
|---|---|
| `isAuthenticated()` | `request.auth != null` |
| `isOwner(userId)` | Authenticated and UID matches |
| `isDemoUser()` | Checks email patterns + `users/{uid}.isDemoAccount == true` |
| `isProductionUser()` | Authenticated and NOT demo |
| `isSuperAdmin()` | `users/{uid}.role == "superadmin"` |
| `getUserFranchiseId()` | Reads `users/{uid}.franchiseId` |
| `hasFranchiseReadAccess()` | Superadmin OR (production user AND document.franchiseId matches) |
| `hasFranchiseWriteAccess()` | Superadmin OR (production user AND request.franchiseId matches) |
| `hasFranchiseDeleteAccess()` | Superadmin OR (production user AND document.franchiseId matches) |

### Access Matrix

| Collection | Read | Write | Delete | List |
|---|---|---|---|---|
| **Franchise-filtered** (araclar, activities, etc.) | `hasFranchiseReadAccess()` | `hasFranchiseWriteAccess()` | `hasFranchiseDeleteAccess()` | `isProductionUser()` |
| **users** | Owner, franchise peers, superadmin | Owner (limited), superadmin | Superadmin only | Superadmin only |
| **userPresence** | Authenticated | Owner only | — | — |
| **notifications** | Authenticated | Authenticated (create only) | — | — |
| **franchises** | Superadmin, franchise member | Superadmin only | Superadmin only | Superadmin only |
| **adminTests/Logs** | Superadmin | Superadmin | Superadmin / false | Superadmin |
| **demo_*** collections | `isDemoUser()` | `isDemoUser()` | `isDemoUser()` | `isDemoUser()` |
| **demo_environments/{userId}/*** | Demo user + UID match | Demo user + UID match | Demo user + UID match | Demo user + UID match |

---

## 7. Data Encoding Conventions

### Date Encoding

| Convention | Used In | Format |
|---|---|---|
| **Firestore Timestamp** | Most collections | Native `Timestamp` type |
| **TimeInterval (Apple)** | `office_operations`, `vacationTimes` | `Double` — seconds since 2001-01-01 00:00:00 UTC |
| **ISO 8601 String** | `protocols` | `String` — "2026-02-07T15:30:00Z" |

### ID Conventions

| Convention | Used In |
|---|---|
| UUID string (uppercase) | Most collections (`araclar`, `activities`, `iadeIslemleri`, etc.) |
| UUID string (lowercase) | `assistantCompanies` (Firestore document ID) |
| Auto-generated | `shuttleEntries`, `shuttleSessions`, `protocols` |
| Composite key | `workSchedules` (`{userId}_{weekStartTimestamp}`) |
| Firebase Auth UID | `users`, `userPresence` |

### Common Fields

Every franchise-filtered document includes:

```
franchiseId: String    // Default: "ch" (Switzerland)
                       // Values: "ch", "tr", "de", etc.
                       // Superadmins see all franchiseId values
```

### Backward Compatibility

All models use `decodeIfPresent` with sensible defaults:
- `franchiseId` defaults to `"ch"` (existing data before multi-franchise)
- `createdBy` defaults to `nil`
- Optional fields default to `nil` or empty string/array
- `isDemoAccount` defaults to `false`

---

## 8. Legacy → Scoped Migration

### Path model

| Layer | Pattern | Example |
|-------|---------|---------|
| **Legacy (root)** | `{collection}/{docId}` | `araclar/{vehicleId}` |
| **Scoped (canonical)** | `franchises/{franchiseId}/{collection}/{docId}` | `franchises/CH/araclar/{vehicleId}` |

Global collections (`users`, `franchises`, `protocolTemplates`, …) stay at the root. Domain data is copied into scoped paths; **legacy root docs are not deleted until a verified scoped copy exists.**

### Metadata fields

| Field | Document | Purpose |
|-------|----------|---------|
| `_migration` | Scoped copy | `sourcePath`, `migratedAt`, `verified`, `contentFingerprint` |
| `_migrationLegacy` | Legacy root (optional) | `scopedPath`, `copyVerified` after successful copy |

Collection list: `scripts/franchise-migration-map.json` → `domainFirestoreCollections`.

### Deployment order

1. **Export backup** (Firestore → GCS).
2. **`migrateLegacyToScoped`** (dry-run, then batched copy) until `getLegacyScopedParity` shows `missingInScoped: 0`.
3. **Deploy app** (iOS/web already read/write `franchises/{id}/…`).
4. **`cleanupVerifiedLegacyDocs`** only after parity + spot checks (`confirmToken: DELETE_VERIFIED_LEGACY`).
5. **Deploy rules** (optional tightening of legacy root writes).

### Callable functions (`functions/index.js`)

| Function | Role |
|----------|------|
| `migrateLegacyToScoped` | Copy legacy → scoped (idempotent, `dryRun`, `batchLimit`, `startAfter`) |
| `getLegacyScopedParity` | Count legacy vs scoped / list missing copies |
| `cleanupVerifiedLegacyDocs` | Delete legacy docs with verified scoped copies only |
| `getMigrationHealth` | Queue health; pass `includeParity: true` for parity snapshot |
| `migrateAddFranchiseId` | Older helper: stamps `franchiseId` on root docs only (no path move) |

**Auth:** `superadmin` or `globaladmin` only (Admin SDK bypasses rules).

**Example (Firebase CLI / client SDK):**

```javascript
// Dry-run one batch
const fn = httpsCallable(functions, 'migrateLegacyToScoped');
await fn({ dryRun: true, batchLimit: 100, franchiseId: 'CH' });

// Continue with cursor from previous response
await fn({ batchLimit: 100, startAfter: { araclar: 'last-doc-id' } });

// Parity check
await httpsCallable(functions, 'getLegacyScopedParity')({ franchiseId: 'CH' });

// Cleanup (destructive)
await httpsCallable(functions, 'cleanupVerifiedLegacyDocs')({
  dryRun: false,
  confirmToken: 'DELETE_VERIFIED_LEGACY',
  franchiseId: 'CH',
});
```

**Local script:** `node scripts/backfill_firestore_scoped.js --dry-run` (same engine as the callable).

### Client read/write during transition

- **iOS** (`FirebaseService`): scoped reads/writes enabled; legacy root not used for new data.
- **Web** (`firebaseHelpers.getCollectionRef`): production paths are `franchises/{FRANCHISE_ID}/{collection}`.
- Legacy root listeners in old builds may still run until cleanup; copy-first migration avoids data loss.
