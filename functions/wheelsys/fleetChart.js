/**
 * WheelSys Fleet Chart fetch + normalize (read-only).
 * Cookie never logged or returned to clients.
 */
/* eslint-disable max-len */

const BASE_URL = "https://ch.wheelsys.greenmotion.com";
const FLEET_PAGE = "/ui/dashboards/fleetchart.aspx";
const FLEET_DATA_PATH = "/ui/dashboards/fleetchart.aspx/GetFleetchartData";

// Exact Chrome User-Agent — WheelSys may reject simplified UA strings.
const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) " +
  "Chrome/125.0.0.0 Safari/537.36";

const {buildFleetAuthCookie, cookiePresenceLog} = require("./cookieJar");

/** Browser-verified request body (Jun 13 – Jul 3 2026). */
const FLEET_CHART_REQUEST_BODY = {
  startDate: "/Date(1781308800000)/",
  endDate: "/Date(1783123199000)/",
  selectedStations: ",ZRH,",
  expandedResources: null,
  expandAll: true,
};

/**
 * @param {Date} date
 * @return {string}
 */
function toWheelSysDate(date) {
  return `/Date(${date.getTime()})/`;
}

/**
 * @return {Date}
 */
function startOfToday() {
  // WheelSys CH operates on Europe/Zurich wall clock.
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Zurich",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const y = Number(parts.find((p) => p.type === "year").value);
  const m = Number(parts.find((p) => p.type === "month").value);
  const d = Number(parts.find((p) => p.type === "day").value);
  // Approximate Zurich midnight using noon UTC trick.
  const utcNoon = Date.UTC(y, m - 1, d, 12, 0, 0, 0);
  const zurichHour = Number(new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Zurich",
    hour: "numeric",
    hour12: false,
  }).format(new Date(utcNoon)));
  const offsetHours = 12 - zurichHour;
  return new Date(Date.UTC(y, m - 1, d, offsetHours, 0, 0, 0));
}

/**
 * @param {Date} startDate
 * @return {Date}
 */
function defaultFleetEndDate(startDate) {
  const end = new Date(startDate);
  end.setDate(end.getDate() + 20);
  end.setHours(23, 59, 59, 999);
  return end;
}

/**
 * @param {string} html
 * @return {string}
 */
function stripHtml(html) {
  return String(html || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
}

/**
 * @param {string} text
 * @return {string}
 */
function decodeHtmlEntities(text) {
  return String(text || "")
      .replace(/&nbsp;/gi, " ")
      .replace(/&amp;/gi, "&")
      .replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">")
      .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
      .replace(/\s+/g, " ")
      .trim();
}

/**
 * @param {string} html
 * @return {string}
 */
function cleanCell(html) {
  return decodeHtmlEntities(stripHtml(html));
}

/**
 * @param {string} html
 * @return {string}
 */
function normalizePlate(html) {
  const raw = cleanCell(html);
  if (!raw) return "";
  return raw.replace(/\s+/g, " ").trim().toUpperCase();
}

/**
 * @param {string} value
 * @return {object}
 */
function parseHiddenColorFuel(value) {
  const raw = cleanCell(value);
  if (!raw) return {color: null, fuelType: null};
  const parts = raw.split("/").map((p) => p.trim()).filter(Boolean);
  if (parts.length >= 2) {
    return {color: parts[0], fuelType: parts[1]};
  }
  if (parts.length === 1) {
    if (/hybrid|diesel|petrol|electric/i.test(parts[0])) {
      return {color: null, fuelType: parts[0]};
    }
    return {color: parts[0], fuelType: null};
  }
  return {color: null, fuelType: null};
}

/**
 * @param {string} cssClass
 * @return {string}
 */
function vehicleStatusFromCss(cssClass) {
  const c = String(cssClass || "").toLowerCase();
  if (c.includes("fleetchart-rental-active-bgcolor")) return "on_rental";
  if (c.includes("fleetchart-non-revenue-running-bgcolor")) return "non_revenue";
  if (c.includes("fleetchart-non-revenue-closed-bgcolor")) return "non_revenue_closed";
  return "available";
}

/**
 * @param {object} event
 * @return {string}
 */
