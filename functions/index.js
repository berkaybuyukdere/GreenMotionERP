/**
 * Firebase Cloud Functions for Push Notifications
 * Version 2 API (firebase-functions v6)
 *
 * This file should be placed in: functions/index.js
 * After creating Firebase Functions with: firebase init functions
 */

const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
// Legacy runtime config support (used as fallback for API keys).
// Note: functions.config() is deprecated, but still works for now and
// avoids needing unsupported deploy flags like --set-env-vars.
const legacyFunctions = require("firebase-functions");
const functionsV1 = require("firebase-functions/v1");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();

// Firestore reference
const db = admin.firestore();

/**
 * Removes presence rows for a UID (legacy top-level + scoped userPresence).
 * Auth deletion does not remove Firestore presence docs; without this,
 * dashboards list stale teammates forever.
 * @param {string} uid Firebase Auth UID
 * @return {Promise<void>}
 */
async function deleteAllUserPresenceDocumentsForUid(uid) {
  const uidStr = String(uid || "").trim();
  if (!uidStr) return;
  try {
    await db.collection("userPresence").doc(uidStr).delete();
  } catch (e) {
    console.warn(
        "deleteAllUserPresenceDocumentsForUid legacy",
        uidStr,
        e.message,
    );
  }
  try {
    const frSnap = await db.collection("franchises").get();
    for (const fr of frSnap.docs) {
      try {
        await fr.ref.collection("userPresence").doc(uidStr).delete();
      } catch (e) {
        console.warn(
            "deleteAllUserPresenceDocumentsForUid scoped",
            fr.id,
            uidStr,
            e.message,
        );
      }
    }
  } catch (e) {
    console.error("deleteAllUserPresenceDocumentsForUid franchises", e);
  }
}

/**
 * When an Auth user is deleted (Console, Admin SDK, or
 * adminDeleteUserCompletely), strip their presence and Firestore profile so
 * clients never show ghost teammates.
 */
exports.authOnUserDeleteCleanup = functionsV1.auth.user()
    .onDelete(async (user) => {
      const uid = user.uid;
      console.log("authOnUserDeleteCleanup: uid=", uid);
      await deleteAllUserPresenceDocumentsForUid(uid);
      try {
        await db.collection("users").doc(uid).delete();
      } catch (e) {
        console.warn("authOnUserDeleteCleanup users doc", uid, e.message);
      }
    });

// Wheelsys API key (prefer Secret Manager).
const wheelsysApiKeySecret = defineSecret("WHEELSYS_API_KEY");
const wheelsysPreCheckInOptions = {secrets: [wheelsysApiKeySecret]};

/**
 * Returns the configured Wheelsys API key.
 * Priority: process.env.WHEELSYS_API_KEY -> functions.config().wheelsys.api_key
 * @return {string}
 */
function getWheelsysApiKey() {
  const envKey = String(process.env.WHEELSYS_API_KEY || "").trim();
  if (envKey) return envKey;

  // Legacy Functions runtime config is commonly injected as FIREBASE_CONFIG.
  // We parse it directly so this works even when legacyFunctions.config()
  // isn't wired correctly for v2 runtime.
  const firebaseConfigRaw = process.env.FIREBASE_CONFIG;
  if (firebaseConfigRaw) {
    try {
      let parsed = null;
      try {
        parsed = JSON.parse(firebaseConfigRaw);
      } catch (e) {
        // Some runtimes inject base64-encoded config.
        const decoded = Buffer.from(
            String(firebaseConfigRaw),
            "base64",
        ).toString("utf8");
        parsed = JSON.parse(decoded);
      }
      const wheelsysCfg = parsed && parsed.wheelsys ? parsed.wheelsys : {};
      const cfgKey = wheelsysCfg.api_key || wheelsysCfg.apiKey || "";
      if (cfgKey) return String(cfgKey).trim();
    } catch (e) {
      // ignore parse errors and try other fallbacks
    }
  }

  try {
    let cfg = null;
    if (legacyFunctions &&
        typeof legacyFunctions.config === "function") {
      cfg = legacyFunctions.config();
    }
    const wheelsysCfg = (cfg && cfg.wheelsys) ? cfg.wheelsys : {};
    const cfgKey = wheelsysCfg.api_key || wheelsysCfg.apiKey || "";
    return String(cfgKey || "").trim();
  } catch (e) {
    return "";
  }
}

/**
 * Resolve SMTP password from Secret Manager/env with safe fallback.
 * Production target: keep password in secrets, not Firestore.
 * @param {Object} smtp smtp config object
 * @param {string} franchiseId franchise identifier
 * @return {string} smtp password
 */
function resolveSmtpPassword(smtp, franchiseId) {
  const normalized = String(franchiseId || "CH").toUpperCase();
  const scopedEnvName = `SMTP_PASSWORD_${normalized}`;
  const scopedSecret = process.env[scopedEnvName];
  if (scopedSecret && scopedSecret.trim()) {
    return scopedSecret.trim();
  }
  const globalSecret = process.env.SMTP_PASSWORD;
  if (globalSecret && globalSecret.trim()) {
    return globalSecret.trim();
  }
  return String(smtp.password || "");
}

/**
 * Merges smtpConfigurations/{id} with franchise defaults (iOS app parity).
 * Env secrets from resolveSmtpPassword still override stored passwords.
 * @param {string} franchiseId franchise id
 * @param {Object} smtpFromDoc Firestore data or {}
 * @return {Object|null} merged config, or null if unusable
 */
function mergeDefaultSmtpIfNeeded(franchiseId, smtpFromDoc) {
  const fromDoc = (smtpFromDoc && typeof smtpFromDoc === "object") ?
    smtpFromDoc :
    {};
  if (!String(fromDoc.host || "").trim()) return null;
  if (!String(fromDoc.username || "").trim()) return null;
  return fromDoc;
}

/**
 * Reads SMTP config doc safely and returns merged config or null.
 * @param {string} docId
 * @return {Promise<Object|null>}
 */
async function readSmtpConfigDoc(docId) {
  const id = String(docId || "").trim();
  if (!id) return null;
  const snap = await db.collection("smtpConfigurations").doc(id).get();
  if (!snap.exists) return null;
  return mergeDefaultSmtpIfNeeded(id, snap.data() || {});
}

/**
 * Nodemailer options for submission: 465/443 use implicit TLS; others use
 * STARTTLS when useTLS is true. Wrong secure flag on 443 causes
 * "Greeting never received".
 * @param {Object} smtp merged SMTP config
 * @param {string} smtpPassword resolved password
 * @return {Object} nodemailer.createTransport argument
 */
function nodemailerSmtpTransportOptions(smtp, smtpPassword) {
  const portRaw = Number(smtp.port || 587);
  const port = Number.isFinite(portRaw) && portRaw > 0 ? portRaw : 587;
  const implicitTls = port === 465 || port === 443;
  return {
    host: String(smtp.host || "").trim(),
    port,
    secure: implicitTls,
    requireTLS: smtp.useTLS === true && !implicitTls,
    auth: {
      user: smtp.username,
      pass: smtpPassword,
    },
    connectionTimeout: 20000,
    greetingTimeout: 20000,
    socketTimeout: 60000,
  };
}

/**
 * Creates prioritized SMTP transport options for fallback retries.
 * @param {Object} smtp merged SMTP config
 * @param {string} smtpPassword resolved password
 * @return {Object[]} list of nodemailer transport options
 */
function buildSmtpTransportCandidates(smtp, smtpPassword) {
  const primary = nodemailerSmtpTransportOptions(smtp, smtpPassword);
  const candidates = [primary];
  const useTls = smtp.useTLS === true;

  const pushUnique = (port, secure) => {
    if (candidates.some(
        (item) => item.port === port && item.secure === secure,
    )) {
      return;
    }
    candidates.push({
      ...primary,
      port,
      secure,
      requireTLS: useTls && !secure,
    });
  };

  if (primary.port === 443) {
    pushUnique(465, true);
    pushUnique(587, false);
  } else if (primary.port === 465) {
    pushUnique(443, true);
    pushUnique(587, false);
  } else if (primary.port === 587) {
    pushUnique(465, true);
    pushUnique(443, true);
  }

  return candidates;
}

/**
 * Returns true if SMTP error is likely transport/handshake related.
 * @param {*} error unknown sendMail error
 * @return {boolean} retryable transport failure
 */
function isRetryableSmtpTransportError(error) {
  const code = String(error && error.code ? error.code : "").toUpperCase();
  if (code === "EAUTH" || code === "EENVELOPE" || code === "EMESSAGE") {
    return false;
  }
  if (["ECONNECTION", "ETIMEDOUT", "ESOCKET", "ECONNRESET"].includes(code)) {
    return true;
  }
  const message = String(error && error.message ? error.message : "")
      .toLowerCase();
  return message.includes("greeting never received") ||
    message.includes("connection timeout") ||
    message.includes("socket closed unexpectedly");
}

/**
 * Sends email by trying configured SMTP transport, then safe fallbacks.
 * @param {Object} smtp merged SMTP config
 * @param {string} smtpPassword resolved password
 * @param {Object} mailOptions nodemailer sendMail payload
 * @param {string} contextLabel logging context
 * @return {Promise<void>} resolves when mail is sent
 */
async function sendMailWithSmtpFallback(
    smtp,
    smtpPassword,
    mailOptions,
    contextLabel,
) {
  const candidates = buildSmtpTransportCandidates(smtp, smtpPassword);
  let lastError = null;

  for (let i = 0; i < candidates.length; i++) {
    const options = candidates[i];
    const transporter = nodemailer.createTransport(options);
    try {
      await transporter.sendMail(mailOptions);
      console.log(
          `📧 SMTP send ok [${contextLabel}] ` +
          `host=${options.host} port=${options.port} secure=${options.secure}`,
      );
      return;
    } catch (error) {
      lastError = error;
      const retryable = isRetryableSmtpTransportError(error);
      console.warn(
          `⚠️ SMTP attempt failed [${contextLabel}] ` +
          `host=${options.host} ` +
          `port=${options.port} secure=${options.secure} ` +
          `code=${error && error.code ? error.code : "unknown"} ` +
          `message=${error && error.message ? error.message : "unknown"}`,
      );
      if (!retryable || i === candidates.length - 1) {
        throw error;
      }
    }
  }

  if (lastError) throw lastError;
  throw new Error("SMTP send failed without an explicit error");
}

/**
 * Builds deterministic idempotency lock key.
 * @param {string} type lock type prefix
 * @param {string} rawKey source uniqueness payload
 * @return {string} lock document id
 */
function makeIdempotencyKey(type, rawKey) {
  const hash = crypto.createHash("sha256").update(String(rawKey)).digest("hex");
  return `${type}_${hash}`;
}

/**
 * Attempts to claim a one-time processing lock.
 * @param {string} type lock type prefix
 * @param {string} rawKey source uniqueness payload
 * @param {Object} context debug metadata
 * @return {Promise<{created: boolean, key: string}>} lock result
 */
async function claimIdempotency(type, rawKey, context = {}) {
  const key = makeIdempotencyKey(type, rawKey);
  const ref = db.collection("_functionLocks").doc(key);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const created = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      return false;
    }
    tx.set(ref, {
      type,
      rawKey: String(rawKey).slice(0, 1024),
      context,
      createdAt: now,
    });
    return true;
  });

  return {created, key};
}

/**
 * Normalizes confirmation number for deterministic matching.
 * @param {*} value untrusted confirmation number
 * @return {string} normalized value
 */
function normalizeConfirmationNo(value) {
  return String(value || "").trim().toUpperCase();
}

/**
 * Parses mileage as a non-negative integer.
 * @param {*} value untrusted mileage value
 * @return {number|null} parsed mileage or null
 */
function parseMileage(value) {
  const mileage = Number(value);
  if (!Number.isFinite(mileage)) return null;
  if (mileage < 0) return null;
  if (!Number.isInteger(mileage)) return null;
  return mileage;
}

