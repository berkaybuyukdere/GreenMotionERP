# Wheelsys Pre-Check-In API Contract

## Endpoint
- **Method:** `POST`
- **Function:** `wheelsysPreCheckIn`
- **Purpose:** Set vehicle pre-check-in snapshot using `confirmation_no`, `fuel`, `mileage`.

## Authentication and Security

### Required
- API key:
  - Header `x-api-key: <key>`
  - or `Authorization: Bearer <key>`
- Server env:
  - `WHEELSYS_API_KEY`

### Optional (recommended)
- HMAC request signing:
  - Header `x-timestamp: <ISO date>`
  - Header `x-signature: <hex sha256 hmac>`
  - Signature payload: `<x-timestamp>.<rawBody>`
  - Server env:
    - `WHEELSYS_HMAC_SECRET`
- Replay protection window: 5 minutes.

## Request Body

```json
{
  "confirmation_no": "WS-2026-000123",
  "fuel": 0.75,
  "mileage": 45230,
  "event_time": "2026-03-25T17:30:00.000Z",
  "source_event_id": "wheels-evt-9b34",
  "customer_name": "John Doe"
}
```

### Field rules
- `confirmation_no`: required, string, normalized to uppercase.
- `fuel`: required.
  - accepted: `0..1` or `0..100`
  - internally normalized to `0..1`.
- `mileage`: required, non-negative integer.
- `event_time`: optional ISO timestamp; defaults to server time.
- `source_event_id`: optional but strongly recommended for idempotency.

## Resolution Logic

Deterministic lookup order:
1. `exitIslemleri.resKodu == confirmation_no`
2. `protocols.reservationNumber == confirmation_no`

If no match: `404 reservation_not_found`  
If multiple conflicting vehicle matches: `409 ambiguous_match`

## Write Behavior

Target document: matched `araclar/{vehicleId}`  
Mode: merge update (non-destructive)

Appends one row to `checkInKayitlari` (iOS canonical list) and updates `lastCheckIn` for backward compatibility.

`checkInKayitlari` row (aligns with `LastCheckInSnapshot`):
- `id`, `timestamp`, `km`, `fuelEighths` (0–8), `fuelLevel`, `fuelTankFull`, `reservationNumber`, `checkedInBy` (`wheelsys_api`), optional `customerName`, `linkedExitId` (null)

`lastCheckIn` payload (legacy + integration metadata):
- `timestamp` (Firestore Timestamp)
- `km` (int)
- `fuelLevel` (double, 0..1)
- `reservationNumber` (`confirmation_no`)
- `checkedInBy` (`wheelsys_api`)
- `customerName` (optional)
- `sourceEventId` (optional)
- `source` (`wheelsys`)
- `updatedAt` (server timestamp)

Also writes activity log entry in `activities`.

## Idempotency

- Lock collection: `_functionLocks`
- Lock key source:
  - `source_event_id` if present
  - fallback: `confirmation_no|mileage|fuel|event_time`
- Duplicate payload behavior: `202 already_processed`

## Response Codes

- `200`: updated
- `202`: already processed (idempotent duplicate)
- `401`: unauthorized / invalid signature
- `404`: reservation not found
- `409`: ambiguous match
- `422`: validation error
- `500`: integration misconfiguration (e.g. missing API key env)

## Success Response Example

```json
{
  "status": "updated",
  "confirmation_no": "WS-2026-000123",
  "vehicle_id": "A1B2C3D4-E5F6-7788-9900-AABBCCDDEEFF",
  "source": "exitIslemleri.resKodu",
  "franchise_id": "CH",
  "fuel_level": 0.75,
  "mileage": 45230
}
```