function eventTypeFromEvent(event) {
  const html = String(event.html || "").toLowerCase();
  const domain = Number(event.Domain);
  if (html.includes("fleetchart-event-main-rental") || domain === 101) return "rental";
  if (html.includes("fleetchart-event-main-booking") || domain === 100) return "booking";
  if (html.includes("fleetchart-event-main-non-revenue") || domain === 8) return "non_revenue";
  if (html.includes("fleetchart-event-insurance") || domain === 0) return "insurance";
  return "other";
}

/**
 * @param {object} event
 * @return {string}
 */
function eventStatusFromEvent(event) {
  const html = String(event.html || "").toLowerCase();
  if (html.includes("fleetchart-rental-active-bgcolor")) return "active";
  if (html.includes("fleetchart-rental-closed-bgcolor")) return "closed";
  if (html.includes("fleetchart-booking-bgcolor")) return "booking";
  if (html.includes("fleetchart-non-revenue-running-bgcolor")) return "active";
  if (html.includes("fleetchart-non-revenue-closed-bgcolor")) return "closed";
  return "unknown";
}

/**
 * @param {string} html
 * @param {string} className
 * @return {string}
 */
function extractSpanText(html, className) {
  const re = new RegExp(
      `class=['"]${className}['"][^>]*>([^<]*)`,
      "i",
  );
  const m = String(html || "").match(re);
  return m ? cleanCell(m[1]) : "";
}

/**
 * @param {string} html
 * @return {string}
 */
function extractDriverName(html) {
  return extractSpanText(html, "fleetchart-event-text-driver");
}

/**
 * @param {number|string} value
 * @return {number|null}
 */
function parseMileage(value) {
  const digits = String(value || "").replace(/[^\d]/g, "");
  if (!digits) return null;
  const n = Number(digits);
  return Number.isFinite(n) ? n : null;
}

/**
 * @param {object} parsed
 * @param {object} meta
 * @return {object}
 */
function normalizeFleetChartData(parsed, meta) {
  const resources = Array.isArray(parsed.resources) ? parsed.resources : [];
  const rawEvents = Array.isArray(parsed.events) ? parsed.events : [];
  const vehicles = [];
  const events = rawEvents.map((ev) => normalizeEvent(ev));

  for (const group of resources) {
    const groupCode = String(group.name || group.groupName || group.id || "").trim();
    const children = Array.isArray(group.children) ? group.children : [];
    for (const row of children) {
      const vehicleId = String(row.id || "").trim();
      if (!vehicleId || vehicleId.includes("_grp")) continue;
      const cols = Array.isArray(row.columns) ? row.columns : [];
      const hiddenMeta = parseHiddenColorFuel(cols[9] && cols[9].html);
      const vehicleEvents = events.filter((e) => e.vehicleId === vehicleId);
      const status = vehicleEvents.some((e) => e.status === "active" && e.type === "rental") ?
        "on_rental" :
        vehicleStatusFromCss(row.cssClass);
      vehicles.push({
        vehicleId,
        group: groupCode,
        plate: normalizePlate(cols[2] && cols[2].html),
        model: cleanCell(cols[3] && cols[3].html),
        station: cleanCell(cols[4] && cols[4].html) || meta.station,
        mileage: parseMileage(cleanCell(cols[5] && cols[5].html)),
        color: hiddenMeta.color,
        fuelType: hiddenMeta.fuelType,
        status,
        rawCssClass: String(row.cssClass || ""),
        events: vehicleEvents,
      });
    }
  }

  return {
    station: meta.station,
    startDate: meta.startDate.toISOString().slice(0, 10),
    endDate: meta.endDate.toISOString().slice(0, 10),
    vehiclesCount: vehicles.length,
    eventsCount: events.length,
    vehicles,
    events,
  };
}

/**
 * @param {object} ev
 * @return {object}
 */
