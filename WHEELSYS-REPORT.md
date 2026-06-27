Wheelsys / GreenMotion CH — Comprehensive Data & Operations Integration Technical Report

Target system: https://ch.wheelsys.greenmotion.com
Realtime infrastructure: https://signalrcore.wheelsys.io
Context: GreenMotion Switzerland / CH tenant panel running on Wheelsys core infrastructure
Source material: Provided HAR captures including Rental Detail & Check-in, Booking List, Fleet List, Availability, Fleet Chart, Daily View, Journal and additional Wheelsys browser traces.
Purpose: Provide a single technical reference for building an internal integration layer that reads operational data from Wheelsys and supports correct Checkout / Return / Check-in workflows inside the internal GreenMotionERP / Vehicle Operations app.

⸻

Critical Disclaimer

The endpoints documented below are not confirmed as an official public partner API. They are browser-facing internal AJAX, ASP.NET WebForms, PageMethod and REST helper endpoints used by the Wheelsys web panel.

They may change without prior notice.

For production use, the integration should be implemented through a secure internal backend service and, where possible, confirmed with Wheelsys / GreenMotion technical contacts.

This report is intended for integration with our own authorized GreenMotion CH operational data.

⸻

1. Executive Summary

The Wheelsys system exposes several useful internal data surfaces through the browser panel.

The integration must clearly separate:

1. Read-only operational data
2. Rental detail loading
3. Internal customer display
4. Vehicle identity resolution
5. Checkout workflow
6. Return / Check-in workflow
7. Stateful save operations

The most important principle is:

Daily View / Journal / Booking List / Fleet List are good for operational lists and lookups.
rental.aspx?entityId={rentalId} is the source of truth for exact rental detail, customer info, vehicle assignment, mileage/fuel fields and save operations.

For our app, customer information should be displayed internally only. The app currently needs only:

- First name
- Last name
- Full name
- Email

The best source for these fields is:

rental.aspx?entityId={rentalId}
→ driverInfoContainer["1"]

Fallback:

rdDriver_text
rdDriver_value

For write operations, especially Return / Check-in:

CalcRates success:true does not mean the rental was saved.
InvoicePrep success:true does not mean the rental was saved.
Only wheels.afterSave(...).success === true confirms that the rental was saved.

If the response contains:

Record was changed by b berkay

then the form state is stale. The app must reload the rental page, parse a fresh form state, reapply the intended changes and save again only once.

⸻

2. Recommended Architecture

2.1 Correct Architecture

The integration must be backend-driven.

iOS / Web App
    ↓
Internal Backend API
    ↓
Wheelsys Integration Service
    ↓
Wheelsys

The frontend must not directly call Wheelsys with browser cookies.

2.2 Wrong Architecture

iOS / Web App
    ↓
Direct Wheelsys calls with exposed .wheelsys / __Secure-SID cookies

This is insecure and should not be used.

2.3 Main Backend Modules

Recommended modules:

WheelsysHttpClient
WheelsysAuthSessionManager
WheelsysResponseParser
WheelsysDateFormatter
WheelsysBookingListService
WheelsysFleetListService
WheelsysDailyViewService
WheelsysJournalService
WheelsysAvailabilityService
WheelsysFleetChartService
WheelsysRentalPageService
WheelsysRentalFormParser
WheelsysCustomerMapper
WheelsysVehicleMapper
WheelsysRentalContextResolver
WheelsysCheckoutService
WheelsysCheckInService
WheelsysPdfService
WheelsysSyncLogger

⸻

3. Authentication and Session Model

The HAR files were captured from an already authenticated browser session. Therefore, the actual login process is not fully documented here.

Observed session cookies:

.wheelsys
__Secure-SID

3.1 Required Cookies

Cookie	Purpose	Required
.wheelsys	Main authenticated session ticket	Yes
__Secure-SID	Session identifier, also used by SignalR context	Yes

UI preference cookies such as dailyview-remarks, availableGroupRow, groundedGroupRow, OptanonConsent are not core authentication cookies and should not be relied upon.

3.2 Required Headers

For most AJAX/PageMethod calls:

X-Requested-With: XMLHttpRequest
Accept: application/json, text/javascript, */*; q=0.01
Origin: https://ch.wheelsys.greenmotion.com
Referer: https://ch.wheelsys.greenmotion.com/{current-page}
Cookie: .wheelsys=...; __Secure-SID=...

For JSON PageMethod calls:

Content-Type: application/json; charset=utf-8

For form-encoded helper REST calls:

Content-Type: application/x-www-form-urlencoded; charset=UTF-8

For ASP.NET WebForms postback save:

Content-Type: application/x-www-form-urlencoded; charset=utf-8
X-MicrosoftAjax: Delta=true
X-Requested-With: XMLHttpRequest

3.3 Security Rules

- Never commit session cookies.
- Never expose Wheelsys session cookies to the frontend.
- Never store raw HAR files containing real cookies in the repository.
- Store secrets only in secure backend environment variables or secret manager.
- Redact cookies, tokens and customer PII from logs.

⸻

4. Universal Response Parsing

Wheelsys responses are not fully consistent. The parser must support several shapes.

4.1 Common Shapes

Shape A — d.data is JSON string

{
  "d": {
    "__type": "Wheels.Core.WebMethodResult",
    "data": "[{\"id\":397,\"plateno\":\"ZG73869\"}]",
    "success": true,
    "message": null
  }
}

Shape B — d itself is JSON string

{
  "d": "{\"Rental\":{\"StationFrom\":\"ZRH\"},\"Success\":true}"
}

Shape C — d is already an object

{
  "d": {
    "__type": "Wheels.Entities.ProcessingResult",
    "success": true,
    "keyValue": null
  }
}

Shape D — ASP.NET WebForms partial response

1|#||4|61053|updatePanel|rentalPanel|<div>...</div>|...
wheels.afterSave({...}, false);

This is not JSON and must be parsed separately.

4.2 Universal Parser

export function parseWheelsysResponse(raw: any): any {
  if (!raw) return null;
  const d = raw.d;
  if (typeof d === "string") {
    try {
      return JSON.parse(d);
    } catch {
      return d;
    }
  }
  if (d && typeof d === "object") {
    if (typeof d.data === "string") {
      try {
        return JSON.parse(d.data);
      } catch {
        return d.data;
      }
    }
    return d;
  }
  return raw;
}

4.3 Journal Special Rule

For Journal specifically:

Always attempt to parse d.data first.
Do not reject Journal only because success is false or ambiguous.
Useful data can still exist inside d.data.

⸻

5. Date Formatting Rules

Do not use toISOString() for selected operational dates because UTC conversion can shift the local day.

5.1 Daily View / Journal Date

Correct:

export function formatLocalDateForWheelsys(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}T00:00:00.000`;
}

Example:

2026-06-19T00:00:00.000

5.2 Rental Form Date

export function formatDateDDMMYYYY(date: Date): string {
  const day = String(date.getDate()).padStart(2, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const year = date.getFullYear();
  return `${day}/${month}/${year}`;
}

Example:

19/06/2026

5.3 Rental Form Time

export function formatTimeHHmm(date: Date): string {
  const hour = String(date.getHours()).padStart(2, "0");
  const minute = String(date.getMinutes()).padStart(2, "0");
  return `${hour}:${minute}`;
}

Example:

21:42

5.4 Fleet Chart ASP.NET Date

Fleet Chart uses:

/Date(1781827200000)/

Helper:

export function toAspNetDate(date: Date): string {
  return `/Date(${date.getTime()})/`;
}

⸻

6. Core Entity Concepts

6.1 Rental Entity ID

Example:

19812
19816

Source:

bookingview.Id
dailyview.id
journal.checkOuts/checkIns.id
rental.aspx?entityId={rentalId}

This is the preferred primary key once known.

6.2 RNT Number

Example:

RNT-13243

Source:

rdDispDocno_text
displaydocno
DisplayDocNo

6.3 RES Number

Example:

RES-17745

Source:

rdResDocNo
rdResDocDisp_text
DisplayDocNo

6.4 IRN

Example:

3HL218

Source:

rdIrnDisp_text
irn
Irn

6.5 Customer / Driver ID

Example:

3630

Source:

rdDriver_value
driverInfoContainer["1"].Id

Important:

rdDriver_value = customer / driver entity ID

6.6 Vehicle / Car ID

Example:

397

Source:

rdPlateNo_value
Daily View Checkins.CarTable_Id
Daily View Available.id
Journal avCars.id
Fleet List.Id

Important:

rdPlateNo_value = vehicle / car entity ID

Do not confuse:

rdDriver_value  = customer ID
rdPlateNo_value = vehicle ID

6.7 Plate Normalization

export function normalizePlate(plate: string | null | undefined): string {
  return String(plate || "")
    .replace(/\s+/g, "")
    .replace(/\*/g, "")
    .trim()
    .toUpperCase();
}

⸻

7. Endpoint Families

7.1 General List Engine

Endpoint:

POST /ui/manage/views/mainviewex.aspx/GetData

Used for:

viewName = bookingview
viewName = vehicleview

Request

{
  "searchField": "DisplayDocNo",
  "searchValue": "",
  "viewName": "bookingview",
  "stations": "N'ZRH'",
  "status": "",
  "mongoSupport": "false",
  "dataSkip": "0",
  "dataSize": "50",
  "searchUserId": "1",
  "sortModel": "[]",
  "dateStart": "",
  "dateEnd": ""
}

