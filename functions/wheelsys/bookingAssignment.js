/**
 * WheelSys booking vehicle assignment:
 * QueryData → canUseCar → CalcRates → booking save.
 */
/* eslint-disable max-len */

const cheerio = require("cheerio");
const {
  BASE_URL,
  parseFormToPayload,
  parseWheelsysResponse,
  formatMileageText,
  formatTankText,
  formatTankHidden,
  extractRentalFieldSnapshot,
  fetchRentalPage,
} = require("./checkinSync");
const {searchBookingsList, findBookingEntityIdsFromList, warmBookingViewPage} = require("./bookingsList");
const {looksLikeResNo} = require("./resCodeHelpers");

const BOOKING_PATH = "/ui/manage/master/booking.aspx";
const RENTAL_CALC_PATH = "/ui/manage/master/rental.aspx/CalcRates";
const CAR_SEARCH_PATH = "/ui/dialogs/RentalCarSearch.aspx/QueryData";
const CAN_USE_CAR_PATH = "/api/entities/rentalsupport/car/canusecar";

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

const UUID_RE = "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}";

/**
 * @param {string} html
 * @return {string}
 */
function extractCacheKey(html) {
  const h = String(html || "");
  const patterns = [
    new RegExp(`cacheKey['"]\\s*[:=]\\s*['"](${UUID_RE})['"]`, "i"),
    new RegExp(`CacheKey['"]\\s*[:=]\\s*['"](${UUID_RE})['"]`),
    new RegExp(`"cacheKey"\\s*:\\s*"(${UUID_RE})"`, "i"),
    new RegExp(`"CacheKey"\\s*:\\s*"(${UUID_RE})"`),
    new RegExp(`rentalCacheKey['"]\\s*[:=]\\s*['"](${UUID_RE})['"]`, "i"),
    new RegExp(`"rentalCacheKey"\\s*:\\s*"(${UUID_RE})"`, "i"),
    new RegExp(`data-cachekey\\s*=\\s*['"](${UUID_RE})['"]`, "i"),
    new RegExp(
        `RentalData[\\s\\S]{0,800}?["']?(?:cacheKey|CacheKey)["']?\\s*:\\s*["'](${UUID_RE})["']`,
        "i",
    ),
  ];
  for (const pattern of patterns) {
    const m = h.match(pattern);
    if (m && m[1]) return m[1];
  }

  const $ = cheerio.load(html);
  const hid = String(
      $("input[name='cacheKey'], #cacheKey, input[name='rentalCacheKey']").attr("value") || "",
  ).trim();
  if (hid) return hid;

  const dataAttr = String($("[data-cachekey]").first().attr("data-cachekey") || "").trim();
  if (dataAttr) return dataAttr;

  return "";
}

/**
 * Warm booking rental panel so WheelSys emits cacheKey, then re-fetch page.
 * @param {string} cookie
 * @param {number|string} entityId
 * @param {object} page
 * @return {Promise<string>}
 */
async function ensureBookingCacheKey(cookie, entityId, page) {
  let key = String((page && page.fields && page.fields.cacheKey) || "").trim();
  if (!key && page && page.html) {
    key = extractCacheKey(page.html);
  }
  if (key) return key;

  const id = String(entityId).trim();
  const pageUrl = `${BASE_URL}${BOOKING_PATH}?entityId=${id}`;
  const warmTargets = ["rentalPanel", "rdGroup_combo"];

  for (const eventTarget of warmTargets) {
    const payload = parseFormToPayload(page.html);
    const group = String(
        (page.fields && page.fields.carGroup) ||
        (page.fields && page.fields.groupInv) ||
        "",
    ).trim();
    if (group && group !== "-") {
      payload.set("rdGroup_combo", group);
      payload.set("rdGroupRes_text", group);
    }
    payload.set(
        "ctl00$ctl00$ctl00$coreBody$ScriptManager",
        `ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|${eventTarget}`,
    );
    payload.set("__EVENTTARGET", eventTarget);
    payload.set("__ASYNCPOST", "true");

    try {
      const postRes = await fetch(pageUrl, {
        method: "POST",
        headers: {
          "Cookie": cookie,
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          "X-MicrosoftAjax": "Delta=true",
          "X-Requested-With": "XMLHttpRequest",
          "Origin": BASE_URL,
          "Referer": pageUrl,
          "User-Agent": UA,
        },
        body: payload.toString(),
      });
      const postText = await postRes.text();
      const postKey = extractWarmCacheKey(postText);
      if (postKey) return postKey;
    } catch (_) {
      // try next warm target
    }

    const refreshed = await fetchBookingPage(cookie, id);
    key = String(refreshed.fields.cacheKey || extractCacheKey(refreshed.html) || "").trim();
    if (key) return key;
  }

  throw new Error("Booking cacheKey not found — reload booking page.");
}

