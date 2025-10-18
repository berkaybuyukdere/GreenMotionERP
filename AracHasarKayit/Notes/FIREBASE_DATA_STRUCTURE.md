# Firebase Firestore Data Structure Documentation

## Overview
This document describes the complete data structure used in Firebase Firestore for the Green Motion Vehicle Damage Management System.

---

## Collections & Documents

### 1. **`users`** Collection
Stores user account information and authentication details.

#### Document ID: `{uid}` (Firebase Auth User ID)

#### Fields:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `uid` | String | Firebase Authentication User ID | `"abc123xyz456"` |
| `email` | String | User's email address | `"user@greenmotion.ch"` |
| `firstName` | String | User's first name | `"John"` |
| `lastName` | String | User's last name | `"Doe"` |
| `createdAt` | Timestamp | Account creation date | `2024-01-15T10:30:00Z` |

#### Example Document:
```json
{
  "uid": "abc123xyz456",
  "email": "john.doe@greenmotion.ch",
  "firstName": "John",
  "lastName": "Doe",
  "createdAt": "2024-01-15T10:30:00.000Z"
}
```

---

### 2. **`araclar`** Collection (Vehicles)
Stores all vehicle information including damage records.

#### Document ID: `{aracId}` (UUID)

#### Fields:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `id` | String (UUID) | Unique vehicle identifier | `"550e8400-e29b-41d4-a716-446655440000"` |
| `plaka` | String | License plate (uppercase, no spaces) | `"ZH123456"` |
| `marka` | String | Vehicle brand/make | `"BMW"` |
| `model` | String | Vehicle model | `"320i"` |
| `kategori` | String | Vehicle category (A-Z single letter) | `"A"` |
| `vignetteVar` | Boolean | Whether vehicle has vignette | `true` |
| `spareKeyCount` | Number | Number of spare keys | `2` |
| `headDocumentURL` | String? (optional) | Firebase Storage URL for vehicle document | `"https://storage..."` |
| `hasarKayitlari` | Array | Array of damage records (nested) | `[{...}, {...}]` |

#### Nested `hasarKayitlari` (Damage Records) Structure:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `id` | String (UUID) | Unique damage record ID | `"660e8400-e29b-41d4-a716-446655440001"` |
| `tarih` | Timestamp | Damage record date | `2024-02-20T14:30:00Z` |
| `handoverTarihi` | Timestamp | Vehicle handover date | `2024-02-20T09:00:00Z` |
| `resKodu` | String | RES code (format: RES-XXXX) | `"RES-1234"` |
| `km` | Number | Vehicle mileage at damage time | `45000` |
| `fotograflar` | Array[String] | URLs of damage photos (1st=HANDOVER, rest=RETURN) | `["https://...", "https://..."]` |
| `durum` | String | Status: "In Progress" or "Done" | `"Done"` |