Notes

Captured from `NOTE-SECTION.har` (2026-06-20, booking `entityId=19771`, RES-17797 context). WheelSys exposes user notes through `/api/usernotes/*`. The web UI sidebar loads notes on open and after save/delete.

⸻

9. User Notes API

9.1 Domains

| Domain | Value | Entity type | Example page |
|---|---|---|---|
| Rental / booking | `5` | Active booking or closed rental | `booking.aspx?entityId=…`, `rental.aspx?entityId=…` |
| Vehicle (fleet) | `1` | Fleet car master | `vehicle.aspx?entityId=…` |

Notes are **scoped to entity + domain**. To show the full picture for a return/check-out, load **both**:

1. Rental notes — `domain: 5`, `entityId: {rentalEntityId}` (booking or rental entity)
2. Vehicle notes — `domain: 1`, `entityId: {vehicleEntityId}` (fleet car id)

Merge client-side; tag each row with `source: "rental" | "vehicle"` (already done in `fetchFullRentalData` → `notes.rentalNotes` + `notes.vehicleNotes`).

9.2 List / refresh notes

```
POST /api/usernotes/GetEntityNotes
Content-Type: application/json; charset=utf-8
Cookie: .wheelsys=…
```

Request (HAR — booking entity 19771):

```json
{
  "userId": 12,
  "domain": 5,
  "entityId": "19771"
}
```

Alternative (legacy, no userId):

```json
{
  "entityKey": "19771",
  "domain": "5"
}
```

Response shape:

```json
{
  "UnreadCount": 0,
  "entities": [
    {
      "Id": 30412,
      "KeyValue": 30412,
      "Domain": 5,
      "DatePosted": "2026-06-20T18:08:47",
      "ReferenceEntity_Id": "19771",
      "UserTable_Id": 6,
      "Creator": "A Irina",
      "Text": "…",
      "Recipient_UserTable_Id": null,
      "Recipient": "",
      "RecipientEmail": null,
      "Email": false,
      "IsRead": true,
      "Uid": null
    }
  ]
}
```

**Refresh:** Re-post the same `GetEntityNotes` body after save/delete or when the user taps refresh in the notes sidebar.

**Parser note:** Response array key is `entities` (not `notes`). Backend normalizer must include `data.entities`.

9.3 Add note

```
POST /api/usernotes/savenote
```

Request (HAR):

```json
{
  "createdAt": "2026-06-20T21:37:17.946Z",
  "cacheKey": null,
  "entityKey": "19771",
  "domain": "5",
  "creatorId": 12,
  "creatorFullName": "MEHMET20",
  "noteText": "test",
  "email": false,
  "notificationRecipientId": null,
  "notificationRecipientFullName": null,
  "notify": false
}
```

Response: single note object (same fields as list item). `Id` is the note id used for delete.

9.4 Delete note

```
POST /api/usernotes/deletenote
```

Request (HAR — confirmed working):

```json
{
  "NoteId": 30416,
  "RecipientId": "0",
  "isRead": true
}
```

Response: `1` (plain integer success).

**Do not** send `entityKey`/`domain` for delete — WheelSys expects `NoteId` only.

9.5 Viewing notes from other reservations / entities

WheelSys web shows notes **only for the entity currently open**. There is no cross-reservation feed in one call.

To replicate full ops context in the app:

| Need | Action |
|---|---|
| Current booking notes | `GetEntityNotes` domain `5`, rental/booking `entityId` |
| Linked vehicle history | `GetEntityNotes` domain `1`, fleet `vehicleEntityId` |
| Notes on a *different* closed rental for same plate | Resolve that rental’s `entityId` (booking list / rental search), then `GetEntityNotes` domain `5` with that id |
| After vehicle reassignment | Always resolve entity by **current RES** (booking list), not stale fleet `rentalEntityId` from a prior closed rental |

Implementation: `fetchFullRentalData` loads rental + vehicle notes. Return flow sidebar should display merged list with `source` badge. Optional future: lazy-load notes for prior rental entity ids found in fleet chart history.

9.6 Callable mapping (Firebase)

| Callable | WheelSys endpoint |
|---|---|
| `wheelsysGetRentalPreview` | Includes `rentalNotes` + `vehicleNotes` via `fetchFullRentalData` |
| `wheelsysSaveNote` | `savenote` |
| `wheelsysDeleteNote` | `deletenote` (`NoteId` payload) |
| `wheelsysGetEntityNotes` (if exposed) | `GetEntityNotes` |

⸻

8. Booking List Integration

The HAR indicated that `dataSize` and `dataSkip` may not be enforced server-side. In one observed case, a request with `dataSize: "50"` still returned thousands of records.

Therefore:

- Do not rely on `dataSize`/`dataSkip` for real pagination.
- Use `dateStart`/`dateEnd`/`status`/`searchValue` filters whenever possible.

8.1 Endpoint

POST /ui/manage/views/mainviewex.aspx/GetData
viewName = bookingview

8.2 Purpose

Use Booking List for broad rental/reservation search:

- RNT number
- RES number
- IRN
- Voucher number
- Confirmation number
- Plate number
- Date range

Do not use Booking List as the final source for Checkout/Return save operations.

Use Booking List to resolve rentalId, then open:

/ui/manage/master/rental.aspx?entityId={rentalId}

8.3 Important Fields

Id
SStr
DisplayDocNo
Plateno
irn
VoucherNo
ConfirmationNo
DateFrom
DateTo
StationFrom
StationTo
CarModel
CarGroup
CarGroupInv
Driver_Name
DriverFirstName
DriverLastName
DriverEmail
DriverPhone
Driver_Id
Agent_Name
Source_Name
ChargeTotal
CurrencyCode
ResDocNo

8.4 Search Strategy

export async function findBookingByDocumentNo(docNo: string) {
  const searchFields = [
    "DisplayDocNo",
    "ReservationNo",
    "RaDocNo",
    "IRN",
    "VoucherNo",
    "ConfirmationNo"
  ];
  for (const field of searchFields) {
    const rows = await searchBookingView({
      searchField: field,
      searchValue: docNo
    });
    if (rows.length > 0) {
      return rows[0];
    }
  }
  return null;
}

⸻

9. Fleet List Integration

9.1 Endpoint

POST /ui/manage/views/mainviewex.aspx/GetData
viewName = vehicleview

9.2 Purpose

Use Fleet List for:

- master vehicle list
- plate-to-carId fallback
- VIN
- model
- ownership
- station
- general vehicle status

Do not use Fleet List as the only operational source for daily Checkout/Return data.

9.3 Important Fields

Id
Plateno
CarStatus
Codeid
Ownership
CarGroup
Model_Name
ModelYear
Mileage
Station
Vin
Fuel
InsuranceExpiry
MOTExpiry
RoadTaxExpiry
HasAttachments

⸻

10. Daily View Integration

10.1 Base Path

/ui/dashboards/dailyview.aspx/

10.2 Common Request Body

{
  "SelectedDate": "2026-06-19T00:00:00.000",
  "SelectedStations": "ZRH",
  "PendingOnly": false,
  "ForExport": false
}

10.3 Endpoints

POST /ui/dashboards/dailyview.aspx/GetDataCheckouts
POST /ui/dashboards/dailyview.aspx/GetDataCheckins
POST /ui/dashboards/dailyview.aspx/GetDataNonrevenue
POST /ui/dashboards/dailyview.aspx/GetDataOverdue
POST /ui/dashboards/dailyview.aspx/GetDataAvailable
POST /ui/dashboards/dailyview.aspx/GetDataGrounded
POST /ui/dashboards/dailyview.aspx/GetDataBookings
POST /ui/dashboards/dailyview.aspx/GetDataPrecheckins
POST /ui/dashboards/dailyview.aspx/GetDataRequests
POST /ui/dashboards/dailyview.aspx/GetDataCancellations
POST /ui/dashboards/dailyview.aspx//GetFlightsStatus

10.4 Daily View Checkouts

Use for the app’s Checkout list.

Important fields:

id
sstr
datefrom
dateto
stationfrom
stationto
displaydocno
status
cargroupinv
cargroup
confirmationno
drivername
plateno
fuel
agent
source
domain
VoucherNo
Irn
carmodel

Recommended use:

Show daily operational checkout tasks.
When user opens one item, load rental detail by id/entityId for exact customer, vehicle and save context.

10.5 Daily View Checkins

Use for the app’s Return / Check-in list.

Important fields:

id
sstr
dateto
datefrom
displaydocno
status
cargroup
confirmationno
mileage
carmodel
drivername
plateno
fuel
balance
agent
stationfrom
stationto
CarTable_Id
VoucherNo
domain

Important:

CarTable_Id is a strong vehicle entity ID when available.

10.6 Daily View Available

Use for current available vehicles and current vehicle state.

Important fields:

id
plateno
platenotyres
cargroup
grpcode
carmodel
VehicleClassName
station
OwningStation
mileage
fuel
available_until
lastcheckin
lastcheckinlocation
active
inuse
hardhold
OnService
Vin

Important:

id = vehicle / car entity ID

10.7 Daily View Bookings

Use for current day bookings/reservation creation view.

