/**
 * Encrypted WheelSys session cookie storage (server-side only).
 * One active session per Firebase user + franchise + station.
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
function legacySessionDocRef(db, franchiseId, station = "ZRH") {
  return db.collection("franchises").doc(String(franchiseId).toUpperCase())
      .collection("wheelsysSessions").doc(String(station).toUpperCase());
}

/**
 * Per-user WheelSys session document.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {string} station
 * @param {string} userId Firebase Auth uid
 * @return {FirebaseFirestore.DocumentReference}
 */
function sessionDocRef(db, franchiseId, station = "ZRH", userId) {
  const uid = String(userId || "").trim();
  if (!uid) throw new Error("userId is required for WheelSys session.");
  const st = String(station || "ZRH").toUpperCase();
  return db.collection("franchises").doc(String(franchiseId).toUpperCase())
      .collection("wheelsysSessions").doc(`${st}_${uid}`);
}

/**
 * @param {object} snap
 * @param {string} encryptionKeyHex
 * @return {string|null}
 */
function readCookieFromSessionSnap(snap, encryptionKeyHex) {
  if (!snap || !snap.exists) return null;
  const data = snap.data() || {};
  if (data.isActive === false || !data.cookieEncrypted) return null;
  const exp = data.expiresAt;
  if (exp && exp.toMillis && exp.toMillis() <= Date.now()) return null;
  return decryptCookie(data.cookieEncrypted, encryptionKeyHex);
}

/**
 * @param {object} p
 * @param {FirebaseFirestore.Firestore} p.db
 * @param {string} p.franchiseId
 * @param {string} p.station
 * @param {string} p.cookiePlain
 * @param {string} p.encryptionKeyHex
 * @param {string} p.createdBy Firebase Auth uid
 * @param {number} [p.ttlHours=12]
 */
async function saveSession({
  db, franchiseId, station, cookiePlain, encryptionKeyHex, createdBy, ttlHours = 12,
  wheelSysUserId, wheelSysUserName,
}) {
  const cookie = String(cookiePlain || "").trim();
  if (!cookie) throw new Error("Cookie is empty.");
  const uid = String(createdBy || "").trim();
  if (!uid) throw new Error("createdBy (Firebase uid) is required.");
  const encrypted = encryptCookie(cookie, encryptionKeyHex);
  const now = admin.firestore.Timestamp.now();
  const expires = admin.firestore.Timestamp.fromMillis(
      Date.now() + ttlHours * 60 * 60 * 1000,
  );
  const patch = {
    cookieEncrypted: encrypted,
    station: String(station).toUpperCase(),
    createdBy: uid,
    createdAt: now,
    updatedAt: now,
    expiresAt: expires,
    isActive: true,
  };
  const wsUserId = String(wheelSysUserId || "").trim();
  const wsUserName = String(wheelSysUserName || "").trim();
  if (/^\d+$/.test(wsUserId)) patch.wheelSysUserId = wsUserId;
  if (wsUserName) patch.wheelSysUserName = wsUserName;
  await sessionDocRef(db, franchiseId, station, uid).set(patch, {merge: true});
}

/**
 * WheelSys operator tied to the stored session cookie (rdUserTo).
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {string} station
 * @param {string} userId Firebase Auth uid
 * @return {Promise<{userId: string, userName: string}>}
 */
async function loadSessionOperator(db, franchiseId, station, userId) {
  const uid = String(userId || "").trim();
  if (!uid) return {userId: "", userName: ""};
  const snap = await sessionDocRef(db, franchiseId, station, uid).get();
  if (!snap.exists) return {userId: "", userName: ""};
  const data = snap.data() || {};
  return {
    userId: String(data.wheelSysUserId || "").trim(),
    userName: String(data.wheelSysUserName || "").trim(),
  };
}

/**
 * @param {object} p
 * @param {FirebaseFirestore.Firestore} p.db
 * @param {string} p.franchiseId
 * @param {string} p.station
 * @param {string} p.encryptionKeyHex
 * @param {string} p.userId Firebase Auth uid
 * @param {string} [p.fallbackCookie] from Secret Manager
 * @return {Promise<string>}
 */
async function loadActiveSessionCookie({
  db, franchiseId, station, encryptionKeyHex, userId, fallbackCookie,
}) {
  const encKey = String(encryptionKeyHex || "").trim();
  const uid = String(userId || "").trim();
  if (!uid) {
    throw new Error("WheelSys session requires a signed-in user.");
  }
  if (encKey.length === 64) {
    const userSnap = await sessionDocRef(db, franchiseId, station, uid).get();
    const userCookie = readCookieFromSessionSnap(userSnap, encKey);
    if (userCookie) return userCookie;

    // One-time migration: legacy shared doc only when createdBy matches this user.
    const legacySnap = await legacySessionDocRef(db, franchiseId, station).get();
    if (legacySnap.exists) {
      const legacyData = legacySnap.data() || {};
      if (String(legacyData.createdBy || "").trim() === uid) {
        const legacyCookie = readCookieFromSessionSnap(legacySnap, encKey);
        if (legacyCookie) {
          await saveSession({
            db,
            franchiseId,
            station,
            cookiePlain: legacyCookie,
            encryptionKeyHex: encKey,
            createdBy: uid,
            ttlHours: 12,
          });
          return legacyCookie;
        }
      }
    }
  }
  const fb = String(fallbackCookie || "").trim();
  if (fb) return fb;
  throw new Error(
      "No WheelSys session for this user. Log in to WheelSys in the app.",
  );
}

module.exports = {
  encryptCookie,
  decryptCookie,
  legacySessionDocRef,
  sessionDocRef,
  saveSession,
  loadActiveSessionCookie,
  loadSessionOperator,
};
