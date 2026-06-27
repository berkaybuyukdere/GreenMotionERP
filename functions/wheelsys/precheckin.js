/* eslint-disable max-len */
/**
 * WheelSys rental "Pre-check-in" context builder + submit.
 *
 * All WheelSys traffic stays server-side: the session cookie, raw HTML and
 * customer-sensitive fields (license/passport/phone/card) NEVER leave the
 * server. Attachment + body-diagram image URLs are exposed only as short-lived
 * signed preview tokens that the existing wheelsysDamageAttachmentPreview HTTP
 * function can resolve with the cookie.
 *
 * Pre-check-in save mirrors the browser: CalcRates (PRECHECKIN → KMDriven →
 * FuelPolicy) then rental.aspx async postback with
 * __EVENTARGUMENT {"action":"BTSAVE","itemId":...} while rdStatus stays 2.
 * Success is confirmed only by wheels.afterSave({...}).success === true.
 */

const cheerio = require("cheerio");
const {
  BASE_URL,
  CAR_PATH,
  parseFormToPayload,
  postToWheelsys,
  fetchRentalPage,
  searchRentalsByRes,
  parseMoney,
  mapCustomerFromRentalForm,
  formatMileageText,
  formatTankText,
  formatTankHidden,
  extractRentalFieldSnapshot,
  resolveCheckInUserId,
  resolveCheckInUserName,
  pickNamedFormValue,
  backfillIdentityFormFields,
  extractSelectFieldMeta,
  zurichWheelSysNow,
} = require("./checkinSync");
const {
  extractCacheKey,
  combineDateTimeLocal,
  localIsoToUtcIso,
  canUseCar,
  calcRates,
  buildCalcRatesPayload,
} = require("./bookingAssignment");
const {
  wheelsysFetchJson,
  normalizePlate,
  WheelsysClientError,
  ERR,
} = require("./client");
const {
  signAttachmentPreviewToken,
  PREVIEW_FUNCTION,
} = require("./vehicleDamageHistory");

const RENTAL_PATH = "/ui/manage/master/rental.aspx";
const VEHICLE_DIAGRAM_PATH = "/api/entities/rentalsupport/car/vehiclediagram";
const PREVIEW_TTL_MS = 5 * 60 * 1000;

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

/**
 * Read a trimmed string value from a URLSearchParams form or plain object.
 * @param {URLSearchParams|object} form
 * @param {string} key
 * @return {string}
 */
function formGet(form, key) {
  if (form && typeof form.get === "function") return String(form.get(key) || "").trim();
  if (form && form[key] != null) return String(form[key]).trim();
  return "";
}

/**
 * @param {*} value
 * @return {number|null}
 */
function toIntOrNull(value) {
  if (value == null || value === "") return null;
  const cleaned = String(value).replace(/[^\d-]/g, "");
  if (cleaned === "" || cleaned === "-") return null;
  const n = parseInt(cleaned, 10);
  return Number.isFinite(n) ? n : null;
}

/**
 * Parse a CHF money string: strip "CHF", "." as thousands, "," as decimal.
 * Returns null when empty/unparseable.
 * @param {*} value
 * @return {number|null}
 */
function parseChfMoney(value) {
  const raw = String(value == null ? "" : value).trim();
  if (!raw) return null;
  const n = parseMoney(raw);
  return Number.isFinite(n) ? n : null;
}

/**
 * @param {object} row
 * @param {...string} keys
 * @return {*}
 */
function pick(row, ...keys) {
  if (!row || typeof row !== "object") return null;
  for (const key of keys) {
    if (row[key] != null && row[key] !== "") return row[key];
  }
  return null;
}

/**
 * Convert WheelSys "/Date(ms)/" (or parseable date) into ISO 8601.
 * @param {*} value
 * @return {string|null}
 */