Important fields:

id
usagetype
sstr
irn
datefrom
dateto
displaydocno
cargroup
cargroupinv
drivername
agent
rpd
resdate
VoucherNo

⸻

11. Journal Integration

11.1 Endpoint

POST /ui/dashboards/journal.aspx/GetDetailsRecords

11.2 Request

{
  "dt": "2026-06-19T00:00:00.000",
  "stations": "ZRH"
}

11.3 Response Structure

{
  "checkOuts": [],
  "checkIns": [],
  "avCars": []
}

11.4 Purpose

Journal is a combined operational snapshot:

checkOuts + checkIns + avCars

Use Journal when the app needs a fast daily operational overview.

Use Daily View when the app needs individual tab-level operational lists.

Do not call both Journal and the equivalent Daily View categories unnecessarily for the same refresh cycle unless explicitly needed.

11.5 Special Parsing Rule

For Journal, parse d.data first.
Do not reject only because success is false or ambiguous.

⸻

12. Availability Integration

12.1 Endpoints

POST /ui/dashboards/availability.aspx/GetData
POST /ui/dashboards/availability.aspx/GetDataFromCacheKey

12.2 Step 1 — Start Calculation

{
  "Params": "{\"cacheKey\":\"a333df42-7740-4c7d-ad1d-6a424b8caaa3\",\"dateFormat\":\"dd/MM/yyyy\",\"dateFrom\":\"2026-06-18T00:00:00.000Z\",\"dateTo\":\"2026-07-18T23:59:59.000Z\",\"stations\":\"ZRH\",\"groups\":\"UP,T,Y,DS,A,C,J\",\"hourIntervals\":1,\"uninsured\":true,\"forecast\":true,\"grace\":true,\"showAllMetrics\":true,\"useClass\":false}"
}

Returns:

{
  "d": "a333df42-7740-4c7d-ad1d-6a424b8caaa3"
}

12.3 Step 2 — Fetch Result

{
  "cacheKey": "a333df42-7740-4c7d-ad1d-6a424b8caaa3",
  "metric": "available"
}

12.4 Purpose

Use Availability for:

- group-level availability
- future capacity planning
- dashboard availability matrix

Do not use Availability for customer details or exact Checkout/Return save operations.

⸻

13. Fleet Chart Integration

13.1 Endpoint

POST /ui/dashboards/fleetchart.aspx/GetFleetchartData

13.2 Request

{
  "startDate": "/Date(1781827200000)/",
  "endDate": "/Date(1783641599000)/",
  "selectedStations": ",ZRH,",
  "expandedResources": null,
  "expandAll": true
}

13.3 Response

{
  "resources": [],
  "events": []
}

Important event fields:

start
end
id
resource
initialCarGroup
stationFrom
html
Domain
RentalTable_Id
recordId

13.4 Purpose

Use Fleet Chart for:

- timeline visualization
- vehicle utilization
- reservation/rental block overview

Do not use Fleet Chart as the primary source for customer email or rental save operations.

⸻

14. Rental Detail Page

14.1 Main URL

GET /ui/manage/master/rental.aspx?entityId={rentalId}
POST /ui/manage/master/rental.aspx?entityId={rentalId}

Example:

/ui/manage/master/rental.aspx?entityId=19812

This page is the source of truth for:

- rental identity
- RES/RNT references
- customer/driver details
- customer email through driverInfoContainer
- vehicle assignment
- checkout mileage/fuel
- return mileage/fuel
- rate calculations
- final save operation

14.2 Important Form Fields

Identity:

rdDispDocno_text
rdResDocNo
rdResDocDisp_text
rdIrnDisp_text
rdUsageType
rdStatus

Customer:

rdDriver_text
rdDriver_value
driverInfoContainer
rdDriver2_text
rdDriver2_value
rdDriver3_text
rdDriver3_value
rdDriver4_text
rdDriver4_value

Vehicle:

rdPlateNo_text
rdPlateNo_value
rdModel_text
rdModel_value
rdGroup_combo
rdGroupRes_text
rdGroupInv_combo
VehiclefilterCombo_combo

Checkout:

rdDateFrom_text
rdTimeFrom_text
rdStationFrom_combo
rdUserFrom_combo
rdMileageFrom_text
rdMileageFrom_hidden
rdTankFrom_text
rdTankFrom_hidden

Return / Check-in:

rdDateTo_text
rdTimeTo_text
rdStationTo_combo
rdUserTo_combo
rdMileageTo_text
rdMileageTo_hidden
rdTankTo_text
rdTankTo_hidden
rdCarCondition_combo

Charges and calculated values:

rdMilesDriven_text
rdMilesDriven_hidden
rdFuelPolicy_combo
rdFuel_text
rdFuel_hidden
rdChargeNet_text
rdChargeNet_hidden
rdTax1Amount_text
rdTax1Amount_hidden
rdChargeTotal_text
rdChargeTotal_hidden
rdPOA_text
rdPOA_hidden
rdBal_text
rdBal_hidden

ASP.NET WebForms state:

__VIEWSTATE
__ASYNCPOST
__EVENTTARGET
__EVENTARGUMENT
cachekey

⸻

15. Rental Form Parser

The app must always load the latest rental page before a save operation.

15.1 Browser Parser Example

export function parseRentalFormFromHtml(html: string): URLSearchParams {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, "text/html");
  const form = new URLSearchParams();
  doc.querySelectorAll("input, select, textarea").forEach((el: any) => {
    const name = el.getAttribute("name");
    if (!name) return;
    if (el.tagName === "SELECT") {
      form.set(name, el.value || "");
      return;
    }
    if (el.type === "checkbox") {
      if (el.checked) {
        form.set(name, "on");
      }
      return;
    }
    form.set(name, el.value || "");
  });
  return form;
}

Backend Node.js should use cheerio or jsdom.

⸻

16. Customer Display Integration

16.1 Requirement

The app only needs the following customer fields:

- First name
- Last name
- Full name
- Email

These are used only for internal display inside Checkout and Return screens.

They must be read-only.

They must not overwrite Wheelsys customer records.

16.2 Primary Source

Primary source:

rental.aspx?entityId={rentalId}
→ driverInfoContainer["1"]

Example:

{
  "1": {
    "Id": 3630,
    "Name": "Dom TEST",
    "Email": "berkaybdere@gmail.com",
    "FirstName": "Dom",
    "LastName": "TEST",
    "Telephone": "(+41) 7111111111",
    "Country": "GB",
    "RequiredFieldsFilled": true,
    "DoNotRent": false,
    "RentalCount": 1
  }
}

Needed fields only:

Id
Name
FirstName
LastName
Email

16.3 Fallback Source

Fallback:

rdDriver_text
rdDriver_value

If driverInfoContainer is not available:

fullName = rdDriver_text
wheelsysDriverId = rdDriver_value
email = null

Booking List fields such as DriverEmail, DriverFirstName and DriverLastName can be used only as a secondary fallback if rental detail cannot be loaded.

16.4 Customer Display Model

export type WheelsysCustomerDisplayInfo = {
  wheelsysDriverId?: number | null;
  firstName?: string | null;
  lastName?: string | null;
  fullName: string;
  email?: string | null;
  source:
    | "driverInfoContainer"
    | "rdDriverFallback"
    | "bookingViewFallback";
};

16.5 Customer Mapper

export function mapCustomerFromRentalForm(
  form: URLSearchParams,
  bookingFallback?: {
    DriverFirstName?: string | null;
    DriverLastName?: string | null;
    Driver_Name?: string | null;
    DriverEmail?: string | null;
    Driver_Id?: number | string | null;
  }
): WheelsysCustomerDisplayInfo {
  const driverNameFallback = form.get("rdDriver_text") || "";
  const driverIdFallback = form.get("rdDriver_value");
  const driverInfoRaw = form.get("driverInfoContainer");
  if (driverInfoRaw) {
    try {
      const parsed = JSON.parse(driverInfoRaw);
      const mainDriver = parsed?.["1"];
      if (mainDriver) {
        const firstName = mainDriver.FirstName || null;
        const lastName = mainDriver.LastName || null;
        const fullName =
          mainDriver.Name ||
          [firstName, lastName].filter(Boolean).join(" ") ||
          driverNameFallback ||
          "Customer information not available";
        return {
          wheelsysDriverId: mainDriver.Id
            ? Number(mainDriver.Id)
            : driverIdFallback
              ? Number(driverIdFallback)
              : null,
          firstName,
          lastName,
          fullName,
          email: mainDriver.Email || null,
          source: "driverInfoContainer"
        };
      }
    } catch {
      // Fallback below
    }
  }
  if (driverNameFallback) {
    const fallbackName = splitFullName(driverNameFallback);
    return {
      wheelsysDriverId: driverIdFallback ? Number(driverIdFallback) : null,
      firstName: fallbackName.firstName,
      lastName: fallbackName.lastName,
      fullName: driverNameFallback,
      email: null,
      source: "rdDriverFallback"
    };
  }
  if (bookingFallback) {
    const firstName = bookingFallback.DriverFirstName || null;
    const lastName = bookingFallback.DriverLastName || null;
    const fullName =
      bookingFallback.Driver_Name ||
      [firstName, lastName].filter(Boolean).join(" ") ||
      "Customer information not available";
    return {
      wheelsysDriverId: bookingFallback.Driver_Id
        ? Number(bookingFallback.Driver_Id)
        : null,
      firstName,
      lastName,
      fullName,
      email: bookingFallback.DriverEmail || null,
      source: "bookingViewFallback"
    };
  }
  return {
    wheelsysDriverId: null,
    firstName: null,
    lastName: null,
    fullName: "Customer information not available",
    email: null,
    source: "rdDriverFallback"
  };
}
function splitFullName(fullName: string): {
  firstName: string | null;
  lastName: string | null;
} {
  const clean = fullName.trim();
  if (!clean) {
    return {
      firstName: null,
      lastName: null
    };
  }
  const parts = clean.split(/\s+/);
  if (parts.length === 1) {
    return {
      firstName: parts[0],
      lastName: null
    };
  }
  return {
    firstName: parts[0],
    lastName: parts.slice(1).join(" ")
  };
}