/**
 * Extract cache key directly from WheelSys async partial response.
 * @param {string} responseText
 * @return {string}
 */
function extractWarmCacheKey(responseText) {
  const raw = String(responseText || "");
  if (!raw) return "";

  const normalized = raw
      .replace(/\\u0022/g, "\"")
      .replace(/\\u0027/g, "'")
      .replace(/\\\//g, "/");

  const direct = extractCacheKey(normalized) || extractCacheKey(raw);
  if (direct) return direct;

  const fieldMatch = normalized.match(
      new RegExp(`(?:^|\\|)(?:cacheKey|CacheKey|rentalCacheKey)\\|(${UUID_RE})(?:\\||$)`, "i"),
  );
  if (fieldMatch && fieldMatch[1]) return fieldMatch[1];

  return "";
}

/**
 * @param {string} dateText dd/MM/yyyy
 * @param {string} timeText HH:mm
 * @return {string|null} ISO local Wheelsys style 2026-06-17T10:30:00
 */
function combineDateTimeLocal(dateText, timeText) {
  const d = String(dateText || "").trim();
  const t = String(timeText || "").trim();
  if (!d) return null;
  const dm = d.match(/^(\d{1,2})[./](\d{1,2})[./](\d{4})$/);
  if (!dm) return null;
  const day = dm[1].padStart(2, "0");
  const month = dm[2].padStart(2, "0");
  const year = dm[3];
  let hour = "00";
  let minute = "00";
  const tm = t.match(/^(\d{1,2}):(\d{2})/);
  if (tm) {
    hour = tm[1].padStart(2, "0");
    minute = tm[2];
  }
  return `${year}-${month}-${day}T${hour}:${minute}:00`;
}

/**
 * @param {string} localIso
 * @return {string|null} UTC ISO for canusecar
 */
function localIsoToUtcIso(localIso) {
  if (!localIso) return null;
  const m = localIso.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/);
  if (!m) return null;
  const utcNoon = Date.UTC(+m[1], +m[2] - 1, +m[3], 12, 0, 0);
  const zurichHour = Number(new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Zurich",
    hour: "numeric",
    hour12: false,
  }).format(new Date(utcNoon)));
  const offsetHours = 12 - zurichHour;
  const utc = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4] - offsetHours, +m[5], +m[6]));
  return utc.toISOString().replace(/\.\d{3}Z$/, ".000Z");
}

/**
 * @param {string} html
 * @return {object}
 */
function extractBookingFieldSnapshot(html) {
  const base = extractRentalFieldSnapshot(html);
  const $ = cheerio.load(html);
  const pick = (name) => {
    const el = $(`[name="${name}"]`).first();
    if (!el.length) return "";
    const val = String(el.attr("value") || el.text() || "").trim();
    const pre = String(el.attr("data-prevalue") || "").trim();
    return pre || val;
  };
  return {
    ...base,
    stationFrom: pick("rdStationFrom_combo"),
    stationTo: pick("rdStationTo_combo"),
    dateFrom: pick("rdDateFrom_text"),
    timeFrom: pick("rdTimeFrom_text"),
    dateTo: pick("rdDateTo_text"),
    timeTo: pick("rdTimeTo_text"),
    carGroup: pick("rdGroup_combo") || pick("rdGroupRes_text"),
    groupInv: pick("rdGroupInv_combo"),
    usageType: pick("rdUsageType") || pick("rdUsageType_combo") || "1",
    agent: pick("rdAgent_value") || pick("rdAgent_combo"),
    driver: pick("rdDriver_value") || pick("rdDriver_combo"),
    rateId: pick("rdRateId_combo") || pick("rdRateCode_combo"),
    rateCode: pick("rdRateCode_combo"),
    resModeId: pick("rdResModeId") || pick("rdResMode_combo"),
    carId: pick("rdPlateNo_value"),
    modelId: pick("rdModel_value"),
    modelText: pick("rdModel_text"),
    cacheKey: extractCacheKey(html),
    extensionRate: pick("rdExtensionRate_hidden"),
    rentalRate: pick("rdRPD_hidden"),
    rentalCharge: pick("rdRentalCharge_hidden"),
    insuranceCharge: pick("rdInsurance_hidden"),
    extraCharge: pick("rdExtras_hidden"),
    fuelPolicy: pick("rdFuelPolicy_combo"),
    fuelCharge: pick("rdFuel_hidden"),
    chargeNet: pick("rdChargeNet_hidden"),
    tax1Rate: pick("rdTax1Perc_hidden"),
    tax1Amount: pick("rdTax1Amount_hidden"),
    chargeTotal: pick("rdChargeTotal_hidden"),
    voucherValue: pick("rdVoucherVal_hidden"),
    balance: pick("rdBal_hidden"),
    total2: pick("rdTotal2_hidden"),
    localTotal: pick("rdLTotal_hidden"),
    locationFrom: pick("rdLocationFrom_text"),
    locationTo: pick("rdLocationTo_text"),
    corporate: pick("rdCorporate_value") || pick("rdCorporate_combo"),
    driver2: pick("rdDriver2_value"),
    driver3: pick("rdDriver3_value"),
    driver4: pick("rdDriver4_value"),
    brand: pick("rdBrand_combo"),
    rentalType: pick("rdRentalType_combo") || "R",
    status: pick("rdStatus_hidden") || "1",
  };
}

