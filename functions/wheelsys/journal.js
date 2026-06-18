/**
 * WheelSys Journal rows from Fleet Chart
 * (checkouts, returns, unassigned bookings).
 */
/* eslint-disable max-len */

const {
  fetchWheelSysFleetChart,
  startOfToday,
  defaultFleetEndDate,
} = require("./fleetChart");
const {
  buildOperationalDate,
  wheelsysFetchJson,
  parseWheelsysWebMethodObject,
  pickField,
  normalizePlate,
  BASE_URL,
  WheelsysClientError,
  ERR,
} = require("./client");
const {pickResNoFromRow, pickAgentConfirmationFromRow} = require("./resCodeHelpers");

const ZURICH_TZ = "Europe/Zurich";
const JOURNAL_PAGE = "/ui/dashboards/journal.aspx";
const JOURNAL_DETAILS_PATH = "/ui/dashboards/journal.aspx/GetDetailsRecords";

/**
 * @param {Date} date
 * @return {string} yyyy-MM-dd in Zurich
 */
function formatZurichDay(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: ZURICH_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

/**
 * @param {string} raw
 * @param {string} timeText
 * @return {Date|null}
 */
function parseFleetInstant(raw, timeText = "") {
  const trimmed = String(raw || "").trim();
  if (trimmed.startsWith("/Date(")) {
    let inner = trimmed.slice(6);
    if (inner.endsWith(")/")) inner = inner.slice(0, -2);
    else if (inner.endsWith(")")) inner = inner.slice(0, -1);
    const numPart = inner.split(/[+-]/)[0];
    const ms = Number(numPart);
    if (Number.isFinite(ms)) return new Date(ms);
  }
  const candidates = [trimmed, String(timeText || "").trim()].filter(Boolean);
  for (const c of candidates) {
    if (/^\d{4}-\d{2}-\d{2}T/.test(c) && !/[zZ]|[+-]\d{2}:\d{2}$/.test(c)) {
      const m = c.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
      if (m) {
        const utcNoon = Date.UTC(+m[1], +m[2] - 1, +m[3], 12, 0, 0);
        const zurichHour = Number(new Intl.DateTimeFormat("en-GB", {
          timeZone: ZURICH_TZ,
          hour: "numeric",
          hour12: false,
        }).format(new Date(utcNoon)));
        const offsetHours = 12 - zurichHour;
        return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4] - offsetHours, +m[5], 0));
      }
    }
    const d = new Date(c);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return null;
}

/**
 * @param {object} event
 * @return {boolean}
 */
function isJournalEvent(event) {
  return event.type === "rental" || event.type === "booking";
}

/**
 * @param {object} fleetData
 * @param {string} selectedDay yyyy-MM-dd Zurich
 * @param {string} stationFilter
 * @return {{checkout: object[], returns: object[]}}
 */
