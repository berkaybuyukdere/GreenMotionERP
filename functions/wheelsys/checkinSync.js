/**
 * WheelSys rental check-in mileage & fuel sync (ASP.NET WebForms async POST).
 * Internal use only — session cookie never leaves the server.
 */
/* eslint-disable max-len */

const cheerio = require("cheerio");

const BASE_URL = "https://ch.wheelsys.greenmotion.com";
const RENTAL_PATH = "/ui/manage/master/rental.aspx";
const CAR_PATH = "/ui/manage/master/car.aspx";
const RENTALS_LIST_PATH = "/ui/manage/master/rentals.aspx";

const WHEELSYS_DOMAINS = {
  vehicle: 1,
  rental: 5,
};

const UA = "Mozilla/5.0 (compatible; VehicleSentinel/1.0; +internal)";

/**
 * WheelSys km text: dot as thousands separator, e.g. 117650 → "117.650 km".
 * @param {number} value
 * @return {string}
 */
function formatMileageText(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return "";
  // Swiss locale uses ' as thousands sep → replace with WheelSys dot convention.
  return n.toLocaleString("de-CH").replace(/'/g, ".") + " km";
}

/**
 * Vehicle master mileage text — dot thousands, no " km" suffix.
 * @param {number} value
 * @return {string}
 */
function formatVehicleMileageText(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return "";
  return n.toLocaleString("de-CH").replace(/'/g, ".");
}

/**
 * @param {number} tank
 * @return {string}
 */
function formatTankText(tank) {
  const n = Number(tank);
  if (!Number.isFinite(n)) return "";
  return `${n} /8`;
}

/**
 * @param {number} tank
 * @return {string}
 */
function formatTankHidden(tank) {
  const n = Number(tank);
  if (!Number.isFinite(n)) return "";
  return String(n);
}

/**
 * Parse WheelSys money field (e.g. "3.000,00" or "3000.00").
 * @param {*} value
 * @return {number}
 */
function parseMoney(value) {
  if (value == null || value === "") return 0;
  const raw = String(value).trim();
  if (!raw) return 0;
  // European: 3.000,00 → 3000.00
  if (/,/.test(raw) && /\./.test(raw)) {
    const normalized = raw.replace(/[^\d,.-]/g, "").replace(/\./g, "").replace(",", ".");
    const n = parseFloat(normalized);
    return Number.isFinite(n) ? n : 0;
  }
  const normalized = raw.replace(/[^\d.-]/g, "");
  const n = parseFloat(normalized);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Extract sanitised error message from WheelSys async response text.
 * Never returns raw HTML or cookie values.
 * @param {string} text
 * @return {{success: boolean, staleRecord: boolean, message: string}}
 */
function parseWheelsysResponse(text) {
  const t = String(text || "");
  // Prefer structured wheels.afterSave({...}) JSON — not bare script references.
  const afterSave = t.match(/wheels\.afterSave\s*\(\s*(\{[\s\S]*?\})\s*\)/);
  if (afterSave) {
    try {
      const obj = JSON.parse(afterSave[1]);
      if (obj.success === true) {
        return {success: true, staleRecord: false, message: String(obj.message || "")};
      }
      const msg = String(obj.message || "WheelSys save rejected.");
      return {success: false, staleRecord: /Record was changed by/i.test(msg), message: msg};
    } catch (_) {
      // fall through
    }
  }
  if (/"success"\s*:\s*true/.test(t)) {
    return {success: true, staleRecord: false, message: ""};
  }
  const staleRecord = /Record was changed by/i.test(t);
  let message = "WheelSys did not confirm success.";
  const msgMatch = t.match(/"message"\s*:\s*"([^"]{1,300})"/);
  if (msgMatch) {
    message = msgMatch[1];
  } else if (staleRecord) {
    const who = t.match(/Record was changed by ([^\n"<]{1,60})/i);
    message = who ? `Record was changed by ${who[1].trim()}` : "Record was changed by another user.";
  } else if (t.includes("\"success\":false")) {
    const errMatch = t.match(/"error"\s*:\s*"([^"]{1,300})"/);
    if (errMatch) message = errMatch[1];
  }
  return {success: false, staleRecord, message};
}

/**
 * Read effective input value — WheelSys uses data-prevalue for pending edits.
 * @param {cheerio.Cheerio} el
 * @param {string} [fieldName]
 * @return {string}
 */
function effectiveInputValue(el, fieldName = "") {
  const pre = String(el.attr("data-prevalue") || "").trim();
  const val = String(el.attr("value") || el.text() || "").trim();
  const name = fieldName || String(el.attr("name") || el.attr("id") || "");
  if (name.endsWith("_hidden") && pre) {
    const digits = pre.replace(/[^\d.-]/g, "");
    if (digits) return digits;
  }
  if (pre && (val === "" || val === "0")) return pre;
  return val;
}

/**
 * Extract selected check-in user id from rental HTML.
 * @param {string} html
 * @return {string}
 */
function extractCheckInUserId(html) {
  const $ = cheerio.load(html);
  const sel = $("select[name=\"rdUserTo_combo\"]");
  const selected = String(sel.find("option[selected]").attr("value") || "").trim();
  if (selected) return selected;
  let fallback = "";
  sel.find("option").each((_, o) => {
    const v = String($(o).attr("value") || "").trim();
    if (v && !fallback) fallback = v;
  });
  return fallback;
}

/**
 * @param {string} html
 * @return {Array<{id: string, name: string}>}
 */
function extractCheckInUserOptions(html) {
  const $ = cheerio.load(html);
  const out = [];
  $("select[name=\"rdUserTo_combo\"] option").each((_, o) => {
    const id = String($(o).attr("value") || "").trim();
    const name = String($(o).text() || "").trim();
    if (id) out.push({id, name});
  });
  return out;
}

/**
 * @param {string} html
 * @return {URLSearchParams}
 */
function parseFormToPayload(html) {
  const $ = cheerio.load(html);
  const payload = new URLSearchParams();

  $("input").each((_, el) => {
    const name = $(el).attr("name");
    if (!name) return;
    const type = String($(el).attr("type") || "").toLowerCase();
    if (type === "checkbox" || type === "radio") {
      if ($(el).attr("checked") !== undefined) {
        payload.set(name, $(el).attr("value") || "on");
      }
      return;
    }
    payload.set(name, effectiveInputValue($(el), name));
  });

  $("select").each((_, el) => {
    const name = $(el).attr("name");
    if (!name) return;
    const selected =
      $(el).find("option[selected]").attr("value") ||
      $(el).find("option").first().attr("value") ||
      "";
    payload.set(name, selected);
  });

  $("textarea").each((_, el) => {
    const name = $(el).attr("name");
    if (!name) return;
    payload.set(name, $(el).text() || "");
  });

  return payload;
}

/**
 * Resolve car.aspx entity id for vehicle master sync.
 * @param {object} opts hints
 * @return {string} numeric entity id or ""
 */
function resolveVehicleEntityId({
  rentalFields,
  rentalHtml,
  plate,
  fleetCarIdHint,
  explicitHint,
}) {
  const candidates = [];
  const push = (v) => {
    const s = String(v || "").trim();
    if (s && /^\d+$/.test(s) && !candidates.includes(s)) {
      candidates.push(s);
    }
  };

  push(explicitHint);
  if (rentalFields) push(rentalFields.vehicleEntityId);
  push(fleetCarIdHint);

  const html = String(rentalHtml || "");
  if (html) {
    const linkMatch = html.match(/car\.aspx\?entityId=(\d+)/i);
    if (linkMatch) push(linkMatch[1]);
    const hiddenMatch = html.match(
        /(?:id|name)=["']rdPlateNo_value["'][^>]*value=["'](\d+)["']/i,
    );
    if (hiddenMatch) push(hiddenMatch[1]);
  }

  if (!candidates.length && plate) {
    console.warn(
        `resolveVehicleEntityId: no car entity for plate=${plate}`,
    );
  }
  return candidates[0] || "";
}

/**
 * Parse rental.aspx HTML into field snapshot.
 * @param {string} html rental page html
 * @return {object} field snapshot
 */
function extractRentalFieldSnapshot(html) {
  const $ = cheerio.load(html);
  const pick = (id) => {
    const el = $(`#${id}, [name="${id}"]`).first();
    if (!el.length) return "";
    return effectiveInputValue(el, id);
  };
  const pickFirst = (...ids) => {
    for (const id of ids) {
      const v = pick(id);
      if (v) return v;
    }
    return "";
  };
  const vehicleFromDom = pick("rdPlateNo_value") ||
    pick("rdCarId_hidden") ||
    pick("rdVehicleId_hidden");
  return {
    mileageFromHidden: pick("rdMileageFrom_hidden"),
    mileageFromText: pick("rdMileageFrom_text"),
    mileageToHidden: pick("rdMileageTo_hidden"),
    mileageToText: pick("rdMileageTo_text"),
    milesDrivenHidden: pick("rdMilesDriven_hidden"),
    tankFromHidden: pick("rdTankFrom_hidden"),
    tankFromText: pick("rdTankFrom_text"),
    tankToHidden: pick("rdTankTo_hidden"),
    tankToText: pick("rdTankTo_text"),
    userTo: pick("rdUserTo_combo"),
    dateTo: pick("rdDateTo_text"),
    timeTo: pick("rdTimeTo_text"),
    plate: pickFirst("rdPlateNo_text", "rdPlate_text", "rdPlate_hidden"),
    vehicleEntityId: vehicleFromDom,
    vehicleModel: pickFirst("rdModel_text", "rdCarModel_text", "rdVehicleModel_text"),
    insuranceText: pick("rdInsurance_text"),
    insuranceHidden: pick("rdInsurance_hidden"),
    excessText: pick("rdExcess_text"),
    excessHidden: pick("rdExcess_hidden"),
    dmgExcessText: pick("rdDmgExcess_text"),
    dmgExcessHidden: pick("rdDmgExcess_hidden"),
    raNo: pickFirst("rdRaDocNo", "rdRaNo_text", "rdRaNo_hidden"),
    resNo: pickFirst("rdResDocDisp_text", "rdResDocNo", "rdResNo_text", "rdResNo_hidden"),
  };
}

/**
 * @param {object} fields
 * @param {string} entityId
 * @return {boolean}
 */
function rentalPreviewLooksEmpty(fields) {
  const f = fields || {};
  const mileageFrom = Number(f.mileageFromHidden) || 0;
  const mileageTo = Number(f.mileageToHidden) || 0;
  const resNo = String(f.resNo || "").trim();
  const raNo = String(f.raNo || "").trim();
  if (resNo || raNo) return false;
  if (mileageFrom > 0 || mileageTo > 0) return false;
  if (f.pageTitle && /RNT-\d+/i.test(String(f.pageTitle))) return false;
  return true;
}

/**
 * @param {string} cookie
 * @param {number|string} entityId
 * @return {Promise<{html: string, url: string, fields: object}>}
 */
async function fetchRentalPage(cookie, entityId) {
  const id = String(entityId).trim();
  if (!/^\d+$/.test(id)) throw new Error("Invalid entityId.");
  const pagePath = `${RENTAL_PATH}?entityId=${id}`;
  const pageUrl = `${BASE_URL}${pagePath}`;
  const res = await fetch(pageUrl, {
    headers: {
      "Cookie": cookie,
      "User-Agent": UA,
      "Accept": "text/html,application/xhtml+xml",
    },
    redirect: "follow",
  });
  if (!res.ok) {
    throw new Error(`WheelSys GET failed (${res.status}). Session may have expired.`);
  }
  const html = await res.text();
  if (/login|sign.?in/i.test(html) && !html.includes("rdMileageFrom_hidden")) {
    throw new Error("WheelSys session expired. Sign in again from the app.");
  }
  const titleMatch = html.match(/<title>\s*([^<]+)/i);
  const fields = extractRentalFieldSnapshot(html);
  fields.checkInUserId = extractCheckInUserId(html);
  fields.checkInUserOptions = extractCheckInUserOptions(html);
  if (titleMatch) {
    fields.pageTitle = String(titleMatch[1] || "").trim();
    if (!fields.raNo) {
      const raFromTitle = fields.pageTitle.match(/RNT-\d+/i);
      if (raFromTitle) fields.raNo = raFromTitle[0].toUpperCase();
    }
  }
  return {html, url: pageUrl, fields};
}

/**
 * @param {object} fields
 * @return {object}
 */
function parseInsuranceSummary(fields) {
  const f = fields || {};
  const insuranceChargeAmount = parseMoney(f.insuranceHidden);
  const excessAmount = parseMoney(f.excessHidden);
  const damageExcessAmount = parseMoney(f.dmgExcessHidden);
  return {
    hasInsuranceCharge: insuranceChargeAmount > 0,
    insuranceChargeAmount,
    excessAmount: excessAmount || null,
    damageExcessAmount: damageExcessAmount || null,
    insuranceTypes: [],
  };
}

/**
 * @param {string} html
 * @return {object}
 */
function extractCarFieldSnapshot(html) {
  const $ = cheerio.load(html);
  const pick = (id) => {
    const el = $(`#${id}, [name="${id}"]`).first();
    if (!el.length) return "";
    return effectiveInputValue(el, id);
  };
  const pickFirst = (...ids) => {
    for (const id of ids) {
      const v = pick(id);
      if (v) return v;
    }
    return "";
  };
  return {
    mileageText: pick("rdMileage_text"),
    mileageHidden: pick("rdMileage_hidden"),
    tankText: pick("rdTank_text"),
    tankHidden: pick("rdTank_hidden"),
    plate: pickFirst("rdPlate_text", "rdPlateNo_text"),
    model: pickFirst("rdModel_text", "rdCarModel_text", "rdVehicleModel_text"),
  };
}

/**
 * @param {string} cookie
 * @param {number|string} vehicleEntityId
 * @return {Promise<{html: string, url: string, fields: object}>}
 */
async function fetchCarPage(cookie, vehicleEntityId) {
  const id = String(vehicleEntityId).trim();
  if (!/^\d+$/.test(id)) throw new Error("Invalid vehicleEntityId.");
  const pagePath = `${CAR_PATH}?entityId=${id}`;
  const pageUrl = `${BASE_URL}${pagePath}`;
  const res = await fetch(pageUrl, {
    headers: {
      "Cookie": cookie,
      "User-Agent": UA,
      "Accept": "text/html,application/xhtml+xml",
    },
    redirect: "follow",
  });
  if (!res.ok) {
    throw new Error(`WheelSys car GET failed (${res.status}). Session may have expired.`);
  }
  const html = await res.text();
  if (/login|sign.?in/i.test(html) && !html.includes("rdMileage_hidden")) {
    throw new Error("WheelSys session expired. Sign in again from the app.");
  }
  const fields = extractCarFieldSnapshot(html);
  const titleMatch = html.match(/<title>\s*([^<]+)/i);
  if (titleMatch) fields.pageTitle = String(titleMatch[1] || "").trim();
  return {html, url: pageUrl, fields};
}

/**
 * Apply vehicle master mileage/fuel onto car.aspx form payload.
 * @param {URLSearchParams} payload
 * @param {object} opts
 */
function applyVehicleMasterFields(payload, {vehicleEntityId, mileage, fuel}) {
  payload.set(
      "ctl00$ctl00$ctl00$coreBody$ScriptManager",
      "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$carPanel|carPanel",
  );
  payload.set("__EVENTTARGET", "carPanel");
  payload.set(
      "__EVENTARGUMENT",
      JSON.stringify({action: "BTSAVE", itemId: String(vehicleEntityId)}),
  );
  payload.set("__ASYNCPOST", "true");

  payload.set("rdMileage_text", formatVehicleMileageText(mileage));
  payload.set("rdMileage_hidden", String(mileage));
  payload.set("rdTank_text", formatTankText(fuel));
  payload.set("rdTank_hidden", formatTankHidden(fuel));
  payload.set("rdTank_combo", formatTankHidden(fuel));
}

/**
 * POST vehicle master mileage/fuel to car.aspx.
 * @param {object} p
 * @return {Promise<object>}
 */
async function updateWheelsysVehicleMaster({
  vehicleEntityId,
  mileage,
  fuel,
  wheelsysCookie,
  verifyAfterSave = true,
}) {
  const id = String(vehicleEntityId).trim();
  if (!/^\d+$/.test(id)) throw new Error("Invalid vehicleEntityId — must be numeric.");
  const mileageVal = Number(mileage);
  const fuelVal = Number(fuel);

  if (!wheelsysCookie) throw new Error("Missing WheelSys session cookie.");
  if (!Number.isFinite(mileageVal) || !Number.isInteger(mileageVal)) {
    throw new Error("Invalid vehicle mileage — must be a whole number.");
  }
  if (!Number.isFinite(fuelVal) || fuelVal < 0 || fuelVal > 8) {
    throw new Error("Vehicle fuel must be between 0 and 8.");
  }

  /**
   * @return {Promise<object>}
   */
  async function attempt() {
    const {html, url: pageUrl} = await fetchCarPage(wheelsysCookie, id);
    const payload = parseFormToPayload(html);
    applyVehicleMasterFields(payload, {
      vehicleEntityId: id,
      mileage: mileageVal,
      fuel: fuelVal,
    });
    const {parsed, rawText, httpStatus} = await postToWheelsys(pageUrl, wheelsysCookie, payload);
    return {pageUrl, parsed, rawText, httpStatus};
  }

  let r = await attempt();
  if (!r.parsed.success && r.parsed.staleRecord) {
    console.warn(`wheelsys vehicle master stale record entityId=${id}, retrying once.`);
    r = await attempt();
  }

  let verifiedMileage = null;
  let verifiedFuel = null;
  let verifyOk = !verifyAfterSave;
  if (r.parsed.success && verifyAfterSave) {
    const verify = await verifyMileageWithRetry({
      fetchFields: async () => {
        const page = await fetchCarPage(wheelsysCookie, id);
        return page.fields;
      },
      expectedMileage: mileageVal,
      expectedFuel: fuelVal,
      mileageField: "mileageHidden",
      fuelField: "tankHidden",
    });
    verifiedMileage = verify.mileage;
    verifiedFuel = verify.fuel;
    verifyOk = verify.ok;
    if (!verifyOk) {
      console.warn(
          `wheelsys vehicle verify mismatch entityId=${id}: ` +
          `expectedKm=${mileageVal} actualKm=${verifiedMileage} ` +
          `expectedFuel=${fuelVal} actualFuel=${verifiedFuel}`,
      );
    }
  }

  const confirmed = r.parsed.success && verifyOk;
  let errorMessage = r.parsed.message;
  if (r.parsed.success && verifyAfterSave && !verifyOk) {
    errorMessage =
      "WheelSys returned success but vehicle master km/fuel was not saved.";
  }

  return {
    success: confirmed,
    staleRecord: r.parsed.staleRecord,
    errorMessage,
    vehicleEntityId: id,
    mileage: mileageVal,
    fuel: fuelVal,
    verifiedMileage,
    verifiedFuel,
    responsePreview: r.rawText.slice(0, 1500),
    httpStatus: r.httpStatus,
  };
}

/**
 * Normalize a note from WheelSys API response.
 * @param {object} note
 * @param {string} entityKey
 * @param {number} domain
 * @param {string} source
 * @return {object}
 */
function normalizeEntityNote(note, entityKey, domain, source) {
  const n = note || {};
  return {
    id: n.Id != null ? n.Id : (n.id != null ? n.id : null),
    text: String(n.Text || n.text || n.noteText || "").trim(),
    createdBy: String(n.Creator || n.createdBy || n.creatorFullName || "").trim() || null,
    createdAt: String(n.DatePosted || n.createdAt || n.datePosted || "").trim() || null,
    entityId: String(n.ReferenceEntity_Id || n.entityKey || n.entityId || entityKey),
    domain: Number(n.Domain != null ? n.Domain : domain),
    source: source || (domain === WHEELSYS_DOMAINS.vehicle ? "vehicle" : "rental"),
  };
}

/**
 * Fetch notes for a WheelSys entity.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<Array<object>>}
 */
async function getEntityNotes(cookie, {entityKey, domain, source}) {
  const key = String(entityKey || "").trim();
  if (!key) return [];
  const domainNum = Number(domain);
  try {
    const res = await fetch(`${BASE_URL}/api/usernotes/getentitynotes`, {
      method: "POST",
      headers: {
        "Cookie": cookie,
        "Content-Type": "application/json; charset=UTF-8",
        "X-Requested-With": "XMLHttpRequest",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "User-Agent": UA,
      },
      body: JSON.stringify({
        entityKey: key,
        domain: String(domainNum),
      }),
    });
    if (!res.ok) return [];
    const data = await res.json();
    const arr = Array.isArray(data) ?
      data :
      (data.notes || data.Items || data.items || data.d || []);
    if (!Array.isArray(arr)) return [];
    const src = source || (domainNum === WHEELSYS_DOMAINS.vehicle ? "vehicle" : "rental");
    return arr.map((n) => normalizeEntityNote(n, key, domainNum, src));
  } catch (e) {
    console.warn(`getEntityNotes failed entityKey=${key} domain=${domain}: ${e.message}`);
    return [];
  }
}

/**
 * Save a note on a WheelSys entity.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function saveEntityNote(cookie, {
  entityKey,
  domain,
  noteText,
  creatorId,
  creatorFullName,
  notify = false,
  email = false,
  notificationRecipientId = null,
  notificationRecipientFullName = null,
}) {
  const key = String(entityKey || "").trim();
  const text = String(noteText || "").trim();
  if (!key) throw new Error("entityKey is required for note save.");
  if (!text) throw new Error("noteText is required for note save.");

  const payload = {
    createdAt: new Date().toISOString(),
    cacheKey: null,
    entityKey: key,
    domain: String(domain),
    creatorId: Number(creatorId) || creatorId,
    creatorFullName: String(creatorFullName || "").trim(),
    noteText: text,
    notificationRecipientFullName: notificationRecipientFullName || null,
    notificationRecipientId: notificationRecipientId || null,
    notify: Boolean(notify),
    email: Boolean(email),
  };

  const res = await fetch(`${BASE_URL}/api/usernotes/savenote`, {
    method: "POST",
    headers: {
      "Cookie": cookie,
      "Content-Type": "application/json; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest",
      "Accept": "application/json, text/javascript, */*; q=0.01",
      "User-Agent": UA,
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    throw new Error(`Failed to save note (${res.status}).`);
  }
  const data = await res.json();
  if (!data || data.Id == null) {
    throw new Error("Note save response did not confirm success.");
  }
  return normalizeEntityNote(data, key, Number(domain), null);
}

/**
 * Fetch rental page plus optional car page and entity notes.
 * @param {string} cookie
 * @param {number|string} rentalEntityId
 * @return {Promise<object>}
 */
async function fetchFullRentalData(cookie, rentalEntityId) {
  const rental = await fetchRentalPage(cookie, rentalEntityId);
  const fields = rental.fields;
  const vehicleEntityId = String(fields.vehicleEntityId || "").trim();
  const insurance = parseInsuranceSummary(fields);

  let carPage = null;
  let vehicleNotes = [];
  if (vehicleEntityId && /^\d+$/.test(vehicleEntityId)) {
    try {
      carPage = await fetchCarPage(cookie, vehicleEntityId);
    } catch (e) {
      console.warn(`fetchFullRentalData car page entityId=${vehicleEntityId}: ${e.message}`);
    }
    vehicleNotes = await getEntityNotes(cookie, {
      entityKey: vehicleEntityId,
      domain: WHEELSYS_DOMAINS.vehicle,
      source: "vehicle",
    });
  }

  const rentalNotes = await getEntityNotes(cookie, {
    entityKey: String(rentalEntityId),
    domain: WHEELSYS_DOMAINS.rental,
    source: "rental",
  });

  const vehicleMaster = carPage ? {
    mileage: Number(carPage.fields.mileageHidden) || 0,
    tank: Number(carPage.fields.tankHidden) || 0,
    mileageText: carPage.fields.mileageText || "",
    tankText: carPage.fields.tankText || "",
    model: carPage.fields.model || fields.vehicleModel || "",
    plate: carPage.fields.plate || fields.plate || "",
  } : null;

  return {
    rentalEntityId: String(rentalEntityId),
    fields,
    vehicleEntityId: vehicleEntityId || null,
    insurance,
    notes: {rentalNotes, vehicleNotes},
    vehicleMaster,
    mileage: {
      checkout: {
        mileage: Number(fields.mileageFromHidden) || 0,
        tank: Number(fields.tankFromHidden) || 0,
        mileageText: fields.mileageFromText || formatMileageText(fields.mileageFromHidden),
        tankText: fields.tankFromText || formatTankText(fields.tankFromHidden),
      },
      checkin: {
        mileage: Number(fields.mileageToHidden) || 0,
        tank: Number(fields.tankToHidden) || 0,
        mileageText: fields.mileageToText || formatMileageText(fields.mileageToHidden),
        tankText: fields.tankToText || formatTankText(fields.tankToHidden),
      },
      vehicleMaster,
    },
    html: rental.html,
    url: rental.url,
  };
}

/**
 * Build and apply check-in fields onto an existing URLSearchParams payload.
 * Mutates payload in-place. Returns {mileageFrom, milesDriven}.
 * @param {URLSearchParams} payload
 * @param {object} opts
 * @return {{mileageFrom: number, milesDriven: number}}
 */
function applyCheckinFields(payload, {
  id, mileageTo, fuelTo, checkInUserId, checkInDate, checkInTime, checkInCondition,
}) {
  payload.set(
      "ctl00$ctl00$ctl00$coreBody$ScriptManager",
      "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|rentalPanel",
  );
  payload.set("__EVENTTARGET", "rentalPanel");
  payload.set("__EVENTARGUMENT", JSON.stringify({action: "BTSAVE", itemId: String(id)}));
  payload.set("__ASYNCPOST", "true");

  const mileageFrom = Number(payload.get("rdMileageFrom_hidden") || 0);
  if (mileageTo < mileageFrom) {
    throw new Error(
        `Check-in mileage (${mileageTo}) cannot be lower than check-out mileage (${mileageFrom}).`,
    );
  }
  const milesDriven = mileageTo - mileageFrom;

  payload.set("rdMileageTo_text", formatMileageText(mileageTo));
  payload.set("rdMileageTo_hidden", String(mileageTo));
  payload.set("rdTankTo_text", formatTankText(fuelTo));
  payload.set("rdTankTo_hidden", formatTankHidden(fuelTo));
  payload.set("rdMilesDriven_text", `${milesDriven} km`);
  payload.set("rdMilesDriven_hidden", String(milesDriven));

  const userId = String(checkInUserId || payload.get("rdUserTo_combo") || "").trim();
  if (!userId || !/^\d+$/.test(userId)) {
    throw new Error(
        "Check-in user (rdUserTo_combo) is required. Select a WheelSys user before syncing.",
    );
  }
  payload.set("rdUserTo_combo", userId);

  const dateTo = String(checkInDate || payload.get("rdDateTo_text") || "").trim();
  const timeTo = String(checkInTime || payload.get("rdTimeTo_text") || "").trim();
  if (!dateTo || !timeTo) {
    throw new Error("Check-in date and time are required for WheelSys save.");
  }
  payload.set("rdDateTo_text", dateTo);
  payload.set("rdTimeTo_text", timeTo);

  if (checkInCondition != null && String(checkInCondition).trim()) {
    payload.set("rdCarCondition_combo", String(checkInCondition).trim());
  }
  return {mileageFrom, milesDriven};
}

/**
 * Re-fetch a WheelSys page and confirm mileage/fuel persisted (WheelSys can lag).
 * @param {object} opts
 * @return {Promise<object>} ok, mileage, fuel
 */
async function verifyMileageWithRetry({
  fetchFields,
  expectedMileage,
  expectedFuel = null,
  mileageField = "mileageToHidden",
  fuelField = "tankToHidden",
  maxAttempts = 6,
  initialDelayMs = 400,
  retryDelayMs = 700,
}) {
  let lastMileage = null;
  let lastFuel = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const delay = attempt === 1 ? initialDelayMs : retryDelayMs;
    await new Promise((resolve) => setTimeout(resolve, delay));
    try {
      const fields = await fetchFields();
      lastMileage = Number(fields[mileageField]) || null;
      lastFuel = expectedFuel != null ? Number(fields[fuelField]) : null;
      const fuelMatches = expectedFuel == null ||
        !Number.isFinite(lastFuel) ||
        lastFuel === expectedFuel;
      if (lastMileage === expectedMileage && fuelMatches) {
        return {ok: true, mileage: lastMileage, fuel: lastFuel};
      }
    } catch (e) {
      if (attempt === maxAttempts) {
        console.warn(`verifyMileageWithRetry fetch failed: ${e.message}`);
      }
    }
  }
  return {ok: false, mileage: lastMileage, fuel: lastFuel};
}

/**
 * POST a prepared payload to WheelSys and return parsed response.
 * @param {string} pageUrl
 * @param {string} cookie
 * @param {URLSearchParams} payload
 * @return {Promise<{parsed: object, rawText: string}>}
 */
async function postToWheelsys(pageUrl, cookie, payload) {
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
  const rawText = String(await postRes.text());
  const parsed = parseWheelsysResponse(rawText);
  return {parsed, rawText, httpStatus: postRes.status};
}

/**
 * GET rental page, modify check-in fields, POST, return result.
 * Automatically retries once if WheelSys reports a stale record conflict.
 * @param {object} p
 * @return {Promise<object>}
 */
async function updateWheelsysCheckin({
  entityId,
  checkInMileage,
  checkInFuel,
  checkInUserId,
  checkInDate,
  checkInTime,
  wheelsysCookie,
  checkInCondition,
  verifyAfterSave = true,
  plate = "",
  fleetCarIdHint = "",
  vehicleEntityIdHint = "",
}) {
  const id = String(entityId).trim();
  if (!/^\d+$/.test(id)) throw new Error("Invalid entityId — must be numeric.");
  const mileageTo = Number(checkInMileage);
  const fuelTo = Number(checkInFuel);

  if (!wheelsysCookie) throw new Error("Missing WheelSys session cookie.");
  if (!Number.isFinite(mileageTo) || !Number.isInteger(mileageTo)) {
    throw new Error("Invalid check-in mileage — must be a whole number.");
  }
  if (!Number.isFinite(fuelTo) || fuelTo < 0 || fuelTo > 8) {
    throw new Error("Fuel must be between 0 and 8.");
  }

  /**
   * One attempt: fresh GET → apply fields → POST.
   * @return {Promise<object>}
   */
  async function attempt() {
    const {html, url: pageUrl, fields} = await fetchRentalPage(wheelsysCookie, id);
    const payload = parseFormToPayload(html);
    const resolvedUser = String(
        checkInUserId || fields.checkInUserId || extractCheckInUserId(html) || "",
    ).trim();
    const {mileageFrom, milesDriven} = applyCheckinFields(payload, {
      id,
      mileageTo,
      fuelTo,
      checkInUserId: resolvedUser,
      checkInDate,
      checkInTime,
      checkInCondition,
    });
    const {parsed, rawText, httpStatus} = await postToWheelsys(pageUrl, wheelsysCookie, payload);
    return {
      mileageFrom,
      milesDriven,
      mileageToFromPage: Number(fields.mileageToHidden) || 0,
      resolvedUserId: resolvedUser,
      vehicleEntityId: String(fields.vehicleEntityId || "").trim(),
      fields,
      html,
      pageUrl,
      parsed,
      rawText,
      httpStatus,
    };
  }

  let r = await attempt();

  // On stale record, do one automatic fresh-GET retry.
  if (!r.parsed.success && r.parsed.staleRecord) {
    console.warn(`wheelsys stale record on entityId=${id}, retrying once.`);
    r = await attempt();
  }

  const rentalSaved = r.parsed.success;

  // Post-save verification with retries — does not block vehicle master sync.
  let verifiedMileageTo = null;
  let verifyOk = !verifyAfterSave;
  if (rentalSaved && verifyAfterSave) {
    const verify = await verifyMileageWithRetry({
      fetchFields: async () => {
        const page = await fetchRentalPage(wheelsysCookie, id);
        return page.fields;
      },
      expectedMileage: mileageTo,
      mileageField: "mileageToHidden",
      fuelField: "tankToHidden",
    });
    verifiedMileageTo = verify.mileage;
    verifyOk = verify.ok;
    if (!verifyOk) {
      console.warn(
          `wheelsys verify mismatch entityId=${id}: ` +
          `expected=${mileageTo} actual=${verifiedMileageTo}`,
      );
    }
  }

  const confirmed = rentalSaved && verifyOk;
  let errorMessage = r.parsed.message;
  if (rentalSaved && verifyAfterSave && !verifyOk) {
    errorMessage =
      "WheelSys returned success but mileage was not saved. " +
      "Ensure check-in user, date and time are set.";
  }

  // After rental POST succeeds, sync vehicle master mileage/fuel (even if verify slow).
  let vehicleEntityId = resolveVehicleEntityId({
    rentalFields: r.fields,
    rentalHtml: r.html,
    plate,
    fleetCarIdHint,
    explicitHint: vehicleEntityIdHint || r.vehicleEntityId,
  });
  if (!vehicleEntityId && rentalSaved) {
    try {
      const refreshed = await fetchRentalPage(wheelsysCookie, id);
      vehicleEntityId = resolveVehicleEntityId({
        rentalFields: refreshed.fields,
        rentalHtml: refreshed.html,
        plate: plate || refreshed.fields.plate,
        fleetCarIdHint,
        explicitHint: vehicleEntityIdHint,
      });
    } catch (e) {
      console.warn(`wheelsys post-save rental refresh failed: ${e.message}`);
    }
  }

  let vehicleMasterSynced = false;
  let vehicleMileageVerified = null;
  let vehicleFuelVerified = null;
  let vehicleMasterResult = null;

  if (rentalSaved && vehicleEntityId && /^\d+$/.test(vehicleEntityId)) {
    try {
      vehicleMasterResult = await updateWheelsysVehicleMaster({
        vehicleEntityId,
        mileage: mileageTo,
        fuel: fuelTo,
        wheelsysCookie,
        verifyAfterSave,
      });
      vehicleMasterSynced = Boolean(vehicleMasterResult.success);
      vehicleMileageVerified = vehicleMasterResult.verifiedMileage;
      vehicleFuelVerified = vehicleMasterResult.verifiedFuel;
      if (!vehicleMasterSynced) {
        errorMessage = vehicleMasterResult.errorMessage ||
          "Rental saved but vehicle master sync failed.";
      }
    } catch (e) {
      console.warn(`wheelsys vehicle master sync failed entityId=${vehicleEntityId}: ${e.message}`);
      errorMessage = `Rental saved but vehicle master sync failed: ${e.message}`;
    }
  } else if (rentalSaved && !vehicleEntityId) {
    console.warn(
        `wheelsys checkin entityId=${id}: no vehicle entity resolved ` +
        `(plate=${plate || "n/a"} fleetCar=${fleetCarIdHint || "n/a"}).`,
    );
  }

  const requiresVehicleMaster = Boolean(vehicleEntityId);
  const fullSuccess = confirmed && (!requiresVehicleMaster || vehicleMasterSynced);

  return {
    success: fullSuccess,
    staleRecord: r.parsed.staleRecord,
    errorMessage: fullSuccess ? "" : errorMessage,
    entityId: id,
    mileageFrom: r.mileageFrom,
    mileageTo,
    milesDriven: r.milesDriven,
    fuelTo,
    verifiedMileageTo,
    checkInUserId: r.resolvedUserId,
    vehicleEntityId: vehicleEntityId || null,
    vehicleMasterSynced,
    vehicleMileageVerified,
    vehicleFuelVerified,
    vehicleMaster: vehicleMasterResult,
    responsePreview: r.rawText.slice(0, 1500),
    httpStatus: r.httpStatus,
  };
}

/**
 * Search WheelSys rentals list HTML for entityId by RES/RNT token.
 * @param {string} cookie
 * @param {string} resQuery
 * @return {Promise<Array<object>>}
 */
async function searchRentalsByRes(cookie, resQuery) {
  const token = String(resQuery || "").trim().toUpperCase();
  if (!token) return [];

  const digits = token.replace(/[^0-9]/g, "");
  const candidates = new Set([token]);
  if (digits) {
    candidates.add(`RES-${digits}`);
    candidates.add(`RNT-${digits}`);
    candidates.add(digits);
  }

  const listUrl = `${BASE_URL}${RENTALS_LIST_PATH}`;
  const res = await fetch(listUrl, {
    headers: {"Cookie": cookie, "User-Agent": UA},
    redirect: "follow",
  });
  if (!res.ok) {
    throw new Error(`WheelSys rental list unavailable (${res.status}).`);
  }
  const html = await res.text();
  const results = [];
  const seen = new Set();

  for (const cand of candidates) {
    if (!cand) continue;
    const re = new RegExp(
        `entityId=(\\d+)[^"'<>]{0,400}?${cand.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}`,
        "gi",
    );
    let m;
    while ((m = re.exec(html)) !== null) {
      const entityId = m[1];
      if (seen.has(entityId)) continue;
      seen.add(entityId);
      results.push({entityId, resNo: cand, source: "wheelsys_list"});
    }
    const re2 = new RegExp(
        `${cand.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")}[^"'<>]{0,400}?entityId=(\\d+)`,
        "gi",
    );
    while ((m = re2.exec(html)) !== null) {
      const entityId = m[1];
      if (seen.has(entityId)) continue;
      seen.add(entityId);
      results.push({entityId, resNo: cand, source: "wheelsys_list"});
    }
  }

  return results.slice(0, 20);
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {string} resQuery
 * @return {Promise<Array<object>>}
 */
async function searchLocalExitsByRes(db, franchiseId, resQuery) {
  const raw = String(resQuery || "").trim().toUpperCase();
  const digits = raw.replace(/[^0-9]/g, "");
  const variants = new Set([raw]);
  if (digits) {
    variants.add(`RES-${digits}`);
    variants.add(`RNT-${digits}`);
    variants.add(digits);
  }

  const col = db.collection("franchises").doc(franchiseId).collection("exitIslemleri");
  const hits = [];
  for (const v of variants) {
    if (!v) continue;
    const snap = await col.where("resKodu", "==", v).limit(10).get();
    snap.docs.forEach((d) => {
      const data = d.data() || {};
      if (data.isDeleted === true) return;
      hits.push({
        exitId: d.id,
        resNo: data.resKodu || v,
        plate: data.aracPlaka || "",
        customer: [data.customerFirstName, data.customerLastName].filter(Boolean).join(" "),
        km: data.km,
        source: "vehicle_sentinel_exit",
      });
    });
  }
  return hits;
}

module.exports = {
  BASE_URL,
  CAR_PATH,
  WHEELSYS_DOMAINS,
  formatMileageText,
  formatVehicleMileageText,
  formatTankText,
  formatTankHidden,
  parseMoney,
  parseInsuranceSummary,
  parseWheelsysResponse,
  parseFormToPayload,
  extractRentalFieldSnapshot,
  extractCarFieldSnapshot,
  extractCheckInUserId,
  extractCheckInUserOptions,
  rentalPreviewLooksEmpty,
  fetchRentalPage,
  fetchCarPage,
  fetchFullRentalData,
  applyVehicleMasterFields,
  updateWheelsysCheckin,
  updateWheelsysVehicleMaster,
  resolveVehicleEntityId,
  verifyMileageWithRetry,
  getEntityNotes,
  saveEntityNote,
  searchRentalsByRes,
  searchLocalExitsByRes,
};