function normalizeEvent(ev) {
  const html = String(ev.html || "");
  return {
    eventId: String(ev.id || ev.eventId || ""),
    vehicleId: String(ev.resource || ""),
    domain: ev.Domain != null ? Number(ev.Domain) : null,
    type: eventTypeFromEvent(ev),
    status: eventStatusFromEvent(ev),
    rentalEntityId: ev.RentalTable_Id != null ? Number(ev.RentalTable_Id) : null,
    recordId: ev.recordId != null ? String(ev.recordId) : null,
    start: ev.start ? String(ev.start) : null,
    end: ev.end ? String(ev.end) : null,
    stationFrom: ev.stationFrom ? String(ev.stationFrom) : null,
    initialCarGroup: ev.initialCarGroup ? String(ev.initialCarGroup) : null,
    driverName: extractDriverName(html),
    startTimeText: extractSpanText(html, "fleetchart-event-text-start-time"),
    endTimeText: extractSpanText(html, "fleetchart-event-text-end-time"),
    rawHtml: html.slice(0, 500),
  };
}

/**
 * @param {string} a
 * @param {string} b
 * @return {boolean}
 */
function platesEqual(a, b) {
  // Canonical comparison: strip every separator (space, hyphen, dot) so
  // "ZH 123 123" == "ZH123123" == "ZH-123123". Mirrors iOS WheelSysPlateNormalizer.
  const norm = (v) =>
    String(v || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return norm(a) === norm(b) && norm(a).length > 0;
}

/**
 * Resolve WheelSys rental.aspx entityId from Fleet Chart by plate.
 * Uses active rental event RentalTable_Id (e.g. ZG87464 → 19525, not stale 18781).
 * @param {object} fleetData normalized fleet from normalizeFleetChartData
 * @param {string} plate
 * @return {number|null}
 */
function findRentalEntityIdByPlate(fleetData, plate) {
  const vehicles = Array.isArray(fleetData && fleetData.vehicles) ?
    fleetData.vehicles : [];
  const vehicle = vehicles.find((v) => platesEqual(v.plate, plate));
  if (!vehicle) return null;
  const events = Array.isArray(vehicle.events) ? vehicle.events : [];
  const activeRental = events.find(
      (e) => e.type === "rental" && e.status === "active" && e.rentalEntityId,
  );
  if (activeRental) return activeRental.rentalEntityId;
  const anyRental = events.find((e) => e.type === "rental" && e.rentalEntityId);
  return anyRental ? anyRental.rentalEntityId : null;
}

/**
 * @param {string} text
 * @return {string}
 */
function safeResponsePreview(text) {
  // Keep raw (no whitespace strip) so we can read ASP.NET error HTML.
  return String(text || "").slice(0, 1500);
}

/**
 * POST Fleet Chart — matches Chrome DevTools request exactly.
 * Cookie is pre-filtered to .wheelsys + __Secure-SID by the caller.
 * @param {string} authCookie  already-built ".wheelsys=…; __Secure-SID=…"
 * @param {string} pageUrl
 * @param {string} dataUrl
 * @param {object} body
 * @return {Promise<object>}
 */
async function postFleetChartRequest(authCookie, pageUrl, dataUrl, body) {
  const requestBody = JSON.stringify(body);

  const headers = {
    "Accept": "*/*",
    "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7,de;q=0.6",
    "Cache-Control": "no-cache",
    "Content-Type": "application/json; charset=UTF-8",
    "Origin": BASE_URL,
    "Pragma": "no-cache",
    "Referer": pageUrl,
    "User-Agent": UA,
    "X-Requested-With": "XMLHttpRequest",
    "Cookie": authCookie,
  };

  console.info("[WheelSysFleet] outgoing request", {
    url: dataUrl,
    method: "POST",
    payload: body,
    contentType: headers["Content-Type"],
    origin: headers["Origin"],
    referer: headers["Referer"],
    userAgent: UA.slice(0, 40),
    ...cookiePresenceLog(authCookie),
  });

  const res = await fetch(dataUrl, {
    method: "POST",
    headers,
    body: requestBody,
  });

  const text = String(await res.text());
  let outer = null;
  try {
    outer = JSON.parse(text);
  } catch (_) {
    outer = null;
  }

  const preview = safeResponsePreview(text);
  console.info("[WheelSysFleet] WheelSys response", {
    status: res.status,
    contentType: res.headers.get("content-type") || null,
    rawType: outer !== null ? "json" : "text",
    dSuccess: outer && outer.d ? outer.d.success : null,
    dMessage: outer && outer.d ? outer.d.message : null,
    rawPreview: preview,
  });

  return {res, text, outer, preview};
}

/**
 * @param {string} wheelsysCookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchWheelSysFleetChart({
  wheelsysCookie,
  station = "ZRH",
}) {
  if (!wheelsysCookie) {
    const err = new Error("Missing WheelSys session.");
    err.code = "WHEELSYS_SESSION_MISSING";
    throw err;
  }

  const authCookie = buildFleetAuthCookie(wheelsysCookie);
  if (!authCookie) {
    const err = new Error(
        "WheelSys cookie missing .wheelsys or __Secure-SID.",
    );
    err.code = "WHEELSYS_SESSION_MISSING";
    throw err;
  }

  const pageUrl = `${BASE_URL}${FLEET_PAGE}`;
  const dataUrl = `${BASE_URL}${FLEET_DATA_PATH}`;
  const startMs = 1781308800000;
  const endMs = 1783123199000;
  const start = new Date(startMs);
  const end = new Date(endMs);

  // selectedStations must be ",ZRH," not "ZRH".
  const body = {
    ...FLEET_CHART_REQUEST_BODY,
    selectedStations: `,${station},`,
  };

  console.info("[WheelSysFleet] start", {
    endpoint: dataUrl,
    station,
    bodyKeys: Object.keys(body),
    selectedStations: body.selectedStations,
    expandedResources: body.expandedResources,
    expandAll: body.expandAll,
    ...cookiePresenceLog(authCookie),
  });

  const {res, text, outer, preview} = await postFleetChartRequest(
      authCookie, pageUrl, dataUrl, body,
  );

  if (outer && outer.d && outer.d.success === true && outer.d.data != null) {
    let inner;
    try {
      inner = typeof outer.d.data === "string" ?
        JSON.parse(outer.d.data) : outer.d.data;
    } catch (_) {
      const err = new Error("WheelSys Fleet Chart inner data parse failed.");
      err.code = "WHEELSYS_FLEET_INVALID_RESPONSE";
      err.debugPreview = preview;
      throw err;
    }

    const resourcesCount = Array.isArray(inner.resources) ?
      inner.resources.length : 0;
    const eventsCount = Array.isArray(inner.events) ?
      inner.events.length : 0;

    console.info("[WheelSysFleet] parsed success", {
      resourcesCount,
      eventsCount,
    });

    const normalized = normalizeFleetChartData(
        inner, {station, startDate: start, endDate: end},
    );
    return {
      ...normalized,
      resources: inner.resources || [],
      events: inner.events || [],
      resourcesCount,
    };
  }

  if (/login|sign.?in/i.test(text) &&
      !text.includes("\"success\":true")) {
    const err = new Error(
        "WheelSys session expired. Reopen WheelSys login in the app.",
    );
    err.code = "WHEELSYS_SESSION_EXPIRED";
    err.debugPreview = preview;
    throw err;
  }

  if (res.status === 401 || res.status === 403) {
    const err = new Error(
        "WheelSys session expired. Reopen WheelSys login in the app.",
    );
    err.code = "WHEELSYS_SESSION_EXPIRED";
    err.debugPreview = preview;
    throw err;
  }

  const wheelSysMessage =
    (outer && outer.d && outer.d.message) ||
    (outer && outer.Message) || null;
  const lastMessage =
    wheelSysMessage || "WheelSys Fleet Chart request failed.";

  console.error("[WheelSysFleet] request failed", {
    httpStatus: res.status,
    wheelSysMessage,
    dSuccess: outer && outer.d ? outer.d.success : null,
    responsePreview: preview,
  });

  const err = new Error(lastMessage);
  err.code = "WHEELSYS_FLEET_ERROR";
  err.httpStatus = res.status;
  err.debugPreview = preview;
  err.wheelSysMessage = wheelSysMessage;
  throw err;
}

module.exports = {
  BASE_URL,
  FLEET_PAGE,
  FLEET_CHART_REQUEST_BODY,
  toWheelSysDate,
  startOfToday,
  defaultFleetEndDate,
  stripHtml,
  decodeHtmlEntities,
  normalizePlate,
  platesEqual,
  parseHiddenColorFuel,
  normalizeFleetChartData,
  findRentalEntityIdByPlate,
  fetchWheelSysFleetChart,
};