/**
 * Parses fuel level and normalizes to 0.0 - 1.0.
 * Supports ratio (0-1), eighths (0-8), and percentage (0-100).
 * NOTE: Wheelsys uses eighths; we prioritize 0-8 interpretation for values > 1.
 * @param {*} value untrusted fuel value
 * @return {number|null} normalized fuel ratio
 */
function parseFuelLevel(value) {
  if (typeof value === "string") {
    const cleaned = value.trim();
    const slashMatch = cleaned.match(/^(\d{1,3})\s*\/\s*8$/);
    if (slashMatch) {
      const eighths = Number(slashMatch[1]);
      if (Number.isFinite(eighths) && eighths >= 0 && eighths <= 8) {
        return eighths / 8;
      }
    }
  }
  const fuel = Number(value);
  if (!Number.isFinite(fuel)) return null;
  if (fuel < 0) return null;
  if (fuel <= 1) return fuel;
  // Wheelsys compatibility: 0..8 means fuel eighths
  if (fuel <= 8) return fuel / 8;
  if (fuel <= 100) return fuel / 100;
  return null;
}

/**
 * Returns a UTC ISO timestamp from request payload.
 * @param {*} value input event time
 * @return {string} valid ISO timestamp
 */
function normalizeEventTime(value) {
  const date = value ? new Date(value) : new Date();
  if (Number.isNaN(date.getTime())) {
    return new Date().toISOString();
  }
  return date.toISOString();
}

/**
 * Reads API key from x-api-key or Bearer token.
 * @param {*} req HTTP request
 * @return {string} API key candidate
 */
function readApiKey(req) {
  const headerKey = String(req.get("x-api-key") || "").trim();
  if (headerKey) return headerKey;
  const authHeader = String(req.get("authorization") || "");
  if (authHeader.toLowerCase().startsWith("bearer ")) {
    return authHeader.slice(7).trim();
  }
  return "";
}

/**
 * Verifies optional HMAC signature with replay-window check.
 * @param {*} req HTTP request
 * @param {string} rawBody raw request string
 * @return {boolean} true when signature is valid or disabled
 */
function verifyWheelsysSignature(req, rawBody) {
  const secret = String(process.env.WHEELSYS_HMAC_SECRET || "").trim();
  if (!secret) return true;

  const timestamp = String(req.get("x-timestamp") || "").trim();
  const signature = String(req.get("x-signature") || "").trim();
  if (!timestamp || !signature) return false;

  const reqMs = Date.parse(timestamp);
  if (Number.isNaN(reqMs)) return false;
  const diffSeconds = Math.abs(Date.now() - reqMs) / 1000;
  if (diffSeconds > 300) return false;

  const payload = `${timestamp}.${rawBody}`;
  const expected = crypto
      .createHmac("sha256", secret)
      .update(payload)
      .digest("hex");
  const expectedBuf = Buffer.from(expected, "hex");
  const signatureBuf = Buffer.from(signature, "hex");
  if (expectedBuf.length !== signatureBuf.length) return false;
  return crypto.timingSafeEqual(expectedBuf, signatureBuf);
}

/**
 * Max odometer from `checkInKayitlari` or legacy `lastCheckIn`.
 * @param {Object} vehicleData vehicle doc
 * @return {number|null}
 */
function maxCheckInKmFromVehicle(vehicleData) {
  const data = vehicleData || {};
  let maxKm = null;
  const arr = data.checkInKayitlari;
  if (Array.isArray(arr)) {
    for (const row of arr) {
      const k = Number(row && row.km);
      if (Number.isFinite(k)) {
        if (maxKm === null || k > maxKm) maxKm = k;
      }
    }
  }
  const legacy = data.lastCheckIn && data.lastCheckIn.km;
  const lk = Number(legacy);
  if (Number.isFinite(lk)) {
    if (maxKm === null || lk > maxKm) maxKm = lk;
  }
  return maxKm;
}

/**
 * Builds alternative confirmation strings for Firestore equality queries.
 * Handles common unicode-hyphen variants (integration payloads may vary).
 * @param {string} confirmationNo normalized confirmation number
 * @return {string[]} candidate codes
 */
function makeConfirmationCandidates(confirmationNo) {
  const raw = String(confirmationNo || "").trim().toUpperCase();
  const digitsMatch = raw.match(/(\d+)/);
  if (!raw.startsWith("RES") || !digitsMatch) return [raw];

  const digits = digitsMatch[1];
  const hyphenChars = [
    "-",
    "\u2010", // hyphen
    "\u2011", // non-breaking hyphen
    "\u2013", // en dash
    "\u2014", // em dash
    "\u2212", // minus sign
    "\u2043", // hyphen bullet
    "\u00ad", // soft hyphen
  ];

  const set = new Set();
  set.add(`RES-${digits}`);
  set.add(`RES${digits}`);
  hyphenChars.forEach((h) => set.add(`RES${h}${digits}`));
  return Array.from(set);
}

/**
 * Derive franchise id from a Firestore document reference path.
 * Example: franchies/{id}/exitIslemleri/{docId}
 * @param {FirebaseFirestore.DocumentReference} docRef Firestore doc reference
 * @return {string} franchise id or empty string
 */
function deriveFranchiseIdFromDocRef(docRef) {
  const path = String(docRef && docRef.path ? docRef.path : "");
  const parts = path.split("/");
  const idx = parts.indexOf("franchises");
  if (idx >= 0 && parts[idx + 1]) return parts[idx + 1];
  return "";
}

/**
 * Fetch exit documents for a RES code from franchise-scoped paths only.
 * @param {string} resKodu normalized RES code
 * @return {Promise<FirebaseFirestore.QueryDocumentSnapshot[]>}
 */
async function getExitDocsByResKodu(resKodu) {
  const franchisesSnap = await db.collection("franchises").get();
  for (const fidDoc of franchisesSnap.docs) {
    const fid = String(fidDoc.data().franchiseId || fidDoc.id || "")
        .trim();
    if (!fid) continue;
    const scopedSnap = await db.collection("franchises").doc(fid)
        .collection("exitIslemleri")
        .where("resKodu", "==", resKodu)
        .limit(20)
        .get();
    if (!scopedSnap.empty) return scopedSnap.docs;
  }

  return [];
}

/**
 * Fetch protocol documents from franchise-scoped paths only.
 * @param {string} reservationNumber normalized reservation number
 * @return {Promise<FirebaseFirestore.QueryDocumentSnapshot[]>}
 */
async function getProtocolDocsByReservationNumber(reservationNumber) {
  const franchisesSnap = await db.collection("franchises").get();
  for (const fidDoc of franchisesSnap.docs) {
    const fid = String(fidDoc.data().franchiseId || fidDoc.id || "")
        .trim();
    if (!fid) continue;
    const scopedSnap = await db.collection("franchises").doc(fid)
        .collection("protocols")
        .where("reservationNumber", "==", reservationNumber)
        .limit(20)
        .get();
    if (!scopedSnap.empty) return scopedSnap.docs;
  }

  return [];
}

/**
 * Resolves vehicle reference from confirmation number.
 * Priority: exitIslemleri.resKodu -> protocols.reservationNumber.
 * @param {string} confirmationNo normalized confirmation number
 * @return {Promise<Object>} resolution object
 */
async function resolveVehicleFromConfirmation(confirmationNo) {
  const candidates = makeConfirmationCandidates(confirmationNo);

  for (const code of candidates) {
    const exitDocs = await getExitDocsByResKodu(code);
    if (exitDocs.length > 0) {
      const ordered = exitDocs.sort((a, b) => {
        const ad = a.data() || {};
        const bd = b.data() || {};
        const at = parseAnyDateValue(ad.exitTarihi) ||
          parseAnyDateValue(ad.createdAt) ||
          new Date(0);
        const bt = parseAnyDateValue(bd.exitTarihi) ||
          parseAnyDateValue(bd.createdAt) ||
          new Date(0);
        return bt.getTime() - at.getTime();
      });

      const uniqueVehicleIds = new Set(
          ordered.map((d) => String((d.data() || {}).aracId || "").trim())
              .filter(Boolean),
      );
      if (uniqueVehicleIds.size > 1) {
        return {
          status: "ambiguous",
          reason: "multiple_vehicle_matches_in_exit",
        };
      }

      const chosenExit = ordered[0].data() || {};
      const franchiseFromExit = String(chosenExit.franchiseId || "").trim() ||
        deriveFranchiseIdFromDocRef(ordered[0].ref) ||
        "CH";
      const franchiseIdNorm = franchiseFromExit.toUpperCase();

      const vehicleId = String(chosenExit.aracId || "").trim();
      if (vehicleId) {
        const directScopedRef = db.collection("franchises")
            .doc(franchiseIdNorm)
            .collection("araclar")
            .doc(vehicleId);
        const directScopedSnap = await directScopedRef.get();
        if (directScopedSnap.exists) {
          return {
            status: "matched",
            source: "exitIslemleri.resKodu",
            vehicleRef: directScopedRef,
            vehicleData: directScopedSnap.data() || {},
            franchiseId: String(
                (directScopedSnap.data() || {}).franchiseId ||
                franchiseIdNorm,
            ).toUpperCase(),
          };
        }
      }
      const plate = String(chosenExit.aracPlaka || "").trim();
      if (plate) {
        const byPlateScoped = await db.collection("franchises")
            .doc(franchiseIdNorm)
            .collection("araclar")
            .where("plaka", "==", plate)
            .limit(2)
            .get();

        if (byPlateScoped.size === 1) {
          const vehicleDoc = byPlateScoped.docs[0];
          return {
            status: "matched",
            source: "exitIslemleri.resKodu",
            vehicleRef: vehicleDoc.ref,
            vehicleData: vehicleDoc.data() || {},
            franchiseId: String(
                (vehicleDoc.data() || {}).franchiseId ||
                franchiseIdNorm,
            ).toUpperCase(),
          };
        }
        if (byPlateScoped.size > 1) {
          return {
            status: "ambiguous",
            reason: "multiple_vehicle_matches_by_plate",
          };
        }
      }
    }
  }

  for (const code of candidates) {
    const protocolDocs = await getProtocolDocsByReservationNumber(code);
    if (protocolDocs.length > 0) {
      const ordered = protocolDocs.sort((a, b) => {
        const ad = a.data() || {};
        const bd = b.data() || {};
        const at = parseAnyDateValue(ad.createdAt) || new Date(0);
        const bt = parseAnyDateValue(bd.createdAt) || new Date(0);
        return bt.getTime() - at.getTime();
      });

      const selected = ordered[0].data() || {};
      const franchiseFromProtocol = String(selected.franchiseId || "").trim() ||
        deriveFranchiseIdFromDocRef(ordered[0].ref) ||
        "CH";
      const franchiseIdNorm = franchiseFromProtocol.toUpperCase();

      const plate = String(selected.vehiclePlate || "").trim();
      if (plate) {
        const byPlateScoped = await db.collection("franchises")
            .doc(franchiseIdNorm)
            .collection("araclar")
            .where("plaka", "==", plate)
            .limit(2)
            .get();

        if (byPlateScoped.size === 1) {
          const vehicleDoc = byPlateScoped.docs[0];
          return {
            status: "matched",
            source: "protocols.reservationNumber",
            vehicleRef: vehicleDoc.ref,
            vehicleData: vehicleDoc.data() || {},
            franchiseId: String(
                (vehicleDoc.data() || {}).franchiseId ||
                franchiseIdNorm,
            ).toUpperCase(),
          };
        }

        if (byPlateScoped.size > 1) {
          return {
            status: "ambiguous",
            reason: "multiple_vehicle_matches_by_plate",
          };
        }
      }
    }
  }

  return {status: "not_found"};
}

/**
 * Receives Wheelsys pre-checkin payload and updates vehicle check-in snapshot.
 */