/**
 * @param {string} html
 * @return {boolean}
 */
function isValidBookingPage(html) {
  const h = String(html || "");
  if (/login|sign.?in/i.test(h) && !h.includes("rdGroup_combo")) return false;
  return h.includes("rdGroup_combo") ||
    h.includes("rdGroupRes_text") ||
    h.includes("rentalPanel");
}

/**
 * @param {string} html rental.aspx HTML
 * @return {string|null}
 */
function extractBookingIdFromRentalHtml(html) {
  const h = String(html || "");
  const linkMatch = h.match(/booking\.aspx\?entityId=(\d+)/i);
  if (linkMatch) return linkMatch[1];
  const $ = cheerio.load(h);
  const hid = String(
      $("input[name*='BookingTable_Id'], #BookingTable_Id").first().attr("value") || "",
  ).trim();
  return /^\d+$/.test(hid) ? hid : null;
}

/**
 * @param {string} cookie
 * @param {number|string|null|undefined} hint
 * @param {object} opts
 * @return {Promise<{entityId: string, source: string, resNo: string}>}
 */
async function resolveBookingEntityId(cookie, hint, opts = {}) {
  const hintId = hint != null ? String(hint).trim() : "";
  const resNo = String(opts.resNo || "").trim();
  const displayDocNo = String(opts.displayDocNo || "").trim();
  const station = String(opts.station || "ZRH").toUpperCase();

  const listIds = await findBookingEntityIdsFromList(cookie, {
    resNo,
    displayDocNo,
    station,
  });
  if (listIds.length) {
    const id = listIds[0];
    try {
      const page = await fetchBookingPage(cookie, id);
      if (isValidBookingPage(page.html)) {
        return {
          entityId: id,
          source: "bookings_list",
          resNo: String(page.fields.resNo || resNo || ""),
        };
      }
    } catch (_) {
      // fall through
    }
  }

  if (hintId && /^\d+$/.test(hintId)) {
    const [bookingTry, rentalTry] = await Promise.allSettled([
      fetchBookingPage(cookie, hintId),
      fetchRentalPage(cookie, hintId),
    ]);

    if (bookingTry.status === "fulfilled" &&
        isValidBookingPage(bookingTry.value.html)) {
      return {
        entityId: hintId,
        source: "hint_booking",
        resNo: String(bookingTry.value.fields.resNo || resNo || ""),
      };
    }

    if (rentalTry.status === "fulfilled") {
      const linkedId = extractBookingIdFromRentalHtml(rentalTry.value.html);
      if (linkedId) {
        const linked = await fetchBookingPage(cookie, linkedId);
        if (isValidBookingPage(linked.html)) {
          return {
            entityId: linkedId,
            source: "rental_link",
            resNo: String(linked.fields.resNo || resNo || ""),
          };
        }
      }
    }
  }

  const searchTerms = [...new Set([resNo, displayDocNo].filter(Boolean))];
  if (searchTerms.length) {
    const listResults = await Promise.all(
        searchTerms.map((term) => {
          const searchField = looksLikeResNo(term) ? "ConfirmationNo" : "DisplayDocNo";
          return searchBookingsList(cookie, {
            searchField,
            searchValue: term,
            station,
            pageSize: 15,
          }).catch(() => ({rows: []}));
        }),
    );
    for (let i = 0; i < searchTerms.length; i++) {
      const term = searchTerms[i];
      const rows = listResults[i] && listResults[i].rows ?
        listResults[i].rows : [];
      const termUpper = term.toUpperCase();
      const digits = termUpper.replace(/[^0-9]/g, "");
      const hit = rows.find((r) => {
        const rowRes = String(r.resNo || r.confirmationNo || "").toUpperCase();
        const conf = String(r.confirmationNo || "").toUpperCase();
        const doc = String(r.displayDocNo || "").toUpperCase();
        return rowRes === termUpper || conf === termUpper || doc === termUpper ||
          (digits && (rowRes.includes(digits) || conf.includes(digits) || doc.includes(digits)));
      }) || rows[0];
      if (hit && hit.entityId) {
        const id = String(hit.entityId);
        if (/^\d+$/.test(id)) {
          return {
            entityId: id,
            source: "bookings_list",
            resNo: String(hit.resNo || hit.confirmationNo || resNo || ""),
          };
        }
      }
    }
  }

  throw new Error(
      "Could not resolve booking entity ID. " +
      "Use booking.aspx?entityId=… (not rental entity or RES number).",
  );
}

