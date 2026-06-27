/**
 * Shared WheelSys HTTP client helpers (ASP.NET WebMethods).
 */
/* eslint-disable max-len */

// Local constant — do NOT import from checkinSync (circular require leaves BASE_URL undefined).
const BASE_URL = "https://ch.wheelsys.greenmotion.com";
const {buildFleetAuthCookie} = require("./cookieJar");

const ZURICH_TZ = "Europe/Zurich";

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

const ERR = {
  SESSION_EXPIRED: "SESSION_EXPIRED",
  NO_DATA: "NO_DATA",
  PARSE_FAILED: "PARSE_FAILED",
};

/** WheelSys client error with machine-readable code. */
class WheelsysClientError extends Error {
  /**
   * @param {string} code
   * @param {string} message
   * @param {object} [extras]
   */
  constructor(code, message, extras = {}) {
    super(message);
    this.name = "WheelsysClientError";
    this.code = code;
    Object.assign(this, extras);
  }
}

/**
 * @param {string} plate
 * @return {string}
 */
function normalizePlate(plate) {
  return String(plate || "")
      .trim()
      .replace(/\s+/g, "")
      .replace(/\*/g, "")
      .toUpperCase();
}

/**
 * @param {Date|string} input Date or yyyy-MM-dd
 * @return {string} YYYY-MM-DDT00:00:00.000 (Zurich calendar, no UTC shift)
 */
function buildOperationalDate(input) {
  let year;
  let month;
  let day;
  if (input instanceof Date && !Number.isNaN(input.getTime())) {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: ZURICH_TZ,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(input);
    year = parts.find((p) => p.type === "year").value;
    month = parts.find((p) => p.type === "month").value;
    day = parts.find((p) => p.type === "day").value;
  } else {
    const str = String(input || "").trim().slice(0, 10);
    const m = str.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!m) {
      throw new WheelsysClientError(
          ERR.PARSE_FAILED,
          `Invalid operational date: ${input}`,
      );
    }
    year = m[1];
    month = m[2];
    day = m[3];
  }
  return `${year}-${month}-${day}T00:00:00.000`;
}

/**
 * @param {object} outer ASP.NET { d: { success, data, message } }
 * @return {object}
 */
function parseWheelsysWebMethodObject(outer) {
  const d = outer && outer.d;
  if (!d) {
    throw new WheelsysClientError(ERR.PARSE_FAILED, "Missing WheelSys d wrapper.");
  }
  if (d.data == null || d.data === "") {
    throw new WheelsysClientError(
        ERR.NO_DATA,
        String(d.message || "WheelSys returned no data."),
    );
  }
  try {
    return typeof d.data === "string" ? JSON.parse(d.data) : d.data;
  } catch (e) {
    throw new WheelsysClientError(ERR.PARSE_FAILED, "Failed to parse WheelSys data.", {
      debugPreview: String(d.data).slice(0, 500),
      cause: e.message,
    });
  }
}

/**
 * @param {object} outer
 * @return {Array}
 */
function parseWheelsysWebMethodArray(outer) {
  const parsed = parseWheelsysWebMethodObject(outer);
  if (Array.isArray(parsed)) return parsed;
  if (parsed && Array.isArray(parsed.rows)) return parsed.rows;
  if (parsed && Array.isArray(parsed.data)) return parsed.data;
  if (parsed && Array.isArray(parsed.Data)) return parsed.Data;
  if (parsed && Array.isArray(parsed.Items)) return parsed.Items;
  throw new WheelsysClientError(ERR.PARSE_FAILED, "Expected array in WheelSys data.");
}

/**
 * @param {string} text
 * @return {boolean}
 */
function looksLikeLoginPage(text) {
  const t = String(text || "");
  return /login|sign.?in/i.test(t) &&
    !t.includes("\"success\":true");
}

/**
 * @param {string} cookie Session cookie header.
 * @param {string} url Request path or absolute URL.
 * @param {object} body JSON POST body.
 * @param {object} [options] Optional fetch overrides.
 * @return {Promise<object>}
 */
async function wheelsysFetchJson(cookie, url, body, options = {}) {
  const authCookie = buildFleetAuthCookie(cookie) || String(cookie || "");
  if (!authCookie) {
    throw new WheelsysClientError(
        ERR.SESSION_EXPIRED,
        "WheelSys cookie missing .wheelsys or __Secure-SID.",
    );
  }

  const fullUrl = url.startsWith("http") ? url : `${BASE_URL}${url}`;
  const referer = options.referer ||
    fullUrl.replace(/\/[^/]+\/?$/, "/").replace(/\.aspx\/[^/]+$/, ".aspx");

  const res = await fetch(fullUrl, {
    method: "POST",
    headers: {
      "Accept": "application/json, text/javascript, */*; q=0.01",
      "Content-Type": "application/json; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest",
      "Origin": BASE_URL,
      "Referer": referer,
      "User-Agent": UA,
      "Cookie": authCookie,
      ...(options.headers || {}),
    },
    body: JSON.stringify(body),
  });

  const text = String(await res.text());
  let outer = null;
  try {
    outer = JSON.parse(text);
  } catch (_) {
    outer = null;
  }

  if (res.status === 401 || res.status === 403 || looksLikeLoginPage(text)) {
    throw new WheelsysClientError(
        ERR.SESSION_EXPIRED,
        "WheelSys session expired. Reopen WheelSys login in the app.",
        {httpStatus: res.status, debugPreview: text.slice(0, 500)},
    );
  }

  if (!res.ok) {
    throw new WheelsysClientError(
        ERR.PARSE_FAILED,
        `WheelSys request failed (${res.status}).`,
        {httpStatus: res.status, debugPreview: text.slice(0, 500)},
    );
  }

  return {res, text, outer};
}

/**
 * @param {object} row
 * @param {...string} keys
 * @return {*}
 */
function pickField(row, ...keys) {
  if (!row || typeof row !== "object") return "";
  for (const key of keys) {
    if (row[key] != null && row[key] !== "") return row[key];
    const lower = String(key).toLowerCase();
    for (const [rk, rv] of Object.entries(row)) {
      if (String(rk).toLowerCase() === lower && rv != null && rv !== "") {
        return rv;
      }
    }
  }
  return "";
}

/**
 * WheelSys station list for dashboard POST bodies.
 * @param {string} station
 * @return {string}
 */
function formatSelectedStations(station) {
  const s = String(station || "ZRH").trim().toUpperCase();
  if (s.startsWith(",") && s.endsWith(",")) return s;
  return `,${s},`;
}

/**
 * SQL-style station literal for mainviewex grids.
 * @param {string} station
 * @return {string}
 */
function formatStationsLiteral(station) {
  const s = String(station || "ZRH").trim().toUpperCase();
  if (s.startsWith("N'") && s.endsWith("'")) return s;
  return `N'${s}'`;
}

module.exports = {
  BASE_URL,
  UA,
  ERR,
  WheelsysClientError,
  normalizePlate,
  buildOperationalDate,
  parseWheelsysWebMethodObject,
  parseWheelsysWebMethodArray,
  wheelsysFetchJson,
  pickField,
  formatSelectedStations,
  formatStationsLiteral,
};
