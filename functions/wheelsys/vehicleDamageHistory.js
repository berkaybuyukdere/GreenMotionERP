/* eslint-disable max-len */
/**
 * WheelSys vehicle damage history — car.aspx parse + attachment preview.
 * Session cookie and raw HTML never leave the server.
 */

const crypto = require("crypto");
const cheerio = require("cheerio");
const {
  fetchCarPage,
  BASE_URL,
  parseFormToPayload,
  postToWheelsys,
  CAR_PATH,
} = require("./checkinSync");
const {canonicalPlate} = require("./plateNormalize");
const {loadVehicleMasterCache} = require("./vehicleMasterCache");
const {fetchVehicleListPage} = require("./vehicleList");
const {wheelsysFetchJson} = require("./client");

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

const PREVIEW_TTL_MS = 5 * 60 * 1000;
const PREVIEW_FUNCTION = "wheelsysDamageAttachmentPreview";

/**
 * @param {string} keyHex
 * @return {string}
 */
function previewSigningKey(keyHex) {
  return crypto.createHmac("sha256", Buffer.from(keyHex, "hex"))
      .update("wheelsys-damage-attachment-preview")
      .digest();
}

/**
 * @param {object} payload
 * @param {string} keyHex
 * @return {string}
 */
function signAttachmentPreviewToken(payload, keyHex) {
  const body = JSON.stringify(payload);
  const sig = crypto.createHmac("sha256", previewSigningKey(keyHex))
      .update(body)
      .digest("base64url");
  return `${Buffer.from(body).toString("base64url")}.${sig}`;
}

/**
 * @param {string} token
 * @param {string} keyHex
 * @return {object}
 */
function verifyAttachmentPreviewToken(token, keyHex) {
  const raw = String(token || "");
  const dot = raw.indexOf(".");
  if (dot <= 0) throw new Error("Invalid preview token.");
  const bodyB64 = raw.slice(0, dot);
  const sig = raw.slice(dot + 1);
  const body = Buffer.from(bodyB64, "base64url").toString("utf8");
  const expected = crypto.createHmac("sha256", previewSigningKey(keyHex))
      .update(body)
      .digest("base64url");
  if (sig !== expected) throw new Error("Invalid preview token signature.");
  const payload = JSON.parse(body);
  if (!payload.exp || Number(payload.exp) < Date.now()) {
    throw new Error("Preview token expired.");
  }
  return payload;
}

/**
 * @param {string} href
 * @return {string}
 */
function toRelativeWheelsysPath(href) {
  const h = String(href || "").trim();
  if (!h) return "";
  if (h.startsWith("http://") || h.startsWith("https://")) {
    if (h.startsWith(BASE_URL)) return h.slice(BASE_URL.length);
    return "";
  }
  return h.startsWith("/") ? h : `/${h}`;
}

/**
 * @param {string} value
 * @return {number|null}
 */