16.6 Privacy Rule

Do not store unnecessary customer data.

Allowed:

- Wheelsys driver ID
- First name
- Last name
- Full name
- Email
- Source metadata

Avoid storing:

- License number
- Birth date
- ID/passport number
- tax ID
- card token
- payment token
- full address
- unnecessary phone data

⸻

17. Vehicle Resolver

17.1 Priority Order

Use this order:

1. rdPlateNo_value from rental.aspx
2. CarTable_Id from Daily View Checkins
3. id from Daily View Available / Journal avCars
4. Fleet List Id by normalized plate
5. VIN fallback
6. normalized plate fallback

17.2 Vehicle Snapshot Model

export type WheelsysVehicleSnapshot = {
  carId?: number | null;
  plateNo: string;
  normalizedPlateNo: string;
  model?: string | null;
  modelId?: number | null;
  group?: string | null;
  chargedGroup?: string | null;
  mileage?: number | null;
  fuel?: number | null;
  station?: string | null;
  vin?: string | null;
  source: string;
};

17.3 Mapper from Rental Form

export function mapVehicleFromRentalForm(
  form: URLSearchParams
): WheelsysVehicleSnapshot {
  const plateNo = form.get("rdPlateNo_text") || "";
  return {
    carId: form.get("rdPlateNo_value")
      ? Number(form.get("rdPlateNo_value"))
      : null,
    plateNo,
    normalizedPlateNo: normalizePlate(plateNo),
    model: form.get("rdModel_text"),
    modelId: form.get("rdModel_value")
      ? Number(form.get("rdModel_value"))
      : null,
    group: form.get("rdGroup_combo"),
    chargedGroup: form.get("rdGroupInv_combo"),
    mileage: form.get("rdMileageTo_hidden")
      ? Number(form.get("rdMileageTo_hidden"))
      : form.get("rdMileageFrom_hidden")
        ? Number(form.get("rdMileageFrom_hidden"))
        : null,
    fuel: form.get("rdTankTo_hidden")
      ? Number(form.get("rdTankTo_hidden"))
      : form.get("rdTankFrom_hidden")
        ? Number(form.get("rdTankFrom_hidden"))
        : null,
    station: form.get("rdStationTo_combo") || form.get("rdStationFrom_combo"),
    vin: null,
    source: "rentalForm"
  };
}

⸻

18. Mileage and Fuel Rules

18.1 Mileage

Text field:

24560 km

Hidden field:

24560

Normalizer:

export function normalizeMileage(value: unknown): number {
  const numeric = Number(String(value).replace("km", "").trim());
  if (Number.isNaN(numeric)) {
    throw new Error("Invalid mileage value");
  }
  if (numeric < 0) {
    throw new Error("Mileage cannot be negative");
  }
  return Math.round(numeric);
}

18.2 Fuel

Wheelsys fuel uses a 0–8 scale.

0 /8
1 /8
2 /8
3 /8
4 /8
5 /8
6 /8
7 /8
8 /8

Normalizer:

export function normalizeFuelLevel(value: unknown): number {
  const numeric = Number(String(value).replace("/8", "").trim());
  if (Number.isNaN(numeric)) {
    throw new Error("Invalid fuel value");
  }
  if (numeric < 0 || numeric > 8) {
    throw new Error("Fuel level must be between 0 and 8");
  }
  return numeric;
}

18.3 Return Mileage Validation

export function validateReturnMileage(
  checkoutMileage: number,
  returnMileage: number
): void {
  if (returnMileage < checkoutMileage) {
    throw new Error("Return mileage cannot be lower than checkout mileage");
  }
}

⸻

19. Unified Rental Context Resolver

19.1 Purpose

The app must be able to resolve a rental context from:

- rentalId / entityId
- RNT number
- RES number
- IRN
- plate + selected date

19.2 Preferred Order

1. rentalId / entityId
2. RNT number
3. RES number
4. IRN
5. plate + selected date

19.3 Context Model

export type WheelsysRentalContext = {
  rentalId: number;
  rntNo?: string | null;
  resNo?: string | null;
  irn?: string | null;
  status?: number | null;
  usageType?: number | null;
  customer: WheelsysCustomerDisplayInfo;
  vehicle: WheelsysVehicleSnapshot;
  checkout?: {
    date?: string | null;
    time?: string | null;
    mileage?: number | null;
    fuel?: number | null;
    station?: string | null;
  };
  checkin?: {
    date?: string | null;
    time?: string | null;
    mileage?: number | null;
    fuel?: number | null;
    station?: string | null;
  };
  form: URLSearchParams;
  syncedAt: string;
};

19.4 Resolver Behavior

1. If rentalId exists, load rental.aspx directly.
2. If only RNT exists, search bookingview and resolve Id.
3. If only RES exists, search bookingview and resolve Id.
4. If only IRN exists, search bookingview and resolve Id.
5. If only plate + date exists, search Daily View Checkins / Checkouts and Journal.
6. Load rental.aspx?entityId={rentalId}.
7. Parse form fields.
8. Extract customer from driverInfoContainer.
9. Extract vehicle from rental form.
10. Return full context.

19.5 Mapper

export function mapRentalContext(
  rentalId: number,
  form: URLSearchParams,
  bookingFallback?: any
): WheelsysRentalContext {
  const customer = mapCustomerFromRentalForm(form, bookingFallback);
  const vehicle = mapVehicleFromRentalForm(form);
  return {
    rentalId,
    rntNo: form.get("rdDispDocno_text") || null,
    resNo: form.get("rdResDocNo") || form.get("rdResDocDisp_text") || null,
    irn: form.get("rdIrnDisp_text") || null,
    status: form.get("rdStatus") ? Number(form.get("rdStatus")) : null,
    usageType: form.get("rdUsageType") ? Number(form.get("rdUsageType")) : null,
    customer,
    vehicle,
    checkout: {
      date: form.get("rdDateFrom_text"),
      time: form.get("rdTimeFrom_text"),
      mileage: form.get("rdMileageFrom_hidden")
        ? Number(form.get("rdMileageFrom_hidden"))
        : null,
      fuel: form.get("rdTankFrom_hidden")
        ? Number(form.get("rdTankFrom_hidden"))
        : null,
      station: form.get("rdStationFrom_combo")
    },
    checkin: {
      date: form.get("rdDateTo_text"),
      time: form.get("rdTimeTo_text"),
      mileage: form.get("rdMileageTo_hidden")
        ? Number(form.get("rdMileageTo_hidden"))
        : null,
      fuel: form.get("rdTankTo_hidden")
        ? Number(form.get("rdTankTo_hidden"))
        : null,
      station: form.get("rdStationTo_combo")
    },
    form,
    syncedAt: new Date().toISOString()
  };
}

⸻

20. Checkout Screen Integration

20.1 Operational Source Priority

For checkout list:

1. Daily View GetDataCheckouts
2. Journal checkOuts
3. Booking List fallback
4. rental.aspx detail for exact customer/vehicle/save context

20.2 Flow

1. User opens Checkout screen.
2. App loads Daily View Checkouts or Journal checkOuts.
3. User selects a reservation/rental.
4. App resolves rentalId.
5. App opens rental.aspx?entityId={rentalId}.
6. App parses driverInfoContainer["1"].
7. App displays customer full name and email.
8. App parses vehicle ID, plate, model, group, mileage/fuel.
9. Staff performs operational checkout tasks.
10. If writing back to Wheelsys, app saves through the proper rental.aspx stateful form flow.

20.3 Customer Display Block

export type CheckoutCustomerBlock = {
  fullName: string;
  firstName?: string | null;
  lastName?: string | null;
  email?: string | null;
  rntNo?: string | null;
  resNo?: string | null;
};
export function buildCheckoutCustomerBlock(
  context: WheelsysRentalContext
): CheckoutCustomerBlock {
  return {
    fullName: context.customer.fullName,
    firstName: context.customer.firstName,
    lastName: context.customer.lastName,
    email: context.customer.email,
    rntNo: context.rntNo,
    resNo: context.resNo
  };
}

⸻

21. Return / Check-in Screen Integration

21.1 Operational Source Priority

For return list:

1. Daily View GetDataCheckins
2. Journal checkIns
3. Plate + date lookup
4. rental.aspx detail for exact customer/vehicle/save context

21.2 Flow

