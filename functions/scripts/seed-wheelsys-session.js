#!/usr/bin/env node
/**
 * Seeds encrypted WheelSys session cookie in Firestore.
 *
 * Never commit cookie values. Pass via env:
 *
 *   cd functions
 *   WHEELSYS_API_KEY='…' \
 *   WHEELSYS_SESSION_COOKIE='__Secure-SID=…; .wheelsys=…' \
 *   npm run seed:wheelsys-session
 *
 * Optional: WHEELSYS_STATION=ZRH  WHEELSYS_FRANCHISE=CH  WHEELSYS_TTL_HOURS=24
 */

const crypto = require("crypto");
const admin = require("firebase-admin");
const {saveSession} = require("../wheelsys/sessionStore");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * @return {string}
 */
function encryptionKeyHex() {
  const apiKey = String(process.env.WHEELSYS_API_KEY || "").trim();
  if (!apiKey) return "";
  return crypto.createHash("sha256").update(apiKey).digest("hex");
}

/**
 * @return {Promise<void>}
 */
async function main() {
  const cookiePlain = String(process.env.WHEELSYS_SESSION_COOKIE || "").trim();
  const encKey = encryptionKeyHex();

  if (!encKey) {
    console.error(
        "Missing WHEELSYS_API_KEY (same secret used by Cloud Functions).",
    );
    process.exit(1);
  }
  if (!cookiePlain || cookiePlain.length < 20) {
    console.error("Missing WHEELSYS_SESSION_COOKIE (Cookie header value).");
    process.exit(1);
  }

  const franchiseId = (process.env.WHEELSYS_FRANCHISE || "CH")
      .trim().toUpperCase();
  const station = (process.env.WHEELSYS_STATION || "ZRH").trim().toUpperCase();
  const ttlHours = Math.min(
      72,
      Math.max(1, Number(process.env.WHEELSYS_TTL_HOURS) || 24),
  );

  await saveSession({
    db,
    franchiseId,
    station,
    cookiePlain,
    encryptionKeyHex: encKey,
    createdBy: "seed-wheelsys-session",
    ttlHours,
  });

  console.log(
      `OK: franchises/${franchiseId}/wheelsysSessions/${station} ` +
      `(encrypted, TTL ${ttlHours}h).`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