function parseChargeAmount(value) {
  if (!value) return null;
  const cleaned = String(value)
      .replace(/CHF/gi, "")
      .replace(/\./g, "")
      .replace(",", ".")
      .replace(/[^\d.-]/g, "")
      .trim();
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * @param {string} value
 * @return {string|null}
 */
function detectCurrency(value) {
  if (!value) return null;
  if (String(value).toUpperCase().includes("CHF")) return "CHF";
  return null;
}

/**
 * @param {string} html
 * @return {object}
 */
function parseSelectedDamageDetail(html) {
  const pick = (pattern) => {
    const $ = cheerio.load(html);
    const el = $(`[name*='${pattern}'], [id*='${pattern}']`).first();
    if (!el.length) return null;
    const tag = String(el.prop("tagName") || "").toLowerCase();
    if (tag === "select") {
      return String(el.find("option[selected]").text() || el.attr("value") || "").trim() || null;
    }
    if (tag === "textarea") {
      return String(el.text() || "").trim() || null;
    }
    return String(el.attr("value") || el.text() || "").trim() || null;
  };

  return {
    vehicle: pick("Vehicle"),
    area: pick("Area"),
    element: pick("Element"),
    damageType: pick("DamageType") || pick("Damage"),
    action: pick("Action"),
    memo: pick("Memo"),
    rateText: pick("Rate"),
    chargedText: pick("Charged"),
    recordedBy: pick("RecordedBy"),
    recordedOn: pick("RecordedOn"),
    labourHours: pick("Labour"),
    source: "car.aspx.damageDetail",
  };
}

/**
 * @param {cheerio.CheerioAPI} $
 * @param {cheerio.Element} row
 * @return {object[]}
 */
function parseRowAttachments($, row) {
  const attachments = [];
  $(row).find("a[href]").each((_, link) => {
    const filename = String($(link).text() || "").trim();
    const href = String($(link).attr("href") || "").trim();
    if (!filename || !href) return;
    const looksLikeAttachment =
      /\.(jpg|jpeg|png|webp|gif|pdf)$/i.test(filename) ||
      /\.(jpg|jpeg|png|webp|gif|pdf)$/i.test(href);
    if (!looksLikeAttachment) return;
    const relPath = toRelativeWheelsysPath(href);
    if (!relPath) return;
    const lower = filename.toLowerCase();
    const fileType =
      /\.(jpg|jpeg|png|webp|gif)$/i.test(lower) ? "image" :
      /\.pdf$/i.test(lower) ? "pdf" : "other";
    attachments.push({
      filename,
      relPath,
      fileType,
      previewable: fileType === "image",
      source: "car.aspx.attachment",
    });
  });
  return attachments;
}

/**
 * @param {string} html
 * @return {object[]}
 */
function parseDamageAttachments(html) {
  const $ = cheerio.load(html);
  const attachments = [];
  $("a[href]").each((_, link) => {
    const filename = String($(link).text() || "").trim();
    const href = String($(link).attr("href") || "").trim();
    if (!filename || !href) return;
    const looksLikeAttachment =
      /\.(jpg|jpeg|png|webp|gif|pdf)$/i.test(filename) ||
      /\.(jpg|jpeg|png|webp|gif|pdf)$/i.test(href);
    if (!looksLikeAttachment) return;
    const relPath = toRelativeWheelsysPath(href);
    if (!relPath) return;
    const lower = filename.toLowerCase();
    const fileType =
      /\.(jpg|jpeg|png|webp|gif)$/i.test(lower) ? "image" :
      /\.pdf$/i.test(lower) ? "pdf" : "other";
    attachments.push({
      filename,
      relPath,
      fileType,
      previewable: fileType === "image",
      source: "car.aspx.attachment",
    });
  });
  return attachments;
}

/**
 * @param {string} html
 * @param {string} ajaxText
 * @return {string}
 */
function mergeCarHtmlSources(html, ajaxText) {
  const parts = [String(html || ""), String(ajaxText || "")];
  return parts.filter(Boolean).join("\n<!--ajax-->\n");
}

/**
 * @param {string} html
 * @return {string|null}
 */
function discoverDamagesTabPostBackTarget(html) {
  const $ = cheerio.load(html);
  let target = null;
  $("a[href*='__doPostBack'], [onclick*='__doPostBack']").each((_, el) => {
    const label = $(el).text().replace(/\s+/g, " ").trim().toLowerCase();
    if (!label.includes("damage")) return;
    const href = String($(el).attr("href") || $(el).attr("onclick") || "");
    const m = href.match(/__doPostBack\s*\(\s*['"]([^'"]+)['"]/i);
    if (m && m[1]) {
      target = m[1];
      return false;
    }
    return undefined;
  });
  return target;
}

/**
 * @param {string} cookie
 * @param {number|string} vehicleEntityId
 * @param {string} eventTarget
 * @param {string} [eventArgument]
 * @return {Promise<string>}
 */
async function postCarPanelEvent(cookie, vehicleEntityId, eventTarget, eventArgument = "") {
  const id = String(vehicleEntityId).trim();
  const {html, url: pageUrl} = await fetchCarPage(cookie, id);
  const payload = parseFormToPayload(html);
  payload.set(
      "ctl00$ctl00$ctl00$coreBody$ScriptManager",
      "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$carPanel|carPanel",
  );
  payload.set("__EVENTTARGET", eventTarget);
  payload.set("__EVENTARGUMENT", eventArgument);
  payload.set("__ASYNCPOST", "true");
  const {rawText} = await postToWheelsys(pageUrl, cookie, payload);
  return mergeCarHtmlSources(html, rawText);
}

/**
 * Load car.aspx and activate Damages tab when grid is lazy-loaded.
 * @param {string} cookie
 * @param {number|string} vehicleEntityId
 * @return {Promise<{html: string, strategy: string}>}
 */
async function fetchCarDamagesHtml(cookie, vehicleEntityId) {
  const id = String(vehicleEntityId).trim();
  const initial = await fetchCarPage(cookie, id);
  let html = initial.html;
  let rows = parseVehicleDamageGrid(html, id);
  if (rows.length > 0) {
    return {html, strategy: "initial_get"};
  }

  const tabTarget = discoverDamagesTabPostBackTarget(html);
  if (tabTarget) {
    html = await postCarPanelEvent(cookie, id, tabTarget, "");
    rows = parseVehicleDamageGrid(html, id);
    if (rows.length > 0) {
      return {html, strategy: "damages_tab_postback"};
    }
  }

  const panelArgs = [
    JSON.stringify({action: "TAB", tab: "Damages"}),
    JSON.stringify({action: "TAB", tab: "damages"}),
    JSON.stringify({action: "SWITCHTAB", itemId: id, tab: "Damages"}),
    JSON.stringify({action: "LOAD", panel: "Damages"}),
  ];
  for (const arg of panelArgs) {
    try {
      html = await postCarPanelEvent(cookie, id, "carPanel", arg);
      rows = parseVehicleDamageGrid(html, id);
      if (rows.length > 0) {
        return {html, strategy: "car_panel_tab"};
      }
    } catch (e) {
      console.warn("fetchCarDamagesHtml carPanel tab attempt failed", e.message);
    }
  }

  // Derive the cacheKey + plate the correct GetDamages PageMethod needs.
  const cacheKey = String(parseFormToPayload(initial.html).get("cachekey") || extractCacheKeyFromHtml(initial.html) || "").trim();
  const plate = String(initial.fields.plate || "").trim();
  const ajaxRows = await tryFetchVehicleDamagesFromAjax(cookie, id, {cacheKey, plate});
  if (ajaxRows.length > 0) {
    return {html, strategy: "ajax_endpoint", ajaxRows};
  }

  return {html, strategy: "empty"};
}

/**
 * Extract a cacheKey UUID from car.aspx page JS when there is no hidden field.
 * @param {string} html
 * @return {string}
 */
function extractCacheKeyFromHtml(html) {
  const h = String(html || "");
  const m = h.match(/cacheKey['"]?\s*[:=]\s*['"]([a-f0-9-]{32,36})['"]/i);
  return m && m[1] ? m[1] : "";
}

/**
 * Fetch existing vehicle damages via the correct GetDamages PageMethod.
 * PRIMARY: GetDamages(cacheKey, carid, plateno) → rental.aspx + car.aspx, rows
 * live at parsed.ExtraData. Legacy payloads are kept as fallbacks.
 * @param {string} cookie
 * @param {number|string} vehicleId
 * @param {object} [opts] {cacheKey, plate}
 * @return {Promise<object[]>}
 */
async function tryFetchVehicleDamagesFromAjax(cookie, vehicleId, opts = {}) {
  const id = Number(vehicleId);
  const cacheKey = String(opts.cacheKey || "").trim();
  const plate = String(opts.plate || "").trim();
  const referer = `${BASE_URL}${CAR_PATH}?entityId=${id}`;
  const rentalReferer = `${BASE_URL}/ui/manage/master/rental.aspx`;

  // Correct PageMethod payload first: {cacheKey, carid, plateno}.
  const primary = {cacheKey, carid: id, plateno: plate};
  const attempts = [
    {path: "/ui/manage/master/rental.aspx/GetDamages", body: primary, referer: rentalReferer, primary: true},
    {path: `${CAR_PATH}/GetDamages`, body: primary, referer, primary: true},
    // Legacy fallbacks (kept for resilience if the PageMethod shape changes).
    {path: `${CAR_PATH}/GetDamages`, body: {entityId: id, carId: id}, referer},
    {path: `${CAR_PATH}/GetVehicleDamages`, body: {entityId: id, carId: id}, referer},
    {path: `${CAR_PATH}/GetDamages`, body: {vehicleId: id}, referer},
    {path: "/ui/manage/master/rental.aspx/GetDamages", body: {carId: id}, referer: rentalReferer},
  ];

  for (const attempt of attempts) {
    try {
      const {outer} = await wheelsysFetchJson(cookie, attempt.path, attempt.body, {referer: attempt.referer});
      const rows = attempt.primary ?
        normalizeGetDamagesExtraData(outer, id, plate) :
        normalizeAjaxDamageRows(outer, id);
      console.info(
          `tryFetchVehicleDamagesFromAjax ${attempt.path} primary=${Boolean(attempt.primary)} ` +
          `cacheKey=${cacheKey ? "yes" : "no"} plate=${plate || "n/a"} rows=${rows.length}`,
      );
      if (rows.length > 0) return rows;
    } catch (e) {
      console.warn(`tryFetchVehicleDamagesFromAjax ${attempt.path}`, e.message);
    }
  }
  return [];
}

/**
 * Normalize GetDamages → parsed.ExtraData rows into the same grid-row shape the
 * HTML parser emits, so getVehicleDamageHistory keeps producing the existing
 * record shape (with attachments + signed previewPath) for iOS.
 * @param {object} outer ASP.NET {d: ...}
 * @param {number} vehicleId
 * @param {string} plate
 * @return {object[]}
 */
function normalizeGetDamagesExtraData(outer, vehicleId, plate) {
  if (!outer) return [];
  let d = outer.d != null ? outer.d : outer;
  if (typeof d === "string") {
    try {
      d = JSON.parse(d);
    } catch (_) {
      return [];
    }
  }
  let extra = d && (d.ExtraData != null ? d.ExtraData : (d.extraData != null ? d.extraData : null));
  if (typeof extra === "string") {
    try {
      extra = JSON.parse(extra);
    } catch (_) {
      extra = null;
    }
  }
  const list = Array.isArray(extra) ? extra :
    (Array.isArray(d) ? d : (d && Array.isArray(d.rows) ? d.rows : []));
  if (!list.length) return [];

  const get = (row, ...keys) => {
    for (const k of keys) {
      if (row[k] != null && row[k] !== "") return row[k];
    }
    return null;
  };

  return list.map((row, index) => {
    const r = row || {};
    const attachUrl = get(r, "AttachmentUrl", "attachmentUrl", "FileUrl", "DocUrl", "Url", "url");
    const attachName = get(r, "AttachmentName", "attachmentName", "FileName", "fileName", "Filename");
    const attachUid = get(r, "AttachmentUid", "attachmentUid", "DocUid", "FileUid", "Uid", "uid");
    const attachments = [];
    const name = attachName != null ? String(attachName) : "";
    if (name && /\.(jpg|jpeg|png|webp|gif|pdf)$/i.test(name)) {
      let relPath = "";
      if (attachUrl) {
        relPath = toRelativeWheelsysPath(String(attachUrl));
      } else if (attachUid) {
        // Best-effort uid path (documented assumption — see precheckin.js).
        relPath = `/handlers/formupload.ashx?uid=${encodeURIComponent(String(attachUid))}&name=${encodeURIComponent(name)}`;
      }
      if (relPath) {
        const fileType = /\.(jpg|jpeg|png|webp|gif)$/i.test(name) ? "image" :
          (/\.pdf$/i.test(name) ? "pdf" : "other");
        attachments.push({
          filename: name,
          relPath,
          fileType,
          previewable: fileType === "image",
          source: "rental.GetDamages.attachment",
        });
      }
    }

    const charge = get(r, "NetCharge", "netCharge", "Charge", "Charged", "Amount");
    return {
      damageNo: String(get(r, "DamageNo", "damageNo", "No", "Id", "DamageId", "id") || (index + 1)),
      vehicleId,
      plateNo: get(r, "Plateno", "PlateNo", "plateNo", "plateno") || plate || null,
      damageType: get(r, "DamageType", "damageType", "Damage", "Type"),
      chargeText: charge != null ? String(charge) : null,
      relatedRentalNo: get(r, "RentalNo", "rentalNo", "RNT", "RelatedRentalNo", "RaNo", "DocNo"),
      addedOn: get(r, "EntryDate", "entryDate", "AddedOn", "DateAdded", "RecordedOn", "Date"),
      attachments,
      source: "rental.GetDamages",
    };
  });
}

/**
 * @param {object} outer
 * @param {number} vehicleId
 * @return {object[]}
 */
function normalizeAjaxDamageRows(outer, vehicleId) {
  const d = outer && outer.d;
  let data = d && d.data != null ? d.data : null;
  if (typeof data === "string") {
    try {
      data = JSON.parse(data);
    } catch (_) {
      data = null;
    }
  }
  const list = Array.isArray(data) ? data :
    (data && Array.isArray(data.rows) ? data.rows :
      (data && Array.isArray(data.damages) ? data.damages : []));
  if (!list.length) return [];

  return list.map((row, index) => ({
    damageNo: String(row.damageNo || row.No || row.no || index + 1),
    vehicleId,
    plateNo: row.plateNo || row.PlateNo || row.Vehicle || row.vehicle || null,
    damageType: row.damageType || row.DamageType || row.type || null,
    chargeText: row.chargeText || row.Charge || row.charge || null,
    relatedRentalNo: row.relatedRentalNo || row.RA || row.RNT || row.rentalNo || null,
    addedOn: row.addedOn || row.AddedOn || row.date || null,
    attachments: [],
    source: "car.aspx.ajax",
  })).filter((row) => row.damageType || row.relatedRentalNo);
}

/**
 * @param {cheerio.Cheerio} cells
 * @param {cheerio.CheerioAPI} $
 * @return {string[]}
 */
function cellTexts(cells, $) {
  return cells.map((_, c) => {
    return String($(c).text() || "")
        .replace(/\u00a0/g, " ")
        .replace(/\s+/g, " ")
        .trim();
  }).get();
}

/**
 * @param {string[]} texts
 * @param {string} rowText
 * @return {boolean}
 */
function looksLikeDamageGridRow(texts, rowText) {
  if (!texts || texts.length < 3) return false;
  const joined = texts.join(" ").toLowerCase();
  if (/^no\.?\s*vehicle\s+damage type/i.test(joined)) return false;
  if (joined.includes("damage type") && joined.includes("added on")) return false;

  const hasRnt = /RNT-\d+/i.test(rowText);
  const hasDamageCode = texts.some((t) => /^#\d{2,4}-/.test(t));
  const hasPlate = texts.some((t) => /^[A-Z]{1,3}\s?[A-Z0-9]{3,8}$/i.test(t.replace(/\s/g, "")));
  const hasDate = /\d{1,2}[./]\d{1,2}[./]\d{2,4}/.test(rowText);
  const hasDamageWord = /scratch|dent|chip|bumper|wing|wheel|glass/i.test(rowText);

  return (hasRnt || hasDamageCode || hasDamageWord) && (hasPlate || hasDate || hasRnt);
}

/**
 * @param {string} html
 * @param {number|string} vehicleId
 * @return {object[]}
 */
function parseVehicleDamageGrid(html, vehicleId) {
  const $ = cheerio.load(html);
  const vid = Number(vehicleId);
  const rows = [];
  const seen = new Set();

  const pushRow = (cells, rowEl) => {
    if (!cells || cells.length < 3) return;
    const texts = cellTexts(cells, $);
    const rowText = texts.join(" ");
    if (!looksLikeDamageGridRow(texts, rowText)) return;

    const damageNo = texts[0] || null;
    const plateNo = texts[1] || null;
    let damageType = texts[2] || null;
    let chargeText = texts[3] || null;
    let relatedRentalNo = texts[4] || null;
    let addedOn = texts[5] || null;

    // Some grids omit plate column when viewing single vehicle.
    if (plateNo && /^#\d/.test(plateNo)) {
      addedOn = texts[5] || texts[4] || addedOn;
      relatedRentalNo = texts[4] || texts[3] || relatedRentalNo;
      chargeText = texts[3] || texts[2] || chargeText;
      damageType = plateNo;
    }

    for (let i = 0; i < texts.length; i += 1) {
      if (/^RNT-\d+/i.test(texts[i])) relatedRentalNo = texts[i].toUpperCase();
      if (/^#\d{2,4}-/.test(texts[i])) damageType = texts[i];
      if (/\d{1,2}[./]\d{1,2}[./]\d{2,4}/.test(texts[i])) addedOn = texts[i];
      if (/CHF|\d+[.,]\d{2}/.test(texts[i]) && !/^RNT-/i.test(texts[i])) {
        chargeText = chargeText || texts[i];
      }
    }

    if (!damageType && !relatedRentalNo) return;

    const key = [damageNo, plateNo, damageType, relatedRentalNo, addedOn].join("\u0001");
    if (seen.has(key)) return;
    seen.add(key);

    rows.push({
      damageNo,
      vehicleId: vid,
      plateNo,
      damageType,
      chargeText,
      relatedRentalNo,
      addedOn,
      attachments: parseRowAttachments($, rowEl),
      source: "car.aspx.damageGrid",
    });
  };

  const selectors = [
    "#damageGrid tr",
    "#ctl00_ctl00_ctl00_coreBody_contentBody_formFields_carPanel_DamageGrid tr",
    ".damage-grid tr",
    "[id*='DamageGrid'] tr",
    "[id*='Damage'] table tr",
    "[id*='damage'] table tr",
    "table[id*='damage'] tr",
    "table[class*='damage'] tr",
    ".rgMasterTable tr.rgRow",
    ".rgMasterTable tr.rgAltRow",
    "tr.rgRow",
    "tr.rgAltRow",
    "tr[role='row']",
  ];

  for (const sel of selectors) {
    $(sel).each((_, row) => {
      const cells = $(row).find("td, [role='gridcell']");
      pushRow(cells, row);
    });
    if (rows.length) break;
  }

  if (!rows.length) {
    $("table tr").each((_, row) => {
      if ($(row).find("th").length > 0) return;
      const cells = $(row).find("td");
      pushRow(cells, row);
    });
  }

  return rows;
}

/**
 * @param {string} cookie
 * @param {number|string} vehicleId
 * @return {Promise<{html: string, url: string}>}
 */
async function fetchWheelsysVehiclePage(cookie, vehicleId) {
  const page = await fetchCarPage(cookie, vehicleId);
  return {html: page.html, url: page.url};
}

/**
 * @param {string} attachmentUrl
 * @param {string} cookie
 * @return {Promise<{buffer: Buffer, contentType: string}>}
 */
async function fetchWheelsysAttachmentAsBuffer(attachmentUrl, cookie) {
  const url = String(attachmentUrl || "").trim();
  if (!url.startsWith(BASE_URL)) {
    throw new Error("Invalid attachment URL.");
  }
  const res = await fetch(url, {
    method: "GET",
    headers: {
      "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
      "User-Agent": UA,
      "Cookie": cookie,
      "Referer": `${BASE_URL}/ui/manage/master/car.aspx`,
    },
    redirect: "follow",
  });
  if (!res.ok) {
    throw new Error(`Failed to fetch Wheelsys attachment (${res.status}).`);
  }
  const arrayBuffer = await res.arrayBuffer();
  return {
    buffer: Buffer.from(arrayBuffer),
    contentType: res.headers.get("content-type") || "application/octet-stream",
  };
}

/**
 * @param {object} opts
 * @return {Promise<string|null>}
 */
async function resolveVehicleEntityId(opts) {
  const {
    db,
    franchiseId,
    station = "ZRH",
    wheelsysVehicleId,
    plate,
    rentalFields,
    fleetCarIdHint,
    wheelsysCookie,
  } = opts || {};

  const push = (v) => {
    const s = String(v || "").trim();
    return /^\d+$/.test(s) ? s : null;
  };

  const plateNorm = plate ? canonicalPlate(plate) : "";

  if (plateNorm && db) {
    try {
      const cache = await loadVehicleMasterCache(db, franchiseId, station);
      const vehicles = cache && Array.isArray(cache.vehicles) ? cache.vehicles : [];
      const hit = vehicles.find((v) => {
        const np = canonicalPlate(v.normalizedPlate || v.plateNo || "");
        return np && np === plateNorm;
      });
      if (hit) {
        const id = push(hit.wheelsysVehicleId || hit.id);
        if (id) return id;
      }
    } catch (e) {
      console.warn("resolveVehicleEntityId fleet cache lookup failed", e.message);
    }
  }

  if (plateNorm && wheelsysCookie) {
    const searchValues = [
      plate,
      plateNorm,
      plateNorm.replace(/^([A-Z]{2})(\d)/, "$1 $2"),
    ].filter(Boolean);
    for (const searchValue of searchValues) {
      try {
        const batch = await fetchVehicleListPage(wheelsysCookie, {
          station,
          searchField: "Plateno",
          searchValue,
          pageSize: 25,
        });
        const hit = (batch.rows || []).find((v) => {
          const np = canonicalPlate(v.normalizedPlate || v.plateNo || "");
          return np === plateNorm;
        });
        if (hit) {
          const id = push(hit.wheelsysVehicleId || hit.id);
          if (id) {
            console.info(
                `resolveVehicleEntityId plate=${plateNorm} -> entityId=${id} via vehicle master`,
            );
            return id;
          }
        }
      } catch (e) {
        console.warn("resolveVehicleEntityId vehicle master search failed", e.message);
      }
    }
  }

  if (rentalFields && rentalFields.vehicleEntityId) {
    const id = push(rentalFields.vehicleEntityId);
    if (id) return id;
  }

  const id = push(wheelsysVehicleId) || push(fleetCarIdHint);
  if (id) return id;

  return null;
}

/**
 * @param {object} p
 * @return {Promise<object>}
 */
async function getVehicleDamageHistory(p) {
  const vehicleId = Number(p.vehicleId);
  if (!Number.isFinite(vehicleId) || vehicleId <= 0) {
    throw new Error("Invalid vehicleId.");
  }
  if (!p.wheelsysCookie) throw new Error("Missing WheelSys session cookie.");

  const fetched = await fetchCarDamagesHtml(p.wheelsysCookie, vehicleId);
  const html = fetched.html;
  const damageRows = fetched.ajaxRows && fetched.ajaxRows.length ?
    fetched.ajaxRows :
    parseVehicleDamageGrid(html, vehicleId);
  const pageAttachments = parseDamageAttachments(html);
  const detail = parseSelectedDamageDetail(html);
  const syncedAt = new Date().toISOString();
  const keyHex = String(p.encryptionKeyHex || "");
  const franchiseId = String(p.franchiseId || "CH").toUpperCase();
  const station = String(p.station || "ZRH").toUpperCase();

  const damages = damageRows.map((row, index) => {
    const rowAttachments = row.attachments && row.attachments.length ?
      row.attachments :
      (index === 0 ? pageAttachments : []);

    const attachments = rowAttachments.map((attachment, attachmentIndex) => {
      const attachmentId = `${vehicleId}-${index}-${attachmentIndex}`;
      let previewPath = null;
      if (attachment.previewable && attachment.relPath && keyHex) {
        const token = signAttachmentPreviewToken({
          franchiseId,
          station,
          relPath: attachment.relPath,
          exp: Date.now() + PREVIEW_TTL_MS,
        }, keyHex);
        previewPath = `${PREVIEW_FUNCTION}?token=${encodeURIComponent(token)}`;
      }
      return {
        attachmentId,
        filename: attachment.filename,
        fileType: attachment.fileType,
        previewable: attachment.previewable,
        previewPath,
      };
    });

    return {
      damageId: `${vehicleId}-${row.damageNo || index}`,
      damageNo: row.damageNo,
      vehicleId,
      plateNo: row.plateNo,
      normalizedPlateNo: row.plateNo ? canonicalPlate(row.plateNo) : null,
      damageType: row.damageType || detail.damageType,
      area: detail.area,
      element: detail.element,
      action: detail.action,
      memo: detail.memo,
      chargeText: row.chargeText || detail.chargedText || detail.rateText,
      chargeAmount: parseChargeAmount(row.chargeText || detail.chargedText || detail.rateText),
      currency: detectCurrency(row.chargeText || detail.chargedText || detail.rateText),
      relatedRentalNo: row.relatedRentalNo,
      addedOn: row.addedOn || detail.recordedOn,
      recordedBy: detail.recordedBy,
      recordedOn: detail.recordedOn,
      labourHours: detail.labourHours,
      attachments,
      relatedItems: [],
      source: "wheelsys.car.aspx",
      syncedAt,
    };
  });

  return {
    vehicleId,
    damages,
    damageCount: damages.length,
    syncedAt,
    parseStrategy: fetched.strategy,
    htmlHasRntMarker: /RNT-\d+/i.test(html),
    htmlHasDamageCode: /#\d{2,4}-/.test(html),
  };
}

/**
 * Stream attachment bytes for HTTP preview endpoint.
 * @param {object} req
 * @param {object} res
 * @param {object} deps
 * @return {Promise<void>}
 */
async function handleDamageAttachmentPreview(req, res, deps) {
  if (req.method !== "GET") {
    res.status(405).json({error: "method_not_allowed"});
    return;
  }

  try {
    const authHeader = String(req.headers.authorization || "");
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({error: "unauthenticated"});
      return;
    }
    await deps.verifyIdToken(authHeader.slice(7).trim());

    const token = String(req.query.token || "");
    const payload = verifyAttachmentPreviewToken(token, deps.encryptionKeyHex);
    const cookie = await deps.loadCookie({
      franchiseId: payload.franchiseId,
      station: payload.station || "ZRH",
    });

    const relPath = String(payload.relPath || "");
    if (!relPath || relPath.includes("..")) {
      res.status(400).json({error: "invalid_attachment_path"});
      return;
    }
    const absoluteUrl = `${BASE_URL}${relPath.startsWith("/") ? "" : "/"}${relPath}`;
    if (!absoluteUrl.startsWith(BASE_URL)) {
      res.status(400).json({error: "invalid_attachment_url"});
      return;
    }

    const file = await fetchWheelsysAttachmentAsBuffer(absoluteUrl, cookie);
    res.set("Content-Type", file.contentType);
    res.set("Cache-Control", "private, max-age=300");
    res.send(file.buffer);
  } catch (e) {
    console.warn("handleDamageAttachmentPreview", e.message);
    if (!res.headersSent) {
      const status = /unauthenticated|auth/i.test(e.message) ? 401 :
        /expired|Invalid preview/i.test(e.message) ? 403 : 500;
      res.status(status).json({error: e.message || "Attachment preview failed."});
    }
  }
}

module.exports = {
  fetchWheelsysVehiclePage,
  fetchCarDamagesHtml,
  fetchWheelsysAttachmentAsBuffer,
  parseVehicleDamageGrid,
  parseSelectedDamageDetail,
  parseDamageAttachments,
  getVehicleDamageHistory,
  resolveVehicleEntityId,
  tryFetchVehicleDamagesFromAjax,
  handleDamageAttachmentPreview,
  signAttachmentPreviewToken,
  verifyAttachmentPreviewToken,
  PREVIEW_FUNCTION,
};
