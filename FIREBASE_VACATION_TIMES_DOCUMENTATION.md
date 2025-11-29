# Firebase Data Documentation - Vacation Times

## Overview
This document describes the Firebase data structure for the Vacation Times feature added to the Office Operations section.

## New Collection: `vacationTimes`

### Collection Path
```
/vacationTimes/{documentId}
```

### Document Structure
```json
{
  "id": "uuid-string",
  "documentId": "firebase-document-id",
  "employeeName": "string",
  "startDate": 1234567890.0,
  "endDate": 1234567890.0,
  "isActive": true,
  "createdBy": "user-email@example.com",
  "createdAt": 1234567890.0
}
```

### Field Descriptions

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String (UUID) | Unique identifier for the vacation time record | Yes |
| `documentId` | String | Firebase document ID (for web compatibility) | Optional |
| `employeeName` | String | Name of the employee on vacation | Yes |
| `startDate` | Number (TimeInterval) | Start date of vacation (seconds since 2001-01-01) | Yes |
| `endDate` | Number (TimeInterval) | End date of vacation (seconds since 2001-01-01) | Yes |
| `isActive` | Boolean | Whether the vacation is currently active | Yes (default: true) |
| `createdBy` | String | Email of the user who created the record | Yes |
| `createdAt` | Number (TimeInterval) | Creation timestamp (seconds since 2001-01-01) | Yes |

### Date Format
- Dates are stored as **TimeInterval** (Double) representing seconds since 2001-01-01 00:00:00 UTC
- This format is compatible with both iOS and web applications
- Example: `978307200.0` = 2001-01-01 00:00:00 UTC

### Access Control
- **Read**: All authenticated users can view vacation times
- **Write**: Only users with email containing "yasemin" or specific Yasemin emails can create/edit/delete

### Web Application Integration

For web application compatibility, use the following structure:

```javascript
// Create vacation time
const vacationTime = {
  id: uuidv4(),
  documentId: doc.id, // Firebase document ID
  employeeName: "John Doe",
  startDate: getTimeInterval(date), // Convert to TimeInterval format
  endDate: getTimeInterval(date),
  isActive: true,
  createdBy: currentUser.email,
  createdAt: getTimeInterval(new Date())
};

// Helper function to convert Date to TimeInterval
function getTimeInterval(date) {
  const baseDate = new Date('2001-01-01T00:00:00Z');
  return (date.getTime() - baseDate.getTime()) / 1000;
}

// Helper function to convert TimeInterval to Date
function getDateFromTimeInterval(timeInterval) {
  const baseDate = new Date('2001-01-01T00:00:00Z');
  return new Date(baseDate.getTime() + timeInterval * 1000);
}
```

## Existing Collections (No Changes)

### `office_operations`
- **No structural changes**
- Additional Sales and Traffic Fine cards now show enhanced metrics
- Data structure remains the same

### All Other Collections
- No changes to existing data structures
- Only display logic updates in the application

## Query Examples

### Get all active vacation times
```javascript
db.collection('vacationTimes')
  .where('isActive', '==', true)
  .get()
```

### Get vacation times for a specific employee
```javascript
db.collection('vacationTimes')
  .where('employeeName', '==', 'John Doe')
  .where('isActive', '==', true)
  .get()
```

### Get vacation times for a date range
```javascript
const startTimeInterval = getTimeInterval(startDate);
const endTimeInterval = getTimeInterval(endDate);

db.collection('vacationTimes')
  .where('startDate', '<=', endTimeInterval)
  .where('endDate', '>=', startTimeInterval)
  .where('isActive', '==', true)
  .get()
```

## Firestore Security Rules

Recommended security rules for `vacationTimes` collection:

```javascript
match /vacationTimes/{documentId} {
  // Allow read for all authenticated users
  allow read: if request.auth != null;
  
  // Allow write only for Yasemin
  allow create, update, delete: if request.auth != null 
    && (request.auth.token.email.matches('.*yasemin.*') 
        || request.auth.token.email == 'yasemin@greenmotion.com'
        || request.auth.token.email == 'yasemin@wheelsys.com');
}
```

## Notes

1. **Date Format Compatibility**: The TimeInterval format (seconds since 2001-01-01) is used for compatibility between iOS and web applications.

2. **Employee Names**: Employee names are stored as plain strings. Consider normalizing names for consistency.

3. **Active Status**: The `isActive` field allows soft deletion - set to `false` instead of deleting the document.

4. **Created By**: The `createdBy` field tracks who created the vacation time record for audit purposes.

5. **Real-time Updates**: The collection supports real-time listeners for live updates across all clients.