function buildJournalRows(fleetData, selectedDay, stationFilter = "all") {
  const vehicles = Array.isArray(fleetData.vehicles) ? fleetData.vehicles : [];
  const events = Array.isArray(fleetData.events) ? fleetData.events : [];
  const vehicleById = new Map(vehicles.map((v) => [v.vehicleId, v]));

  const journalEvents = events.filter((e) => isJournalEvent(e) && e.rentalEntityId);
  const checkout = [];
  const returns = [];

  for (const event of journalEvents) {
    const vehicle = vehicleById.get(event.vehicleId);
    const station = (vehicle && vehicle.station) || event.stationFrom || "ZRH";
    if (stationFilter !== "all") {
      const a = String(station).toUpperCase();
      const b = String(stationFilter).toUpperCase();
      if (a !== b && !a.startsWith(b) && !b.startsWith(a)) continue;
    }

    const startDate = parseFleetInstant(event.start, event.startTimeText);
    const endDate = parseFleetInstant(event.end, event.endTimeText);
    const entityId = Number(event.rentalEntityId);
    const group = event.initialCarGroup || (vehicle && vehicle.group) || "";
    const plate = (vehicle && vehicle.plate) || "";
    const isUnassigned = event.type === "booking" || !plate;

    const base = {
      rentalEntityId: entityId,
      bookingEntityId: entityId,
      eventType: event.type,
      plate,
      normalizedPlate: plate.replace(/[^A-Z0-9]/gi, "").toUpperCase(),
      vehicleGroup: group,
      model: (vehicle && vehicle.model) || "",
      station,
      resourceId: event.vehicleId || "",
      driverNameFromFleet: event.driverName || "",
      isUnassigned,
      isAssigned: !isUnassigned && Boolean(plate),
    };

    if (startDate && formatZurichDay(startDate) === selectedDay) {
      checkout.push({
        ...base,
        kind: "checkout",
        eventDateTime: startDate.toISOString(),
        eventStart: startDate.toISOString(),
        eventEnd: endDate ? endDate.toISOString() : null,
      });
    }
    if (endDate && formatZurichDay(endDate) === selectedDay) {
      returns.push({
        ...base,
        kind: "return",
        eventDateTime: endDate.toISOString(),
        eventStart: startDate ? startDate.toISOString() : null,
        eventEnd: endDate.toISOString(),
      });
    }
  }

  const sortFn = (a, b) => new Date(a.eventDateTime) - new Date(b.eventDateTime);
  checkout.sort(sortFn);
  returns.sort(sortFn);

  return {
    checkout: checkout.map((row, i) => ({...row, rowNumber: i + 1})),
    returns: returns.map((row, i) => ({...row, rowNumber: i + 1})),
    vehiclesCount: vehicles.length,
    rentalEventsCount: journalEvents.length,
  };
}

/**
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchJournalData(cookie, {selectedDay, station = "ZRH"}) {
  const day = String(selectedDay || formatZurichDay(startOfToday())).slice(0, 10);
  const start = startOfToday();
  const end = defaultFleetEndDate(start);
  const fleet = await fetchWheelSysFleetChart({
    wheelsysCookie: cookie,
    station,
    startDate: start,
    endDate: end,
  });
  const built = buildJournalRows(fleet, day, station === "ZRH" ? "all" : station);
  return {
    selectedDay: day,
    station,
    source: "fleet_chart",
    ...built,
    fleetMeta: {
      startDate: fleet.startDate,
      endDate: fleet.endDate,
      vehiclesCount: fleet.vehiclesCount,
      eventsCount: fleet.eventsCount,
    },
  };
}

/**
 * @param {*} value
 * @return {number|null} positive entity id or null
 */