1. User scans plate or selects item from Return list.
2. App resolves active rental.
3. App opens rental.aspx?entityId={rentalId}.
4. App parses customer from driverInfoContainer["1"].
5. App displays customer full name and email.
6. App parses checkout mileage/fuel.
7. Staff enters return mileage and return fuel.
8. App validates return mileage >= checkout mileage.
9. App updates return/check-in form fields.
10. App runs required Wheelsys checks/calculations.
11. App saves with BTSAVE.
12. App confirms only after wheels.afterSave.success === true.

21.3 Return Display Block

export type ReturnCustomerBlock = {
  fullName: string;
  firstName?: string | null;
  lastName?: string | null;
  email?: string | null;
  rntNo?: string | null;
  resNo?: string | null;
  plateNo?: string | null;
};
export function buildReturnCustomerBlock(
  context: WheelsysRentalContext
): ReturnCustomerBlock {
  return {
    fullName: context.customer.fullName,
    firstName: context.customer.firstName,
    lastName: context.customer.lastName,
    email: context.customer.email,
    rntNo: context.rntNo,
    resNo: context.resNo,
    plateNo: context.vehicle.plateNo
  };
}

⸻

22. Return / Check-in Write Operation

22.1 Observed Flow

Observed HAR sequence:

1. User lookup
2. User notes
3. Blacklist check
4. Vehicle search / QueryData
5. Vehicle diagram
6. CalcRates
7. canusecar
8. GetDamages
9. CalcRates again for mileage/fuel/extra day changes
10. InvoicePrep prepare
11. InvoicePrep confirm
12. rental.aspx BTSAVE
13. GetPdf if required

22.2 Important Rule

The actual save is BTSAVE to rental.aspx?entityId={rentalId}.
CalcRates and InvoicePrep are not final save confirmations.

22.3 Check-in Fields to Update

rdDateTo_text
rdTimeTo_text
rdStationTo_combo
rdUserTo_combo
rdMileageTo_text
rdMileageTo_hidden
rdTankTo_text
rdTankTo_hidden
rdMilesDriven_text
rdMilesDriven_hidden
rdStatus
rdUsageType

Example:

rdDateTo_text        = 19/06/2026
rdTimeTo_text        = 21:42
rdStationTo_combo    = ZRH
rdUserTo_combo       = 14
rdMileageTo_text     = 2 km
rdMileageTo_hidden   = 2
rdTankTo_text        = 0 /8
rdTankTo_hidden      = 0
rdMilesDriven_text   = 1 km
rdMilesDriven_hidden = 1
rdUsageType          = 2
rdStatus             = 3

22.4 canusecar

Endpoint:

POST /api/entities/rentalsupport/car/canusecar

Payload:

plateNo=ZG73869
carId=397
dateFrom=2026-06-19T21:34:00.000Z
dateTo=2026-06-19T21:42:00.000Z
usageReq=2
rId=19812
isRentalId=true

22.5 CalcRates

Endpoint:

POST /ui/manage/master/rental.aspx/CalcRates

Known operations from observed behavior:

CHECKIN
FuelPolicy
ExtraDay
KMDriven

Rule:

CalcRates success:true = calculation succeeded only.

22.6 InvoicePrep

Endpoint:

POST /ui/manage/master/rental.aspx/InvoicePrep

Used when Wheelsys requires invoice preparation.

Rule:

InvoicePrep success:true = invoice preparation succeeded only.
It is not the final rental save confirmation.

22.7 BTSAVE

Endpoint:

POST /ui/manage/master/rental.aspx?entityId={rentalId}

Required form fields:

__EVENTTARGET = rentalPanel
__EVENTARGUMENT = {"action":"BTSAVE","itemId":"{rentalId}"}
__ASYNCPOST = true

Important:

Send the complete fresh form state.
Do not send only changed fields.
Do not reuse old form state after a successful save.

⸻

23. Save Response Parsing

The successful save result is embedded in:

wheels.afterSave(...)

23.1 Success Example

{
  "message": null,
  "success": true,
  "keyValue": 19816,
  "ExtraData": {
    "usageType": 2,
    "mustprint": true,
    "mustinvoice": false,
    "irn": "3KBC79",
    "newTitle": "Review rental - RNT-13244"
  }
}

23.2 Failure Example

{
  "message": "Record was changed by b berkay",
  "success": false,
  "keyValue": null
}

23.3 Parser

export function parseAfterSave(responseText: string): any {
  const marker = "wheels.afterSave(";
  const start = responseText.indexOf(marker);
  if (start === -1) {
    throw new Error("wheels.afterSave result not found");
  }
  const jsonStart = start + marker.length;
  const jsonEnd = responseText.indexOf(", false);", jsonStart);
  if (jsonEnd === -1) {
    throw new Error("wheels.afterSave JSON end not found");
  }
  const jsonText = responseText.slice(jsonStart, jsonEnd);
  return JSON.parse(jsonText);
}

23.4 Completion Rule

Only afterSave.success === true confirms the operation was saved.

⸻

24. Version Conflict Handling

Observed error:

Record was changed by b berkay

Meaning:

The rental record changed after the current form state was loaded.
The app/browser attempted to save using stale form state.

Common causes:

- First save already succeeded.
- Same rental is open in another tab.
- The user manually changed the rental.
- The app sent a second BTSAVE using old form state.
- __VIEWSTATE/cachekey/form state is stale.

24.1 Correct Handling

1. Do not retry with the same payload.
2. Reload rental.aspx?entityId={rentalId}.
3. Parse fresh form state.
4. Re-apply intended changes.
5. Save once.
6. If afterSave.success === true, stop.

24.2 Critical Rule

If the first BTSAVE returns success:true, do not send a second BTSAVE with the same form state.

⸻

25. Internal Data Storage

25.1 Checkout Record Example

{
  "type": "checkout",
  "wheelsys": {
    "rentalId": 19812,
    "rntNo": "RNT-13243",
    "resNo": "RES-17745",
    "irn": "3HL218",
    "plateNo": "ZG73869",
    "carId": 397
  },
  "customerSnapshot": {
    "wheelsysDriverId": 3630,
    "firstName": "Dom",
    "lastName": "TEST",
    "fullName": "Dom TEST",
    "email": "berkaybdere@gmail.com",
    "source": "driverInfoContainer"
  },
  "vehicleSnapshot": {
    "carId": 397,
    "plateNo": "ZG73869",
    "model": "KIA CEED",
    "group": "R",
    "mileage": 1,
    "fuel": 0
  },
  "operation": {
    "status": "completed",
    "source": "Wheelsys",
    "syncedAt": "2026-06-19T21:43:00.000Z"
  }
}

25.2 Return Record Example

{
  "type": "return",
  "wheelsys": {
    "rentalId": 19812,
    "rntNo": "RNT-13243",
    "resNo": "RES-17745",
    "irn": "3HL218",
    "plateNo": "ZG73869",
    "carId": 397
  },
  "customerSnapshot": {
    "wheelsysDriverId": 3630,
    "firstName": "Dom",
    "lastName": "TEST",
    "fullName": "Dom TEST",
    "email": "berkaybdere@gmail.com",
    "source": "driverInfoContainer"
  },
  "returnData": {
    "checkoutMileage": 1,
    "returnMileage": 2,
    "milesDriven": 1,
    "checkoutFuel": 0,
    "returnFuel": 0,
    "returnStation": "ZRH"
  },
  "operation": {
    "status": "completed",
    "wheelsysSaveSuccess": true,
    "syncedAt": "2026-06-19T21:43:00.000Z"
  }
}

⸻

26. Performance and Optimization Strategy

26.1 Parallel Calls

Daily View category endpoints are independent. They can be called concurrently with a safe concurrency limit.

Recommended concurrency:

5–8 concurrent requests per account/session

Do not mix large Booking List pulls with smaller operational dashboard calls in the same queue. Use separate queues:

Small fast operational queue:
- Daily View
- Journal
- UserList
- helper endpoints
Heavy data queue:
- bookingview
- vehicleview
- availability
- fleetchart

26.2 Avoid Duplicate Pulling

Journal already contains:

checkOuts
checkIns
avCars

Daily View contains these separately.

Do not fetch both for the same refresh cycle unless explicitly needed.

26.3 Booking List Payload Control

Because dataSize/dataSkip may not be enforced:

- Always use dateStart/dateEnd where possible.
- Use status filters if available.
- Split large time ranges into weekly or monthly chunks.
- Avoid pulling all history on every refresh.

26.4 HTTP Optimization

Use:

- keep-alive
- HTTP/2 if supported
- gzip / br compression
- connection pooling
- retry with exponential backoff

26.5 Recommended Polling Frequencies

Dataset	Frequency
Daily View / Journal	1–3 minutes
Booking List	2–5 minutes
Fleet List	30–60 minutes
Availability	15–30 minutes
Fleet Chart	5–10 minutes
UserList / lookups	Startup + daily refresh

26.6 Diff-Based Processing

After each sync:

1. Normalize IDs and plate numbers.
2. Compare with previous snapshot.
3. Process only changed records.
4. Avoid rewriting unchanged data to Firestore.

26.7 SignalR Future Option

SignalR negotiate was observed:

https://signalrcore.wheelsys.io/signalr/hubs/negotiate

It is optional for the first implementation.

Use polling first. SignalR can be evaluated later for event-driven updates.

⸻

27. Error Handling

27.1 Session Expired

