# Assistant Company System Documentation

## Overview

The Assistant Company system allows users to manage company records with names and phone numbers, and associate them with check-out operations. This feature enables tracking of assistant companies for vehicle check-out processes.

## Firebase Data Structure

### Collection: `assistantCompanies`

Each document in the `assistantCompanies` collection has the following structure:

```json
{
  "id": "UUID",
  "name": "Company Name",
  "phoneNumber": "+41 XX XXX XX XX",
  "createdAt": "Timestamp",
  "createdBy": "User ID (optional)"
}
```

### Collection: `exitIslemleri` (Updated)

The `exitIslemleri` collection now includes assistant company information:

```json
{
  "id": "UUID",
  "aracId": "UUID",
  "aracPlaka": "Vehicle Plate",
  "exitTarihi": "Timestamp",
  "createdAt": "Timestamp",
  "fotograflar": ["URL1", "URL2", ...],
  "notlar": "Notes",
  "resKodu": "RES-XXXX",
  "status": "In Progress" | "Completed",
  "createdBy": "User ID (optional)",
  "assistantCompanyName": "Company Name (optional)",
  "assistantCompanyPhone": "+41 XX XXX XX XX (optional)"
}
```

## Phone Number Format

### Swiss Phone Number Format

The system supports two Swiss phone number formats:

1. **International Format**: `+41 XX XXX XX XX`
   - Starts with `+41`
   - Followed by 9 digits
   - Example: `+41 79 123 45 67`

2. **National Format**: `0XX XXX XX XX`
   - Starts with `0`
   - Followed by 9 digits (total 10 digits)
   - Example: `079 123 45 67`

### Validation

The `AssistantCompany.isValidSwissPhoneNumber(_:)` method validates phone numbers:
- Removes spaces, dashes, and parentheses
- Checks for `+41` prefix (9 digits after)
- Checks for `0` prefix (10 digits total)
- Ensures all characters are numbers

### Formatting

The `AssistantCompany.formatSwissPhoneNumber(_:)` method automatically formats phone numbers:
- Converts input to proper Swiss format
- Adds spaces for readability
- Handles both international and national formats

## Data Models

### AssistantCompany

```swift
struct AssistantCompany: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var phoneNumber: String
    var createdAt: Date
    var createdBy: String?
}
```

### ExitIslemi (Updated)

```swift
struct ExitIslemi: Identifiable, Codable {
    // ... existing fields ...
    var assistantCompanyName: String?
    var assistantCompanyPhone: String?
}
```

## Firebase Service Methods

### Load Assistant Companies

```swift
func loadAssistantCompanies(completion: @escaping ([AssistantCompany]?, Error?) -> Void)
```

Loads all assistant companies from Firebase, ordered by name.

### Save Assistant Company

```swift
func saveAssistantCompany(_ company: AssistantCompany, completion: @escaping (Error?) -> Void)
```

Saves or updates an assistant company in Firebase.

### Delete Assistant Company

```swift
func deleteAssistantCompany(_ company: AssistantCompany, completion: @escaping (Error?) -> Void)
```

Deletes an assistant company from Firebase.

### Observe Assistant Companies

```swift
func observeAssistantCompanies(completion: @escaping ([AssistantCompany]?, Error?) -> Void) -> ListenerRegistration?
```

Sets up a real-time listener for assistant companies. Returns a `ListenerRegistration` for cleanup.

## ViewModel Methods

### Load Assistant Companies

```swift
func assistantCompaniesYukle()
```

Loads assistant companies from Firebase and updates the `@Published var assistantCompanies` array.

### Add Assistant Company

```swift
func assistantCompanyEkle(_ company: AssistantCompany)
```

Adds a new assistant company to the local array and saves it to Firebase.

### Update Assistant Company

```swift
func assistantCompanyGuncelle(_ company: AssistantCompany)
```

Updates an existing assistant company in the local array and Firebase.

### Delete Assistant Company

```swift
func assistantCompanySil(_ company: AssistantCompany)
```

Removes an assistant company from the local array and deletes it from Firebase.

## User Interface

### Assistant Number View

Located at: `AracHasarKayit/Views/AssistantNumberView.swift`

Features:
- List of all assistant companies
- Add new company button
- Edit existing companies
- Delete companies with confirmation
- Phone number validation

### Company Picker View

Located at: `AracHasarKayit/Views/CompanyPickerView.swift`

Features:
- Scrollable list of companies
- Select company for check-out operation
- Shows company name and phone number
- Visual indicator for selected company

### Exit Islem View (Updated)

Located at: `AracHasarKayit/Views/ExitIslemView.swift`

New Features:
- Assistant Company selection section
- Shows selected company name and phone number
- Remove company option
- Automatically saves company info with check-out record

## Usage Flow

### 1. Adding a Company

1. Navigate to **Reports** → **Assistant Numbers**
2. Tap **"Add New Company"**
3. Enter company name
4. Enter phone number (Swiss format)
5. Tap **"Save"**

### 2. Selecting Company for Check-Out

1. Open a vehicle's detail page
2. Tap **"CHECK OUT"**
3. In the **"Assistant Company"** section, tap **"Select Company"**
4. Choose a company from the list
5. Company name and phone number will be displayed
6. Complete the check-out process

### 3. Viewing Company in Reports

1. Navigate to **Reports** → **Check Out Reports**
2. Open a check-out record
3. View assistant company information if associated

## Firebase Rules

### Firestore Rules

Add the following rules to `firestore.rules`:

```javascript
match /assistantCompanies/{companyId} {
  allow read: if request.auth != null;
  allow create: if request.auth != null;
  allow update: if request.auth != null;
  allow delete: if request.auth != null;
}
```

### Storage Rules

No storage rules needed for assistant companies (no file uploads).

## Migration Notes

### Existing Exit Operations

Existing exit operations in Firebase will have `null` values for:
- `assistantCompanyName`
- `assistantCompanyPhone`

These fields are optional, so existing data remains valid.

### Backward Compatibility

The `ExitIslemi` model uses optional fields for assistant company information, ensuring backward compatibility with existing check-out records.

## Search Functionality

### Check-Out Reports Search

The search functionality in Check-Out Reports now includes:
- Vehicle plate number
- Notes
- **RES codes** (newly added)

Users can search for check-out operations by entering RES codes in the search field.

## Best Practices

1. **Phone Number Format**: Always use Swiss phone number format when entering phone numbers
2. **Company Names**: Use clear, descriptive company names
3. **Data Cleanup**: Regularly review and remove unused companies
4. **Validation**: Always validate phone numbers before saving

## Error Handling

The system includes comprehensive error handling:
- Phone number format validation
- Firebase connection errors
- User feedback via toast messages
- Error logging via LogManager

## Real-Time Updates

Assistant companies are synchronized in real-time across all devices using Firebase listeners. Changes made on one device are immediately reflected on all other devices.

## Security

- All operations require authentication
- Users can only access assistant companies if logged in
- Company data is stored securely in Firebase Firestore