function toPositiveEntityId(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/**
 * Extract rental/booking entity ids from journal API row fields.
 * @param {object} row
 * @return {object} rentalEntityId, bookingEntityId, domain
 */
function extractJournalEntityIds(row) {
  const domainRaw = pickField(row, "Domain", "domain");
  const domain = domainRaw != null ? Number(domainRaw) : null;
  const isBooking = domain === 100;
  const entityId = pickField(row, "EntityId", "entityId", "Id", "id");
  const rentalTableId = pickField(
      row, "RentalTable_Id", "rentalTable_Id", "RentalTableId",
  );
  const bookingTableId = pickField(
      row, "BookingTable_Id", "bookingTable_Id", "BookingTableId",
  );

  let rentalEntityId = toPositiveEntityId(rentalTableId);
  let bookingEntityId = toPositiveEntityId(bookingTableId);

  if (isBooking) {
    if (!bookingEntityId) bookingEntityId = toPositiveEntityId(entityId);
  } else if (!rentalEntityId) {
    rentalEntityId = toPositiveEntityId(entityId);
  }

  if (!rentalEntityId && !bookingEntityId) {
    const fallback = toPositiveEntityId(entityId);
    if (fallback) {
      if (isBooking) bookingEntityId = fallback;
      else rentalEntityId = fallback;
    }
  }

  return {rentalEntityId, bookingEntityId, domain};
}

/**
 * @param {object} row
 * @return {object}
 */
function normalizeJournalCheckout(row) {
  const plate = String(pickField(row, "PlateNo", "plateno", "Plate") || "");
  const ids = extractJournalEntityIds(row);
  const domain = ids.domain != null ? ids.domain : pickField(row, "Domain", "domain");
  // displaydocno = real RES number (DisplayDocNo field from Wheelsys, e.g. RES-17694)
  // confirmationno = external agent confirmation (ConfirmationNo field, e.g. JIG(A)-...)
  // Never put confirmationno into displaydocno.
  const rawDisplayDoc = String(pickField(row, "DisplayDocNo", "displaydocno", "DocNo") || "").trim();
  const rawConfNo = String(pickField(row, "ConfirmationNo", "confirmationno", "ConfNo") || "").trim();
  return {
    displaydocno: rawDisplayDoc,
    confirmationno: rawConfNo || pickAgentConfirmationFromRow(row),
    resno: pickResNoFromRow(row),
    drivername: String(pickField(row, "DriverName", "drivername", "Customer") || ""),
    plateno: plate,
    cargroup: String(pickField(row, "CarGroup", "cargroup", "Group") || ""),
    fuel: pickField(row, "Fuel", "fuel", "Tank"),
    datefrom: pickField(row, "DateFrom", "datefrom"),
    dateto: pickField(row, "DateTo", "dateto"),
    status: pickField(row, "Status", "status"),
    agent: String(pickField(row, "Agent", "agent", "Booker") || ""),
    domain,
    rentalEntityId: ids.rentalEntityId,
    bookingEntityId: ids.bookingEntityId,
    isUnassigned: domain === 100 || !plate,
    raw: row,
  };
}

/**
 * @param {object} row
 * @return {object}
 */
function normalizeJournalCheckin(row) {
  const plate = String(pickField(row, "PlateNo", "plateno", "Plate") || "");
  const ids = extractJournalEntityIds(row);
  const domain = ids.domain != null ? ids.domain : pickField(row, "Domain", "domain");
  const rawDisplayDoc = String(pickField(row, "DisplayDocNo", "displaydocno", "DocNo") || "").trim();
  const rawConfNo = String(pickField(row, "ConfirmationNo", "confirmationno", "ConfNo") || "").trim();
  return {
    displaydocno: rawDisplayDoc,
    confirmationno: rawConfNo || pickAgentConfirmationFromRow(row),
    resno: pickResNoFromRow(row),
    plateno: plate,
    mileage: pickField(row, "Mileage", "mileage", "Km"),
    fuel: pickField(row, "Fuel", "fuel", "Tank"),
    vehicleEntityId: pickField(row, "CarTable_Id", "carTable_Id", "CarId", "carId"),
    dateto: pickField(row, "DateTo", "dateto"),
    datefrom: pickField(row, "DateFrom", "datefrom"),
    drivername: String(pickField(row, "DriverName", "drivername", "Customer") || ""),
    domain,
    rentalEntityId: ids.rentalEntityId,
    bookingEntityId: ids.bookingEntityId,
    raw: row,
  };
}

/**
 * @param {object} row
 * @return {object}
 */
function normalizeJournalAvailableVehicle(row) {
  const plate = String(pickField(row, "PlateNo", "plateno", "Plate", "plate") || "");
  return {
    vehicleEntityId: pickField(row, "id", "Id", "CarTable_Id", "carTable_Id", "CarId"),
    plate,
    normalizedPlate: normalizePlate(plate),
    group: String(pickField(row, "CarGroup", "cargroup", "Group", "group") || ""),
    model: String(pickField(row, "Model", "model", "ModelName") || ""),
    mileage: pickField(row, "Mileage", "mileage", "Km"),
    fuel: pickField(row, "Fuel", "fuel", "Tank"),
    availableUntil: pickField(row, "AvailableUntil", "availableUntil", "DateTo"),
    lastCheckin: pickField(row, "LastCheckin", "lastCheckin", "LastCheckIn"),
    active: Boolean(pickField(row, "Active", "active")),
    inUse: Boolean(pickField(row, "InUse", "inUse", "Inuse")),
    hardHold: Boolean(pickField(row, "HardHold", "hardHold")),
    onService: Boolean(pickField(row, "OnService", "onService", "Service")),
    vin: String(pickField(row, "VIN", "vin", "Vin") || ""),
    raw: row,
  };
}

/**
 * @param {*} value
 * @return {Array}
 */
function asRowArray(value) {
  if (Array.isArray(value)) return value;
  if (value && Array.isArray(value.rows)) return value.rows;
  if (value && Array.isArray(value.data)) return value.data;
  return [];
}

/**
 * Primary Journal API — journal.aspx/GetDetailsRecords.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchJournalSnapshot(cookie, {selectedDate, station = "ZRH"}) {
  const st = String(station || "ZRH").toUpperCase();
  const dt = buildOperationalDate(selectedDate || new Date());
  const payload = {
    dt,
    stations: st,
  };

  const pageUrl = `${BASE_URL}${JOURNAL_PAGE}`;
  const {outer} = await wheelsysFetchJson(cookie, JOURNAL_DETAILS_PATH, payload, {
    referer: pageUrl,
  });

  const parsed = parseWheelsysWebMethodObject(outer);
  const checkOutsRaw = asRowArray(
      parsed.checkOuts || parsed.checkouts || parsed.CheckOuts,
  );
  const checkInsRaw = asRowArray(
      parsed.checkIns || parsed.checkins || parsed.CheckIns || parsed.returns,
  );
  const avCarsRaw = asRowArray(
      parsed.avCars || parsed.availableVehicles || parsed.AvCars || parsed.available,
  );

  return {
    selectedDate: dt.slice(0, 10),
    station: st,
    source: "journal_api",
    checkOuts: checkOutsRaw.map(normalizeJournalCheckout),
    checkIns: checkInsRaw.map(normalizeJournalCheckin),
    availableVehicles: avCarsRaw.map(normalizeJournalAvailableVehicle),
    raw: {
      checkOuts: checkOutsRaw,
      checkIns: checkInsRaw,
      avCars: avCarsRaw,
    },
  };
}

/**
 * Journal snapshot with fleet-chart fallback when API is empty or fails.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchJournalSnapshotWithFallback(cookie, opts = {}) {
  try {
    const snapshot = await fetchJournalSnapshot(cookie, opts);
    const hasRows = snapshot.checkOuts.length ||
      snapshot.checkIns.length ||
      snapshot.availableVehicles.length;
    if (hasRows) return snapshot;
  } catch (e) {
    if (e instanceof WheelsysClientError &&
        (e.code === ERR.SESSION_EXPIRED || e.code === ERR.PARSE_FAILED)) {
      throw e;
    }
    console.warn("fetchJournalSnapshot primary failed, using fleet chart", e.message);
  }

  const fleetJournal = await fetchJournalData(cookie, {
    selectedDay: opts.selectedDate,
    station: opts.station,
  });
  return {
    selectedDate: fleetJournal.selectedDay,
    station: fleetJournal.station,
    source: "fleet_chart_fallback",
    checkOuts: fleetJournal.checkout.map((row) => ({
      displaydocno: row.rentalNumber || String(row.rentalEntityId || ""),
      confirmationno: "",
      drivername: row.driverNameFromFleet || "",
      plateno: row.plate || "",
      cargroup: row.vehicleGroup || "",
      fuel: null,
      datefrom: row.eventStart,
      dateto: row.eventEnd,
      status: row.eventType,
      agent: "",
      domain: row.isUnassigned ? 100 : null,
      rentalEntityId: row.isUnassigned ? null : row.rentalEntityId,
      bookingEntityId: row.isUnassigned ? row.bookingEntityId : null,
      isUnassigned: row.isUnassigned,
      raw: row,
    })),
    checkIns: fleetJournal.returns.map((row) => ({
      displaydocno: row.rentalNumber || String(row.rentalEntityId || ""),
      plateno: row.plate || "",
      mileage: null,
      fuel: null,
      vehicleEntityId: row.resourceId || null,
      dateto: row.eventEnd,
      drivername: row.driverNameFromFleet || "",
      rentalEntityId: row.rentalEntityId,
      raw: row,
    })),
    availableVehicles: [],
    fleetMeta: fleetJournal.fleetMeta,
    checkout: fleetJournal.checkout,
    returns: fleetJournal.returns,
  };
}

module.exports = {
  formatZurichDay,
  buildJournalRows,
  fetchJournalData,
  fetchJournalSnapshot,
  fetchJournalSnapshotWithFallback,
  extractJournalEntityIds,
  normalizeJournalCheckout,
  normalizeJournalCheckin,
  normalizeJournalAvailableVehicle,
};