#### Example Document:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "plaka": "ZH123456",
  "marka": "BMW",
  "model": "320i",
  "kategori": "A",
  "vignetteVar": true,
  "spareKeyCount": 2,
  "headDocumentURL": "https://firebasestorage.googleapis.com/...",
  "hasarKayitlari": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "tarih": "2024-02-20T14:30:00.000Z",
      "handoverTarihi": "2024-02-20T09:00:00.000Z",
      "resKodu": "RES-1234",
      "km": 45000,
      "fotograflar": [
        "https://firebasestorage.googleapis.com/hasar_fotograflari/handover.jpg",
        "https://firebasestorage.googleapis.com/hasar_fotograflari/return1.jpg",
        "https://firebasestorage.googleapis.com/hasar_fotograflari/return2.jpg"
      ],
      "durum": "Done"
    }
  ]
}
```

---

### 3. **`servisKayitlari`** Collection (Service Records)
Stores vehicle service records.

#### Document ID: `{servisId}` (UUID)

#### Fields:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `id` | String (UUID) | Unique service record ID | `"770e8400-e29b-41d4-a716-446655440002"` |
| `aracId` | String (UUID) | Reference to vehicle ID | `"550e8400-e29b-41d4-a716-446655440000"` |
| `aracPlaka` | String | Vehicle license plate | `"ZH123456"` |
| `servisFirmaAdi` | String | Service company name | `"AutoCenter Zurich"` |
| `servisTuru` | String | Type of service | `"Oil Change"` |
| `aciklama` | String | Service description/notes | `"Full synthetic oil change + filter"` |
| `gonderilmeTarihi` | Timestamp | Service start date | `2024-03-01T08:00:00Z` |
| `tahminiTeslimTarihi` | Timestamp | Estimated completion date | `2024-03-02T17:00:00Z` |
| `durum` | String | Status: "Serviste", "Tamamlandı", "İptal" | `"Tamamlandı"` |
| `maliyet` | Number (Double) | Service cost | `250.50` |

#### Example Document:
```json
{
  "id": "770e8400-e29b-41d4-a716-446655440002",
  "aracId": "550e8400-e29b-41d4-a716-446655440000",
  "aracPlaka": "ZH123456",
  "servisFirmaAdi": "AutoCenter Zurich",
  "servisTuru": "Oil Change",
  "aciklama": "Full synthetic oil change + filter replacement",
  "gonderilmeTarihi": "2024-03-01T08:00:00.000Z",
  "tahminiTeslimTarihi": "2024-03-02T17:00:00.000Z",
  "durum": "Tamamlandı",
  "maliyet": 250.50
}
```

---

### 4. **`servisFirmalari`** Collection (Service Companies)
Stores service company/vendor information.

#### Document ID: `{firmaId}` (UUID)

#### Fields:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `id` | String (UUID) | Unique company ID | `"880e8400-e29b-41d4-a716-446655440003"` |
| `ad` | String | Company name | `"AutoCenter Zurich"` |
| `telefon` | String | Phone number | `"+41 44 123 4567"` |
| `adres` | String | Company address | `"Bahnhofstrasse 1, 8001 Zurich"` |
| `email` | String | Email address | `"info@autocenter.ch"` |
| `notlar` | String | Additional notes | `"Preferred partner, 10% discount"` |

#### Example Document:
```json
{
  "id": "880e8400-e29b-41d4-a716-446655440003",
  "ad": "AutoCenter Zurich",
  "telefon": "+41 44 123 4567",
  "adres": "Bahnhofstrasse 1, 8001 Zurich",
  "email": "info@autocenter.ch",
  "notlar": "Preferred partner, 10% discount available"
}
```

---

### 5. **`iadeIslemleri`** Collection (Return Operations)
Stores vehicle return/checkout operations.

#### Document ID: `{iadeId}` (UUID)

#### Fields:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `id` | String (UUID) | Unique return operation ID | `"990e8400-e29b-41d4-a716-446655440004"` |
| `aracId` | String (UUID) | Reference to vehicle ID | `"550e8400-e29b-41d4-a716-446655440000"` |
| `aracPlaka` | String | Vehicle license plate | `"ZH123456"` |
| `musteriAdi` | String | Customer name | `"Alice Johnson"` |
| `iadeTarihi` | Timestamp | Return date/time | `2024-03-15T16:30:00Z` |
| `notlar` | String | Return notes | `"Vehicle returned in good condition"` |
| `fotograflar` | Array[String] | URLs of return inspection photos | `["https://...", "https://..."]` |
| `imzaURL` | String? (optional) | Customer signature image URL | `"https://storage..."` |

#### Example Document:
```json
{
  "id": "990e8400-e29b-41d4-a716-446655440004",
  "aracId": "550e8400-e29b-41d4-a716-446655440000",
  "aracPlaka": "ZH123456",
  "musteriAdi": "Alice Johnson",
  "iadeTarihi": "2024-03-15T16:30:00.000Z",
  "notlar": "Vehicle returned in excellent condition",
  "fotograflar": [
    "https://firebasestorage.googleapis.com/return_photos/photo1.jpg",
    "https://firebasestorage.googleapis.com/return_photos/photo2.jpg"
  ],
  "imzaURL": "https://firebasestorage.googleapis.com/signatures/signature1.png"
}
```

---

### 6. **`officeOperations`** Collection (Office Operations)
Stores various office operation records (Credit Card, POS, Fuel, Washing).

#### Document ID: `{operationId}` (UUID)

#### Fields:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `id` | String (UUID) | Unique operation ID | `"aa0e8400-e29b-41d4-a716-446655440005"` |
| `type` | String | Operation type: "creditCard", "posClosing", "fuelReceipt", "washing" | `"creditCard"` |
| `amount` | Number (Double) | Transaction amount | `150.75` |
| `date` | Timestamp | Operation date/time | `2024-03-20T12:00:00Z` |
| `description` | String | Operation description/notes | `"Monthly credit card payment"` |
| `category` | String (optional) | Additional category info | `"Expense"` |

#### Example Document:
```json
{
  "id": "aa0e8400-e29b-41d4-a716-446655440005",
  "type": "creditCard",
  "amount": 150.75,
  "date": "2024-03-20T12:00:00.000Z",
  "description": "Monthly credit card payment for vehicle expenses",
  "category": "Expense"
}
```

---

### 7. **`activities`** Collection (Activity Log)
Stores user activity/action logs for audit trail.

#### Document ID: `{activityId}` (UUID)

#### Fields:
| Field Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| `id` | String (UUID) | Unique activity ID | `"bb0e8400-e29b-41d4-a716-446655440006"` |
| `tip` | String | Activity type (see ActivityType enum below) | `"Araç Eklendi"` |
| `aciklama` | String | Activity description | `"ZH 123456 - BMW 320i"` |
| `tarih` | Timestamp | Activity timestamp | `2024-03-25T10:15:00Z` |
| `aracPlaka` | String? (optional) | Related vehicle plate | `"ZH123456"` |
| `detayliAciklama` | String? (optional) | Detailed description | `"Added new vehicle to fleet"` |
| `kullaniciAdi` | String? (optional) | User who performed action | `"John Doe"` |
| `kullaniciEmail` | String? (optional) | User's email | `"john.doe@greenmotion.ch"` |

#### ActivityType Enum Values:
- `"Araç Eklendi"` - Vehicle Added
- `"Araç Silindi"` - Vehicle Deleted
- `"Hasar Eklendi"` - Damage Added
- `"Hasar Silindi"` - Damage Deleted
- `"Hasar Güncellendi"` - Damage Updated
- `"Servis Eklendi"` - Service Added
- `"İade Yapıldı"` - Return Completed

#### Example Document:
```json
{
  "id": "bb0e8400-e29b-41d4-a716-446655440006",
  "tip": "Araç Eklendi",
  "aciklama": "ZH 123456 - BMW 320i",
  "tarih": "2024-03-25T10:15:00.000Z",
  "aracPlaka": "ZH123456",
  "detayliAciklama": "New vehicle added to the fleet",
  "kullaniciAdi": "John Doe",
  "kullaniciEmail": "john.doe@greenmotion.ch"
}
```

---

## Firebase Storage Structure

### Storage Buckets & Paths:

#### 1. **`hasar_fotograflari/`**
Stores damage record photos
- Path: `hasar_fotograflari/{uuid}.jpg`
- Example: `hasar_fotograflari/abc123-def456-ghi789.jpg`

#### 2. **`kafa_kagitlari/`**
Stores vehicle head documents (registration papers)
- Path: `kafa_kagitlari/{vehiclePlate}/head_{uuid}.jpg`
- Example: `kafa_kagitlari/ZH123456/head_abc123.jpg`

#### 3. **`return_photos/`**
Stores return inspection photos
- Path: `return_photos/{uuid}.jpg`
- Example: `return_photos/xyz789-abc123.jpg`

#### 4. **`signatures/`**
Stores customer signatures
- Path: `signatures/{uuid}.png`
- Example: `signatures/sig_abc123.png`

---

## Data Naming Conventions

### Field Naming:
- **camelCase** for field names in Firestore
- **Turkish** field names in code (e.g., `aracPlaka`, `hasarKayitlari`)
- **English** for user-facing text in UI

### ID Generation:
- All IDs use **UUID** format: `"550e8400-e29b-41d4-a716-446655440000"`
- Generated using: `UUID().uuidString` in Swift

### Date Format:
- All dates stored as **Firebase Timestamp**
- Example: `2024-03-25T10:15:00.000Z`
- Converted to Swift `Date` object in app

### String Format:
- License plates: **UPPERCASE, NO SPACES** (e.g., `"ZH123456"`)
- RES codes: **"RES-" prefix + numbers** (e.g., `"RES-1234"`)
- Names: **Title Case** (e.g., `"John Doe"`)

---

## Query Examples

### 1. Get all vehicles:
```swift
Firestore.firestore().collection("araclar").getDocuments()
```

### 2. Get specific vehicle:
```swift
Firestore.firestore().collection("araclar").document(vehicleId).getDocument()
```

### 3. Get services for a vehicle:
```swift
Firestore.firestore().collection("servisKayitlari")
    .whereField("aracId", isEqualTo: vehicleId)
    .getDocuments()