// eslint-disable-next-line max-len
exports.wheelsysPreCheckIn = onRequest(wheelsysPreCheckInOptions, async (req, res) => {
  res.set("Content-Type", "application/json; charset=utf-8");

  if (req.method !== "POST") {
    res.status(405).json({error: "method_not_allowed"});
    return;
  }

  let configuredApiKey = getWheelsysApiKey();
  try {
    const secretVal = await wheelsysApiKeySecret.value();
    const secretKey = String(secretVal || "").trim();
    if (secretKey) configuredApiKey = secretKey;
  } catch (e) {
    res.status(500).json({error: "wheelsys_secret_access_failed"});
    return;
  }
  if (!configuredApiKey) {
    res.status(500).json({error: "wheelsys_api_key_not_configured"});
    return;
  }
  const providedApiKey = readApiKey(req);
  if (!providedApiKey || providedApiKey !== configuredApiKey) {
    res.status(401).json({error: "unauthorized"});
    return;
  }

  const rawBody = typeof req.rawBody === "string" ?
    req.rawBody :
    Buffer.from(req.rawBody || "").toString("utf8");
  if (!verifyWheelsysSignature(req, rawBody)) {
    res.status(401).json({error: "invalid_signature"});
    return;
  }

  const payload = (req.body && typeof req.body === "object") ? req.body : {};
  const confirmationNo = normalizeConfirmationNo(
      payload.confirmation_no ||
      payload.confirmationNo ||
      payload.reservationNumber,
  );
  const mileage = parseMileage(payload.mileage);
  const fuelLevel = parseFuelLevel(payload.fuel);
  if (!confirmationNo) {
    res.status(422).json({error: "validation_error", field: "confirmation_no"});
    return;
  }
  if (mileage === null) {
    res.status(422).json({error: "validation_error", field: "mileage"});
    return;
  }
  if (fuelLevel === null) {
    res.status(422).json({error: "validation_error", field: "fuel"});
    return;
  }

  const eventTime = normalizeEventTime(payload.event_time || payload.eventTime);
  const sourceEventId = String(
      payload.source_event_id || payload.sourceEventId || "",
  ).trim();
  const idempotencyRawKey = sourceEventId ||
    `${confirmationNo}|${mileage}|${fuelLevel}|${eventTime}`;
  const lock = await claimIdempotency(
      "wheelsys_precheckin",
      idempotencyRawKey,
      {confirmationNo, sourceEventId: sourceEventId || null},
  );
  if (!lock.created) {
    res.status(202).json({
      status: "already_processed",
      confirmation_no: confirmationNo,
    });
    return;
  }

  const resolved = await resolveVehicleFromConfirmation(confirmationNo);
  if (resolved.status === "not_found") {
    res.status(404).json({
      error: "reservation_not_found",
      confirmation_no: confirmationNo,
    });
    return;
  }
  if (resolved.status === "ambiguous") {
    res.status(409).json({
      error: "ambiguous_match",
      confirmation_no: confirmationNo,
      reason: resolved.reason || "multiple_matches",
    });
    return;
  }

  const eventDate = new Date(eventTime);
  const vehicleData = resolved.vehicleData || {};
  const custName =
    String(payload.customer_name || payload.customerName || "").trim() || null;
  const fuelEighths = Math.min(8, Math.max(0, Math.round(fuelLevel * 8)));
  const entryId = crypto.randomUUID();
  const entryTimestamp = admin.firestore.Timestamp.fromDate(eventDate);
  const newCheckInRow = {
    id: entryId,
    timestamp: entryTimestamp,
    km: mileage,
    fuelEighths,
    fuelLevel: fuelEighths / 8.0,
    fuelTankFull: fuelEighths >= 8,
    reservationNumber: confirmationNo,
    checkedInBy: "wheelsys_api",
    customerName: custName,
    linkedExitId: null,
  };
  const legacyLastCheckIn = {
    timestamp: entryTimestamp,
    km: mileage,
    fuelLevel,
    reservationNumber: confirmationNo,
    checkedInBy: "wheelsys_api",
    customerName: custName,
    sourceEventId: sourceEventId || null,
    source: "wheelsys",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(resolved.vehicleRef);
      const data = snap.data() || {};
      const maxKm = maxCheckInKmFromVehicle(data);
      if (Number.isFinite(maxKm) && mileage < maxKm) {
        const err = new Error("mileage_lower_than_existing_last_checkin");
        err.code = "mileage_low";
        throw err;
      }
      const existing = Array.isArray(data.checkInKayitlari) ?
        [...data.checkInKayitlari] :
        [];
      tx.set(
          resolved.vehicleRef,
          {
            checkInKayitlari: [...existing, newCheckInRow],
            lastCheckIn: legacyLastCheckIn,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
    });
  } catch (e) {
    if (e && e.code === "mileage_low") {
      res.status(422).json({
        error: "validation_error",
        field: "mileage",
        reason: "mileage_lower_than_existing_last_checkin",
      });
      return;
    }
    console.error("wheelsysPreCheckIn transaction failed", e);
    res.status(500).json({error: "write_failed"});
    return;
  }

  const franchiseId = String(resolved.franchiseId || "CH").toUpperCase();
  const activitiesRef = db.collection("franchises")
      .doc(franchiseId)
      .collection("activities");
  await activitiesRef.add({
    id: crypto.randomUUID().toUpperCase(),
    tip: "Wheelsys Pre Check-In",
    aciklama: `Wheelsys pre-checkin synced (${confirmationNo})`,
    tarih: admin.firestore.FieldValue.serverTimestamp(),
    aracPlaka: String(vehicleData.plaka || ""),
    detayliAciklama:
      `Source=${resolved.source}, mileage=${mileage}, fuelLevel=${fuelLevel}`,
    kullaniciAdi: "wheelsys_api",
    kullaniciEmail: "integration@wheelsys",
    franchiseId,
  });

  res.status(200).json({
    status: "updated",
    confirmation_no: confirmationNo,
    vehicle_id: resolved.vehicleRef.id,
    source: resolved.source,
    franchise_id: franchiseId,
    fuel_level: fuelLevel,
    mileage,
  });
});

/**
 * Sends push notifications when a new document
 * is created in the 'notifications' collection
 * @param {*} event Firestore trigger event
 * @param {string} source legacy or scoped trigger
 * @return {Promise} processing result
 */
async function processNotificationEvent(event, source) {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("No data associated with the event");
    return null;
  }

  const data = snapshot.data();
  const notificationId = event.params.notificationId;
  const rawKey = data.idempotencyKey ||
    `${notificationId}|${data.franchiseId || "CH"}|${source}`;
  const lock = await claimIdempotency("notification", rawKey, {
    source,
    notificationId,
  });
  if (!lock.created) {
    console.log(`⏭️ [CF] Duplicate notification skipped (${lock.key})`);
    await snapshot.ref.delete();
    return null;
  }

  const title = data.title || "Green Motion";
  const body = data.body || "New notification";
  let tokens = [];
  const notificationData = data.data || {};
  const franchiseId = String(data.franchiseId || "CH").toUpperCase();
  console.log("📬 [CF] ========== Cloud Function Triggered ==========");
  console.log(`📬 [CF] Notification ID: ${notificationId}`);
  console.log(`📬 [CF] Source: ${source}, franchise: ${franchiseId}`);

  // Always resolve tokens server-side from users collection (franchise-scoped).
  const usersSnapshot = await admin.firestore()
      .collection("users")
      .where("franchiseId", "==", franchiseId)
      .get();
  tokens = usersSnapshot.docs
      .map((doc) => doc.data().fcmToken)
      .filter((t) => typeof t === "string" && t.length > 20);

  if (!tokens || tokens.length === 0) {
    console.log("⚠️ [CF] No FCM tokens found. Skipping notification.");
    await snapshot.ref.delete();
    return null;
  }

  const message = {
    notification: {title, body},
    data: {
      ...notificationData,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    tokens,
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          "sound": "default",
          "badge": 1,
          "content-available": 1,
          "mutable-content": 1,
        },
      },
    },
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    if (response.failureCount > 0) {
      response.responses.forEach((resp, idx) => {
        if (!resp.success && resp.error) {
          const isInvalidToken =
            resp.error.code === "messaging/invalid-registration-token";
          const isNotRegistered =
            resp.error.code === "messaging/registration-token-not-registered";
          if (isInvalidToken || isNotRegistered) {
            const invalidToken = tokens[idx];
            admin.firestore()
                .collection("users")
                .where("fcmToken", "==", invalidToken)
                .get()
                .then((userSnapshot) => {
                  userSnapshot.forEach((doc) => {
                    doc.ref.update({
                      fcmToken: admin.firestore.FieldValue.delete(),
                    });
                  });
                })
                .catch((err) => {
                  console.error("❌ [CF] Error removing token:", err);
                });
          }
        }
      });
    }

    await snapshot.ref.delete();
    return response;
  } catch (error) {
    console.error("❌ [CF] Error sending notification:", error);
    return null;
  }
}

exports.sendNotification = onDocumentCreated(
    "notifications/{notificationId}",
    async (event) => processNotificationEvent(event, "legacy"),
);

exports.sendNotificationScoped = onDocumentCreated(
    "franchises/{franchiseId}/notifications/{notificationId}",
    async (event) => processNotificationEvent(event, "scoped"),
);

/**
 * Small async delay utility for retry backoff.
 * @param {number} ms milliseconds to wait
 * @return {Promise<void>} resolves after timeout
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Tries to resolve queued email PDF from URL or Storage paths.
 * @param {Object} payload queued email payload
 * @param {string} franchiseId resolved franchise id
 * @param {string|undefined} payloadFranchiseId payload franchise id
 * @param {string|undefined} paramFranchiseId trigger param franchise id
 * @return {Promise<Buffer|null>} PDF bytes or null when unavailable
 */
async function resolveQueuedEmailPdfBuffer(
    payload,
    franchiseId,
    payloadFranchiseId,
    paramFranchiseId,
) {
  const list = await resolveQueuedEmailPdfBuffers(
      payload,
      franchiseId,
      payloadFranchiseId,
      paramFranchiseId,
  );
  return list.length > 0 ? list[0] : null;
}

/**
 * Resolves one or more PDF attachments (explicit pdfURLs, else legacy pdfURL + Storage).
 * @param {Object} payload queued email payload
 * @param {string} franchiseId resolved franchise id
 * @param {string|undefined} payloadFranchiseId payload franchise id
 * @param {string|undefined} paramFranchiseId trigger param franchise id
 * @return {Promise<Buffer[]>} zero or more PDF buffers (multi-URL requires all OK)
 */
async function resolveQueuedEmailPdfBuffers(
    payload,
    franchiseId,
    payloadFranchiseId,
    paramFranchiseId,
) {
  const fromUrls = Array.isArray(payload.pdfURLs) ?
    payload.pdfURLs.map((u) => String(u || "").trim()).filter(Boolean) :
    [];

  if (fromUrls.length > 0) {
    const buffers = [];
    for (const url of fromUrls) {
      try {
        const response = await fetch(url);
        if (response.ok) {
          buffers.push(Buffer.from(await response.arrayBuffer()));
        } else {
          console.warn(
              `⚠️ Multi-PDF URL fetch failed (HTTP ${response.status}) for queued email`,
          );
        }
      } catch (urlFetchError) {
        console.warn(
            "⚠️ Multi-PDF URL fetch threw:",
            urlFetchError.message || urlFetchError,
        );
      }
    }
    if (buffers.length === fromUrls.length && buffers.length > 0) {
      return buffers;
    }
    return [];
  }

  let pdfBuffer = null;

  if (payload.pdfURL) {
    try {
      const response = await fetch(payload.pdfURL);
      if (response.ok) {
        const arrayBuffer = await response.arrayBuffer();
        pdfBuffer = Buffer.from(arrayBuffer);
      } else {
        console.warn(
            `⚠️ PDF URL fetch failed (HTTP ${response.status}), ` +
            "trying Storage fallback",
        );
      }
    } catch (urlFetchError) {
      console.warn(
          "⚠️ PDF URL fetch threw error, trying Storage fallback:",
          urlFetchError.message || urlFetchError,
      );
    }
  }

  if (!pdfBuffer && payload.returnId) {
    const franchiseCandidates = Array.from(new Set([
      franchiseId,
      payloadFranchiseId,
      payloadFranchiseId ? String(payloadFranchiseId).toUpperCase() : null,
      paramFranchiseId,
    ].filter(Boolean)));
    const candidatePaths = franchiseCandidates.map(
        (id) => `franchises/${id}/return_pdfs/${payload.returnId}.pdf`,
    );
    candidatePaths.push(`return_pdfs/${payload.returnId}.pdf`);

    for (const candidatePath of candidatePaths) {
      const file = admin.storage().bucket().file(candidatePath);
      const exists = await file.exists();
      if (exists[0]) {
        const downloaded = await file.download();
        pdfBuffer = downloaded[0];
        console.log(`📄 PDF fallback hit: ${candidatePath}`);
        break;
      }
    }
  }

  return pdfBuffer ? [pdfBuffer] : [];
}