Detect:

HTTP 401
HTTP 403
HTTP 302 to login
unexpected HTML login page

Action:

Trigger backend re-authentication / session refresh.

27.2 Customer Missing

If no customer found:

Display: Customer information not available
Allow operation if business rules allow
Log the rentalId and source

27.3 Email Missing

If email is missing:

Show full name.
Show email as empty / No email available.
Do not block Checkout/Return unless email is mandatory for a specific workflow.

27.4 Vehicle ID Missing

Fallback order:

1. rdPlateNo_value
2. CarTable_Id
3. Daily View Available / Journal avCars id
4. Fleet List Id by normalized plate
5. VIN
6. normalized plate only

27.5 Save Conflict

If message contains:

Record was changed

Action:

Reload rental detail.
Rebuild form state.
Reapply intended changes.
Save once.

⸻

28. Implementation Priority for Our App

This is the recommended build order.

Phase 1 — Read-only Data Layer

[ ] WheelsysHttpClient
[ ] Universal response parser
[ ] Daily View service
[ ] Journal service
[ ] Booking List service
[ ] Fleet List service
[ ] Rental Detail loader

Phase 2 — Customer and Vehicle Context

[ ] Rental context resolver
[ ] Customer mapper using driverInfoContainer["1"]
[ ] Customer fallback using rdDriver_text
[ ] BookingView customer fallback
[ ] Vehicle mapper using rdPlateNo_value
[ ] Vehicle fallback using Daily View / Journal / Fleet List

Phase 3 — App Screen Integration

[ ] Show customer full name and email in Checkout screen
[ ] Show customer full name and email in Return screen
[ ] Keep customer fields read-only
[ ] Store minimal customerSnapshot
[ ] Store vehicleSnapshot

Phase 4 — Return / Check-in Write Flow

[ ] Load fresh rental form
[ ] Update return mileage/fuel/date/time
[ ] Validate return mileage
[ ] Call canusecar if required
[ ] Call GetDamages if required
[ ] Call CalcRates
[ ] Call InvoicePrep if required
[ ] Send BTSAVE
[ ] Parse wheels.afterSave
[ ] Handle version conflict
[ ] Update internal return record after success

Phase 5 — Checkout Write Flow

[ ] Resolve checkout rental
[ ] Load fresh rental form
[ ] Display customer info
[ ] Validate vehicle/mileage/fuel
[ ] Save through proper Wheelsys stateful form flow
[ ] Confirm wheels.afterSave.success

⸻

29. Golden Rules

1. Use rentalId/entityId when available.
2. Use Booking List to search broadly.
3. Use Daily View for operational Checkout/Return lists.
4. Use Journal for combined daily snapshot.
5. Use Fleet List for master vehicle metadata.
6. Use rental.aspx as the source of truth for customer name/email.
7. Use driverInfoContainer["1"] for customer first name, last name, full name and email.
8. Use rdDriver_text only as customer fallback.
9. Use rdPlateNo_value as vehicle ID.
10. Use rdDriver_value as customer ID.
11. Never confuse customer ID with vehicle ID.
12. Use CarTable_Id / Available.id / avCars.id as vehicle fallback.
13. Normalize plates before matching.
14. Avoid toISOString for local selected dates.
15. Parse d, d.data and JSON-string responses safely.
16. For Journal, parse d.data even if success flag is false or ambiguous.
17. CalcRates success:true is not a save confirmation.
18. InvoicePrep success:true is not a save confirmation.
19. Only wheels.afterSave.success === true confirms save.
20. Never send a second BTSAVE after a successful save using stale form state.
21. On “Record was changed”, reload rental detail and rebuild fresh form state.
22. Store only minimal customerSnapshot.
23. Keep customer fields read-only.
24. Keep Wheelsys cookies server-side only.
25. Do not commit HAR files, cookies, production config or real session data.

⸻

30. Final Recommended Cursor Task

Implement the integration in this exact order:

1. Build Wheelsys read-only data layer:
   - Daily View
   - Journal
   - Booking List
   - Fleet List
   - Rental Detail loader
2. Build Rental Context Resolver:
   - Resolve by entityId, RNT, RES, IRN, plate+date
   - Load rental.aspx
   - Parse form state
3. Build Customer Display Resolver:
   - Primary: driverInfoContainer["1"]
   - Fallback: rdDriver_text / rdDriver_value
   - Secondary fallback: bookingview DriverEmail / DriverFirstName / DriverLastName
4. Build Vehicle Resolver:
   - Primary: rdPlateNo_value
   - Fallback: CarTable_Id, Available.id, Journal avCars.id, Fleet List Id, VIN, normalized plate
5. Integrate into app UI:
   - Checkout screen customer block
   - Return screen customer block
   - Read-only fields
   - Minimal Firestore customerSnapshot
6. Implement Return / Check-in write operation:
   - Fresh rental form state
   - Mileage/fuel validation
   - CalcRates
   - InvoicePrep if required
   - BTSAVE
   - afterSave parsing
   - version conflict handling
7. Add secure backend-only session handling.
8. Add logging, retries, rate limits and sanitized HAR-based tests.

The immediate priority for the current app is:

When user opens Checkout or Return:
- resolve rentalId
- load rental.aspx?entityId={rentalId}
- parse driverInfoContainer["1"]
- show customer full name and email internally
- resolve vehicle ID correctly
- store only minimal customerSnapshot and vehicleSnapshot


Wheelsys Vehicle Damage History Integration

Araç Hasar Kayıtlarını ve Fotoğraf Preview’lerini Çekme Teknik Raporu

1. Amaç

Bu entegrasyonun amacı, Wheelsys üzerinde kayıtlı bir aracın geçmiş hasarlarını uygulama içinde görüntülemektir.

Uygulama, bir aracın mevcut/geçmiş hasar kayıtlarını şu kaynak üzerinden okuyacaktır:

GET /ui/manage/master/car.aspx?entityId={vehicleEntityId}

Örnek:

https://ch.wheelsys.greenmotion.com/ui/manage/master/car.aspx?entityId=299

Bu sayfa Wheelsys’teki Vehicle / Car Master Page ekranıdır. Ekrandaki Damages tab’ında aracın geçmiş hasarları, hasar detayları, bağlı rental numarası, tutar bilgisi, attachment dosyaları ve hasar fotoğrafları görülebilir.

⸻

2. Ana Teknik Prensip

Hasar kayıtları için ilk ve güvenli yöntem, car.aspx sayfasını backend üzerinden açıp HTML parse etmektir.

Önemli nokta:

Damage kayıtları frontend’den direkt çekilmemelidir.
Wheelsys session cookie sadece backend tarafında kalmalıdır.

Yani akış şu şekilde olmalıdır:

GreenMotionERP / Vehicle Sentinel App
        ↓
Internal Backend API
        ↓
Wheelsys Integration Service
        ↓
GET car.aspx?entityId={vehicleEntityId}
        ↓
HTML Parse
        ↓
Normalized Damage JSON
        ↓
Frontend’de Existing Damages + Image Preview

⸻

3. Vehicle Entity ID Nasıl Bulunur?

Hasarları çekebilmek için önce aracın Wheelsys içindeki vehicle entityId değeri bulunmalıdır.

Öncelik sırası:

1. rental.aspx içindeki rdPlateNo_value
2. Daily View Check-ins içindeki CarTable_Id
3. Journal avCars içindeki id
4. Daily View Available içindeki id
5. Fleet List / vehicleview içindeki Id
6. Normalize edilmiş plaka eşleşmesi fallback

Örnek resolver mantığı:

function resolveVehicleEntityId(context: {
  rentalForm?: URLSearchParams;
  dailyViewCheckin?: any;
  journalAvCar?: any;
  dailyViewAvailableCar?: any;
  fleetVehicle?: any;
}): number | null {
  const fromRentalForm = context.rentalForm?.get("rdPlateNo_value");
  if (fromRentalForm) {
    return Number(fromRentalForm);
  }
  if (context.dailyViewCheckin?.CarTable_Id) {
    return Number(context.dailyViewCheckin.CarTable_Id);
  }
  if (context.journalAvCar?.id) {
    return Number(context.journalAvCar.id);
  }
  if (context.dailyViewAvailableCar?.id) {
    return Number(context.dailyViewAvailableCar.id);
  }
  if (context.fleetVehicle?.Id) {
    return Number(context.fleetVehicle.Id);
  }
  return null;
}

⸻

4. Vehicle Page Nasıl Çekilecek?

Backend tarafında authenticated Wheelsys session ile şu request yapılır:

export async function fetchWheelsysVehiclePage(vehicleId: number): Promise<string> {
  const url =
    `https://ch.wheelsys.greenmotion.com/ui/manage/master/car.aspx?entityId=${vehicleId}`;
  const response = await fetch(url, {
    method: "GET",
    headers: {
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "User-Agent": "Mozilla/5.0",
      "Referer": "https://ch.wheelsys.greenmotion.com/ui/manage/views/vehicleview.aspx",
      "Cookie": process.env.WHEELSYS_COOKIE!
    }
  });
  if (!response.ok) {
    throw new Error(`Failed to load Wheelsys vehicle page. Status: ${response.status}`);
  }
  return await response.text();
}

Güvenlik notu:

