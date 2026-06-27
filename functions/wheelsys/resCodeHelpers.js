/**
 * WheelSys RES vs agent confirmation field helpers.
 */
/* eslint-disable max-len */

const {pickField} = require("./client");

/**
 * @param {string} value
 * @return {boolean}
 */
function looksLikeResNo(value) {
  return /^RES[-\s]?\d+/i.test(String(value || "").trim());
}

/**
 * Reservation number (RES-12345) from journal / grid row.
 * @param {object} row
 * @return {string}
 */
function pickResNoFromRow(row) {
  const keys = [
    "ResNo", "resNo", "resno",
    "ResDocNo", "resDocNo", "resdocno",
    "ResDocDisp", "resDocDisp", "resdocdisp",
    "ReservationNo", "reservationNo",
    "rdResDocNo", "rdResDocno_text", "rdResDocDisp_text",
    "ResDocDisplay", "resDocDisplay",
  ];
  for (const key of keys) {
    const v = String(pickField(row, key) || "").trim();
    if (looksLikeResNo(v)) return v;
  }
  const conf = String(pickField(row, "ConfirmationNo", "confirmationno") || "").trim();
  if (looksLikeResNo(conf)) return conf;
  const raw = row && row.raw && typeof row.raw === "object" ? row.raw : null;
  if (raw) {
    for (const key of keys) {
      const v = String(pickField(raw, key) || "").trim();
      if (looksLikeResNo(v)) return v;
    }
  }
  return "";
}

/**
 * Agent / display confirmation (e.g. JIG(A)-…) — not RES- code.
 * @param {object} row
 * @return {string}
 */
function pickAgentConfirmationFromRow(row) {
  const display = String(pickField(row, "DisplayDocNo", "displaydocno", "DocNo") || "").trim();
  const conf = String(
      pickField(row, "ConfirmationNo", "confirmationno", "ConfNo", "AgentConf") || "",
  ).trim();
  if (conf && !looksLikeResNo(conf)) return conf;
  if (display && !looksLikeResNo(display)) return display;
  return conf || display;
}

module.exports = {
  looksLikeResNo,
  pickResNoFromRow,
  pickAgentConfirmationFromRow,
};