/**
 * Sends queued return emails using SMTP configuration stored in Firestore.
 * Triggered when a document is created under outgoingEmails.
 * @param {*} event Firestore trigger event
 * @param {string} source legacy or scoped trigger
 * @return {Promise} no response payload
 */
async function processQueuedEmailEvent(event, source) {
  const snapshot = event.data;
  if (!snapshot) return null;

  const emailId = event.params.emailId;
  const payload = snapshot.data();
  const paramFranchiseId = event.params.franchiseId;
  const payloadFranchiseId = payload.franchiseId;
  const franchiseId = paramFranchiseId || payloadFranchiseId || "CH";
  const rawKey = payload.idempotencyKey ||
    `${payload.returnId || emailId}|${payload.to || ""}|${franchiseId}`;
  const lock = await claimIdempotency("outgoing_email", rawKey, {
    source,
    emailId,
    franchiseId,
  });
  if (!lock.created) {
    console.log(`⏭️ [CF] Duplicate email skipped (${lock.key})`);
    await snapshot.ref.update({
      status: "duplicate_skipped",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return null;
  }

  try {
    const smtp = await readSmtpConfigDoc(franchiseId);
    if (!smtp ||
        !String(smtp.host || "").trim() ||
        !String(smtp.username || "").trim()) {
      await snapshot.ref.update({
        status: "failed",
        error: "Missing SMTP configuration",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return null;
    }
    const smtpPassword = resolveSmtpPassword(smtp, franchiseId);

    const attachments = [];
    let pdfBuffers = [];
    // Wait for PDF availability before sending email.
    const pdfRetryDelaysMs = [0, 1500, 3000, 6000, 10000];
    for (let attempt = 0; attempt < pdfRetryDelaysMs.length; attempt++) {
      const delayMs = pdfRetryDelaysMs[attempt];
      if (delayMs > 0) {
        await sleep(delayMs);
      }
      pdfBuffers = await resolveQueuedEmailPdfBuffers(
          payload,
          franchiseId,
          payloadFranchiseId,
          paramFranchiseId,
      );
      if (pdfBuffers.length > 0) {
        break;
      }
      console.warn(
          `⚠️ PDF still unavailable for ${emailId} ` +
          `(attempt ${attempt + 1}/${pdfRetryDelaysMs.length})`,
      );
    }

    if (!pdfBuffers.length) {
      throw new Error("Missing PDF content for queued return email");
    }
    const maxAttachmentBytes =
      22 * 1024 * 1024;
    const totalBytes = pdfBuffers.reduce((s, b) => s + b.length, 0);
    if (totalBytes > maxAttachmentBytes) {
      const pdfMb = Math.round(
          totalBytes / (1024 * 1024),
      );
      throw new Error(
          `PDF attachment too large (${pdfMb}MB). ` +
          "Reduce return photo size and retry.",
      );
    }

    const plateRaw = String(payload.vehiclePlate || "document")
        .replace(/\s+/g, "");
    const isCheckout = String(payload.subject || "")
        .toLowerCase()
        .includes("check out");
    const filePrefix = isCheckout ? "checkout" : "return";
    const multi = pdfBuffers.length > 1;
    pdfBuffers.forEach((pdfBuffer, idx) => {
      let suffix = "";
      if (multi) {
        suffix = idx === 0 ? "_TR" : "_EN";
      }
      attachments.push({
        filename: `${filePrefix}_${plateRaw}${suffix}.pdf`,
        content: pdfBuffer,
        contentType: "application/pdf",
      });
    });

    const formattedBodyHtml = formatEmailBodyAsHtml(payload.body || "");
    const wrapperStyle = [
      "font-family:Arial,Helvetica,sans-serif",
      "font-size:14px",
      "line-height:1.55",
      "color:#111",
    ].join(";");
    const htmlBody = `
      <div
        style="${wrapperStyle}"
      >
        ${formattedBodyHtml}
        <p style="margin:16px 0 0 0;color:#6b7280;font-size:12px;">
          This is an automated no-reply email.
          Please do not reply to this message.
        </p>
      </div>
    `;
    const noReplyNote =
      "[No-Reply] This is an automated email. Please do not reply.";
    const textBody = `${payload.body || ""}\n\n${noReplyNote}`;

    await sendMailWithSmtpFallback(smtp, smtpPassword, {
      from: `"${smtp.senderName || "ERPX"}" <${smtp.senderEmail}>`,
      to: payload.to,
      subject: payload.subject || "Return Confirmation",
      text: textBody,
      html: htmlBody,
      attachments,
    }, `return_email:${emailId}`);

    await snapshot.ref.update({
      status: "sent",
      error: admin.firestore.FieldValue.delete(),
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`✅ Email sent for queue item ${emailId}`);
    return null;
  } catch (error) {
    console.error(`❌ Email send failed for ${emailId}:`, error);
    await snapshot.ref.update({
      status: "failed",
      error: error.message || "Unknown email error",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return null;
  }
}

exports.sendQueuedEmail = onDocumentCreated(
    "outgoingEmails/{emailId}",
    async (event) => processQueuedEmailEvent(event, "legacy"),
);

exports.sendQueuedEmailScoped = onDocumentCreated(
    "franchises/{franchiseId}/outgoingEmails/{emailId}",
    async (event) => processQueuedEmailEvent(event, "scoped"),
);

/**
 * Parses mixed Firestore/ISO date values.
 * @param {*} raw date-like input
 * @return {Date|null} parsed date or null
 */
function parseAnyDateValue(raw) {
  if (!raw) return null;
  if (typeof raw === "string") {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (raw.toDate && typeof raw.toDate === "function") {
    return raw.toDate();
  }
  if (typeof raw.seconds === "number") {
    return new Date(raw.seconds * 1000);
  }
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Calculates outstanding amount for a protocol.
 * @param {Object} protocol protocol payload
 * @return {number} remaining amount
 */
function protocolOutstandingAmount(protocol) {
  const required = Number(protocol.requiredAmount || 0);
  const paid = Number(protocol.paidAmount || 0);
  const outstanding = required - paid;
  return outstanding > 0 ? outstanding : 0;
}

/**
 * Reads customer email from normalized protocol fields.
 * @param {Object} protocol protocol payload
 * @return {string} customer email or empty
 */
function protocolCustomerEmail(protocol) {
  if (protocol.customerEmail) {
    return String(protocol.customerEmail).trim();
  }
  if (typeof protocol.fieldValues === "string") {
    try {
      const parsed = JSON.parse(protocol.fieldValues);
      return String(parsed.CUSTOMER_EMAIL || parsed.EMAIL || "").trim();
    } catch (error) {
      return "";
    }
  }
  if (protocol.fieldValues && typeof protocol.fieldValues === "object") {
    return String(
        protocol.fieldValues.CUSTOMER_EMAIL || protocol.fieldValues.EMAIL || "",
    ).trim();
  }
  return "";
}

/**
 * Replaces reminder template placeholders.
 * @param {string} template message template
 * @param {Object} replacements replacement map
 * @return {string} rendered output
 */
function renderReminderTemplate(template, replacements) {
  let output = String(template || "");
  Object.keys(replacements).forEach((key) => {
    const token = new RegExp(`\\{\\{${key}\\}\\}`, "g");
    output = output.replace(token, String(replacements[key] || ""));
  });
  return output;
}

/**
 * Escapes HTML-sensitive characters.
 * @param {string} value raw text
 * @return {string} escaped text
 */
function escapeHtml(value) {
  return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
}

/**
 * Converts plain text into paragraph-based HTML.
 * Preserves blank-line breaks and in-paragraph line breaks.
 * @param {string} body plain text
 * @return {string} formatted HTML
 */
function formatEmailBodyAsHtml(body) {
  const normalized = String(body || "").replace(/\r\n/g, "\n").trim();
  if (!normalized) return "";
  return normalized
      .split(/\n\s*\n/g)
      .map((paragraph) => `<p style="margin:0 0 12px 0;">${
        escapeHtml(paragraph).replace(/\n/g, "<br/>")
      }</p>`)
      .join("");
}

/**
 * Loads franchise SMTP configuration.
 * @param {string} franchiseId franchise id
 * @return {Promise<Object|null>} smtp config or null
 */
async function loadFranchiseSmtpConfig(franchiseId) {
  const id = String(franchiseId || "CH").trim().toUpperCase();
  const snap = await db.collection("smtpConfigurations")
      .doc(id)
      .get();
  const data = snap.exists ? (snap.data() || {}) : {};
  return mergeDefaultSmtpIfNeeded(id, data);
}

/**
 * Normalizes and resolves franchise currency.
 * Falls back to CH/CHF when the franchise document is missing.
 * @param {string} franchiseId franchise identifier
 * @return {Promise<string>} normalized ISO currency code
 */
async function resolveFranchiseCurrency(franchiseId) {
  const normalizedFranchiseId = String(franchiseId || "CH")
      .trim()
      .toUpperCase();
  const snap = await db.collection("franchises")
      .doc(normalizedFranchiseId)
      .get();
  if (!snap.exists) return "CHF";
  const currency = String((snap.data() || {}).currency || "")
      .trim()
      .toUpperCase();
  return currency || "CHF";
}

/**
 * Sends one protocol reminder email through SMTP.
 * @param {Object} args send arguments
 * @return {Promise<void>} send result
 */
async function sendProtocolReminderWithSmtp({
  smtp,
  smtpPassword,
  to,
  protocolId,
  customerName,
  outstandingAmount,
  createdAtISO,
  franchiseId,
}) {
  const replacements = {
    CUSTOMER_NAME: customerName || "Customer",
    PROTOCOL_ID: protocolId || "N/A",
    OUTSTANDING_AMOUNT: Number(outstandingAmount || 0).toFixed(2),
    CREATED_AT: createdAtISO || "",
    FRANCHISE_ID: franchiseId || "CH",
  };

  const subject = renderReminderTemplate(
      smtp.reminderSubject || "Payment Reminder - {{PROTOCOL_ID}}",
      replacements,
  );
  const body = renderReminderTemplate(
      smtp.reminderBody ||
      "Dear {{CUSTOMER_NAME}},\n\nOutstanding amount for " +
      "protocol {{PROTOCOL_ID}} is {{OUTSTANDING_AMOUNT}} CHF.",
      replacements,
  );

  const htmlBody = body
      .split("\n")
      .map((line) => `<p>${line}</p>`)
      .join("");

  await sendMailWithSmtpFallback(smtp, smtpPassword, {
    from: `"${smtp.senderName || "Green Motion"}" <${smtp.senderEmail}>`,
    to,
    subject,
    text: body,
    html: htmlBody,
  }, `protocol_reminder:${protocolId}`);
}

exports.sendProtocolPaymentReminders = onSchedule(
    "0 9 * * *",
    async () => {
      const now = new Date();
      const snapshot = await db.collectionGroup("protocols").get();
      let sentCount = 0;
      let skippedPaid = 0;
      let skippedNotDue = 0;
      let failedCount = 0;

      for (const docSnap of snapshot.docs) {
        const protocol = docSnap.data() || {};
        const protocolId = protocol.protocolId || docSnap.id;
        const franchiseId = String(protocol.franchiseId || "CH").toUpperCase();
        const outstanding = protocolOutstandingAmount(protocol);
        const createdAtDate = parseAnyDateValue(protocol.createdAt);

        if (!createdAtDate) {
          skippedNotDue += 1;
          continue;
        }

        const dueDate = new Date(createdAtDate);
        dueDate.setDate(dueDate.getDate() + 30);
        const history = Array.isArray(protocol.reminderHistory) ?
          protocol.reminderHistory :
          [];
        const alreadySent = protocol.reminderStatus === "sent" ||
          history.some((h) => h && h.type === "sent");

        if (outstanding <= 0.000001) {
          skippedPaid += 1;
          if (protocol.reminderStatus === "planned") {
            await docSnap.ref.update({
              reminderStatus: "cancelled_paid",
              reminderNextPlannedAt: null,
              reminderHistory: admin.firestore.FieldValue.arrayUnion({
                type: "cancelled_paid",
                at: new Date().toISOString(),
                note: "Outstanding amount closed before reminder send",
              }),
            });
          }
          continue;
        }

        if (alreadySent) {
          continue;
        }

        if (now < dueDate) {
          skippedNotDue += 1;
          continue;
        }

        const to = protocolCustomerEmail(protocol);
        if (!to) {
          failedCount += 1;
          await docSnap.ref.update({
            reminderStatus: "failed_missing_email",
            reminderHistory: admin.firestore.FieldValue.arrayUnion({
              type: "failed_missing_email",
              at: new Date().toISOString(),
              dueAt: dueDate.toISOString(),
              note: "Customer email not found for protocol reminder",
            }),
          });
          continue;
        }

        const smtp = await loadFranchiseSmtpConfig(franchiseId);
        if (!smtp || !smtp.host || !smtp.senderEmail) {
          failedCount += 1;
          await docSnap.ref.update({
            reminderStatus: "failed_missing_smtp",
            reminderHistory: admin.firestore.FieldValue.arrayUnion({
              type: "failed_missing_smtp",
              at: new Date().toISOString(),
              dueAt: dueDate.toISOString(),
              note: `SMTP config missing for ${franchiseId}`,
            }),
          });
          continue;
        }

        if (smtp.reminderEnabled === false) {
          continue;
        }

        try {
          const smtpPassword = resolveSmtpPassword(smtp, franchiseId);
          await sendProtocolReminderWithSmtp({
            smtp,
            smtpPassword,
            to,
            protocolId,
            customerName: protocol.customerName,
            outstandingAmount: outstanding,
            createdAtISO: createdAtDate.toISOString(),
            franchiseId,
          });

          sentCount += 1;
          await docSnap.ref.update({
            reminderStatus: "sent",
            reminderSentAt: new Date().toISOString(),
            reminderLastSentAt: new Date().toISOString(),
            reminderNextPlannedAt: null,
            reminderHistory: admin.firestore.FieldValue.arrayUnion({
              type: "sent",
              at: new Date().toISOString(),
              dueAt: dueDate.toISOString(),
              to,
              outstandingAmount: Number(outstanding.toFixed(2)),
            }),
          });
        } catch (error) {
          failedCount += 1;
          await docSnap.ref.update({
            reminderStatus: "failed_send_error",
            reminderHistory: admin.firestore.FieldValue.arrayUnion({
              type: "failed_send_error",
              at: new Date().toISOString(),
              dueAt: dueDate.toISOString(),
              note: error.message || "Unknown SMTP error",
            }),
          });
        }
      }

      console.log("[Protocol Reminder Sweep]", {
        scanned: snapshot.size,
        sentCount,
        skippedPaid,
        skippedNotDue,
        failedCount,
      });
      return null;
    },
);

exports.sendProtocolReminderTestEmail = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin" && callerRole !== "admin") {
    throw new HttpsError(
        "permission-denied",
        "Only admin/superadmin can send test reminder",
    );
  }

  const to = String((request.data && request.data.to) || "").trim();
  if (!to) {
    throw new HttpsError("invalid-argument", "to is required");
  }
  const franchiseId = String(
      (request.data && request.data.franchiseId) ||
      callerDoc.data().franchiseId ||
      "CH",
  ).toUpperCase();

  const smtp = await loadFranchiseSmtpConfig(franchiseId);
  if (!smtp || !smtp.host || !smtp.senderEmail) {
    throw new HttpsError(
        "failed-precondition",
        `SMTP configuration is missing for ${franchiseId}`,
    );
  }

  await sendProtocolReminderWithSmtp({
    smtp,
    smtpPassword: resolveSmtpPassword(smtp, franchiseId),
    to,
    protocolId: "TEST-PROTOCOL-001",
    customerName: "Test Customer",
    outstandingAmount: 123.45,
    createdAtISO: new Date().toISOString(),
    franchiseId,
  });

  return {
    success: true,
    to,
    franchiseId,
  };
});

/**
 * Clean up expired FCM tokens
 * Runs daily at midnight UTC
 */
exports.cleanupExpiredTokens = onSchedule("0 0 * * *", async () => {
  console.log("🧹 Starting cleanup of expired FCM tokens");

  try {
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
    const usersSnapshot = await admin.firestore()
        .collection("users")
        .where("lastTokenUpdate", "<",
            admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
        .get();

    let deletedCount = 0;
    const batch = admin.firestore().batch();

    usersSnapshot.forEach((doc) => {
      batch.update(doc.ref, {
        fcmToken: admin.firestore.FieldValue.delete(),
        lastTokenUpdate: admin.firestore.FieldValue.delete(),
      });
      deletedCount++;
    });

    if (deletedCount > 0) {
      await batch.commit();
      console.log(`✅ Cleaned up ${deletedCount} expired tokens`);
    } else {
      console.log("✅ No expired tokens to clean up");
    }

    return null;
  } catch (error) {
    console.error("❌ Error during token cleanup:", error);
    return null;
  }
});

/**
 * Cleanup expired notification queue documents.
 * Runs daily. Deletes both legacy and scoped notification docs.
 */
exports.cleanupExpiredNotifications = onSchedule("15 3 * * *", async () => {
  console.log("🧹 Starting cleanup of expired notifications");

  const now = admin.firestore.Timestamp.now();
  let deleted = 0;

  try {
    // collectionGroup("notifications") covers:
    // - /notifications/{id}
    // - /franchises/{franchiseId}/notifications/{id}
    let keepGoing = true;
    while (keepGoing) {
      const snap = await db.collectionGroup("notifications")
          .where("expiresAt", "<", now)
          .limit(400)
          .get();

      if (snap.empty) {
        keepGoing = false;
        continue;
      }

      const batch = db.batch();
      snap.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });
      await batch.commit();
      deleted += snap.size;

      // Small yield to reduce contention in busy projects.
      await new Promise((r) => setTimeout(r, 50));
    }

    console.log(`✅ Expired notifications deleted: ${deleted}`);
    return null;
  } catch (error) {
    console.error("❌ Error during notifications cleanup:", error);
    return null;
  }
});

/**
 * Delete old return PDFs from Firebase Storage.
 * Keeps only last 24 hours to reduce storage usage.
 * Runs daily.
 */
exports.cleanupOldReturnPdfs = onSchedule("30 3 * * *", async () => {
  console.log("🧹 Starting return PDF cleanup (older than 1 day)");

  const bucket = admin.storage().bucket();
  const cutoffMs = Date.now() - (24 * 60 * 60 * 1000);
  const prefixes = ["return_pdfs/"];

  try {
    const franchisesSnapshot = await db.collection("franchises").get();
    franchisesSnapshot.forEach((doc) => {
      prefixes.push(`franchises/${doc.id}/return_pdfs/`);
    });

    let scannedCount = 0;
    let deletedCount = 0;
    let errorCount = 0;

    for (const prefix of prefixes) {
      let pageToken = undefined;

      do {
        const [files, nextQuery] = await bucket.getFiles({
          prefix,
          maxResults: 500,
          pageToken,
        });
        pageToken = nextQuery && nextQuery.pageToken ?
          nextQuery.pageToken :
          undefined;

        for (const file of files) {
          if (!file || !file.name || file.name.endsWith("/")) {
            continue;
          }
          if (!file.name.toLowerCase().endsWith(".pdf")) {
            continue;
          }

          scannedCount += 1;

          try {
            const metadata = file.metadata && file.metadata.timeCreated ?
              file.metadata :
              (await file.getMetadata())[0];
            const createdMs = metadata && metadata.timeCreated ?
              Date.parse(metadata.timeCreated) :
              NaN;
            if (Number.isNaN(createdMs)) {
              continue;
            }
            if (createdMs >= cutoffMs) {
              continue;
            }

            await file.delete({ignoreNotFound: true});
            deletedCount += 1;
          } catch (fileError) {
            errorCount += 1;
            console.error(`❌ Failed deleting ${file.name}:`, fileError);
          }
        }
      } while (pageToken);
    }

    console.log("✅ Return PDF cleanup completed", {
      prefixes: prefixes.length,
      scannedCount,
      deletedCount,
      errorCount,
    });
    return null;
  } catch (error) {
    console.error("❌ Return PDF cleanup failed:", error);
    return null;
  }
});

/**
 * Optional: Send a welcome notification when a new user is created
 */
exports.sendWelcomeNotification = onDocumentCreated(
    "users/{userId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      const userData = snapshot.data();
      const fcmToken = userData.fcmToken;

      if (!fcmToken) {
        const msg = "⚠️ No FCM token for new user";
        console.log(msg + ", skipping welcome notification");
        return;
      }

      const userName = userData.fullName || "there";
      const welcomeMsg = `Hi ${userName}! Your account has been created.`;

      const message = {
        notification: {
          title: "👋 Welcome to Green Motion!",
          body: welcomeMsg,
        },
        token: fcmToken,
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      try {
        await admin.messaging().send(message);
        console.log(`✅ Welcome notification sent to ${userData.email}`);
      } catch (error) {
        console.error("❌ Error sending welcome notification:", error);
      }

      return null;
    },
);

// ============================================================================
// MULTI-FRANCHISE MANAGEMENT FUNCTIONS
// ============================================================================

/**
 * Cleanup expired trial accounts
 * Runs daily at 2:00 AM UTC
 * Deactivates users whose trial period has passed
 */
exports.cleanupExpiredDemos = onSchedule("0 2 * * *", async () => {
  console.log("🧹 [Trial Cleanup] Starting cleanup of expired trial accounts");

  try {
    const now = admin.firestore.Timestamp.now();

    // Primary query (new schema)
    const expiredTrialSnapshot = await db
        .collection("users")
        .where("isTrialUser", "==", true)
        .where("trialEndsAt", "<", now)
        .where("isActive", "==", true)
        .get();

    // Backward-compatible query (legacy schema).
    const expiredLegacySnapshot = await db
        .collection("users")
        .where("isDemo", "==", true)
        .where("demoExpiresAt", "<", now)
        .where("isActive", "==", true)
        .get();

    const expiredUsersMap = new Map();
    expiredTrialSnapshot.docs.forEach((doc) => {
      expiredUsersMap.set(doc.id, doc);
    });
    expiredLegacySnapshot.docs.forEach((doc) => {
      expiredUsersMap.set(doc.id, doc);
    });
    const expiredUsers = Array.from(expiredUsersMap.values());

    if (expiredUsers.length === 0) {
      console.log("✅ [Trial Cleanup] No expired trial accounts found");
      return null;
    }

    console.log(`🔍 [Trial Cleanup] Found ${expiredUsers.length} ` +
      "expired trial accounts");

    const batch = db.batch();
    const franchiseUpdates = {};
    let deactivatedCount = 0;

    expiredUsers.forEach((userDoc) => {
      const userData = userDoc.data();

      // Deactivate the user
      batch.update(userDoc.ref, {
        isActive: false,
        trialStatus: "expired",
        updatedAt: now,
        updatedBy: "system:trial_cleanup",
      });

      // Track franchise user count decrease
      const franchiseId = userData.franchiseId;
      if (franchiseId) {
        franchiseUpdates[franchiseId] =
          (franchiseUpdates[franchiseId] || 0) + 1;
      }

      deactivatedCount++;
      console.log(`🚫 [Trial Cleanup] Deactivating: ${userData.email}`);
    });

    await batch.commit();

    // Update franchise user counts
    for (const [franchiseId, count] of Object.entries(franchiseUpdates)) {
      const franchiseRef = db.collection("franchises").doc(franchiseId);
      await franchiseRef.update({
        currentUserCount: admin.firestore.FieldValue.increment(-count),
        updatedAt: now,
      });
      console.log(`📊 [Trial Cleanup] Updated franchise ${franchiseId}: ` +
        `decreased by ${count}`);
    }

    console.log(`✅ [Trial Cleanup] Deactivated ${deactivatedCount} ` +
      "expired trial accounts");

    return null;
  } catch (error) {
    console.error("❌ [Trial Cleanup] Error:", error);
    return null;
  }
});

/**
 * Send trial expiration warning emails
 * Runs daily at 9:00 AM UTC
 * Sends warning to users with 7, 3, and 1 days remaining
 */
exports.sendDemoExpirationWarning = onSchedule("0 9 * * *", async () => {
  console.log("📧 [Trial Warning] Starting trial expiration warning check");

  try {
    const now = new Date();
    const warningDays = [7, 3, 1];

    for (const days of warningDays) {
      const targetDate = new Date(now);
      targetDate.setDate(targetDate.getDate() + days);

      // Set to start of day
      targetDate.setHours(0, 0, 0, 0);
      const targetStart = admin.firestore.Timestamp.fromDate(targetDate);

      // Set to end of day
      const targetEnd = new Date(targetDate);
      targetEnd.setHours(23, 59, 59, 999);
      const targetEndTs = admin.firestore.Timestamp.fromDate(targetEnd);

      const usersSnapshot = await db
          .collection("users")
          .where("isTrialUser", "==", true)
          .where("isActive", "==", true)
          .where("trialEndsAt", ">=", targetStart)
          .where("trialEndsAt", "<=", targetEndTs)
          .get();

      if (!usersSnapshot.empty) {
        console.log(`📧 [Trial Warning] ${usersSnapshot.size} users ` +
          `expiring in ${days} days`);

        usersSnapshot.forEach((userDoc) => {
          const userData = userDoc.data();
          console.log(`📧 [Trial Warning] Would notify: ${userData.email} ` +
            `(${days} days remaining)`);
          // TODO: Send actual email notification
          // Could integrate with SendGrid, Mailgun, or Firebase Extensions
        });
      }
    }

    console.log("✅ [Trial Warning] Completed warning check");
    return null;
  } catch (error) {
    console.error("❌ [Trial Warning] Error:", error);
    return null;
  }
});

/**
 * Lists trial users for admin panel visibility.
 */
exports.listTrialUsers = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can list trial users",
    );
  }

  const usersSnapshot = await db.collection("users").get();
  const users = [];
  usersSnapshot.forEach((doc) => {
    const data = doc.data();
    const isTrial = data.isTrialUser === true ||
      data.isDemoAccount === true ||
      data.isDemo === true;
    if (!isTrial) return;
    users.push({
      userId: doc.id,
      email: data.email || "",
      firstName: data.firstName || "",
      lastName: data.lastName || "",
      franchiseId: data.franchiseId || "CH",
      trialStatus: data.trialStatus || "active",
      trialEndsAt: data.trialEndsAt || data.demoExpiresAt || null,
      isActive: data.isActive !== false,
    });
  });
  return {users};
});

/**
 * Converts a trial user to a normal user.
 */
exports.convertTrialUser = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can convert trial users",
    );
  }

  const userId = request.data && request.data.userId;
  if (!userId) {
    throw new HttpsError("invalid-argument", "userId is required");
  }

  const updatePayload = {
    isTrialUser: false,
    trialStatus: "converted",
    convertedAt: admin.firestore.Timestamp.now(),
    isDemoAccount: false,
    isDemo: false,
    isActive: true,
    updatedAt: admin.firestore.Timestamp.now(),
    updatedBy: `system:trial_convert:${callerUid}`,
  };

  await db.collection("users").doc(userId).update(updatePayload);
  return {success: true, userId};
});