/**
 * Resolve booking entity and cache key for assignment.
 * Strategy 1: booking GET parse.
 * Strategy 2: warm ScriptManager POSTs + parse warm response + re-GET.
 * Strategy 3: booking list search + re-fetch booking page.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<{bookingEntityId: string, cacheKey: string, resNo: string, source: string}>}
 */
async function resolveBookingContextForAssign(cookie, opts = {}) {
  const station = String(opts.station || "ZRH").toUpperCase();
  await warmBookingViewPage(cookie);

  const tried = new Set();

  /**
   * @param {string} entityId
   * @param {string} source
   * @param {string} [resNoHint]
   * @return {Promise<{bookingEntityId: string, cacheKey: string, resNo: string, source: string}|null>}
   */
  const tryResolveOnEntity = async (entityId, source, resNoHint = "") => {
    const id = String(entityId || "").trim();
    if (!/^\d+$/.test(id) || tried.has(id)) return null;
    tried.add(id);

    const page = await fetchBookingPage(cookie, id);
    const cacheKey = String(page.fields.cacheKey || extractCacheKey(page.html) || "").trim();
    if (cacheKey) {
      return {
        bookingEntityId: id,
        cacheKey,
        resNo: String(page.fields.resNo || resNoHint || opts.resNo || ""),
        source: `${source}_get`,
      };
    }

    let warmKey = "";
    try {
      warmKey = await ensureBookingCacheKey(cookie, id, page);
    } catch (_) {
      warmKey = "";
    }
    if (warmKey) {
      return {
        bookingEntityId: id,
        cacheKey: warmKey,
        resNo: String(page.fields.resNo || resNoHint || opts.resNo || ""),
        source: `${source}_warm`,
      };
    }
    return null;
  };

  // Strategy 0: bookingview grid search (DisplayDocNo / RES) — most reliable for assign.
  const listIds = await findBookingEntityIdsFromList(cookie, {
    resNo: opts.resNo,
    displayDocNo: opts.displayDocNo,
    station,
  });
  for (const listId of listIds) {
    const fromList = await tryResolveOnEntity(listId, "bookings_list", opts.resNo || "");
    if (fromList) return fromList;
  }

  const resolved = await resolveBookingEntityId(
      cookie,
      opts.bookingEntityId || opts.entityId || opts.hintId,
      {resNo: opts.resNo, displayDocNo: opts.displayDocNo, station},
  );

  const baseId = String(resolved.entityId || "").trim();

  // Strategy 1 + 2 on resolved entity id.
  const primary = await tryResolveOnEntity(baseId, resolved.source || "resolved", resolved.resNo);
  if (primary) return primary;

  // Strategy 3: search bookings list terms again on any missed ids.
  const terms = [...new Set([
    opts.resNo,
    opts.displayDocNo,
    resolved.resNo,
  ].map((v) => String(v || "").trim()).filter(Boolean))];

  for (const term of terms) {
    let rows = [];
    try {
      const searchField = looksLikeResNo(term) ? "ConfirmationNo" : "DisplayDocNo";
      const list = await searchBookingsList(cookie, {
        searchField,
        searchValue: term,
        station,
        pageSize: 15,
      });
      rows = Array.isArray(list && list.rows) ? list.rows : [];
    } catch (_) {
      rows = [];
    }
    for (const row of rows) {
      const hitId = String(row && row.entityId || "").trim();
      if (!/^\d+$/.test(hitId)) continue;
      const fromSearch = await tryResolveOnEntity(
          hitId,
          "bookings_list_retry",
          String(row.resNo || row.confirmationNo || term),
      );
      if (fromSearch) return fromSearch;
    }
  }

  throw new Error("Booking cacheKey not found — reload booking page.");
}