Cookie frontend’e gönderilmez.
HTML frontend’e raw olarak gönderilmez.
Backend sadece temizlenmiş JSON response döndürür.

⸻

5. Damage Grid Parse Mantığı

car.aspx HTML’i yüklendikten sonra Damages tab içindeki grid parse edilir.

Ekranda görünen temel alanlar:

No
Vehicle
Damage Type
Charge / Rate
R.A. / RNT
Added On

Örnek HTML parser:

import * as cheerio from "cheerio";
export type WheelsysVehicleDamageRow = {
  damageNo?: string | null;
  vehicleId: number;
  plateNo?: string | null;
  damageType?: string | null;
  chargeText?: string | null;
  relatedRentalNo?: string | null;
  addedOn?: string | null;
  source: "car.aspx.damageGrid";
};
export function parseVehicleDamageGrid(
  html: string,
  vehicleId: number
): WheelsysVehicleDamageRow[] {
  const $ = cheerio.load(html);
  const damages: WheelsysVehicleDamageRow[] = [];
  $("table tr").each((_, row) => {
    const cells = $(row).find("td");
    if (cells.length < 4) return;
    const damageNo = $(cells[0]).text().trim() || null;
    const plateNo = $(cells[1]).text().trim() || null;
    const damageType = $(cells[2]).text().trim() || null;
    const chargeText = $(cells[3]).text().trim() || null;
    const relatedRentalNo = $(cells[4]).text().trim() || null;
    const addedOn = $(cells[5]).text().trim() || null;
    if (!plateNo || !damageType) return;
    damages.push({
      damageNo,
      vehicleId,
      plateNo,
      damageType,
      chargeText,
      relatedRentalNo,
      addedOn,
      source: "car.aspx.damageGrid"
    });
  });
  return damages;
}

Not:

Gerçek production kodunda selector’lar table tr gibi genel bırakılmamalı.
Önce car.aspx HTML source içinden Damages grid’in gerçek id/class/name değeri bulunmalı.
Sonra selector daha kesin yazılmalı.

Örnek daha iyi selector mantığı:

$("#damageGrid tr, .damage-grid tr, [id*='Damage'] tr").each((_, row) => {
  // parse damage row
});

⸻

6. Damage Detail Alanları

Bir hasar seçildiğinde sağ tarafta şu bilgiler görünür:

Vehicle
Area
Element
Damage type
Action
Memo
Rate / Charged
Recorded by / On
Labour hours

Bu alanlar HTML içinde input, select veya textarea olarak bulunabilir.

Genel field parser:

function getInputValue($: cheerio.CheerioAPI, selector: string): string | null {
  const element = $(selector).first();
  if (!element.length) {
    return null;
  }
  return (
    element.attr("value") ||
    element.find("option:selected").text().trim() ||
    element.text().trim() ||
    null
  );
}

Detail parser örneği:

export type WheelsysSelectedDamageDetail = {
  vehicle?: string | null;
  area?: string | null;
  element?: string | null;
  damageType?: string | null;
  action?: string | null;
  memo?: string | null;
  rateText?: string | null;
  chargedText?: string | null;
  recordedBy?: string | null;
  recordedOn?: string | null;
  labourHours?: string | null;
  source: "car.aspx.damageDetail";
};
export function parseSelectedDamageDetail(
  html: string
): WheelsysSelectedDamageDetail {
  const $ = cheerio.load(html);
  return {
    vehicle: getInputValue($, "[name*='Vehicle'], [id*='Vehicle']"),
    area: getInputValue($, "[name*='Area'], [id*='Area']"),
    element: getInputValue($, "[name*='Element'], [id*='Element']"),
    damageType: getInputValue($, "[name*='DamageType'], [id*='DamageType']"),
    action: getInputValue($, "[name*='Action'], [id*='Action']"),
    memo: getInputValue($, "[name*='Memo'], [id*='Memo']"),
    rateText: getInputValue($, "[name*='Rate'], [id*='Rate']"),
    chargedText: getInputValue($, "[name*='Charged'], [id*='Charged']"),
    recordedBy: getInputValue($, "[name*='RecordedBy'], [id*='RecordedBy']"),
    recordedOn: getInputValue($, "[name*='RecordedOn'], [id*='RecordedOn']"),
    labourHours: getInputValue($, "[name*='Labour'], [id*='Labour']"),
    source: "car.aspx.damageDetail"
  };
}

Bu selector’lar ilk entegrasyon için esnek tutulmuştur. Final aşamada car.aspx HTML source incelenerek gerçek field isimleriyle kesinleştirilmelidir.

⸻

7. Geçmiş Hasar Fotoğraflarını Çekme

Ekranda görünen örnek attachment:

ZH676900.jpg

Bu attachment, hasar kaydına bağlı fotoğraf dosyasıdır. Uygulamada geçmiş hasarların foto preview’lerini göstermek için bu dosya linkleri de parse edilmelidir.

Attachment parser:

export type WheelsysDamageAttachment = {
  filename: string;
  url: string;
  fileType: "image" | "pdf" | "other";
  previewable: boolean;
  source: "car.aspx.attachment";
};
export function parseDamageAttachments(html: string): WheelsysDamageAttachment[] {
  const $ = cheerio.load(html);
  const attachments: WheelsysDamageAttachment[] = [];
  $("a").each((_, link) => {
    const filename = $(link).text().trim();
    const href = $(link).attr("href");
    if (!filename || !href) return;
    const looksLikeAttachment =
      /\.(jpg|jpeg|png|webp|gif|pdf)$/i.test(filename) ||
      /\.(jpg|jpeg|png|webp|gif|pdf)$/i.test(href);
    if (!looksLikeAttachment) return;
    const absoluteUrl = href.startsWith("http")
      ? href
      : `https://ch.wheelsys.greenmotion.com${href.startsWith("/") ? "" : "/"}${href}`;
    const lower = filename.toLowerCase();
    const fileType =
      /\.(jpg|jpeg|png|webp|gif)$/i.test(lower)
        ? "image"
        : /\.pdf$/i.test(lower)
          ? "pdf"
          : "other";
    attachments.push({
      filename,
      url: absoluteUrl,
      fileType,
      previewable: fileType === "image",
      source: "car.aspx.attachment"
    });
  });
  return attachments;
}

⸻

8. Foto Preview İçin Backend Proxy Gerekir

Wheelsys attachment URL’si direkt frontend’e verilmemelidir. Çünkü bu URL büyük ihtimalle authenticated session ister.

Doğru yapı:

Frontend image preview
        ↓
GET /api/wheelsys/vehicles/{vehicleId}/damages/{damageId}/attachments/{attachmentId}/preview
        ↓
Backend Wheelsys session ile gerçek attachment URL’ini çeker
        ↓
Image stream veya signed temporary internal URL döndürür

Backend proxy örneği:

