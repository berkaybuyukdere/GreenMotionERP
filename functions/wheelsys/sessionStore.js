/**
 * Encrypted WheelSys session cookie storage (server-side only).
 */
/* eslint-disable max-len */

const crypto = require("crypto");
const admin = require("firebase-admin");

const ALGO = "aes-256-gcm";
const IV_LEN = 12;

/**
 * @param {string} plain
 * @param {string} keyHex 64-char hex = 32 bytes
 * @return {string} iv:tag:ciphertext (hex)
 */
function encryptCookie(plain, keyHex) {
  const key = Buffer.from(String(keyHex || "").trim(), "hex");
  if (key.length !== 32) {
    throw new Error(
        "WHEELSYS_COOKIE_ENCRYPTION_KEY must be 32 bytes (64 hex).",
    );
  }
  const iv = crypto.randomBytes(IV_LEN);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  const enc = Buffer.concat([cipher.update(String(plain), "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${iv.toString("hex")}:${tag.toString("hex")}:${enc.toString("hex")}`;
}

/**
 * @param {string} packed
 * @param {string} keyHex
 * @return {string}
 */
function decryptCookie(packed, keyHex) {
  const key = Buffer.from(String(keyHex || "").trim(), "hex");
  if (key.length !== 32) {
    throw new Error("WHEELSYS_COOKIE_ENCRYPTION_KEY invalid.");
  }
  const parts = String(packed || "").split(":");
  if (parts.length !== 3) throw new Error("Invalid encrypted cookie payload.");
  const iv = Buffer.from(parts[0], "hex");
  const tag = Buffer.from(parts[1], "hex");
  const data = Buffer.from(parts[2], "hex");
  const decipher = crypto.createDecipheriv(ALGO, key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString("utf8");
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {string} station
 * @return {FirebaseFirestore.DocumentReference}
 */
function sessionDocRef(db, franchiseId, station = "ZRH") {
  return db.collection("franchises").doc(String(franchiseId).toUpperCase())
      .collection("wheelsysSessions").doc(String(station).toUpperCase());
}

/**
 * @param {object} p
 * @param {FirebaseFirestore.Firestore} p.db
 * @param {string} p.franchiseId
 * @param {string} p.station
 * @param {string} p.cookiePlain
 * @param {string} p.encryptionKeyHex
 * @param {string} p.createdBy
 * @param {number} [p.ttlHours=12]
 */
async function saveSession({
  db, franchiseId, station, cookiePlain, encryptionKeyHex, createdBy, ttlHours = 12,
}) {
  const cookie = String(cookiePlain || "").trim();
  if (!cookie) throw new Error("Cookie is empty.");
  const encrypted = encryptCookie(cookie, encryptionKeyHex);
  const now = admin.firestore.Timestamp.now();
  const expires = admin.firestore.Timestamp.fromMillis(
      Date.now() + ttlHours * 60 * 60 * 1000,
  );
  await sessionDocRef(db, franchiseId, station).set({
    cookieEncrypted: encrypted,
    station: String(station).toUpperCase(),
    createdBy: String(createdBy || ""),
    createdAt: now,
    updatedAt: now,
    expiresAt: expires,
    isActive: true,
  }, {merge: true});
}

/**
 * @param {object} p
 * @param {FirebaseFirestore.Firestore} p.db
 * @param {string} p.franchiseId
 * @param {string} p.station
 * @param {string} p.encryptionKeyHex
 * @param {string} [p.fallbackCookie] from Secret Manager
 * @return {Promise<string>}
 */
async function loadActiveSessionCookie({
  db, franchiseId, station, encryptionKeyHex, fallbackCookie,
}) {
  const encKey = String(encryptionKeyHex || "").trim();
  if (encKey.length === 64) {
    const snap = await sessionDocRef(db, franchiseId, station).get();
    if (snap.exists) {
      const data = snap.data() || {};
      if (data.isActive !== false && data.cookieEncrypted) {
        const exp = data.expiresAt;
        if (!exp || exp.toMillis() > Date.now()) {
          return decryptCookie(data.cookieEncrypted, encKey);
        }
      }
    }
  }
  const fb = String(fallbackCookie || "").trim();
  if (fb) return fb;
  throw new Error(
      "No active WheelSys session. Ask an admin to configure the session.",
  );
}

module.exports = {
  encryptCookie,
  decryptCookie,
  sessionDocRef,
  saveSession,
  loadActiveSessionCookie,
};