/**
 * @param {string} cookie
 * @param {number|string} entityId
 * @return {Promise<{html: string, url: string, fields: object}>}
 */
async function fetchBookingPage(cookie, entityId) {
  const id = String(entityId).trim();
  if (!/^\d+$/.test(id)) throw new Error("Invalid booking entityId.");
  const pageUrl = `${BASE_URL}${BOOKING_PATH}?entityId=${id}`;
  const res = await fetch(pageUrl, {
    headers: {
      "Cookie": cookie,
      "User-Agent": UA,
      "Accept": "text/html,application/xhtml+xml",
    },
    redirect: "follow",
  });
  if (!res.ok) {
    throw new Error(`WheelSys booking GET failed (${res.status}).`);
  }
  const html = await res.text();
  if (/login|sign.?in/i.test(html) && !html.includes("rdGroup_combo")) {
    throw new Error("WheelSys session expired.");
  }
  const fields = extractBookingFieldSnapshot(html);
  const titleMatch = html.match(/<title>\s*([^<]+)/i);
  if (titleMatch) fields.pageTitle = String(titleMatch[1] || "").trim();
  return {html, url: pageUrl, fields};
}

/**
 * @param {string} cookie
 * @param {object} p
 * @return {Promise<object[]>}
 */
async function searchAvailableVehicles(cookie, p) {
  const body = {
    inparams: {
      availNow: false,
      stationFrom: String(p.stationFrom || "ZRH"),
      stationTo: String(p.stationTo || "ZRH"),
      dateFrom: String(p.dateFrom),
      dateTo: String(p.dateTo),
      carGroup: String(p.carGroup || ""),
      modelId: p.modelId != null ? p.modelId : null,
      EntireFleet: Boolean(p.entireFleet),
      Allocating: false,
      usageType: Number(p.usageType) || 1,
      plateMask: String(p.plateMask || ""),
      rentalId: Number(p.rentalId),
      rentalCarId: p.rentalCarId != null ? p.rentalCarId : null,
      globalFleet: false,
      Brand: String(p.brand || ""),
    },
  };
  const res = await fetch(`${BASE_URL}${CAR_SEARCH_PATH}`, {
    method: "POST",
    headers: {
      "Cookie": cookie,
      "Content-Type": "application/json; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest",
      "Accept": "application/json, text/javascript, */*; q=0.01",
      "User-Agent": UA,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`RentalCarSearch failed (${res.status}).`);
  const outer = await res.json();
  const raw = (outer && outer.d && outer.d.data) ||
    (outer && outer.d) || (outer && outer.data);
  const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  const rows = Array.isArray(parsed) ?
    parsed :
    ((parsed && parsed.rows) || (parsed && parsed.data) || []);
  return rows.map((row) => ({
    id: Number(row.Id != null ? row.Id : row.id),
    plateNo: String(row.Plateno || row.plateNo || ""),
    carGroup: String(row.CarGroup || row.carGroup || ""),
    modelId: Number(row.ModelId != null ? row.ModelId : row.modelId) || 0,
    modelName: String(row.ModelName || row.modelName || ""),
    mileage: Number(row.Mileage != null ? row.Mileage : row.mileage) || 0,
    fuel: Number(row.Fuel != null ? row.Fuel : row.fuel) || 0,
    station: String(row.Station || row.station || ""),
    hasDamages: Boolean(row.HasDamages != null ? row.HasDamages : row.hasDamages),
    readyToGo: Boolean(row.ReadyToGo != null ? row.ReadyToGo : row.readyToGo),
    lastCheckin: String(row.LastCheckin || row.lastCheckin || ""),
    lastLocation: String(row.LastLocation || row.lastLocation || ""),
    fuelTypeCode: String(row.FuelTypeCode || row.fuelTypeCode || ""),
  }));
}

/**
 * @param {string} cookie
 * @param {object} p
 * @return {Promise<object>}
 */
async function canUseCar(cookie, p) {
  const params = new URLSearchParams({
    plateNo: String(p.plateNo || ""),
    carId: String(p.carId || ""),
    dateFrom: String(p.dateFrom),
    dateTo: String(p.dateTo),
    usageReq: String(p.usageReq || "1"),
    rId: String(p.rentalId),
    isRentalId: "true",
  });
  const res = await fetch(`${BASE_URL}${CAN_USE_CAR_PATH}`, {
    method: "POST",
    headers: {
      "Cookie": cookie,
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest",
      "User-Agent": UA,
    },
    body: params.toString(),
  });
  if (!res.ok) throw new Error(`canUseCar failed (${res.status}).`);
  return res.json();
}

/**
 * @param {object} fields
 * @param {object} overrides
 * @return {object}
 */
function buildCalcRatesPayload(fields, overrides = {}) {
  const f = fields || {};
  return {
    UsageType: String(overrides.usageType || f.usageType || "1"),
    Status: String(overrides.status || f.status || "1"),
    Agent: String(f.agent || ""),
    Corporate: String(f.corporate || ""),
    Driver: String(f.driver || ""),
    Driver2: String(f.driver2 || ""),
    Driver3: String(f.driver3 || ""),
    Driver4: String(f.driver4 || ""),
    ResModeId: String(f.resModeId || "6"),
    StationFrom: String(f.stationFrom || "ZRH"),
    DateFrom: String(overrides.dateFrom || localIsoToUtcIso(
        combineDateTimeLocal(f.dateFrom, f.timeFrom)) || ""),
    LocationFrom: String(f.locationFrom || "Zurich Airport"),
    DelCharge: 0,
    StationTo: String(f.stationTo || "ZRH"),
    DateTo: String(overrides.dateTo || localIsoToUtcIso(
        combineDateTimeLocal(f.dateTo, f.timeTo)) || ""),
    LocationTo: String(f.locationTo || "Zurich Airport"),
    ColCharge: 0,
    CarGroup: String(overrides.carGroup || f.carGroup || ""),
    GroupInv: String(overrides.groupInv || f.groupInv || f.carGroup || ""),
    RateId: String(f.rateId || "2"),
    DiscountPlan: "",
    CarId: String(overrides.carId || f.carId || ""),
    ExtensionRate: Number(f.extensionRate) || 0,
    Excess: 0,
    ExtraDay: true,
    CDP: "",
    RentalRate: Number(f.rentalRate) || 0,
    FuelPolicy: String(f.fuelPolicy || ""),
    TotalCharge: Number(f.chargeTotal) || 0,
    PreAuthNo: "",
    PreAuthAmount: 0,
    AllowedMiles: 0,
    MileRate: 0,
    MilesDriven: 0,
    ManualAgreement: "",
    FuelCharge: Number(f.fuelCharge) || 0,
    KilomTo: 0,
    FuelTo: 0,
    GeoLocFrom: "",
    GeoLocTo: "",
    AgentDiscPLan: "",
    CorpDiscPlan: "",
    Brand: String(f.brand || ""),
    RentalType: String(f.rentalType || "R"),
    EstimatedMiles: 0,
    RateCode: String(f.rateCode || "GMI"),
  };
}

/**
 * @param {string} cookie
 * @param {object} p
 * @return {Promise<object>}
 */
async function calcRates(cookie, {cacheKey, operation = "FuelPolicy", rentalData}) {
  const res = await fetch(`${BASE_URL}${RENTAL_CALC_PATH}`, {
    method: "POST",
    headers: {
      "Cookie": cookie,
      "Content-Type": "application/json; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest",
      "User-Agent": UA,
    },
    body: JSON.stringify({
      cacheKey: String(cacheKey),
      operation,
      data: JSON.stringify(rentalData),
    }),
  });
  if (!res.ok) throw new Error(`CalcRates failed (${res.status}).`);
  const outer = await res.json();
  const innerRaw = (outer && outer.d) || outer;
  const calcResult = typeof innerRaw === "string" ? JSON.parse(innerRaw) : innerRaw;
  if (!calcResult || !calcResult.Success) {
    const msg = String(
        (calcResult && calcResult.Message) ||
        (calcResult && calcResult.message) ||
        "CalcRates failed.",
    );
    throw new Error(msg);
  }
  return calcResult;
}

/**
 * @param {URLSearchParams} payload
 * @param {object} vehicle
 * @param {object} rental
 */
function applyVehicleFields(payload, vehicle, rental) {
  const r = (rental && rental.Rental) || rental || {};
  const group = String(vehicle.carGroup || vehicle.CarGroup || r.CarGroup || "");
  const carId = String(vehicle.id || vehicle.Id || r.CarId || "");
  const modelId = String(vehicle.modelId || vehicle.ModelId || "");
  const modelName = String(vehicle.modelName || vehicle.ModelName || "");
  const plate = String(vehicle.plateNo || vehicle.Plateno || "");

  if (group) {
    payload.set("rdGroup_combo", group);
    payload.set("rdGroupRes_text", group);
    payload.set("rdGroupInv_combo", group);
  }
  if (modelName) payload.set("rdModel_text", modelName);
  if (modelId) payload.set("rdModel_value", modelId);
  payload.set("rdModel_hqe", "true");
  if (plate) payload.set("rdPlateNo_text", plate);
  if (carId) payload.set("rdPlateNo_value", carId);
  payload.set("rdPlateNo_hqe", "true");

  const money = (key, val) => {
    if (val == null || val === "") return;
    const n = Number(val);
    if (!Number.isFinite(n)) return;
    const text = n.toFixed(2).replace(".", ",");
    payload.set(`${key}_text`, text);
    payload.set(`${key}_hidden`, String(n));
  };

  money("rdExtensionRate", r.ExtensionRate);
  money("rdRPD", r.RentPerDay != null ? r.RentPerDay : r.RentalRate);
  money("rdRentalCharge", r.RentalCharge);
  money("rdInsurance", r.InsuranceCharge);
  money("rdExtras", r.ExtraCharge);
  if (r.FuelPolicy != null) payload.set("rdFuelPolicy_combo", String(r.FuelPolicy));
  money("rdFuel", r.FuelCharge);
  money("rdChargeNet", r.NetCharge);
  money("rdTax1Perc", r.Tax1Rate);
  money("rdTax1Amount", r.Tax1Charge);
  money("rdChargeTotal", r.TotalCharge);
  money("rdVoucherVal", r.VoucherValue);
  money("rdPOA", r.Balance != null ? r.Balance : 0);
  money("rdBal", r.Balance);
  money("rdTotal2", r.TotalCharge);
  money("rdLTotal", r.LocalTotal != null ? r.LocalTotal : r.TotalCharge);
}

/**
 * @param {URLSearchParams} payload
 * @param {number} km
 * @param {number} fuel
 */
function applyCheckoutMileageFuel(payload, km, fuel) {
  if (km > 0) {
    payload.set("rdMileageFrom_hidden", String(km));
    payload.set("rdMileageFrom_text", formatMileageText(km));
  }
  if (fuel >= 0 && fuel <= 8) {
    payload.set("rdTankFrom_hidden", formatTankHidden(fuel));
    payload.set("rdTankFrom_text", formatTankText(fuel));
  }
}

/**
 * @param {string} cookie
 * @param {object} p
 * @return {Promise<object>}
 */
async function assignVehicleToBooking(cookie, p) {
  const vehicle = p.selectedVehicle || {};
  const carId = Number(vehicle.id || vehicle.carId);
  const plateNo = String(vehicle.plateNo || vehicle.plate || "").trim();
  if (!carId || !plateNo) {
    throw new Error("carId and plateNo are required.");
  }

  const pre = p.preResolvedContext || {};
  const preBookingId = String(pre.bookingEntityId || "").trim();
  const preCacheKey = String(pre.cacheKey || "").trim();
  const hasValidPreContext = /^\d+$/.test(preBookingId) &&
    new RegExp(`^${UUID_RE}$`, "i").test(preCacheKey);

  let bookingEntityId = "";
  let resolved = {
    source: "resolved_context",
    resNo: String(pre.resNo || p.resNo || ""),
  };
  let resolvedCacheKey = "";

  if (hasValidPreContext) {
    bookingEntityId = preBookingId;
    resolvedCacheKey = preCacheKey;
    resolved = {
      source: String(pre.source || "pre_resolved"),
      resNo: String(pre.resNo || p.resNo || ""),
    };
  } else {
    const context = await resolveBookingContextForAssign(cookie, {
      bookingEntityId: p.bookingEntityId || p.entityId,
      resNo: p.resNo,
      displayDocNo: p.displayDocNo,
    });
    bookingEntityId = context.bookingEntityId;
    resolvedCacheKey = context.cacheKey;
    resolved = {
      source: context.source,
      resNo: context.resNo,
    };
  }

  const page = await fetchBookingPage(cookie, bookingEntityId);
  const f = page.fields;
  const dateFromLocal = combineDateTimeLocal(f.dateFrom, f.timeFrom);
  const dateToLocal = combineDateTimeLocal(f.dateTo, f.timeTo);
  const dateFromUtc = localIsoToUtcIso(dateFromLocal);
  const dateToUtc = localIsoToUtcIso(dateToLocal);
  if (!dateFromUtc || !dateToUtc) {
    throw new Error("Booking date/time fields are missing.");
  }

  const canUse = await canUseCar(cookie, {
    plateNo,
    carId,
    dateFrom: dateFromUtc,
    dateTo: dateToUtc,
    usageReq: f.usageType || "1",
    rentalId: bookingEntityId,
  });
  if (!canUse || !canUse.IsUsable) {
    const warnings = Array.isArray(canUse && canUse.Warnings) ?
      canUse.Warnings.map((w) => w.AvailAction || w.Message).filter(Boolean).join("; ") :
      "";
    throw new Error(warnings || "Selected vehicle is not usable for this booking.");
  }

  const rentalData = buildCalcRatesPayload(f, {
    carId: String(carId),
    carGroup: vehicle.carGroup || f.carGroup,
    groupInv: vehicle.carGroup || f.groupInv || f.carGroup,
  });
  const cacheKey = resolvedCacheKey ||
    await ensureBookingCacheKey(cookie, bookingEntityId, page);

  const calcResult = await calcRates(cookie, {cacheKey, rentalData});
  const rental = calcResult.Rental || {};

  const [fresh, canUseRecheck] = await Promise.all([
    fetchBookingPage(cookie, bookingEntityId),
    canUseCar(cookie, {
      plateNo,
      carId,
      dateFrom: dateFromUtc,
      dateTo: dateToUtc,
      usageReq: f.usageType || "1",
      rentalId: bookingEntityId,
    }).catch(() => null),
  ]);
  if (canUseRecheck && !canUseRecheck.IsUsable) {
    const warnings = Array.isArray(canUseRecheck.Warnings) ?
      canUseRecheck.Warnings.map((w) => w.AvailAction || w.Message).filter(Boolean).join("; ") :
      "";
    throw new Error(warnings || "Selected vehicle is not usable for this booking.");
  }

  const payload = parseFormToPayload(fresh.html);
  applyVehicleFields(payload, {
    id: carId,
    plateNo,
    carGroup: vehicle.carGroup || canUse.CarGroup || f.carGroup,
    modelId: vehicle.modelId || (canUse.CarInfo && canUse.CarInfo.ModelTableId),
    modelName: vehicle.modelName || (canUse.CarInfo && canUse.CarInfo.ModelName),
  }, rental);

  if (p.checkOutMileage > 0 || p.checkOutFuel != null) {
    applyCheckoutMileageFuel(payload, Number(p.checkOutMileage) || 0, Number(p.checkOutFuel));
  }

  const pageUrl = `${BASE_URL}${BOOKING_PATH}?entityId=${bookingEntityId}`;
  payload.set(
      "ctl00$ctl00$ctl00$coreBody$ScriptManager",
      "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|rentalPanel",
  );
  payload.set("__EVENTTARGET", "rentalPanel");
  payload.set("__EVENTARGUMENT", JSON.stringify({action: "BTSAVE", itemId: bookingEntityId}));
  payload.set("__ASYNCPOST", "true");

  const postRes = await fetch(pageUrl, {
    method: "POST",
    headers: {
      "Cookie": cookie,
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "X-MicrosoftAjax": "Delta=true",
      "X-Requested-With": "XMLHttpRequest",
      "Origin": BASE_URL,
      "Referer": pageUrl,
      "User-Agent": UA,
    },
    body: payload.toString(),
  });
  const rawText = await postRes.text();
  const parsed = parseWheelsysResponse(rawText);
  if (!parsed.success) {
    throw new Error(parsed.message || "Booking save did not confirm success.");
  }

  return {
    success: true,
    bookingEntityId: Number(bookingEntityId),
    resolvedFrom: resolved.source,
    carId,
    plateNo,
    resNo: f.resNo || resolved.resNo,
    raNo: f.raNo,
    canUseCar: {
      isUsable: true,
      carGroup: canUse.CarGroup,
      carInfo: canUse.CarInfo,
    },
    calcRates: {
      totalCharge: rental.TotalCharge,
      rentalCharge: rental.RentalCharge,
      ancillaries: rental.Ancilliaries || [],
    },
    verifiedPlate: plateNo,
  };
}

module.exports = {
  BOOKING_PATH,
  extractCacheKey,
  extractBookingFieldSnapshot,
  isValidBookingPage,
  extractBookingIdFromRentalHtml,
  resolveBookingEntityId,
  resolveBookingContextForAssign,
  fetchBookingPage,
  ensureBookingCacheKey,
  searchAvailableVehicles,
  canUseCar,
  calcRates,
  assignVehicleToBooking,
  combineDateTimeLocal,
  localIsoToUtcIso,
  buildCalcRatesPayload,
};