function parseWheelsysDate(value) {
  if (value == null || value === "") return null;
  const s = String(value);
  const m = s.match(/\/Date\((-?\d+)(?:[+-]\d{4})?\)\//);
  if (m) {
    const ms = Number(m[1]);
    if (Number.isFinite(ms)) return new Date(ms).toISOString();
  }
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/**
 * Reduce a WheelSys href/URL to a path relative to BASE_URL (or "" if external).
 * @param {string} href
 * @return {string}
 */
function toRelativeWheelsysPath(href) {
  const h = String(href || "").trim();
  if (!h) return "";
  if (/^https?:\/\//i.test(h)) {
    if (h.startsWith(BASE_URL)) return h.slice(BASE_URL.length);
    return "";
  }
  return h.startsWith("/") ? h : `/${h}`;
}

/**
 * Build a short-lived signed preview path the existing attachment-preview HTTP
 * function can resolve. Returns a relative `wheelsysDamageAttachmentPreview?token=…`
 * string (never the raw WheelSys URL/cookie).
 * @param {object} opts
 * @return {string|null}
 */
function buildSignedPreviewPath({relPath, encryptionKeyHex, franchiseId, station}) {
  const rel = String(relPath || "").trim();
  const keyHex = String(encryptionKeyHex || "");
  if (!rel || !keyHex || rel.includes("..")) return null;
  const token = signAttachmentPreviewToken({
    franchiseId: String(franchiseId || "CH").toUpperCase(),
    station: String(station || "ZRH").toUpperCase(),
    relPath: rel,
    exp: Date.now() + PREVIEW_TTL_MS,
  }, keyHex);
  return `${PREVIEW_FUNCTION}?token=${encodeURIComponent(token)}`;
}

/**
 * @param {string} name
 * @return {boolean}
 */
function looksLikeImageName(name) {
  return /\.(jpg|jpeg|png|webp|gif)$/i.test(String(name || ""));
}

/**
 * Full ASP.NET form snapshot for rental.aspx (reuses the shared parser).
 * @param {string} html
 * @return {URLSearchParams}
 */
function parseRentalFormFromHtml(html) {
  return parseFormToPayload(html);
}

/**
 * Map primary customer (driverInfoContainer["1"], fallback rdDriver_*).
 * Exposes only display identity — never license/passport/phone/card.
 * @param {URLSearchParams|object} form
 * @return {object}
 */
function mapCustomer(form) {
  const c = mapCustomerFromRentalForm(form);
  const driverId = c.wheelsysDriverId != null && Number.isFinite(Number(c.wheelsysDriverId)) ?
    Number(c.wheelsysDriverId) : null;
  return {
    driverId,
    firstName: c.firstName || null,
    lastName: c.lastName || null,
    fullName: c.fullName || "",
    email: c.email || null,
  };
}

/**
 * Map assigned vehicle. rdPlateNo_value is the vehicle/car id (NOT the driver).
 * @param {URLSearchParams|object} form
 * @return {object}
 */
function mapVehicle(form) {
  const plateNo = formGet(form, "rdPlateNo_text");
  return {
    vehicleId: toIntOrNull(formGet(form, "rdPlateNo_value")),
    plateNo: plateNo || "",
    normalizedPlateNo: plateNo ? normalizePlate(plateNo) : "",
    model: formGet(form, "rdModel_text") || null,
    modelId: toIntOrNull(formGet(form, "rdModel_value")),
    bookedGroup: formGet(form, "rdGroup_combo") || null,
    chargedGroup: formGet(form, "rdGroupInv_combo") || null,
  };
}

/**
 * @param {URLSearchParams|object} form
 * @return {object}
 */
function mapMileageFuel(form) {
  const checkoutMileage = toIntOrNull(formGet(form, "rdMileageFrom_hidden"));
  const checkoutFuel = toIntOrNull(formGet(form, "rdTankFrom_hidden"));
  const rawReturnMileage = toIntOrNull(formGet(form, "rdMileageTo_hidden"));
  const rawReturnFuel = toIntOrNull(formGet(form, "rdTankTo_hidden"));
  return {
    checkoutMileage,
    checkoutFuel,
    currentReturnMileage: rawReturnMileage === 0 ? null : rawReturnMileage,
    currentReturnFuel: rawReturnFuel === 0 ? null : rawReturnFuel,
    milesDriven: toIntOrNull(formGet(form, "rdMilesDriven_hidden")),
  };
}

/**
 * @param {URLSearchParams|object} form
 * @return {object}
 */
function mapInsurance(form) {
  return {
    excessAmount: parseChfMoney(formGet(form, "rdExcess_hidden")),
    cdp: formGet(form, "rdCdp_combo") || null,
    insuranceCharge: parseChfMoney(formGet(form, "rdInsurance_hidden")),
    damageCharge: parseChfMoney(formGet(form, "rdDamages_hidden")),
    damageExcess: parseChfMoney(formGet(form, "rdDmgExcess_hidden")),
    currency: "CHF",
  };
}

/**
 * @param {URLSearchParams|object} form
 * @param {string|number} rentalId
 * @return {object}
 */
function mapRental(form, rentalId) {
  return {
    rentalId: toIntOrNull(rentalId),
    rntNo: formGet(form, "rdDispDocno_text") || null,
    resNo: formGet(form, "rdResDocDisp_text") || formGet(form, "rdResDocNo") || null,
    irn: formGet(form, "rdIrnDisp_text") || null,
    voucherNo: formGet(form, "rdVoucherno_text") || null,
    confirmationNo: formGet(form, "rdConfno_text") || null,
  };
}

/**
 * @param {URLSearchParams|object} form
 * @return {Array<object>}
 */
function parseRentalAttachments(form) {
  const raw = formGet(form, "formAttachments$formAttachments_hidden");
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed;
    if (parsed && Array.isArray(parsed.Attachments)) return parsed.Attachments;
    return [];
  } catch (_) {
    return [];
  }
}

/**
 * Extract the cacheKey from rental.aspx (JS regex or the hidden "cachekey" field).
 * @param {string} html
 * @param {URLSearchParams|object} form
 * @return {string}
 */
function resolveCacheKey(html, form) {
  return String(extractCacheKey(html) || formGet(form, "cachekey") || "").trim();
}

/**
 * Vehicle body diagram: POST urlencoded plateNo/CarId.
 * Returns the ImgUrl as a signed preview path when it is a WheelSys-hosted
 * (relative/same-host) asset. If ImgUrl is an absolute EXTERNAL https URL (e.g.
 * a public S3 bodychart image with no auth/secrets) we return it directly,
 * since it is a public, non-sensitive diagram and routing it through the
 * cookie-authed proxy would add no security. We never return a same-host raw
 * URL — those are signed.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<object>}
 */
async function fetchVehicleDiagram(cookie, opts) {
  const {plateNo, vehicleId, encryptionKeyHex, franchiseId, station} = opts || {};
  const params = new URLSearchParams({
    plateNo: String(plateNo || ""),
    CarId: String(vehicleId || ""),
  });
  const res = await fetch(`${BASE_URL}${VEHICLE_DIAGRAM_PATH}`, {
    method: "POST",
    headers: {
      "Cookie": cookie,
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest",
      "Accept": "application/json, text/javascript, */*; q=0.01",
      "Origin": BASE_URL,
      "Referer": `${BASE_URL}${RENTAL_PATH}`,
      "User-Agent": UA,
    },
    body: params.toString(),
  });
  if (!res.ok) {
    throw new Error(`vehiclediagram failed (${res.status}).`);
  }
  const json = await res.json();
  let root = json && json.d != null ? json.d : json;
  if (typeof root === "string") {
    try {
      root = JSON.parse(root);
    } catch (_) {
      root = json;
    }
  }
  const diagram = (root && (root.Diagram || root.diagram)) || {};
  const miles = (root && (root.Miles || root.miles)) || {};

  const rawImg = String(diagram.ImgUrl || diagram.imgUrl || "");
  let imageUrl = null;
  if (rawImg) {
    const rel = toRelativeWheelsysPath(rawImg);
    if (rel) {
      imageUrl = buildSignedPreviewPath({relPath: rel, encryptionKeyHex, franchiseId, station});
    } else if (/^https:\/\//i.test(rawImg)) {
      // Public, external bodychart image (no cookie/secret needed) — safe to return as-is.
      imageUrl = rawImg;
    }
  }

  return {
    imageUrl,
    width: toIntOrNull(diagram.Width || diagram.width),
    height: toIntOrNull(diagram.Height || diagram.height),
    miles: {
      mileage: toIntOrNull(miles.Mileage || miles.mileage),
      fuel: toIntOrNull(miles.Fuel || miles.fuel),
      modelName: pick(miles, "ModelName", "modelName"),
      carGroup: pick(miles, "CarGroup", "carGroup"),
      stationCode: pick(miles, "StationCode", "stationCode"),
    },
  };
}

/**
 * Pull the ExtraData rows out of a GetDamages response (raw.d may be a string).
 * @param {object} outer
 * @return {Array<object>}
 */
function extractDamageRowsFromOuter(outer) {
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
  if (Array.isArray(extra)) return extra;
  if (Array.isArray(d)) return d;
  if (d && Array.isArray(d.rows)) return d.rows;
  return [];
}

/**
 * Build signed preview paths for all attachments on a GetDamages row.
 * @param {object} row
 * @param {object} signOpts
 * @return {Array<object>}
 */
function buildDamageAttachments(row, signOpts) {
  const out = [];
  const seen = new Set();
  const add = (att) => {
    if (!att || !att.previewPath) return;
    if (seen.has(att.previewPath)) return;
    seen.add(att.previewPath);
    out.push(att);
  };

  const nestedLists = [
    pick(row, "Attachments", "attachments", "Photos", "photos", "Files", "files", "Documents", "documents"),
  ];
  for (const list of nestedLists) {
    if (!Array.isArray(list)) continue;
    for (const item of list) {
      add(buildDamageAttachment(item, signOpts));
    }
  }

  if (row && typeof row === "object") {
    for (const [key, val] of Object.entries(row)) {
      if (typeof val !== "string") continue;
      const s = val.trim();
      if (!s) continue;
      if (/\.(jpg|jpeg|png|webp|gif)(\?|$)/i.test(s) ||
          /formupload\.ashx|documentpreview|\/handlers\//i.test(s)) {
        add(buildDamageAttachment({
          AttachmentUrl: s,
          AttachmentName: pick(row, "AttachmentName", "FileName") || `${key}.jpg`,
          AttachmentUid: pick(row, "AttachmentUid", "Uid", "DocUid"),
        }, signOpts));
      }
    }
  }

  add(buildDamageAttachment(row, signOpts));
  add(buildDamageAttachment({
    AttachmentUrl: pick(row, "PhotoUrl", "photoUrl", "ImageUrl", "imageUrl", "ImgUrl", "imgUrl", "ThumbnailUrl"),
    AttachmentName: pick(row, "PhotoName", "photoName", "ImageName", "FileName", "AttachmentName"),
    AttachmentUid: pick(row, "PhotoUid", "photoUid", "ImageUid", "AttachmentUid", "DocUid"),
  }, signOpts));

  return out;
}

/**
 * Build a signed preview path for a damage-row attachment.
 *
 * RISK/ASSUMPTION: GetDamages rows reference photos either by an explicit
 * URL/path field (preferred — we sign the relative WheelSys path) or only by
 * AttachmentUid+AttachmentName. There is no confirmed uid→URL endpoint in the
 * HAR captures yet, so for uid-only rows we sign a best-effort WheelSys path
 * (formupload handler). If that path 404s, the preview endpoint fails
 * gracefully without leaking anything.
 * @param {object} row
 * @param {object} signOpts
 * @return {{uid: (string|null), name: (string|null), previewable: boolean, previewPath: (string|null)}}
 */
function buildDamageAttachment(row, signOpts) {
  const attachUid = pick(row, "AttachmentUid", "attachmentUid", "DocUid", "FileUid", "Uid", "uid");
  const attachName = pick(row, "AttachmentName", "attachmentName", "FileName", "fileName", "Filename");
  const attachUrl = pick(row, "AttachmentUrl", "attachmentUrl", "FileUrl", "fileUrl", "DocUrl", "Url", "url",
      "PhotoUrl", "photoUrl", "ImageUrl", "imageUrl", "ImgUrl", "imgUrl", "ThumbnailUrl", "thumbnailUrl");

  const uid = attachUid != null ? String(attachUid) : null;
  const name = attachName != null ? String(attachName) : null;
  const previewable = looksLikeImageName(name) ||
    looksLikeImageName(attachUrl) ||
    Boolean(uid && name);

  let relPath = "";
  if (attachUrl) {
    relPath = toRelativeWheelsysPath(String(attachUrl));
  } else if (uid && name) {
    relPath = `/handlers/formupload.ashx?uid=${encodeURIComponent(uid)}&name=${encodeURIComponent(name)}`;
  } else if (uid) {
    relPath = `/handlers/formupload.ashx?uid=${encodeURIComponent(uid)}`;
  }

  const previewPath = previewable && relPath ?
    buildSignedPreviewPath({...signOpts, relPath}) : null;

  return {uid, name, previewable: Boolean(previewable && previewPath), previewPath};
}

/**
 * Normalize one GetDamages ExtraData row into the iOS damage record shape.
 * Existing damages are READ-ONLY.
 * @param {object} row
 * @param {object} opts
 * @return {object}
 */
function normalizeDamageRow(row, opts) {
  const r = row || {};
  const uid = pick(r, "Uid", "uid", "Guid", "guid");
  const damageIdRaw = pick(r, "Id", "DamageId", "damageId", "id", "DamageNo", "damageNo", "No");
  const damageId = String(damageIdRaw != null ? damageIdRaw : (uid != null ? uid : ""));

  const attachments = buildDamageAttachments(r, {
    encryptionKeyHex: opts.encryptionKeyHex,
    franchiseId: opts.franchiseId,
    station: opts.station,
  });
  const attachment = attachments[0] || buildDamageAttachment(r, {
    encryptionKeyHex: opts.encryptionKeyHex,
    franchiseId: opts.franchiseId,
    station: opts.station,
  });

  return {
    damageId,
    uid: uid != null ? String(uid) : null,
    vehicleId: toIntOrNull(pick(r, "CarId", "carid", "carId", "VehicleId", "vehicleId")) ||
      (opts.vehicleId != null ? Number(opts.vehicleId) : null),
    plateNo: pick(r, "Plateno", "PlateNo", "plateNo", "plateno") || opts.plateNo || null,
    damageType: pick(
        r, "DamageTypeTableName", "DamageType", "damageType", "Damage", "Type",
    ),
    actionName: pick(r, "ActionName", "actionName", "Action", "action"),
    memo: pick(r, "Memo", "memo", "Notes", "Note", "Description"),
    netCharge: parseChfMoney(pick(r, "NetCharge", "netCharge", "Charge", "Charged", "Amount")),
    relatedRentalNo: pick(r, "RentalNo", "rentalNo", "RNT", "RelatedRentalNo", "RaNo", "DocNo"),
    relatedRentalId: toIntOrNull(pick(r, "RentalId", "rentalId", "RelatedRentalId", "RentalTable_Id")),
    addedByName: pick(r, "AddedByName", "addedByName", "CreatedBy", "RecordedBy", "UserName", "User"),
    entryDate: parseWheelsysDate(pick(r, "EntryDate", "entryDate", "AddedOn", "DateAdded", "RecordedOn", "Date")),
    position: {
      x: numOrNull(pick(r, "PosX", "posX", "X", "x")),
      y: numOrNull(pick(r, "PosY", "posY", "Y", "y")),
      markerWidth: numOrNull(pick(r, "MarkerWidth", "markerWidth", "Width", "W")),
      markerHeight: numOrNull(pick(r, "MarkerHeight", "markerHeight", "Height", "H")),
    },
    areaName: pick(
        r, "DamageAreaName", "AreaName", "areaName", "Area", "area",
    ),
    elementName: pick(
        r, "DamageElementTableName", "ElementName", "elementName", "Element", "element",
    ),
    attachment,
    attachments,
    flags: {
      isReadOnly: pickBool(r, "IsReadOnly", "isReadOnly", "ReadOnly"),
      isFixed: pickBool(r, "IsFixed", "isFixed", "Fixed"),
      excessCovered: pickBool(r, "ExcessCovered", "excessCovered", "IsExcessCovered"),
    },
    source: "wheelsys.rental.GetDamages",
  };
}

/**
 * @param {*} value
 * @return {number|null}
 */
function numOrNull(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/**
 * @param {object} row
 * @param {...string} keys
 * @return {boolean}
 */
function pickBool(row, ...keys) {
  const v = pick(row, ...keys);
  if (v == null) return false;
  if (typeof v === "boolean") return v;
  const s = String(v).toLowerCase();
  return s === "true" || s === "1" || s === "yes";
}

/**
 * Existing vehicle damages via the correct PageMethod GetDamages(cacheKey, carid, plateno).
 * Tries rental.aspx first, then car.aspx. Existing damages are READ-ONLY.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<Array<object>>}
 */
async function fetchExistingDamages(cookie, opts) {
  const {rentalId, cacheKey, vehicleId, plateNo} = opts || {};
  const carid = Number(vehicleId);
  const body = {
    cacheKey: String(cacheKey || ""),
    carid: Number.isFinite(carid) ? carid : vehicleId,
    plateno: String(plateNo || ""),
  };
  const referer = `${BASE_URL}${RENTAL_PATH}?entityId=${rentalId}`;
  const paths = [`${RENTAL_PATH}/GetDamages`, `${CAR_PATH}/GetDamages`];

  for (const path of paths) {
    try {
      const {outer} = await wheelsysFetchJson(cookie, path, body, {referer});
      const rows = extractDamageRowsFromOuter(outer);
      console.info(`[WheelSys][Precheckin] GetDamages ${path} rows=${rows.length} carid=${body.carid}`);
      if (rows.length) {
        return rows.map((row) => normalizeDamageRow(row, opts));
      }
    } catch (e) {
      console.warn(`[WheelSys][Precheckin] GetDamages ${path} failed: ${e.message}`);
    }
  }
  return [];
}

/**
 * canusecar warnings (non-blocking unless IsUsable === false).
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<{isUsable: boolean, warnings: string[]}>}
 */
async function fetchCanUseCar(cookie, opts) {
  const {rentalId, plateNo, vehicleId, dateFrom, dateTo} = opts || {};
  try {
    const result = await canUseCar(cookie, {
      plateNo,
      carId: vehicleId,
      dateFrom,
      dateTo,
      usageReq: "2",
      rentalId,
    });
    const warnings = Array.isArray(result && result.Warnings) ?
      result.Warnings
          .map((w) => String((w && (w.AvailAction || w.Message || w.message)) || "").trim())
          .filter(Boolean) :
      [];
    // Only block when WheelSys explicitly says IsUsable === false.
    const isUsable = !(result && result.IsUsable === false);
    return {isUsable, warnings};
  } catch (e) {
    console.warn(`[WheelSys][Precheckin] canusecar failed: ${e.message}`);
    return {isUsable: true, warnings: []};
  }
}

/**
 * Resolve a numeric rentalId from explicit id or RES/RNT search.
 * @param {string} cookie
 * @param {object} opts
 * @return {Promise<string>}
 */
async function resolvePrecheckinRentalId(cookie, opts) {
  const id = String((opts && opts.rentalId) || "").trim();
  if (/^\d+$/.test(id)) return id;
  const query = String((opts && (opts.resNo || opts.rntNo)) || "").trim();
  if (query) {
    const hits = await searchRentalsByRes(cookie, query).catch(() => []);
    const hit = (hits || []).find((h) => h && /^\d+$/.test(String(h.entityId)));
    if (hit) return String(hit.entityId);
  }
  throw new WheelsysClientError(
      ERR.NO_DATA,
      "Could not resolve rental. Provide a valid rentalId or RES/RNT number.",
  );
}

/** Finalized / closed rental statuses only — not return-in-progress (3). */
const PRECHECKIN_INELIGIBLE_RD_STATUS = new Set(["4", "5"]);

/**
 * Detect whether rental.aspx is in a state where PRECHECKIN is allowed.
 * @param {string} html
 * @param {URLSearchParams|object} form
 * @return {object}
 */
function detectPrecheckinEligibility(html, form) {
  const snap = extractRentalFieldSnapshot(html);
  const titleMatch = String(html || "").match(/<title>\s*([^<]+)/i);
  const pageTitle = String((titleMatch && titleMatch[1]) || "").trim();
  const titleLower = pageTitle.toLowerCase();
  const rdStatus = String(formGet(form, "rdStatus") || snap.status || "").trim();
  const rdUsageType = String(formGet(form, "rdUsageType") || snap.usageType || "").trim();
  let dbgInitialStatus = null;
  const dbgMatch = String(html || "").match(/dbgInitialStatus\s*=\s*(\d+)/);
  if (dbgMatch) dbgInitialStatus = dbgMatch[1];

  let eligible = true;
  let reason = null;
  let reasonCode = null;

  // Post pre-check-in / check-in review state (rdStatus=3, rdUsageType=2 per CH BTSAVE flow).
  if (rdStatus === "3" && rdUsageType === "2") {
    eligible = false;
    reasonCode = "already_in_checkin_review";
    reason = "Pre-check-in cannot be completed because this rental is already in review/check-in status in Wheelsys.";
  } else if (PRECHECKIN_INELIGIBLE_RD_STATUS.has(rdStatus)) {
    eligible = false;
    reasonCode = "closed_status";
    reason = `Rental is closed in WheelSys (rdStatus=${rdStatus}). Pre-check-in is not available.`;
  } else if (/closed|checked.?in|finaliz/i.test(titleLower) && !/review\s+rental/i.test(pageTitle)) {
    eligible = false;
    reasonCode = "title_closed";
    reason = "Rental title indicates closed or finalized status.";
  }

  return {
    eligible,
    eligibleForPrecheckin: eligible,
    reasonCode,
    reason,
    blocker: reason,
    pageTitle: pageTitle || null,
    dbgInitialStatus,
    rdStatus: rdStatus || null,
    rdUsageType: rdUsageType || null,
    rdDispDocno_text: formGet(form, "rdDispDocno_text") || snap.dispDocNo || null,
    rdRaDocNo_text: formGet(form, "rdRaDocNo_text") || snap.raNo || null,
    rdResDocNo_text: formGet(form, "rdResDocNo_text") || snap.resNo || null,
    rdDateTo_text: formGet(form, "rdDateTo_text") || snap.dateTo || null,
    rdTimeTo_text: formGet(form, "rdTimeTo_text") || snap.timeTo || null,
  };
}

/**
 * Orchestrate the full pre-check-in context:
 * GET rental.aspx once → parse form → GetDamages + vehiclediagram + canusecar
 * in parallel. Returns the normalized API contract object.
 * @param {object} p
 * @return {Promise<object>}
 */
async function buildPrecheckinContext(p) {
  const {cookie, encryptionKeyHex, franchiseId, station} = p || {};
  const rentalId = await resolvePrecheckinRentalId(cookie, p);

  const page = await fetchRentalPage(cookie, rentalId);
  const form = parseCompleteRentalFormToPayload(page.html);
  const cacheKey = resolveCacheKey(page.html, form);

  const customer = mapCustomer(form);
  const vehicle = mapVehicle(form);
  const mileageFuel = mapMileageFuel(form);
  const insurance = mapInsurance(form);
  const rental = mapRental(form, rentalId);

  const dateFromLocal = combineDateTimeLocal(formGet(form, "rdDateFrom_text"), formGet(form, "rdTimeFrom_text"));
  const dateToLocal = combineDateTimeLocal(formGet(form, "rdDateTo_text"), formGet(form, "rdTimeTo_text"));
  const dateFromUtc = localIsoToUtcIso(dateFromLocal);
  const dateToUtc = localIsoToUtcIso(dateToLocal);

  const signOpts = {encryptionKeyHex, franchiseId, station};

  const [existingDamages, diagram, usability] = await Promise.all([
    fetchExistingDamages(cookie, {
      rentalId,
      cacheKey,
      vehicleId: vehicle.vehicleId,
      plateNo: vehicle.plateNo,
      ...signOpts,
    }).catch((e) => {
      console.warn(`[WheelSys][Precheckin] existingDamages error: ${e.message}`);
      return [];
    }),
    (vehicle.plateNo || vehicle.vehicleId) ?
      fetchVehicleDiagram(cookie, {
        plateNo: vehicle.plateNo,
        vehicleId: vehicle.vehicleId,
        ...signOpts,
      }).catch((e) => {
        console.warn(`[WheelSys][Precheckin] vehiclediagram error: ${e.message}`);
        return null;
      }) :
      Promise.resolve(null),
    (vehicle.plateNo && vehicle.vehicleId && dateFromUtc && dateToUtc) ?
      fetchCanUseCar(cookie, {
        rentalId,
        plateNo: vehicle.plateNo,
        vehicleId: vehicle.vehicleId,
        dateFrom: dateFromUtc,
        dateTo: dateToUtc,
      }) :
      Promise.resolve({isUsable: true, warnings: []}),
  ]);

  const blockers = [];
  if (!customer.driverId) blockers.push("customer_id");
  if (!vehicle.vehicleId) blockers.push("vehicle_id");
  if (!vehicle.plateNo) blockers.push("plate");
  if (!dateFromLocal) blockers.push("checkout_date");
  if (!dateToLocal) blockers.push("return_date");
  const eligibility = detectPrecheckinEligibility(page.html, form);
  if (!eligibility.eligible) {
    blockers.push("rental_status_not_eligible");
  }
  const warnings = [...(usability.warnings || [])];
  if (!eligibility.eligible && eligibility.reason) {
    warnings.push(eligibility.reason);
  }
  const ready = blockers.length === 0;

  return {
    success: true,
    rental,
    customer,
    vehicle,
    mileageFuel,
    insurance,
    bodyDiagram: {
      imageUrl: diagram ? diagram.imageUrl : null,
      width: diagram ? diagram.width : null,
      height: diagram ? diagram.height : null,
    },
    existingDamages,
    carUsability: {
      isUsable: usability.isUsable,
      warnings: usability.warnings,
    },
    precheckinEligibility: eligibility,
    precheckinStatus: {ready, blockers, warnings},
    syncedAt: new Date().toISOString(),
  };
}

/**
 * Sanitize raw WheelSys text for safe logging / API debug payloads.
 * @param {string} text
 * @param {number} [maxLen]
 * @return {string}
 */
function sanitizeResponseSnippet(text, maxLen = 2000) {
  const raw = String(text || "").slice(0, maxLen);
  let out = "";
  for (let i = 0; i < raw.length; i++) {
    const code = raw.charCodeAt(i);
    out += code < 32 && code !== 9 && code !== 10 && code !== 13 ? " " : raw[i];
  }
  return out;
}

/**
 * Extract wheels.afterSave JSON using comma-terminated fallback (ASP.NET delta).
 * @param {string} text
 * @return {object|null}
 */
function extractAfterSaveFromDelta(text) {
  const t = String(text || "").replace(/\\u0022/g, "\"");
  const marker = "wheels.afterSave(";
  const start = t.indexOf(marker);
  if (start === -1) return null;

  const balanced = parseAfterSaveObject(t);
  if (balanced) return balanced;

  const jsonStart = start + marker.length;
  const possibleEnds = [
    t.indexOf(", false);", jsonStart),
    t.indexOf(",false);", jsonStart),
    t.indexOf(");", jsonStart),
  ].filter((i) => i > -1);
  if (possibleEnds.length === 0) return null;
  const jsonEnd = Math.min(...possibleEnds);
  const jsonText = t.slice(jsonStart, jsonEnd).trim();
  try {
    return JSON.parse(jsonText);
  } catch (_) {
    return null;
  }
}

/**
 * Pull scriptStartupBlock / PageRequestManager snippets mentioning errors.
 * @param {string} text
 * @return {string[]}
 */
function extractScriptStartupSnippets(text) {
  const out = [];
  const raw = String(text || "");
  const re = /(?:scriptStartupBlock|PageRequestManager)[\s\S]{0,240}(?:afterSave|error|warning|Validation|required|cannot)[\s\S]{0,480}/gi;
  let m;
  while ((m = re.exec(raw)) !== null && out.length < 8) {
    out.push(sanitizeResponseSnippet(m[0], 400));
  }
  if (out.length === 0) {
    const idx = raw.indexOf("wheels.afterSave(");
    if (idx >= 0) {
      out.push(sanitizeResponseSnippet(raw.slice(Math.max(0, idx - 80), idx + 420)));
    }
  }
  return out;
}

/**
 * Build structured diagnostics for a PRECHECKIN postback response.
 * @param {string} rawText
 * @param {number} httpStatus
 * @param {object} [extra]
 * @return {object}
 */
function buildPrecheckinDiagnostics(rawText, httpStatus, extra = {}) {
  const t = String(rawText || "");
  const normalized = t.replace(/\\u0022/g, "\"").replace(/\\"/g, "\"");
  const afterSave = extractAfterSaveFromDelta(t) ||
    extractAfterSaveFromDelta(normalized) ||
    parseAfterSaveObject(t);

  return {
    httpStatus: Number(httpStatus) || 0,
    responseLength: t.length,
    containsAfterSave: t.includes("wheels.afterSave(") || normalized.includes("wheels.afterSave("),
    containsPrecheckin: /PRECHECKIN/i.test(t),
    containsRecordChanged: /Record was changed/i.test(t),
    containsValidation: /Validation/i.test(t),
    containsRequired: /\brequired\b/i.test(t),
    containsRequiredError: /RequiredError/i.test(t),
    containsCannot: /\bcannot\b/i.test(t),
    sanitizedSnippet: sanitizeResponseSnippet(t),
    scriptStartupSnippets: extractScriptStartupSnippets(t),
    requiredErrorSnippets: extractRequiredErrorSnippets(t),
    afterSave: afterSave || null,
    postbackFormat: extra.postbackFormat || null,
    postbackSource: extra.postbackSource || null,
    missingRequiredFields: extra.missingRequiredFields || [],
  };
}

/**
 * Resolve success/failure from raw WheelSys delta text (never generic-only).
 * @param {string} rawText
 * @param {number} httpStatus
 * @param {object} [formatMeta]
 * @return {object}
 */
function resolvePrecheckinPostbackResult(rawText, httpStatus, formatMeta = {}) {
  const debug = buildPrecheckinDiagnostics(rawText, httpStatus, formatMeta);
  const afterSave = debug.afterSave;

  if (afterSave && afterSave.success === true) {
    return {
      success: true,
      message: String(afterSave.message || ""),
      afterSave,
      debug,
      staleRecord: false,
      retryable: false,
      httpStatus,
    };
  }

  if (afterSave && afterSave.success === false) {
    const msg = String(afterSave.message || "WheelSys pre-check-in rejected.");
    const stale = /Record was changed/i.test(msg);
    return {
      success: false,
      message: msg,
      afterSave,
      debug,
      staleRecord: stale,
      retryable: stale,
      httpStatus,
    };
  }

  let message = "PRECHECKIN was not executed or not confirmed.";
  if (debug.containsRequiredError) {
    const snippet = (debug.requiredErrorSnippets || [])[0] || "";
    message = snippet ?
      `RequiredError before PRECHECKIN: ${snippet.slice(0, 240)}` :
      "RequiredError — rental form has missing required fields.";
  } else if (debug.containsRecordChanged) {
    message = "Record was changed by another user.";
  } else if (debug.containsValidation) {
    const valMatch = String(rawText || "").match(/Validation[^"'\n]{0,160}/i);
    message = valMatch ? valMatch[0].trim() : "Validation error in WheelSys response.";
  } else if (debug.containsRequired) {
    const reqMatch = String(rawText || "").match(/required[^"'\n]{0,120}/i);
    message = reqMatch ? reqMatch[0].trim() : "Required field missing in WheelSys response.";
  } else if (debug.containsCannot) {
    const cannotMatch = String(rawText || "").match(/cannot[^"'\n]{0,120}/i);
    message = cannotMatch ? cannotMatch[0].trim() : "WheelSys rejected the pre-check-in request.";
  } else {
    const msgMatch = String(rawText || "").match(/"message"\s*:\s*"([^"\\]{1,300})"/);
    if (msgMatch) message = msgMatch[1];
  }

  console.warn(
      "[WheelSys][Precheckin] no afterSave — " +
      `len=${debug.responseLength} afterSave=${debug.containsAfterSave} ` +
      `precheckin=${debug.containsPrecheckin} format=${formatMeta.postbackSource || "?"}`,
  );
  console.warn(
      "[WheelSys][Precheckin] snippet:",
      debug.sanitizedSnippet.slice(0, 500),
  );

  return {
    success: false,
    message,
    afterSave: null,
    debug,
    staleRecord: debug.containsRecordChanged,
    retryable: debug.containsRecordChanged && !debug.containsRequiredError,
    httpStatus,
  };
}

/**
 * Extract context around RequiredError markers in a Wheelsys response.
 * @param {string} html
 * @return {string[]}
 */
function extractRequiredErrorSnippets(html) {
  const snippets = [];
  const raw = String(html || "");
  let index = 0;
  while ((index = raw.indexOf("RequiredError", index)) !== -1) {
    const start = Math.max(0, index - 300);
    const end = Math.min(raw.length, index + 300);
    snippets.push(sanitizeResponseSnippet(raw.slice(start, end), 600));
    index += "RequiredError".length;
  }
  return snippets;
}

/** Hard blockers — rentalId path must not depend on Fleet Chart for these. */
const PRECHECKIN_CRITICAL_FIELDS = [
  "cachekey",
  "rdDispDocno_text",
  "rdDriver_value",
  "rdPlateNo_value",
  "rdPlateNo_text",
  "rdDateFrom_text",
  "rdDateTo_text",
];

/** Logged immediately before PRECHECKIN POST for Wheelsys RequiredError diagnosis. */
const PRECHECKIN_SUBMIT_LOG_FIELDS = [
  "cachekey",
  "rdDispDocno_text",
  "rdDriver_value",
  "rdDriver_text",
  "driverInfoContainer",
  "rdPlateNo_value",
  "rdPlateNo_text",
  "rdDateFrom_text",
  "rdTimeFrom_text",
  "rdDateTo_text",
  "rdTimeTo_text",
  "rdStationFrom_combo",
  "rdStationTo_combo",
  "rdGroup_combo",
  "rdGroupInv_combo",
  "rdModel_value",
  "rdModel_text",
  "rdMileageFrom_hidden",
  "rdMileageTo_hidden",
  "rdMilesDriven_hidden",
  "rdTankFrom_hidden",
  "rdTankTo_hidden",
  "rdUserTo_combo",
  "rdCdp_combo",
  "rdRateCode_combo",
];

/** Fields that should be present in rental.aspx form before PRECHECKIN postback. */
const PRECHECKIN_REQUIRED_FIELDS = [
  "cachekey",
  "rdDispDocno_text",
  "rdUsageType",
  "rdStatus",
  "rdDriver_text",
  "rdDriver_value",
  "driverInfoContainer",
  "rdAgent_text",
  "rdAgent_value",
  "rdDateFrom_text",
  "rdTimeFrom_text",
  "rdDateTo_text",
  "rdTimeTo_text",
  "rdStationFrom_combo",
  "rdStationTo_combo",
  "rdGroup_combo",
  "rdGroupInv_combo",
  "rdModel_text",
  "rdModel_value",
  "rdPlateNo_text",
  "rdPlateNo_value",
  "rdMileageFrom_hidden",
  "rdTankFrom_hidden",
  "rdCdp_combo",
  "rdRateCode_combo",
];

/**
 * @param {URLSearchParams|object} form
 * @return {string[]}
 */
function findMissingRequiredFields(form) {
  return PRECHECKIN_REQUIRED_FIELDS.filter((name) => {
    const value = formGet(form, name);
    return value === null || value === undefined || String(value).trim() === "";
  });
}

/**
 * Set a form field when current value is missing/blank.
 * @param {URLSearchParams} payload
 * @param {string} name
 * @param {string} value
 */
/**
 * Always overwrite when a non-empty value is known (HAR-critical identity fields).
 * @param {URLSearchParams} payload
 * @param {string} name
 * @param {string} value
 */
function forceFormField(payload, name, value) {
  const next = String(value || "").trim();
  if (next) payload.set(name, next);
}

/**
 * Ensure rental identity/display fields are present before PRECHECKIN POST.
 * @param {URLSearchParams} payload
 * @param {string} html
 */
function ensureRentalIdentityFields(payload, html) {
  backfillIdentityFormFields(payload, html);
  const snap = extractRentalFieldSnapshot(html);
  const titleMatch = String(html || "").match(/Review rental\s*-\s*(RNT-\d+)/i);
  const titleRa = titleMatch ? titleMatch[1] : "";
  const dispDoc = snap.dispDocNo || snap.raNo || titleRa;
  forceFormField(payload, "rdDispDocno_text", dispDoc);
  // HAR: rdRaDocNo=RNT-13282 (same as rdDispDocno_text)
  forceFormField(payload, "rdRaDocNo", dispDoc);
  forceFormField(payload, "rdResDocDisp_text", snap.resNo);
  forceFormField(payload, "rdResDocNo", pickNamedFormValue(html, "rdResDocNo") || snap.resNo);
  forceFormField(payload, "rdIrnDisp_text", snap.irn);
  forceFormField(payload, "rdConfno_text", snap.confirmationNo);
  forceFormField(payload, "rdVoucherno_text", snap.voucherNo);
  forceFormField(payload, "rdUsageType", snap.usageType || "2");
  forceFormField(payload, "rdDriver_value", formGet(payload, "rdDriver_value") || snap.userTo);
  forceFormField(payload, "rdPlateNo_value", snap.vehicleEntityId);
  if (snap.plate) {
    forceFormField(payload, "rdPlateNo_text", snap.plate);
  }
  // HAR pre-check-in save posts rdStatus=2 while rental is on rent (usageType=2).
  const status = String(formGet(payload, "rdStatus") || snap.status || "").trim();
  if (status === "1" || status === "2") {
    forceFormField(payload, "rdStatus", "2");
  } else if (status) {
    forceFormField(payload, "rdStatus", status);
  }
}

/**
 * Log critical rental form values before PRECHECKIN submit.
 * @param {URLSearchParams|object} form
 * @param {string|number} [rentalId]
 */
function logPrecheckinSubmitFields(form, rentalId = "") {
  const id = rentalId ? ` rentalId=${rentalId}` : "";
  console.info(`[WheelSys][Precheckin] submit field snapshot${id}`);
  for (const key of PRECHECKIN_SUBMIT_LOG_FIELDS) {
    console.info("[PRECHECKIN_FIELD]", key, JSON.stringify(formGet(form, key) || ""));
  }
}

/**
 * Parse rental.aspx into a complete POST payload and backfill critical fields.
 * @param {string} html
 * @return {URLSearchParams}
 */
function parseCompleteRentalFormToPayload(html) {
  const payload = parseRentalFormFromHtml(html);
  enrichRentalFormPayload(payload, html);
  ensureRentalIdentityFields(payload, html);
  return payload;
}

/**
 * Read effective input value from rental.aspx DOM (data-prevalue, selected option).
 * @param {cheerio.Cheerio} el
 * @param {string} [fieldName]
 * @return {string}
 */
function effectiveDomValue(el, fieldName = "") {
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
 * Backfill cachekey, driverInfoContainer and snapshot fields missing from parser.
 * @param {URLSearchParams} payload
 * @param {string} html
 */
function enrichRentalFormPayload(payload, html) {
  const cacheKey = resolveCacheKey(html, payload);
  if (cacheKey) {
    payload.set("cachekey", cacheKey);
  }

  const snap = extractRentalFieldSnapshot(html);
  const backfillPairs = [
    ["rdMileageFrom_hidden", snap.mileageFromHidden],
    ["rdMileageFrom_text", snap.mileageFromText],
    ["rdMileageTo_hidden", snap.mileageToHidden],
    ["rdMileageTo_text", snap.mileageToText],
    ["rdTankFrom_hidden", snap.tankFromHidden],
    ["rdTankFrom_text", snap.tankFromText],
    ["rdTankTo_hidden", snap.tankToHidden],
    ["rdTankTo_text", snap.tankToText],
    ["rdDateFrom_text", snap.dateFrom],
    ["rdTimeFrom_text", snap.timeFrom],
    ["rdDateTo_text", snap.dateTo],
    ["rdTimeTo_text", snap.timeTo],
    ["rdPlateNo_text", snap.plate],
    ["rdPlateNo_value", snap.vehicleEntityId],
    ["rdModel_text", snap.vehicleModel],
  ];
  for (const [name, value] of backfillPairs) {
    if (value && !formGet(payload, name)) {
      payload.set(name, String(value));
    }
  }

  const $ = cheerio.load(html);
  for (const name of PRECHECKIN_REQUIRED_FIELDS) {
    if (formGet(payload, name)) continue;
    const el = $(`#${name}, [name="${name}"]`).first();
    if (!el.length) continue;
    if (el.is("select")) {
      const selected = String(el.find("option[selected]").attr("value") || "").trim();
      if (selected) {
        payload.set(name, selected);
        continue;
      }
      let fallback = "";
      el.find("option").each((_, o) => {
        const v = String($(o).attr("value") || "").trim();
        if (v && !fallback) fallback = v;
      });
      if (fallback) payload.set(name, fallback);
      continue;
    }
    const value = effectiveDomValue(el, name);
    if (value) payload.set(name, value);
  }

  const driverInfoEl = $("[name=\"driverInfoContainer\"]").first();
  if (driverInfoEl.length) {
    const driverInfo = String(
        driverInfoEl.attr("value") || driverInfoEl.text() || "",
    ).trim();
    if (driverInfo && !formGet(payload, "driverInfoContainer")) {
      payload.set("driverInfoContainer", driverInfo);
    }
  }

  const checkInUser = resolveCheckInUserId(html, null);
  if (checkInUser && !formGet(payload, "rdUserTo_combo")) {
    payload.set("rdUserTo_combo", checkInUser);
  }

  ensureRentalIdentityFields(payload, html);
}

/**
 * Derive __EVENTTARGET / __EVENTARGUMENT / ScriptManager from wheels.postBack JS.
 * Falls back to BTSAVE-compatible {action, itemId} shape (WHEELSYS-REPORT §22.7).
 * @param {string} jsText
 * @param {string} command
 * @param {string|number} itemId
 * @return {{eventTarget: string, scriptManager: string, eventArgument: object, source: string}}
 */
function derivePrecheckinPostbackRequest(jsText, command, itemId) {
  const id = String(itemId);
  const cmd = String(command || "PRECHECKIN");
  const defaultTarget = "rentalPanel";
  const defaultPanel = "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel";
  let eventTarget = defaultTarget;
  let scriptManager = `${defaultPanel}|${defaultTarget}`;
  let eventArgument = {action: cmd, itemId: id};
  let source = "wheels-report-btsave-shape";

  const raw = String(jsText || "");
  const targetMatch = raw.match(
      /getPostBackTarget\s*[=:]\s*function[^}]*return\s*["']([^"']+)["']/i,
  );
  if (targetMatch && targetMatch[1]) {
    eventTarget = targetMatch[1];
    scriptManager = `${defaultPanel}|${eventTarget}`;
    source = "js-getPostBackTarget";
  }

  const postBackFn = raw.match(/postBack\s*=\s*function\s*\([^)]*\)\s*\{([\s\S]{0,4000}?)\}/i);
  if (postBackFn && postBackFn[1]) {
    const body = postBackFn[1];
    const stringifyMatch = body.match(/JSON\.stringify\s*\(\s*(\{[\s\S]*?\})\s*\)/);
    if (stringifyMatch && stringifyMatch[1]) {
      const template = stringifyMatch[1]
          .replace(/command/g, `"${cmd}"`)
          .replace(/action/g, `"${cmd}"`)
          .replace(/\bpk\b/g, `"${id}"`)
          .replace(/itemId/g, `"${id}"`);
      try {
        eventArgument = JSON.parse(template);
        source = "js-postBack-stringify";
      } catch (_) {
        eventArgument = {action: cmd, itemId: id};
      }
    }
    const smMatch = body.match(/ScriptManager[^|]*\|["']([^"']+)["']/i) ||
      body.match(/\|\s*["']([A-Z_]+)["']\s*[,+]/i);
    if (smMatch && smMatch[1]) {
      scriptManager = `${defaultPanel}|${smMatch[1]}`;
    }
    if (/PRECHECKIN/i.test(body) && /getPostBackTarget/i.test(body)) {
      source = "js-postBack-body";
    }
  }

  const cmdPanelMatch = raw.match(
      new RegExp(`${defaultPanel}\\|${cmd}`, "i"),
  );
  if (cmdPanelMatch) {
    scriptManager = `${defaultPanel}|${cmd}`;
    source = "js-scriptmanager-command";
  }

  return {eventTarget, scriptManager, eventArgument, source};
}

/**
 * Discover PRECHECKIN __EVENTARGUMENT candidates from rental.aspx + wheels JS.
 * @param {string} html
 * @param {string|number} rentalId
 * @param {string} [jsText]
 * @return {Array<{arg: object, eventTarget: string, scriptManager: string, source: string}>}
 */
function discoverPrecheckinPostbackFormats(html, rentalId, jsText = "") {
  const id = String(rentalId);
  const formats = [];
  const seen = new Set();
  const add = (req, source) => {
    const key = JSON.stringify({
      arg: req.eventArgument,
      eventTarget: req.eventTarget,
      scriptManager: req.scriptManager,
    });
    if (seen.has(key)) return;
    seen.add(key);
    formats.push({
      arg: req.eventArgument,
      eventTarget: req.eventTarget,
      scriptManager: req.scriptManager,
      source,
    });
  };

  const derived = derivePrecheckinPostbackRequest(`${html}\n${jsText}`, "BTSAVE", id);
  add(derived, derived.source);

  add({
    eventTarget: "rentalPanel",
    scriptManager: "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|rentalPanel",
    eventArgument: {action: "BTSAVE", itemId: id},
  }, "btsave-shape");

  const h = String(html || "");
  const cmdDecl = h.match(/precheckin\s*:\s*['"]([^'"]+)['"]/i);
  const cmdWord = cmdDecl && cmdDecl[1] ? cmdDecl[1] : "PRECHECKIN";
  add(
      derivePrecheckinPostbackRequest(`${html}\n${jsText}`, cmdWord, id),
      "html-rentalcommands",
  );

  add({
    eventTarget: "rentalPanel",
    scriptManager: "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|PRECHECKIN",
    eventArgument: {action: "PRECHECKIN", itemId: id},
  }, "scriptmanager-precheckin");

  add({
    eventTarget: "rentalPanel",
    scriptManager: "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|rentalPanel",
    eventArgument: {action: "PRECHECKIN", itemId: id},
  }, "legacy-precheckin-shape");

  return prioritizePrecheckinFormats(formats);
}

/**
 * Prefer ScriptManager PRECHECKIN shape; cap attempts to avoid callable timeouts.
 * @param {Array<object>} formats
 * @return {Array<object>}
 */
function prioritizePrecheckinFormats(formats) {
  // Browser HAR (ONLYCHECKINANDSAVEPROCESS): CalcRates sequence then BTSAVE postback.
  const order = [
    "btsave-shape",
    "js-getPostBackTarget",
    "js-postBack-stringify",
    "js-scriptmanager-command",
    "js-postBack-body",
    "wheels-report-btsave-shape",
    "html-rentalcommands",
    "scriptmanager-precheckin",
    "legacy-precheckin-shape",
  ];
  const sorted = [...(formats || [])].sort((a, b) => {
    const ia = order.indexOf(a.source);
    const ib = order.indexOf(b.source);
    return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
  });
  return sorted.slice(0, 2);
}

/**
 * Apply return km/fuel onto rental form before PRECHECKIN (does not set postback).
 * HAR reference: mileageFrom=149213, mileageTo=149214, milesDriven=1 (always ≥1).
 * @param {URLSearchParams} payload
 * @param {object} opts
 */
function applyPrecheckinMileageFields(payload, opts) {
  const {mileageTo, fuelTo} = opts || {};
  const mileageFrom = Number(payload.get("rdMileageFrom_hidden") || 0);

  let km = null;
  if (mileageTo != null && Number.isFinite(Number(mileageTo)) && Number(mileageTo) > 0) {
    const candidate = Number(mileageTo);
    km = candidate > mileageFrom ? candidate : mileageFrom + 1;
  } else if (mileageFrom > 0) {
    // Always need at least 1 driven km — HAR minimum.
    km = mileageFrom + 1;
    console.info(`[WheelSys][Precheckin] mileageTo missing/zero — using mileageFrom+1=${km}`);
  }

  if (km != null) {
    const milesDriven = Math.max(1, km - mileageFrom);
    payload.set("rdMileageTo_text", formatMileageText(km));
    payload.set("rdMileageTo_hidden", String(km));
    payload.set("rdMilesDriven_text", `${milesDriven} km`);
    payload.set("rdMilesDriven_hidden", String(milesDriven));
  }

  if (fuelTo != null && Number.isFinite(Number(fuelTo))) {
    const fuel = Number(fuelTo);
    if (fuel >= 0 && fuel <= 8) {
      payload.set("rdTankTo_text", formatTankText(fuel));
      payload.set("rdTankTo_hidden", formatTankHidden(fuel));
    }
  }
}

/**
 * Apply return km/fuel and related check-in fields before PRECHECKIN.
 * @param {URLSearchParams} payload
 * @param {string} html
 * @param {object} opts
 */
function applyPrecheckinReturnFields(payload, html, opts) {
  const {mileageTo, fuelTo, checkInUserId, storedSessionUserId} = opts || {};
  const snap = extractRentalFieldSnapshot(html);

  if (snap.mileageFromHidden && !formGet(payload, "rdMileageFrom_hidden")) {
    payload.set("rdMileageFrom_hidden", snap.mileageFromHidden);
    forceFormField(
        payload,
        "rdMileageFrom_text",
        snap.mileageFromText || formatMileageText(snap.mileageFromHidden),
    );
  }
  if (snap.tankFromHidden && !formGet(payload, "rdTankFrom_hidden")) {
    payload.set("rdTankFrom_hidden", snap.tankFromHidden);
    forceFormField(
        payload,
        "rdTankFrom_text",
        snap.tankFromText || formatTankText(snap.tankFromHidden),
    );
  }

  applyPrecheckinMileageFields(payload, {mileageTo, fuelTo});

  const userId = resolveCheckInUserId(html, checkInUserId, storedSessionUserId);
  if (userId) {
    forceFormField(payload, "rdUserTo_combo", userId);
    const userName = resolveCheckInUserName(html, userId);
    if (userName) forceFormField(payload, "rdUserTo_text", userName);
  }

  const zurichNow = zurichWheelSysNow();
  payload.set("rdDateTo_text", zurichNow.date);
  payload.set("rdTimeTo_text", zurichNow.time);
}

/**
 * Set rentalPanel async postback fields for a toolbar/save command.
 * @param {URLSearchParams} payload
 * @param {object} eventArg
 * @param {object} [meta]
 */
function applyPrecheckinPostback(payload, eventArg, meta = {}) {
  const eventTarget = meta.eventTarget || "rentalPanel";
  const scriptManager = meta.scriptManager ||
    "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|rentalPanel";
  payload.set("ctl00$ctl00$ctl00$coreBody$ScriptManager", scriptManager);
  payload.set("__EVENTTARGET", eventTarget);
  payload.set("__EVENTARGUMENT", JSON.stringify(eventArg));
  payload.set("__ASYNCPOST", "true");
}

/**
 * Validate rental form fields required before PRECHECKIN submit.
 * @param {URLSearchParams|object} form
 * @param {string} html
 * @return {{ready: boolean, blockers: string[], cacheKey: string, missingRequiredFields: string[]}}
 */
function validatePrecheckinForm(form, html) {
  const missingRequiredFields = findMissingRequiredFields(form);
  const missingCritical = PRECHECKIN_CRITICAL_FIELDS.filter((name) => {
    const value = formGet(form, name);
    return value === null || value === undefined || String(value).trim() === "";
  });
  const blockers = missingCritical.map((f) => `missing_${f}`);
  const cacheKey = resolveCacheKey(html, form);
  if (!cacheKey) {
    blockers.push("cacheKey");
  }
  return {
    ready: blockers.length === 0,
    blockers,
    cacheKey,
    missingRequiredFields,
    missingCritical,
  };
}

/**
 * Map pre-check-in damage rows to vehicle damage history API shape.
 * @param {Array<object>} rows
 * @param {object} opts
 * @return {Array<object>}
 */
function mapPrecheckinDamagesToHistory(rows, opts) {
  const syncedAt = new Date().toISOString();
  const vehicleId = Number(opts.vehicleId) || 0;
  return (rows || []).map((row, index) => {
    const attList = Array.isArray(row.attachments) && row.attachments.length ?
      row.attachments :
      (row.attachment ? [row.attachment] : []);
    const attachments = attList
        .filter((att) => att && att.previewable && att.previewPath)
        .map((att, attIndex) => ({
          attachmentId: `${row.damageId || index}-${attIndex}`,
          filename: att.name || "photo.jpg",
          fileType: "image",
          previewable: true,
          previewPath: att.previewPath,
        }));
    const charge = row.netCharge;
    return {
      damageId: String(row.damageId || `${vehicleId}-${index}`),
      damageNo: String(row.damageId || index),
      vehicleId: row.vehicleId || vehicleId,
      plateNo: row.plateNo || opts.plateNo || null,
      normalizedPlateNo: row.plateNo ? normalizePlate(row.plateNo) : null,
      damageType: row.damageType || null,
      area: row.areaName || null,
      element: row.elementName || null,
      action: row.actionName || null,
      memo: row.memo || null,
      chargeText: charge != null ? `CHF ${charge}` : null,
      chargeAmount: charge,
      currency: "CHF",
      relatedRentalNo: row.relatedRentalNo || null,
      addedOn: row.entryDate || null,
      recordedBy: row.addedByName || null,
      recordedOn: row.entryDate || null,
      labourHours: null,
      attachments,
      relatedItems: [],
      source: row.source || "wheelsys.rental.GetDamages",
      syncedAt,
    };
  });
}

/**
 * Extract the balanced wheels.afterSave({...}) object from a postback response.
 * @param {string} text
 * @return {object|null}
 */
function parseAfterSaveObject(text) {
  const t = String(text || "");
  const marker = "wheels.afterSave(";
  const start = t.indexOf(marker);
  if (start === -1) return null;
  let i = start + marker.length;
  while (i < t.length && t[i] !== "{") i++;
  if (t[i] !== "{") return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  let end = -1;
  for (let j = i; j < t.length; j++) {
    const ch = t[j];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === "\"") inStr = false;
    } else if (ch === "\"") {
      inStr = true;
    } else if (ch === "{") {
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0) {
        end = j + 1;
        break;
      }
    }
  }
  if (end === -1) return null;
  try {
    return JSON.parse(t.slice(i, end));
  } catch (_) {
    return null;
  }
}

/**
 * Extract MilesDriven from a CalcRates response object.
 * @param {object} calcResult
 * @return {number|null}
 */
function calcRatesMilesDriven(calcResult) {
  const rental = (calcResult && calcResult.Rental) || {};
  const raw = rental.MilesDriven != null ? rental.MilesDriven : calcResult.MilesDriven;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/**
 * Run CalcRates when return km/fuel changed so Wheelsys form state stays consistent.
 * HAR order: PRECHECKIN (0/0/0) → FuelPolicy (0/0/MilesDriven) → KMDriven (KilomTo/0/MilesDriven).
 * @param {string} cookie
 * @param {URLSearchParams} payload
 * @param {string} html
 * @param {object} opts
 * @return {Promise<number|null>} MilesDriven applied to payload
 */
async function maybeRecalcRatesBeforePrecheckin(cookie, payload, html, opts) {
  const {mileageTo, fuelTo, cacheKey, rentalId} = opts || {};
  if (!cacheKey) return null;

  const snap = extractRentalFieldSnapshot(html);
  const mileageFrom = Number(formGet(payload, "rdMileageFrom_hidden") || 0);
  let kmTo = Number.isFinite(Number(mileageTo)) && Number(mileageTo) > 0 ?
    Number(mileageTo) :
    (mileageFrom > 0 ? mileageFrom + 1 : 0);
  if (kmTo <= mileageFrom && mileageFrom > 0) kmTo = mileageFrom + 1;
  let milesDriven = Math.max(1, kmTo - mileageFrom);

  const rateMeta = extractSelectFieldMeta(html, "rdRateCode_combo");
  const rateId = rateMeta.value || formGet(payload, "rdRateCode_combo") || "1";
  const rateCode = rateMeta.text || rateMeta.value || "GMI";

  const basePayload = buildCalcRatesPayload({
    usageType: formGet(payload, "rdUsageType"),
    status: formGet(payload, "rdStatus"),
    agent: formGet(payload, "rdAgent_value"),
    driver: formGet(payload, "rdDriver_value"),
    stationFrom: formGet(payload, "rdStationFrom_combo"),
    stationTo: formGet(payload, "rdStationTo_combo"),
    dateFrom: formGet(payload, "rdDateFrom_text") || snap.dateFrom,
    timeFrom: formGet(payload, "rdTimeFrom_text") || snap.timeFrom,
    dateTo: formGet(payload, "rdDateTo_text") || snap.dateTo,
    timeTo: formGet(payload, "rdTimeTo_text") || snap.timeTo,
    carGroup: formGet(payload, "rdGroup_combo"),
    groupInv: formGet(payload, "rdGroupInv_combo"),
    carId: formGet(payload, "rdPlateNo_value"),
    rateId,
    rateCode,
    rentalType: formGet(payload, "cbRentalType_combo") ||
      formGet(payload, "rdRentalType_combo") || "R",
    chargeTotal: formGet(payload, "rdChargeTotal_hidden"),
  }, {
    carId: formGet(payload, "rdPlateNo_value"),
    carGroup: formGet(payload, "rdGroup_combo"),
    groupInv: formGet(payload, "rdGroupInv_combo"),
  });

  console.info(
      "[WheelSys][Precheckin] CalcRates prep " +
      `rentalId=${rentalId || "?"} checkoutKm=${mileageFrom} latestReturnKm=${kmTo} ` +
      `localMilesDriven=${milesDriven} carId=${formGet(payload, "rdPlateNo_value") || "?"} ` +
      `RateId=${rateId} RateCode=${rateCode}`,
  );

  try {
    const preResult = await calcRates(cookie, {
      cacheKey,
      operation: "PRECHECKIN",
      rentalData: {...basePayload, KilomTo: 0, FuelTo: 0, MilesDriven: 0},
    });
    milesDriven = calcRatesMilesDriven(preResult) || milesDriven;

    await calcRates(cookie, {
      cacheKey,
      operation: "FuelPolicy",
      rentalData: {
        ...basePayload,
        KilomTo: 0,
        FuelTo: 0,
        MilesDriven: milesDriven,
      },
    });

    if (kmTo > 0) {
      const kmResult = await calcRates(cookie, {
        cacheKey,
        operation: "KMDriven",
        rentalData: {
          ...basePayload,
          KilomTo: kmTo,
          FuelTo: 0,
          MilesDriven: milesDriven,
        },
      });
      milesDriven = calcRatesMilesDriven(kmResult) || Math.max(1, kmTo - mileageFrom);
      console.info(
          "[WheelSys][Precheckin] CalcRates KMDriven ok " +
          `KilomTo=${kmTo} returnedMilesDriven=${milesDriven}`,
      );
    }

    payload.set("rdMileageTo_hidden", String(kmTo));
    payload.set("rdMileageTo_text", formatMileageText(kmTo));
    payload.set("rdMilesDriven_hidden", String(milesDriven));
    payload.set("rdMilesDriven_text", `${milesDriven} km`);
    if (fuelTo != null && Number.isFinite(Number(fuelTo))) {
      const fuel = Number(fuelTo);
      payload.set("rdTankTo_hidden", formatTankHidden(fuel));
      payload.set("rdTankTo_text", formatTankText(fuel));
    }
    console.info("[WheelSys][Precheckin] CalcRates pre-check-in sequence ok before BTSAVE");
    return milesDriven;
  } catch (e) {
    console.warn(`[WheelSys][Precheckin] CalcRates before BTSAVE failed: ${e.message}`);
    milesDriven = Math.max(1, kmTo - mileageFrom);
    payload.set("rdMileageTo_hidden", String(kmTo));
    payload.set("rdMileageTo_text", formatMileageText(kmTo));
    payload.set("rdMilesDriven_hidden", String(milesDriven));
    payload.set("rdMilesDriven_text", `${milesDriven} km`);
    return milesDriven;
  }
}

/**
 * Submit PRECHECKIN via rental.aspx async postback (full form state).
 * Uses wheels.postBack-derived request shape; validates required fields first.
 * @param {object} p
 * @return {Promise<object>}
 */
async function submitPrecheckin(p) {
  const {
    cookie, checkInMileage, checkInFuel, checkInUserId, storedSessionUserId,
  } = p || {};
  const id = String((p && p.rentalId) || "").trim();
  if (!/^\d+$/.test(id)) throw new Error("Invalid rentalId — must be numeric.");

  const page = (p && p.page) || await fetchRentalPage(cookie, id);
  const html = page.html;
  const pageUrl = page.url;
  const payload = (p && p.form) || parseCompleteRentalFormToPayload(html);
  const validation = (p && p.validation) || validatePrecheckinForm(payload, html);

  if (!validation.ready) {
    const blockers = (validation.blockers || []).join(", ");
    return {
      success: false,
      message: blockers ?
        `Pre-check-in blocked: missing ${blockers}.` :
        "Missing required fields before PRECHECKIN submit.",
      afterSave: null,
      debug: buildPrecheckinDiagnostics("", 0, {
        missingRequiredFields: validation.missingRequiredFields,
        postbackSource: "precheck-validation",
      }),
      staleRecord: false,
      retryable: false,
      httpStatus: 0,
      missingRequiredFields: validation.missingRequiredFields,
    };
  }

  applyPrecheckinReturnFields(payload, html, {
    mileageTo: checkInMileage,
    fuelTo: checkInFuel,
    checkInUserId,
    storedSessionUserId,
  });
  ensureRentalIdentityFields(payload, html);

  // Use the effective mileage now set in the payload (may be mileageFrom+1 if checkInMileage=0).
  const effectiveMileageTo = Number(payload.get("rdMileageTo_hidden") || 0) || checkInMileage;
  const effectiveFuelTo = Number(payload.get("rdTankTo_hidden") || 0) || checkInFuel;
  await maybeRecalcRatesBeforePrecheckin(cookie, payload, html, {
    mileageTo: effectiveMileageTo,
    fuelTo: effectiveFuelTo,
    cacheKey: validation.cacheKey,
    rentalId: id,
  });

  console.info(
      "[WheelSys][Precheckin] BTSAVE prep " +
      `rentalId=${id} rdMileageFrom_hidden=${formGet(payload, "rdMileageFrom_hidden")} ` +
      `rdMileageTo_hidden=${formGet(payload, "rdMileageTo_hidden")} ` +
      `rdMilesDriven_hidden=${formGet(payload, "rdMilesDriven_hidden")} ` +
      `rdTankTo_hidden=${formGet(payload, "rdTankTo_hidden")} ` +
      `rdUserTo_combo=${formGet(payload, "rdUserTo_combo")}`,
  );

  const formats = discoverPrecheckinPostbackFormats(html, id, "");
  let lastResult = null;

  /**
   * @param {URLSearchParams} postPayload
   * @param {string} url
   * @param {object} format
   * @return {Promise<object>}
   */
  async function postOnce(postPayload, url, format) {
    applyPrecheckinReturnFields(postPayload, html, {
      mileageTo: checkInMileage,
      fuelTo: checkInFuel,
      checkInUserId,
      storedSessionUserId,
    });
    ensureRentalIdentityFields(postPayload, html);
    logPrecheckinSubmitFields(postPayload, id);
    applyPrecheckinPostback(postPayload, format.arg, {
      eventTarget: format.eventTarget,
      scriptManager: format.scriptManager,
    });
    const {rawText, httpStatus} = await postToWheelsys(url, cookie, postPayload);
    return resolvePrecheckinPostbackResult(rawText, httpStatus, {
      postbackFormat: format.arg,
      postbackSource: format.source,
      missingRequiredFields: validation.missingRequiredFields,
    });
  }

  for (const format of formats) {
    const postPayload = new URLSearchParams(payload.toString());
    let result = await postOnce(postPayload, pageUrl, format);
    console.info(
        `[WheelSys][Precheckin] format=${format.source} success=${result.success} ` +
        `afterSave=${Boolean(result.afterSave)} precheckin=${result.debug && result.debug.containsPrecheckin} ` +
        `requiredError=${result.debug && result.debug.containsRequiredError} http=${result.httpStatus}`,
    );

    if (result.success) {
      return {...result, missingRequiredFields: validation.missingRequiredFields};
    }

    lastResult = result;

    if (result.afterSave || (result.debug && result.debug.containsRequiredError)) {
      break;
    }

    if (result.staleRecord) {
      const freshPage = await fetchRentalPage(cookie, id);
      const freshPayload = parseCompleteRentalFormToPayload(freshPage.html);
      applyPrecheckinReturnFields(freshPayload, freshPage.html, {
        mileageTo: checkInMileage,
        fuelTo: checkInFuel,
      });
      ensureRentalIdentityFields(freshPayload, freshPage.html);
      result = await postOnce(freshPayload, freshPage.url, format);
      if (result.success) {
        return {...result, missingRequiredFields: validation.missingRequiredFields};
      }
      lastResult = result;
      break;
    }
  }

  return lastResult || {
    success: false,
    message: "PRECHECKIN postback did not run.",
    afterSave: null,
    debug: buildPrecheckinDiagnostics("", 0),
    staleRecord: false,
    retryable: true,
    httpStatus: 0,
    missingRequiredFields: validation.missingRequiredFields,
  };
}

module.exports = {
  RENTAL_PATH,
  PRECHECKIN_CRITICAL_FIELDS,
  PRECHECKIN_SUBMIT_LOG_FIELDS,
  PRECHECKIN_REQUIRED_FIELDS,
  parseRentalFormFromHtml,
  parseCompleteRentalFormToPayload,
  mapCustomer,
  mapVehicle,
  mapMileageFuel,
  mapInsurance,
  mapRental,
  parseRentalAttachments,
  resolveCacheKey,
  fetchVehicleDiagram,
  fetchExistingDamages,
  fetchCanUseCar,
  resolvePrecheckinRentalId,
  detectPrecheckinEligibility,
  buildPrecheckinContext,
  submitPrecheckin,
  parseAfterSaveObject,
  extractAfterSaveFromDelta,
  buildPrecheckinDiagnostics,
  validatePrecheckinForm,
  ensureRentalIdentityFields,
  logPrecheckinSubmitFields,
  findMissingRequiredFields,
  extractRequiredErrorSnippets,
  derivePrecheckinPostbackRequest,
  discoverPrecheckinPostbackFormats,
  mapPrecheckinDamagesToHistory,
  normalizeDamageRow,
  buildDamageAttachments,
  extractDamageRowsFromOuter,
};