export async function fetchWheelsysAttachmentAsBuffer(
  attachmentUrl: string
): Promise<{
  buffer: Buffer;
  contentType: string;
}> {
  const response = await fetch(attachmentUrl, {
    method: "GET",
    headers: {
      "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
      "User-Agent": "Mozilla/5.0",
      "Cookie": process.env.WHEELSYS_COOKIE!
    }
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch Wheelsys attachment. Status: ${response.status}`);
  }
  const arrayBuffer = await response.arrayBuffer();
  return {
    buffer: Buffer.from(arrayBuffer),
    contentType: response.headers.get("content-type") || "application/octet-stream"
  };
}

Express route örneği:

app.get(
  "/api/wheelsys/attachments/preview",
  async (req, res) => {
    try {
      const attachmentUrl = String(req.query.url || "");
      if (!attachmentUrl.startsWith("https://ch.wheelsys.greenmotion.com/")) {
        return res.status(400).json({
          error: "Invalid attachment URL"
        });
      }
      const file = await fetchWheelsysAttachmentAsBuffer(attachmentUrl);
      res.setHeader("Content-Type", file.contentType);
      res.setHeader("Cache-Control", "private, max-age=300");
      return res.send(file.buffer);
    } catch (error: any) {
      return res.status(500).json({
        error: error.message || "Attachment preview failed"
      });
    }
  }
);

Daha güvenli production yaklaşımı:

Frontend’e gerçek Wheelsys attachment URL verilmez.
Backend attachment için internal attachmentId üretir.
Frontend sadece internal preview endpoint’i çağırır.

⸻

9. Normalized Damage Model

Backend’in frontend’e döndürmesi gereken temiz model:

export type WheelsysVehicleDamage = {
  damageId?: string | null;
  damageNo?: string | null;
  vehicleId: number;
  plateNo?: string | null;
  normalizedPlateNo?: string | null;
  damageType?: string | null;
  area?: string | null;
  element?: string | null;
  action?: string | null;
  memo?: string | null;
  chargeText?: string | null;
  chargeAmount?: number | null;
  currency?: string | null;
  relatedRentalNo?: string | null;
  addedOn?: string | null;
  recordedBy?: string | null;
  recordedOn?: string | null;
  labourHours?: string | null;
  attachments: {
    attachmentId: string;
    filename: string;
    fileType: "image" | "pdf" | "other";
    previewable: boolean;
    previewUrl: string;
  }[];
  relatedItems: {
    type: "preparation" | "maintenance" | "rental" | "unknown";
    label: string;
    url?: string | null;
  }[];
  source: "wheelsys.car.aspx";
  syncedAt: string;
};

⸻

10. Final Service Fonksiyonu

Tüm işlemi birleştiren servis:

export async function getVehicleDamageHistory(
  vehicleId: number
): Promise<{
  vehicleId: number;
  damages: WheelsysVehicleDamage[];
  syncedAt: string;
}> {
  const html = await fetchWheelsysVehiclePage(vehicleId);
  const damageRows = parseVehicleDamageGrid(html, vehicleId);
  const attachments = parseDamageAttachments(html);
  const damages: WheelsysVehicleDamage[] = damageRows.map((row, index) => {
    const relatedAttachments = attachments.map((attachment, attachmentIndex) => ({
      attachmentId: `${vehicleId}-${index}-${attachmentIndex}`,
      filename: attachment.filename,
      fileType: attachment.fileType,
      previewable: attachment.previewable,
      previewUrl: `/api/wheelsys/vehicles/${vehicleId}/damage-attachments/${index}/${attachmentIndex}/preview`
    }));
    return {
      damageId: `${vehicleId}-${row.damageNo || index}`,
      damageNo: row.damageNo,
      vehicleId,
      plateNo: row.plateNo,
      normalizedPlateNo: row.plateNo
        ? normalizePlate(row.plateNo)
        : null,
      damageType: row.damageType,
      area: null,
      element: null,
      action: null,
      memo: null,
      chargeText: row.chargeText,
      chargeAmount: parseChargeAmount(row.chargeText),
      currency: detectCurrency(row.chargeText),
      relatedRentalNo: row.relatedRentalNo,
      addedOn: row.addedOn,
      recordedBy: null,
      recordedOn: null,
      labourHours: null,
      attachments: relatedAttachments,
      relatedItems: [],
      source: "wheelsys.car.aspx",
      syncedAt: new Date().toISOString()
    };
  });
  return {
    vehicleId,
    damages,
    syncedAt: new Date().toISOString()
  };
}

Helper fonksiyonlar:

export function normalizePlate(value: string): string {
  return value
    .replace(/\s+/g, "")
    .replace(/\*/g, "")
    .trim()
    .toUpperCase();
}
export function parseChargeAmount(value?: string | null): number | null {
  if (!value) return null;
  const cleaned = value
    .replace("CHF", "")
    .replace(/\./g, "")
    .replace(",", ".")
    .trim();
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
}
export function detectCurrency(value?: string | null): string | null {
  if (!value) return null;
  if (value.toUpperCase().includes("CHF")) {
    return "CHF";
  }
  return null;
}

⸻

11. Frontend’de Foto Preview Gösterimi

Frontend, backend’den gelen previewUrl değerlerini kullanarak geçmiş hasar fotoğraflarını gösterebilir.

Örnek React/SwiftUI mantığı:

function ExistingDamageCard({ damage }: { damage: WheelsysVehicleDamage }) {
  return (
    <div className="damage-card">
      <div className="damage-header">
        <strong>{damage.damageType || "Unknown damage"}</strong>
        <span>{damage.relatedRentalNo}</span>
      </div>
      <div className="damage-meta">
        <span>Added: {damage.addedOn || "-"}</span>
        <span>Charge: {damage.chargeText || "-"}</span>
      </div>
      <div className="damage-preview-grid">
        {damage.attachments
          .filter((attachment) => attachment.previewable)
          .map((attachment) => (
            <img
              key={attachment.attachmentId}
              src={attachment.previewUrl}
              alt={attachment.filename}
              className="damage-preview-image"
            />
          ))}
      </div>
    </div>
  );
}

UI’da gösterilmesi gereken yapı:

Existing Vehicle Damages
[Damage Type]
RNT / R.A. number
Added date
Charge amount
[Photo preview thumbnails]

⸻

12. Return / Check-in İçindeki Kullanım

Return ekranında akış şu olmalıdır:

1. User scans plate veya return list item seçilir
2. rentalId resolve edilir
3. rental.aspx?entityId={rentalId} açılır
4. rdPlateNo_value üzerinden vehicleEntityId alınır
5. car.aspx?entityId={vehicleEntityId} açılır
6. Damage grid parse edilir
7. Attachment linkleri parse edilir
8. Foto preview URL’leri backend proxy üzerinden hazırlanır
9. Frontend’de Existing Damages listesi gösterilir
10. Yeni hasar giriliyorsa eski hasarlarla karşılaştırılır

⸻

13. Eski Hasar / Yeni Hasar Karşılaştırması

Yeni hasar kaydı girilirken uygulama eski hasarları kontrol etmelidir.

Karşılaştırma alanları:

Plate
Area
Element
Damage Type
Action
Memo keywords
Related photo similarity, optional future feature

Basit duplicate warning örneği:

export function findPossibleExistingDamage(
  newDamage: {
    area?: string | null;
    element?: string | null;
    damageType?: string | null;
  },
  existingDamages: WheelsysVehicleDamage[]
): WheelsysVehicleDamage[] {
  return existingDamages.filter((existing) => {
    const sameArea =
      newDamage.area &&
      existing.area &&
      newDamage.area.toLowerCase() === existing.area.toLowerCase();
    const sameElement =
      newDamage.element &&
      existing.element &&
      newDamage.element.toLowerCase() === existing.element.toLowerCase();
    const sameDamageType =
      newDamage.damageType &&
      existing.damageType &&
      existing.damageType.toLowerCase().includes(
        newDamage.damageType.toLowerCase()
      );
    return Boolean(sameArea || sameElement || sameDamageType);
  });
}

Frontend uyarısı:

This damage may already exist in Wheelsys history.
Please review previous damage records and photos before creating a new damage.

⸻

14. Eğer Ayrı GetDamages Endpoint Yakalanırsa

Şu an ilk yöntem HTML parse olmalıdır. Ancak Network HAR içinde ileride şu tarz bir endpoint yakalanırsa:

GetDamages
GetVehicleDamages
LoadDamages
GetDamageDocuments

o zaman entegrasyon şöyle yapılmalıdır:

1. Önce JSON/AJAX endpoint denenir
2. Başarılı olursa structured JSON kullanılır
3. Başarısız olursa car.aspx HTML parser fallback olarak çalışır

Önerilen yapı:

export async function getVehicleDamagesWithFallback(vehicleId: number) {
  try {
    const apiResult = await tryFetchVehicleDamagesFromAjaxEndpoint(vehicleId);
    if (apiResult && apiResult.length > 0) {
      return apiResult;
    }
  } catch {
    // fallback below
  }
  return await getVehicleDamageHistory(vehicleId);
}

⸻

15. Güvenlik Kuralları

1. Wheelsys cookie frontend’e gönderilmez.
2. Raw car.aspx HTML frontend’e gönderilmez.
3. Attachment URL frontend’e direkt verilmez.
4. Foto preview backend proxy üzerinden gösterilir.
5. Logs içinde cookie, token, customer PII ve raw HTML tutulmaz.
6. Sadece gerekli damage metadata saklanır.
7. Fotoğraflar kalıcı saklanacaksa internal storage kullanılır.
8. Preview URL kısa süreli veya backend-auth protected olmalıdır.

⸻

16. Cursor İçin Net Implementation Task

Implement a Wheelsys Vehicle Damage History Reader.

The system must load vehicle damage history from:

GET /ui/manage/master/car.aspx?entityId={vehicleEntityId}

The implementation must:

1. Resolve vehicleEntityId from rental context.
2. Load car.aspx with backend-only Wheelsys session cookies.
3. Parse the Damages tab from the returned HTML.
4. Extract damage rows:
   - damage number
   - plate
   - damage type
   - charge/rate text
   - related R.A. / RNT number
   - added date
5. Parse selected damage detail fields where available:
   - area
   - element
   - action
   - memo
   - recorded by
   - recorded on
   - labour hours
6. Parse attached documents.
7. Detect image attachments such as jpg, jpeg, png, webp.
8. Create backend preview URLs for image attachments.
9. Do not expose Wheelsys attachment URLs directly to frontend.
10. Return normalized JSON to the app.
11. Display records in the app as read-only Existing Vehicle Damages.
12. Show previous damage photo thumbnails/previews inside Checkout and Return screens.
13. Add fallback architecture so that if a dedicated GetDamages AJAX endpoint is captured later, it can be used before HTML parsing.

The final backend response should look like:

{
  "vehicleId": 299,
  "plateNo": "ZH676900",
  "damages": [
    {
      "damageId": "299-2",
      "damageNo": "2",
      "damageType": "#120-Painted Alloy/Steel Wheel - Scratch",
      "chargeText": "0,00 CHF",
      "relatedRentalNo": "RNT-4734",
      "addedOn": "29/01/2025",
      "attachments": [
        {
          "attachmentId": "299-2-0",
          "filename": "ZH676900.jpg",
          "fileType": "image",
          "previewable": true,
          "previewUrl": "/api/wheelsys/vehicles/299/damage-attachments/299-2-0/preview"
        }
      ],
      "source": "wheelsys.car.aspx"
    }
  ],
  "syncedAt": "2026-06-21T07:30:00.000Z"
}

Final rule:

The vehicle damage page shows historical vehicle-level damage records.
For Return / Check-in, always combine:
rental.aspx context + vehicle entityId + car.aspx damage history + attachment previews.