/**
 * Update franchise user count when a user is created
 */
exports.onUserCreated = onDocumentCreated(
    "users/{userId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      const userData = snapshot.data();
      const franchiseId = userData.franchiseId;

      if (!franchiseId) {
        console.log("📊 [User Count] No franchise ID for user, skipping");
        return null;
      }

      console.log(`📊 [User Count] User created in franchise: ${franchiseId}`);

      try {
        const resolvedCurrency = await resolveFranchiseCurrency(franchiseId);
        const existingCurrency = String(userData.currency || "")
            .trim()
            .toUpperCase();
        if (!existingCurrency || existingCurrency !== resolvedCurrency) {
          await snapshot.ref.set({
            currency: resolvedCurrency,
          }, {merge: true});
          console.log(
              `💱 [User Currency] Set ${snapshot.id} => ${resolvedCurrency}`,
          );
        }

        const franchiseRef = db.collection("franchises").doc(franchiseId);
        const franchiseDoc = await franchiseRef.get();

        if (!franchiseDoc.exists) {
          // Try to find by franchiseId field
          const franchiseQuery = await db
              .collection("franchises")
              .where("franchiseId", "==", franchiseId)
              .limit(1)
              .get();

          if (!franchiseQuery.empty) {
            await franchiseQuery.docs[0].ref.update({
              currentUserCount: admin.firestore.FieldValue.increment(1),
              updatedAt: admin.firestore.Timestamp.now(),
            });
            console.log(`✅ [User Count] Incremented count for ${franchiseId}`);
          }
        } else {
          await franchiseRef.update({
            currentUserCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.Timestamp.now(),
          });
          console.log(`✅ [User Count] Incremented count for ${franchiseId}`);
        }

        return null;
      } catch (error) {
        console.error("❌ [User Count] Error updating franchise count:", error);
        return null;
      }
    },
);