```

### 4. Get recent activities:
```swift
Firestore.firestore().collection("activities")
    .order(by: "tarih", descending: true)
    .limit(to: 20)
    .getDocuments()
```

### 5. Get office operations by type:
```swift
Firestore.firestore().collection("officeOperations")
    .whereField("type", isEqualTo: "creditCard")
    .order(by: "date", descending: true)
    .getDocuments()
```

---

## Data Integrity Rules

1. **License Plates**: Must match Swiss format (2 letters + numbers)
2. **RES Codes**: Must have "RES-" prefix
3. **Damage Photos**: First photo is always HANDOVER, rest are RETURN
4. **Vehicle Categories**: Single letter A-Z
5. **Service Status**: Must be one of: "Serviste", "Tamamlandı", "İptal"
6. **Damage Status**: Must be one of: "In Progress", "Done"
7. **Office Operation Types**: Must be one of: "creditCard", "posClosing", "fuelReceipt", "washing"

---

## Backup & Export

- All data can be exported to **PDF**, **Excel (XLSX)**, or **CSV**
- Export functions available in: `ServisExportManager.swift`
- Data is automatically backed up by Firebase Firestore

---

## Security Rules (Firestore)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Authenticated users can read/write vehicles and related data
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

---

## Additional Notes

- All collections use **auto-generated** document IDs (UUID)
- Nested arrays (like `hasarKayitlari`) are stored **within** the parent document
- Photos are stored in **Firebase Storage** and referenced by URL in Firestore
- User authentication handled by **Firebase Auth**
- Real-time updates available via **Firestore listeners**

---

**Last Updated**: January 2025
**Version**: 1.0
**Author**: Green Motion AG Development Team

