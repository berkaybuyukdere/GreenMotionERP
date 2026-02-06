# WheelSys Integration Documentation
## AracHasarKayit - Database & API Specification

**Version:** 1.0  
**Date:** February 2026  
**Database:** Firebase Firestore + Firebase Storage

---

## 1. Araclar (Vehicles)

```
Collection: araclar
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "plaka": "String",
  "marka": "String",
  "model": "String",
  "kategori": "String",
  "vignetteVar": "Boolean",
  "kayitTarihi": "Timestamp",
  "qrCode": "String",
  "spareKeyCount": "Integer",
  "headDocumentURL": "String?",
  "createdBy": "String?",
  "assistantCompanyName": "String?",
  "assistantCompanyPhone": "String?",
  "hasarKayitlari": "[HasarKaydi] - nested array"
}
```

---

## 2. HasarKayitlari (Damage Records)

```
Nested inside: araclar.hasarKayitlari[]
```

```json
{
  "id": "UUID string",
  "aracId": "UUID string",
  "aracPlaka": "String",
  "tarih": "Timestamp",
  "handoverTarihi": "Timestamp",
  "resKodu": "String",
  "km": "Integer",
  "fotograflar": "[String] - photo URLs",
  "durum": "String - 'In Progress' | 'Done'",
  "notlar": "String",
  "status": "String - 'In Progress' | 'Completed'",
  "createdBy": "String?"
}
```

```
Photo Storage: hasar_fotograflari/{handover|return}/{UUID}.jpg
```

---

## 3. IadeIslemleri (Return Operations)

```
Collection: iadeIslemleri
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "aracId": "UUID string",
  "aracPlaka": "String",
  "iadeTarihi": "Timestamp",
  "fotograflar": "[String] - photo URLs",
  "notlar": "String",
  "status": "String - 'In Progress' | 'Completed'",
  "createdBy": "String?"
}
```

```
Photo Storage: iade_fotograflari/{UUID}.jpg
```

---

## 4. ExitIslemleri (Check-Out Operations)

```
Collection: exitIslemleri
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "aracId": "UUID string",
  "aracPlaka": "String",
  "exitTarihi": "Timestamp",
  "createdAt": "Timestamp",
  "fotograflar": "[String] - photo URLs",
  "notlar": "String",
  "resKodu": "String",
  "status": "String - 'In Progress' | 'Completed'",
  "createdBy": "String?",
  "assistantCompanyName": "String?",
  "assistantCompanyPhone": "String?"
}
```

```
Photo Storage: exit_fotograflari/{UUID}.jpg
```

---

## 5. Servisler (Service Records)

```
Collection: servisler
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "aracId": "UUID string",
  "servisTuru": "String",
  "aciklama": "String",
  "tarih": "Timestamp",
  "ucret": "Double",
  "teslimTarihi": "Timestamp?",
  "servisNedenleri": "[String]",
  "durum": "String - 'Serviste' | 'Tamamlandı' | 'İptal'"
}
```

---

## 6. Office Operations

```
Collection: office_operations
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "documentId": "String?",
  "type": "String - creditCard | posClosing | fuelReceipt | washing | additionalSales | banking | trafficFine",
  "date": "Number (TimeInterval since 2001-01-01)",
  "amount": "Double",
  "photos": "[String] - photo URLs",
  "vehiclePlate": "String?",
  "notes": "String",
  "isCompleted": "Boolean",
  "createdBy": "String?",
  "posCount": "Integer?",
  "posAmounts": "[Double]?",
  "fineNumber": "String?",
  "fineType": "String?",
  "paymentStatus": "String?",
  "transactionNumber": "String?",
  "bankName": "String?",
  "accountNumber": "String?",
  "transactionType": "String?",
  "referenceNumber": "String?",
  "productName": "String?",
  "quantity": "Double?",
  "unitPrice": "Double?",
  "customerName": "String?",
  "invoiceNumber": "String?"
}
```

```
Photo Storage: office_operations/{UUID}.jpg
```

---

## 7. Office Returns

```
Collection: office_Return
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "amount": "Double",
  "reason": "String - vehicleReturn | cancellation | refund | damageClaim | other",
  "date": "Timestamp",
  "photos": "[String] - photo URLs",
  "notes": "String"
}
```

```
Photo Storage: office_Return/{UUID}.jpg
```

---

## 8. Protocols (Rental Agreements)