/**
 * Keeps user currency in sync when franchise changes.
 * This protects web sessions that derive currency directly from users/{uid}.
 */
exports.onUserFranchiseChanged = onDocumentUpdated(
    "users/{userId}",
    async (event) => {
      const beforeData = event.data.before.data() || {};
      const afterData = event.data.after.data() || {};
      const beforeFranchise = String(beforeData.franchiseId || "")
          .trim()
          .toUpperCase();
      const afterFranchise = String(afterData.franchiseId || "")
          .trim()
          .toUpperCase();

      // Only react when franchise assignment actually changes.
      if (!afterFranchise || beforeFranchise === afterFranchise) {
        return null;
      }

      try {
        const resolvedCurrency = await resolveFranchiseCurrency(afterFranchise);
        const currentCurrency = String(afterData.currency || "")
            .trim()
            .toUpperCase();
        if (currentCurrency !== resolvedCurrency) {
          await event.data.after.ref.set({
            currency: resolvedCurrency,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          console.log(
              `💱 [User Currency] Synced ${event.params.userId} ` +
              `=> ${resolvedCurrency}`,
          );
        }
      } catch (error) {
        console.error("❌ [User Currency] Sync error:", error);
      }

      return null;
    },
);

/**
 * When franchise currency changes, propagate it to users in that franchise.
 * This keeps web and iOS session displays aligned without manual user edits.
 */
exports.onFranchiseCurrencyChanged = onDocumentUpdated(
    "franchises/{franchiseDocId}",
    async (event) => {
      const beforeData = event.data.before.data() || {};
      const afterData = event.data.after.data() || {};
      const franchiseDocId = String(event.params.franchiseDocId || "")
          .trim()
          .toUpperCase();
      const franchiseId = String(afterData.franchiseId || franchiseDocId)
          .trim()
          .toUpperCase();

      const beforeCurrency = String(beforeData.currency || "")
          .trim()
          .toUpperCase();
      const afterCurrency = String(afterData.currency || "")
          .trim()
          .toUpperCase();

      if (!franchiseId || !afterCurrency || beforeCurrency === afterCurrency) {
        return null;
      }

      try {
        const candidates = [franchiseId];
        if (franchiseDocId && !candidates.includes(franchiseDocId)) {
          candidates.push(franchiseDocId);
        }

        for (const fid of candidates) {
          const usersSnap = await db.collection("users")
              .where("franchiseId", "==", fid)
              .get();
          if (usersSnap.empty) {
            continue;
          }

          const batch = db.batch();
          usersSnap.docs.forEach((doc) => {
            batch.set(doc.ref, {
              currency: afterCurrency,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          });
          await batch.commit();
          console.log(
              "💱 [Franchise Currency] Updated " +
              `${usersSnap.size} users for ${fid} => ${afterCurrency}`,
          );
        }
      } catch (error) {
        console.error("❌ [Franchise Currency] Propagation error:", error);
      }

      return null;
    },
);

/**
 * Update franchise user count when a user is deleted
 */
exports.onUserDeleted = onDocumentDeleted(
    "users/{userId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      const userData = snapshot.data();
      const franchiseId = userData.franchiseId;

      if (!franchiseId) {
        console.log("📊 [User Count] No franchise ID for deleted user");
        return null;
      }

      // Only decrement if user was active
      if (userData.isActive === false) {
        console.log("📊 [User Count] Deleted user was inactive, skipping");
        return null;
      }

      console.log(`📊 [User Count] User deleted from franchise: ${franchiseId}`);

      try {
        const franchiseRef = db.collection("franchises").doc(franchiseId);
        const franchiseDoc = await franchiseRef.get();

        if (!franchiseDoc.exists) {
          const franchiseQuery = await db
              .collection("franchises")
              .where("franchiseId", "==", franchiseId)
              .limit(1)
              .get();

          if (!franchiseQuery.empty) {
            await franchiseQuery.docs[0].ref.update({
              currentUserCount: admin.firestore.FieldValue.increment(-1),
              updatedAt: admin.firestore.Timestamp.now(),
            });
            console.log(`✅ [User Count] Decremented count for ${franchiseId}`);
          }
        } else {
          await franchiseRef.update({
            currentUserCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.Timestamp.now(),
          });
          console.log(`✅ [User Count] Decremented count for ${franchiseId}`);
        }

        return null;
      } catch (error) {
        console.error("❌ [User Count] Error updating franchise count:", error);
        return null;
      }
    },
);

/**
 * Update franchise user count when a user status changes
 * (activated or deactivated)
 */
exports.onUserStatusChanged = onDocumentUpdated(
    "users/{userId}",
    async (event) => {
      const beforeData = event.data.before.data();
      const afterData = event.data.after.data();

      // Check if isActive changed
      if (beforeData.isActive === afterData.isActive) {
        return null;
      }

      const franchiseId = afterData.franchiseId;
      if (!franchiseId) {
        return null;
      }

      const wasActive = beforeData.isActive !== false;
      const isNowActive = afterData.isActive !== false;

      // Determine increment (1 if activated, -1 if deactivated)
      const incrementValue = isNowActive ? 1 : -1;

      // Only update if there's an actual change
      if (wasActive === isNowActive) {
        return null;
      }

      console.log(`📊 [User Status] User ${afterData.email} ` +
        `${isNowActive ? "activated" : "deactivated"}`);

      try {
        const franchiseRef = db.collection("franchises").doc(franchiseId);
        const franchiseDoc = await franchiseRef.get();

        if (!franchiseDoc.exists) {
          const franchiseQuery = await db
              .collection("franchises")
              .where("franchiseId", "==", franchiseId)
              .limit(1)
              .get();

          if (!franchiseQuery.empty) {
            await franchiseQuery.docs[0].ref.update({
              currentUserCount:
                admin.firestore.FieldValue.increment(incrementValue),
              updatedAt: admin.firestore.Timestamp.now(),
            });
          }
        } else {
          await franchiseRef.update({
            currentUserCount:
              admin.firestore.FieldValue.increment(incrementValue),
            updatedAt: admin.firestore.Timestamp.now(),
          });
        }

        console.log(`✅ [User Status] Updated franchise count by ` +
          `${incrementValue}`);
        return null;
      } catch (error) {
        console.error("❌ [User Status] Error:", error);
        return null;
      }
    },
);

/**
 * Recalculate all franchise user counts
 * Can be called manually via HTTP trigger if counts get out of sync
 * Runs weekly on Sunday at 3:00 AM UTC
 */
exports.recalculateFranchiseCounts = onSchedule("0 3 * * 0", async () => {
  console.log("🔄 [Recalculate] Starting franchise count recalculation");

  try {
    const franchisesSnapshot = await db.collection("franchises").get();

    for (const franchiseDoc of franchisesSnapshot.docs) {
      const franchiseData = franchiseDoc.data();
      const franchiseId = franchiseData.franchiseId || franchiseDoc.id;

      // Count active users in this franchise
      const usersSnapshot = await db
          .collection("users")
          .where("franchiseId", "==", franchiseId)
          .where("isActive", "==", true)
          .get();

      const actualCount = usersSnapshot.size;
      const storedCount = franchiseData.currentUserCount || 0;

      if (actualCount !== storedCount) {
        console.log(`📊 [Recalculate] ${franchiseId}: ` +
          `stored=${storedCount}, actual=${actualCount}`);

        await franchiseDoc.ref.update({
          currentUserCount: actualCount,
          updatedAt: admin.firestore.Timestamp.now(),
        });
      }
    }

    console.log("✅ [Recalculate] Completed franchise count recalculation");
    return null;
  } catch (error) {
    console.error("❌ [Recalculate] Error:", error);
    return null;
  }
});

/**
 * Check if a franchise has available user slots before creating a new user
 * This is a callable function that the web app uses before user creation
 */
exports.checkLicenseLimit = onCall(async (request) => {
  console.log("🔐 [License Check] Checking license limit");

  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is super admin (by role)
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can check license",
    );
  }

  const {franchiseId} = request.data;

  if (!franchiseId) {
    throw new HttpsError("invalid-argument", "franchiseId is required");
  }

  try {
    // Find the franchise
    let franchiseDoc;
    const franchiseRef = db.collection("franchises").doc(franchiseId);
    franchiseDoc = await franchiseRef.get();

    if (!franchiseDoc.exists) {
      // Try finding by franchiseId field
      const franchiseQuery = await db
          .collection("franchises")
          .where("franchiseId", "==", franchiseId)
          .limit(1)
          .get();

      if (franchiseQuery.empty) {
        throw new HttpsError("not-found", "Franchise not found");
      }
      franchiseDoc = franchiseQuery.docs[0];
    }

    const franchiseData = franchiseDoc.data();
    const currentCount = franchiseData.currentUserCount || 0;
    const maxUsers = franchiseData.maxUsers || 0;
    const isActive = franchiseData.isActive !== false;

    // Check if franchise is active
    if (!isActive) {
      return {
        canCreateUser: false,
        reason: "Franchise is inactive",
        currentCount,
        maxUsers,
        availableSlots: 0,
      };
    }

    // Check license limit
    const availableSlots = maxUsers - currentCount;
    const canCreateUser = availableSlots > 0;

    console.log(`🔐 [License Check] ${franchiseId}: ` +
      `${currentCount}/${maxUsers}, can create: ${canCreateUser}`);

    return {
      canCreateUser,
      reason: canCreateUser ? "OK" : "License limit reached",
      currentCount,
      maxUsers,
      availableSlots: Math.max(0, availableSlots),
    };
  } catch (error) {
    console.error("❌ [License Check] Error:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * Enforce license limit before user creation
 * Returns whether the user can be created
 */
exports.enforceLicenseLimit = onCall(async (request) => {
  console.log("🔐 [Enforce License] Pre-create check");

  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is super admin (by role)
  const enfCallerUid = request.auth.uid;
  const enfCallerDoc = await db.collection("users").doc(enfCallerUid).get();
  const enfCallerRole = enfCallerDoc.exists ?
    enfCallerDoc.data().role : null;
  if (enfCallerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can create users",
    );
  }

  // eslint-disable-next-line no-unused-vars
  const {franchiseId, email, firstName, lastName, role, isDemo} = request.data;

  if (!franchiseId || !email) {
    throw new HttpsError(
        "invalid-argument",
        "franchiseId and email are required",
    );
  }

  try {
    // Find the franchise
    let franchiseDoc;
    let franchiseRef;
    const directRef = db.collection("franchises").doc(franchiseId);
    franchiseDoc = await directRef.get();

    if (!franchiseDoc.exists) {
      const franchiseQuery = await db
          .collection("franchises")
          .where("franchiseId", "==", franchiseId)
          .limit(1)
          .get();

      if (franchiseQuery.empty) {
        throw new HttpsError("not-found", "Franchise not found");
      }
      franchiseDoc = franchiseQuery.docs[0];
      franchiseRef = franchiseDoc.ref;
    } else {
      franchiseRef = directRef; // eslint-disable-line no-unused-vars
    }

    const franchiseData = franchiseDoc.data();
    const currentCount = franchiseData.currentUserCount || 0;
    const maxUsers = franchiseData.maxUsers || 0;

    // Check license limit
    if (currentCount >= maxUsers) {
      console.log(`🚫 [Enforce License] ${franchiseId}: limit reached ` +
        `(${currentCount}/${maxUsers})`);
      throw new HttpsError(
          "resource-exhausted",
          `License limit reached. Current: ${currentCount}, Max: ${maxUsers}`,
      );
    }

    console.log(`✅ [Enforce License] ${franchiseId}: ` +
      `can create (${currentCount}/${maxUsers})`);

    return {
      allowed: true,
      currentCount,
      maxUsers,
      remainingSlots: maxUsers - currentCount - 1, // -1 for the new user
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error("❌ [Enforce License] Error:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * Utility function to set countryCode for specific users
 * Can be called with custom users list or uses default list
 */
exports.setUserCountryCodes = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data().role !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can call this function",
    );
  }
  // Accept custom users list or use default
  const defaultUsers = [
    {email: "admin@gmail.com", countryCode: "CH"},
    {email: "front@gmail.com", countryCode: "CH"},
  ];
  const usersToUpdate = (request.data && request.data.users) ?
    request.data.users :
    defaultUsers;

  const results = [];

  for (const user of usersToUpdate) {
    try {
      const snapshot = await db.collection("users")
          .where("email", "==", user.email)
          .get();

      if (snapshot.empty) {
        results.push({email: user.email, status: "not_found"});
        continue;
      }

      for (const doc of snapshot.docs) {
        await doc.ref.update({
          countryCode: user.countryCode,
        });
        results.push({
          email: user.email,
          uid: doc.id,
          countryCode: user.countryCode,
          status: "updated",
        });
      }
    } catch (error) {
      results.push({
        email: user.email,
        status: "error",
        message: error.message,
      });
    }
  }

  console.log("setUserCountryCodes results:", results);
  return {success: true, results};
});

/**
 * Sync all users' countryCode based on their franchiseId
 * This fixes users created from web without countryCode
 */
/**
 * Assign roles to all users
 * admin@gmail.com -> superadmin, others get 'staff' if no role exists
 */
exports.assignUserRoles = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data().role !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can call this function",
    );
  }
  const results = [];

  try {
    const usersSnapshot = await db.collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const email = userData.email || "unknown";

      if (email === "admin@gmail.com") {
        // Always set admin@gmail.com to superadmin
        await userDoc.ref.update({role: "superadmin"});
        results.push({email, status: "set_superadmin"});
      } else if (!userData.role) {
        // Set default role for users without a role
        await userDoc.ref.update({role: "staff"});
        results.push({email, status: "set_staff"});
      } else {
        results.push({
          email,
          role: userData.role,
          status: "already_has_role",
        });
      }
    }
  } catch (error) {
    console.error("assignUserRoles error:", error);
    throw new HttpsError("internal", error.message);
  }

  console.log("assignUserRoles results:", results);
  return {success: true, results};
});

