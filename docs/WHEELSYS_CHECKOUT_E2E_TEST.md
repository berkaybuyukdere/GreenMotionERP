# WheelSys CH Checkout — End-to-End Test Plan

Reference booking (observed in WheelSys):

| Field | Value |
|-------|-------|
| Booking `entityId` | `19686` |
| RES | `RES-17646` |
| IRN | `8371385` |
| Booked group | `T` |
| Station from/to | `ZRH` |
| Date from | `2026-06-17 10:30` |
| Date to | `2026-06-21 17:30` |
| Example vehicle | `ZG59687` (car id `414`, Clio E-TECH, model id `92`) |

---

## 0. Prerequisites

1. **Firebase project** `greenmotionapp-33413`, region `europe-west6`.
2. **WheelSys session** stored at `franchises/CH/wheelsysSessions/ZRH` (encrypted).
   ```bash
   cd functions
   WHEELSYS_API_KEY='…' \
   WHEELSYS_SESSION_COOKIE='__Secure-SID=…; .wheelsys=…' \
   npm run seed:wheelsys-session
   ```
3. **CH staff user** signed into iOS (franchise `CH*`, `wheelsysUserId` on profile optional for assignment).
4. **Functions deployed** (use deploy script if default `firebase deploy` times out):
   ```bash
   ./scripts/deploy_wheelsys_checkout_functions.sh
   ```
5. **Test vehicle** in app fleet with plate matching a real WheelSys car (e.g. `ZG59687`) and known group `T`.

---

## 1. Journal picker (iOS)

| Step | Action | Expected |
|------|--------|----------|
| 1.1 | Open vehicle detail → **CHECK OUT** (CH, not parked reopen) | `WheelSysCheckoutJournalPickerView` opens |
| 1.2 | Confirm date = **today** (Zurich) | Checkout column lists today's departures |
| 1.3 | Compare with WheelSys web journal for same date | Same count/order roughly (fleet chart source) |
| 1.4 | Find unassigned rows (no plate, group X/S/GG/T) | Orange **No car** badge, empty plate `—` |
| 1.5 | Rows matching vehicle group `T` | **Purple** background highlight |
| 1.6 | **Double-tap** a `T` checkout row for `RES-17646` / entity `19686` | Journal closes → `ExitIslemView` opens |
| 1.7 | Check prefill | RES digits `17646`, customer name if enriched, exit time from row |

---

## 2. Checkout form (iOS)

| Step | Action | Expected |
|------|--------|----------|
| 2.1 | Enter km (e.g. `23707`) and fuel `8/8` | Local fields only; not prefilled from WheelSys |
| 2.2 | Take ≥1 photo | Required for complete |
| 2.3 | Tap **Complete** | Progress overlay appears |
| 2.4 | Watch overlay microcopy | `Validating…` → `Recalculating…` → `Saving booking…` |
| 2.5 | On success | `WheelSys booking updated` (or completes even if WheelSys warns) |
| 2.6 | Exit saved in Firestore | `franchises/CH/exitIslemleri/{id}` with `resKodu: RES-17646` |

---

## 3. Backend pipeline (automatic on Complete)

Callable: `wheelsysAssignVehicleToBooking` (`europe-west6`)

1. `GET booking.aspx?entityId=19686` — read form + `cacheKey`
2. `POST …/car/canusecar` — `IsUsable === true`
3. `POST …/rental.aspx/CalcRates` — `Success === true`, updated charges
4. `POST booking.aspx` full form — response contains `wheels.afterSave({"success":true,…})`
5. Firestore exit doc gets `wheelsysSyncStatus: success` (via `writeWheelSysSyncStatus`)

---

## 4. WheelSys verification (web)

After successful iOS complete:

1. Open `booking.aspx?entityId=19686` (or converted rental if status changed).
2. Confirm **Plate** = test vehicle plate (e.g. `ZG59687`).
3. Confirm **Car id** = `414`, model Clio E-TECH.
4. Confirm **Check-out km / fuel** match app entry.
5. Refresh WheelSys journal for checkout day — row shows assigned plate.

---

## 5. Failure scenarios

| Case | Trigger | Expected app behaviour |
|------|---------|----------------------|
| Session expired | Invalid cookie | Callable error; overlay shows failure message; **exit still saved** locally |
| `canUseCar` false | Wrong dates / conflict | Warning text; exit saved; no booking change |
| No booking selected | Skip journal (parked reopen) | No WheelSys sync on complete |
| Missing km | Complete with empty km | WheelSys sync skipped; exit saved |

---

## 6. Manual callable smoke (optional)

From a machine with Firebase Auth ID token for a CH staff user, or via iOS debug:

- `wheelsysGetJournal` — `{ franchiseId: "CH", selectedDay: "2026-06-17", station: "ZRH" }`
- `wheelsysGetBookingPreview` — `{ entityId: 19686 }` → `resNo: RES-17646`, `carGroup: T`
- `wheelsysSearchAvailableVehicles` — use dates/group from preview + `rentalId: 19686`
- `wheelsysAssignVehicleToBooking` — only on a **test** booking; includes `carId`, `plateNo`, `checkOutMileage`, `checkOutFuel`

---

## 7. Deploy troubleshooting

Default Firebase CLI discovery timeout is **10s**; this repo's `functions/index.js` is large.

```bash
export FUNCTIONS_DISCOVERY_TIMEOUT=90
export NODE_OPTIONS="--max-old-space-size=8192"
./scripts/deploy_wheelsys_checkout_functions.sh
```

Symptoms without these env vars:

- `Timeout after 10000` — increase `FUNCTIONS_DISCOVERY_TIMEOUT`
- `JavaScript heap out of memory` during deploy — increase `NODE_OPTIONS` heap

---

## 8. Sign-off checklist

- [ ] Journal shows today checkouts + returns side-by-side
- [ ] Unassigned booking rows visible (no plate)
- [ ] Group `T` row highlighted for `T` vehicle
- [ ] Double-tap fills RES + customer
- [ ] Complete assigns vehicle in WheelSys
- [ ] `wheelsysSyncStatus` on exit document
- [ ] Return flow (`IadeIslemView`) still works independently