```
Collection: protocols
Document ID: String (protocolId)
```

```json
{
  "baseCost": "String",
  "checkInDate": "String - ISO8601",
  "checkOutDate": "String - ISO8601",
  "createdAt": "String - ISO8601",
  "createdBy": "String",
  "customerName": "String",
  "fieldValues": "String - JSON",
  "protocolId": "String",
  "protocolName": "String",
  "protocolType": "String",
  "reservationNumber": "String",
  "status": "String - DRAFT | PENDING | COMPLETE | OVERDUE | CANCELLED",
  "templatePath": "String",
  "updatedAt": "String - ISO8601",
  "updatedBy": "String",
  "vehiclePlate": "String"
}
```

---

## 9. ShuttleEntries

```
Collection: shuttleEntries
Document ID: Auto-generated
```

```json
{
  "id": "String?",
  "customerCount": "Integer",
  "entryType": "String - pickup | dropoff",
  "timestamp": "Timestamp",
  "driverName": "String",
  "driverUID": "String",
  "sessionId": "String"
}
```

---

## 10. ShuttleSessions

```
Collection: shuttleSessions
Document ID: Auto-generated
```

```json
{
  "id": "String?",
  "date": "Timestamp",
  "driverName": "String",
  "driverUID": "String",
  "entries": "[ShuttleEntry]",
  "totalCustomers": "Integer",
  "isActive": "Boolean",
  "startTime": "Timestamp",
  "endTime": "Timestamp?"
}
```

---

## 11. WorkSchedules (Timetable)

```
Collection: workSchedules
Document ID: {userId}_{weekStartTimestamp}
```

```json
{
  "id": "String?",
  "userId": "String",
  "userName": "String",
  "weekStartDate": "Timestamp",
  "weeklyHours": "Double",
  "vacationDays": "Integer",
  "createdAt": "Timestamp",
  "updatedAt": "Timestamp",
  "schedules": [
    {
      "dayOfWeek": "Integer - 1-7",
      "startTime": "String - HH:mm",
      "endTime": "String - HH:mm",
      "isVacation": "Boolean",
      "shiftType": "String - morning | afternoon | evening | fullDay"
    }
  ]
}
```

---

## 12. VacationTimes

```
Collection: vacationTimes
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "documentId": "String?",
  "employeeName": "String",
  "startDate": "Number (TimeInterval since 2001-01-01)",
  "endDate": "Number (TimeInterval since 2001-01-01)",
  "isActive": "Boolean",
  "createdBy": "String",
  "createdAt": "Number (TimeInterval since 2001-01-01)"
}
```

---

## 13. Activities (Audit Log)

```
Collection: activities
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "tip": "String - aracEklendi | aracSilindi | hasarEklendi | hasarSilindi | hasarGuncellendi | servisEklendi | iadeYapildi | shuttlePickup | officeOperation | officeOperationSilindi",
  "aciklama": "String",
  "tarih": "Timestamp",
  "aracPlaka": "String?",
  "detayliAciklama": "String?",
  "kullaniciAdi": "String?",
  "kullaniciEmail": "String?",
  "officeOperationId": "UUID string?"
}
```

---

## 14. ServisFirmalari (Service Companies)

```
Collection: servisFirmalari
Document ID: UUID string
```

```json
{
  "id": "UUID string",
  "ad": "String",
  "telefon": "String",
  "adres": "String",
  "email": "String",
  "notlar": "String",
  "kayitTarihi": "Timestamp"
}
```

---

## 15. AssistantCompanies

```
Collection: assistantCompanies
Document ID: UUID string (lowercase)
```

```json
{
  "id": "UUID string",
  "name": "String",
  "phoneNumber": "String",
  "createdAt": "Timestamp",
  "createdBy": "String?"
}
```

---

## 16. Users

```
Collection: users
Document ID: Firebase UID
```

```json
{
  "uid": "String",
  "email": "String",
  "firstName": "String",
  "lastName": "String",
  "createdAt": "Timestamp"
}
```

---

## Date/Timestamp Formats

```
Type 1: Firestore Timestamp
Used by: Arac, HasarKaydi, IadeIslemi, ExitIslemi, Activity, ShuttleEntry, WorkSchedule
Format: { "_seconds": 1706745600, "_nanoseconds": 0 }

Type 2: TimeInterval since 2001-01-01
Used by: OfficeOperation, VacationTime
Base: 2001-01-01 00:00:00 UTC (timeIntervalSince1970: 978307200)

Type 3: ISO8601 String
Used by: Protocol
Format: "2024-01-15T10:30:00.000Z"
```