// ============================================================================
// FRANCHISE DATA ISOLATION - MIGRATION FUNCTION
// ============================================================================

/**
 * Migration: Add franchiseId to all existing documents
 * Adds franchiseId: "CH" (Switzerland) to all documents that don't have it
 * Uses batch writes for performance (max 500 per batch)
 * Safe to run multiple times - only updates docs without franchiseId
 */
exports.migrateAddFranchiseId = onCall(async (request) => {
  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is superadmin
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can run migrations",
    );
  }

  const FRANCHISE_COLLECTIONS = [
    "araclar", "servisler", "iadeIslemleri", "exitIslemleri", "activities",
    "servisFirmalari", "office_operations", "office_Return",
    "workSchedules", "vacationTimes", "assistantCompanies",
    "protocols", "shuttleEntries", "shuttleSessions", "shuttleReports",
    "trafficFines", "bankingTransactions", "additionalSales",
    "semesInvoices", "audit_logs",
  ];

  const defaultFranchiseId = (request.data && request.data.franchiseId) ||
    "CH";
  const results = [];
  let totalUpdated = 0;
  let totalSkipped = 0;

  console.log(`🔄 [Migration] Starting franchiseId migration ` +
    `(default: "${defaultFranchiseId}")`);

  for (const collectionName of FRANCHISE_COLLECTIONS) {
    try {
      const snapshot = await db.collection(collectionName).get();
      let updated = 0;
      let skipped = 0;
      let batchCount = 0;
      let batch = db.batch();

      for (const docSnap of snapshot.docs) {
        const data = docSnap.data();

        // Only update docs that don't already have franchiseId
        if (!data.franchiseId) {
          batch.update(docSnap.ref, {franchiseId: defaultFranchiseId});
          updated++;
          batchCount++;

          // Firestore batch limit is 500
          if (batchCount >= 450) {
            await batch.commit();
            batch = db.batch();
            batchCount = 0;
          }
        } else {
          skipped++;
        }
      }

      // Commit remaining batch
      if (batchCount > 0) {
        await batch.commit();
      }

      totalUpdated += updated;
      totalSkipped += skipped;

      results.push({
        collection: collectionName,
        total: snapshot.size,
        updated,
        skipped,
        status: "success",
      });

      console.log(`✅ [Migration] ${collectionName}: ` +
        `${updated} updated, ${skipped} skipped (total: ${snapshot.size})`);
    } catch (error) {
      results.push({
        collection: collectionName,
        status: "error",
        message: error.message,
      });
      console.error(`❌ [Migration] ${collectionName}: ${error.message}`);
    }
  }

  console.log(`🏁 [Migration] Complete: ${totalUpdated} updated, ` +
    `${totalSkipped} skipped`);

  return {
    success: true,
    defaultFranchiseId,
    totalUpdated,
    totalSkipped,
    results,
  };
});

/**
 * Debug & Fix: Verify and repair user documents
 * for Firestore rules compatibility.
 * Checks all user docs for required fields.
 * Adds missing fields with sensible defaults.
 */
exports.fixUserDocuments = onCall(async (request) => {
  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data().role !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can run fixUserDocuments",
    );
  }

  const dryRun = request.data && request.data.dryRun === true;
  const results = [];
  let fixedCount = 0;

  try {
    const usersSnapshot = await db.collection("users").get();
    console.log(`🔍 [FixUsers] Checking ${usersSnapshot.size} user documents`);

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const docId = userDoc.id;
      const email = userData.email || "unknown";
      const fixes = {};
      const missing = [];

      // Check franchiseId
      if (userData.franchiseId === undefined || userData.franchiseId === null) {
        missing.push("franchiseId");
        fixes.franchiseId = "CH"; // Default franchise
      }

      // Check isDemoAccount
      if (userData.isDemoAccount === undefined ||
          userData.isDemoAccount === null) {
        missing.push("isDemoAccount");
        fixes.isDemoAccount = userData.isDemo === true ? true : false;
      }

      // Check isTrialUser
      if (userData.isTrialUser === undefined ||
          userData.isTrialUser === null) {
        missing.push("isTrialUser");
        fixes.isTrialUser = userData.isDemoAccount === true ||
          userData.isDemo === true;
      }

      // Check trialStatus for trial users
      if ((userData.isTrialUser === true || userData.isDemoAccount === true) &&
          !userData.trialStatus) {
        missing.push("trialStatus");
        fixes.trialStatus = "active";
      }

      // Check role
      if (!userData.role) {
        missing.push("role");
        if (email === "admin@gmail.com") {
          fixes.role = "superadmin";
        } else {
          fixes.role = "staff";
        }
      }

      // Check countryCode
      if (!userData.countryCode) {
        missing.push("countryCode");
        fixes.countryCode = "CH";
      }

      // Apply fixes if needed
      if (Object.keys(fixes).length > 0) {
        if (!dryRun) {
          await userDoc.ref.update(fixes);
        }
        fixedCount++;
        results.push({
          email,
          docId,
          status: dryRun ? "would_fix" : "fixed",
          missing,
          fixes,
          existingFields: {
            franchiseId: userData.franchiseId,
            isDemoAccount: userData.isDemoAccount,
            isDemo: userData.isDemo,
            isTrialUser: userData.isTrialUser,
            role: userData.role,
            countryCode: userData.countryCode,
          },
        });
      } else {
        results.push({
          email,
          docId,
          status: "ok",
          fields: {
            franchiseId: userData.franchiseId,
            isDemoAccount: userData.isDemoAccount,
            isTrialUser: userData.isTrialUser,
            role: userData.role,
            countryCode: userData.countryCode,
          },
        });
      }
    }

    console.log(`🏁 [FixUsers] Done: ${fixedCount} users ` +
      `${dryRun ? "would be" : ""} fixed out of ${usersSnapshot.size}`);
  } catch (error) {
    console.error("❌ [FixUsers] Error:", error);
    throw new HttpsError("internal", error.message);
  }

  return {
    success: true,
    dryRun,
    totalUsers: results.length,
    fixedCount,
    results,
  };
});

exports.syncUserCountryCodes = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data().role !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can call this function",
    );
  }
  const results = [];

  try {
    // Get all franchises to build franchiseId -> countryCode mapping
    const franchisesSnapshot = await db.collection("franchises").get();
    const franchiseMap = {};

    franchisesSnapshot.forEach((doc) => {
      const data = doc.data();
      if (data.franchiseId && data.countryCode) {
        franchiseMap[data.franchiseId] = data.countryCode;
      }
      // Also map by document id
      if (data.countryCode) {
        franchiseMap[doc.id] = data.countryCode;
      }
    });

    console.log("Franchise mapping:", franchiseMap);

    // Get all users without countryCode or with missing countryCode
    const usersSnapshot = await db.collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      const email = userData.email || "unknown";

      // Check if user needs countryCode update
      if (!userData.countryCode && userData.franchiseId) {
        const countryCode = franchiseMap[userData.franchiseId];

        if (countryCode) {
          await userDoc.ref.update({
            countryCode: countryCode,
          });
          results.push({
            email: email,
            uid: userId,
            franchiseId: userData.franchiseId,
            countryCode: countryCode,
            status: "updated",
          });
        } else {
          results.push({
            email: email,
            uid: userId,
            franchiseId: userData.franchiseId,
            status: "no_franchise_mapping",
          });
        }
      } else if (!userData.countryCode) {
        results.push({
          email: email,
          uid: userId,
          status: "no_franchise_id",
        });
      } else {
        results.push({
          email: email,
          uid: userId,
          countryCode: userData.countryCode,
          status: "already_has_countryCode",
        });
      }
    }
  } catch (error) {
    console.error("syncUserCountryCodes error:", error);
    throw new HttpsError("internal", error.message);
  }

  console.log("syncUserCountryCodes results:", results);
  return {success: true, results};
});

/**
 * Pre-login: list active franchises for a country (login picker).
 * Public; no sensitive fields returned.
 */
exports.listFranchisesForLogin = onCall(
    {cors: true, invoker: "public"},
    async (request) => {
      const countryCode = String(
        request.data && request.data.countryCode != null ?
          request.data.countryCode :
          "",
      )
          .trim()
          .toUpperCase();
      if (!countryCode || countryCode.length < 2 || countryCode.length > 3) {
        throw new HttpsError(
            "invalid-argument",
            "countryCode is required (e.g. CH, TR, DE)",
        );
      }
      const snap = await db.collection("franchises")
          .where("countryCode", "==", countryCode)
          .limit(50)
          .get();
      const franchises = [];
      snap.forEach((doc) => {
        const d = doc.data() || {};
        if (d.isActive === false) {
          return;
        }
        const fid = String(d.franchiseId || doc.id || "").trim();
        if (!fid) {
          return;
        }
        franchises.push({
          id: doc.id,
          franchiseId: fid.toUpperCase(),
          name: String(d.name || d.country || doc.id),
          countryCode: String(d.countryCode || countryCode).toUpperCase(),
          currency: String(d.currency || "").trim().toUpperCase(),
          flag: d.flag != null ? String(d.flag) : "",
        });
      });
      franchises.sort((a, b) => a.name.localeCompare(b.name));
      return {franchises};
    },
);

/**
 * Permanently deletes a user from Firebase Auth and Firestore users collection.
 * Superadmin or globaladmin only.
 */
exports.adminDeleteUserCompletely = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin" && callerRole !== "globaladmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin or globaladmin can delete users",
    );
  }

  const targetUid = request.data && request.data.uid ?
    String(request.data.uid).trim() :
    "";
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "uid is required");
  }
  if (targetUid === callerUid) {
    throw new HttpsError(
        "failed-precondition",
        "You cannot delete your own account",
    );
  }

  const targetRef = db.collection("users").doc(targetUid);
  const targetDoc = await targetRef.get();

  let targetFranchiseId = null;
  if (targetDoc.exists) {
    const data = targetDoc.data() || {};
    targetFranchiseId = (data.franchiseId || "").toUpperCase();
  }

  // Remove presence immediately so dashboards never show deleted accounts
  // even if auth.user().onDelete is delayed or misconfigured.
  await deleteAllUserPresenceDocumentsForUid(targetUid);

  // Delete auth user first so account cannot keep signing in.
  // If user does not exist in Auth, continue with Firestore cleanup.
  try {
    await admin.auth().deleteUser(targetUid);
  } catch (error) {
    if (!error || error.code !== "auth/user-not-found") {
      throw error;
    }
  }

  // Delete Firestore users document if it exists.
  if (targetDoc.exists) {
    await targetRef.delete();
  }

  // Best effort franchise user count correction.
  if (targetFranchiseId) {
    const franchiseRef = db.collection("franchises").doc(targetFranchiseId);
    const franchiseDoc = await franchiseRef.get();
    if (franchiseDoc.exists) {
      const current = Number(franchiseDoc.data().currentUserCount || 0);
      await franchiseRef.update({
        currentUserCount: Math.max(0, current - 1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  return {
    success: true,
    uid: targetUid,
    deletedFirestoreDoc: targetDoc.exists,
  };
});

/**
 * Closes a franchise and permanently removes all users in that franchise.
 * Superadmin only.
 */
exports.adminCloseFranchise = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can close a franchise",
    );
  }

  const rawFranchiseId = request.data && request.data.franchiseId ?
    String(request.data.franchiseId).trim() :
    "";
  if (!rawFranchiseId) {
    throw new HttpsError("invalid-argument", "franchiseId is required");
  }

  const franchiseId = rawFranchiseId.toUpperCase();
  const idCandidates = Array.from(new Set([
    franchiseId,
    rawFranchiseId,
    franchiseId.toLowerCase(),
    rawFranchiseId.toLowerCase(),
  ]));
  let franchiseDoc = null;

  for (const idCandidate of idCandidates) {
    const byIdDoc = await db.collection("franchises").doc(idCandidate).get();
    if (byIdDoc.exists) {
      franchiseDoc = byIdDoc;
      break;
    }
  }

  if (!franchiseDoc) {
    const byFieldSnap = await db.collection("franchises")
        .where("franchiseId", "in", idCandidates.slice(0, 10))
        .limit(1)
        .get();
    if (!byFieldSnap.empty) {
      franchiseDoc = byFieldSnap.docs[0];
    }
  }

  if (!franchiseDoc || !franchiseDoc.exists) {
    throw new HttpsError("not-found", "Franchise not found");
  }

  const franchiseData = franchiseDoc.data() || {};
  const resolvedFranchiseId = String(
      franchiseData.franchiseId || franchiseDoc.id || franchiseId,
  ).trim();
  const fidVariants = new Set([
    resolvedFranchiseId,
    resolvedFranchiseId.toUpperCase(),
    resolvedFranchiseId.toLowerCase(),
  ]);
  const userDocMap = new Map();

  for (const fid of fidVariants) {
    const snap = await db.collection("users")
        .where("franchiseId", "==", fid)
        .get();
    snap.docs.forEach((d) => userDocMap.set(d.id, d));
  }

  const usersToDelete = Array.from(userDocMap.values());
  let authDeleted = 0;
  let authMissing = 0;
  let firestoreDeleted = 0;
  const authErrors = [];

  for (const userDoc of usersToDelete) {
    const uid = userDoc.id;
    try {
      await admin.auth().deleteUser(uid);
      authDeleted += 1;
    } catch (error) {
      if (error && error.code === "auth/user-not-found") {
        authMissing += 1;
      } else {
        authErrors.push({uid, message: error.message || String(error)});
        continue;
      }
    }

    await userDoc.ref.delete();
    firestoreDeleted += 1;
  }

  let franchiseDeleted = false;
  let recursiveDeleteUsed = false;
  try {
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(franchiseDoc.ref);
      recursiveDeleteUsed = true;
    } else {
      await franchiseDoc.ref.delete();
    }
    franchiseDeleted = true;
  } catch (error) {
    throw new HttpsError(
        "internal",
        `Users removed but franchise delete failed: ${error.message || error}`,
    );
  }

  return {
    success: true,
    franchiseId,
    usersMatched: usersToDelete.length,
    authDeleted,
    authMissing,
    firestoreDeleted,
    authErrors,
    franchiseDeleted,
    recursiveDeleteUsed,
  };
});

/**
 * Migration monitoring endpoint for staged cutover.
 * Returns queue and lock health for legacy+scoped paths.
 */
exports.getMigrationHealth = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can read migration health",
    );
  }

  const franchiseId = ((request.data && request.data.franchiseId) || "CH")
      .toUpperCase();

  const [
    legacyEmails,
    scopedEmails,
    legacyNotifications,
    scopedNotifications,
    locks,
  ] =
    await Promise.all([
      db.collection("outgoingEmails").where("status", "==", "queued").get(),
      db.collection("franchises").doc(franchiseId)
          .collection("outgoingEmails").where("status", "==", "queued").get(),
      db.collection("notifications").get(),
      db.collection("franchises").doc(franchiseId)
          .collection("notifications").get(),
      db.collection("_functionLocks")
          .orderBy("createdAt", "desc")
          .limit(200)
          .get(),
    ]);

  return {
    franchiseId,
    generatedAt: new Date().toISOString(),
    queues: {
      legacyOutgoingEmailsQueued: legacyEmails.size,
      scopedOutgoingEmailsQueued: scopedEmails.size,
      legacyNotificationsTotal: legacyNotifications.size,
      scopedNotificationsTotal: scopedNotifications.size,
    },
    functionLocksRecent: locks.size,
  };
});