---

## Photo URL Format

```
Format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encodedPath}?alt=media&token={accessToken}
Image: JPEG, Quality 0.95, Max 2400px, Max 10MB
```

---

## Data Relationships

```
Arac.id ← HasarKaydi.aracId (nested in hasarKayitlari array)
Arac.id ← IadeIslemi.aracId
Arac.id ← ExitIslemi.aracId
Arac.id ← Servis.aracId
Arac.plaka ← OfficeOperation.vehiclePlate
Arac.plaka ← Protocol.vehiclePlate
ShuttleSession.id ← ShuttleEntry.sessionId
ServisFirma.id ← Servis.servisFirmaId
```

---

# WheelSys Integration Requirements

## Integration Flow

```
1. User scans plate in our app
2. Vehicle detail screen (AracDetayView) opens
3. User completes Return (İade) process
4. User presses "Check-In" button in vehicle detail screen
5. Check-In form opens: KM and Fuel input fields
6. User enters KM and Fuel level
7. Data saved to Firestore (araclar collection)
8. WheelSys reads updated KM and Fuel from our database
9. Last customer info updated in check-in record
```

## New Check-In Feature in Our App

### Check-In Button Location
```
AracDetayView (Vehicle Detail Screen)
  └── Check-In Button
        └── Opens Check-In Form
              ├── KM Input (Integer)
              ├── Fuel Level Input (Double 0-100%)
              └── Save Button
```

### New Field in Araclar Collection

```json
// Will be added to araclar collection
{
  "lastCheckIn": {
    "timestamp": "Timestamp",
    "km": "Integer - odometer reading",
    "fuelLevel": "Double - 0.0 to 1.0 (percentage)",
    "customerName": "String? - last customer name",
    "reservationNumber": "String? - last reservation",
    "checkedInBy": "String - user ID who performed check-in"
  }
}
```

## What We Need From WheelSys

### 1. Read Access to Our Check-In Data

WheelSys should read from our Firestore:

```
Collection: araclar
Field: lastCheckIn

Data available:
- lastCheckIn.km (Integer)
- lastCheckIn.fuelLevel (Double)
- lastCheckIn.timestamp (Timestamp)
- lastCheckIn.customerName (String?)
- lastCheckIn.reservationNumber (String?)
```

### 2. Option A: Direct Firestore Access

```
We provide: Firebase Service Account credentials
WheelSys reads: araclar collection, lastCheckIn field
```

### 3. Option B: Webhook Notification

When check-in is completed, our app sends webhook to WheelSys:

```
POST {wheelsys-webhook-url}
Content-Type: application/json

{
  "event": "check_in_completed",
  "vehiclePlate": "ZH123456",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "data": {
    "km": 45230,
    "fuelLevel": 0.75,
    "customerName": "John Doe",
    "reservationNumber": "WS-2024-001234"
  }
}
```

### 4. Option C: API Endpoint

We create REST API endpoint for WheelSys to query:

```
GET /api/vehicle/{plate}/checkin

Response:
{
  "vehiclePlate": "ZH123456",
  "lastCheckIn": {
    "timestamp": "2024-01-15T10:30:00.000Z",
    "km": 45230,
    "fuelLevel": 0.75,
    "customerName": "John Doe",
    "reservationNumber": "WS-2024-001234"
  }
}
```

## What We Need From WheelSys

### Customer Info for Check-In (Optional)

If WheelSys can provide last customer info when we perform check-in:

```
GET {wheelsys-api}/vehicle/{plate}/last-customer

Response:
{
  "customerName": "String",
  "customerEmail": "String?",
  "reservationNumber": "String"
}
```

This will auto-fill customer info in our check-in form.

## What We Provide to WheelSys

```
Available data in Firestore:
- Vehicle list (araclar)
- Damage history (hasarKayitlari - nested)
- Return operations (iadeIslemleri)
- Check-out operations (exitIslemleri)
- Check-in data (araclar.lastCheckIn) ← NEW
- Damage photos (Firebase Storage URLs)
```

---

## Authentication

```
Firebase Auth: Email/Password
Firestore: Authenticated users only
Storage: Authenticated users only, max 10MB per file
```

---

## Contact

For API key and service account access, contact development team.
