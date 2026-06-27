/**
 * Callable endpoints for WheelSys check-in sync (CH only).
 */
/* eslint-disable max-len */

const crypto = require("crypto");
const admin = require("firebase-admin");
const {defineSecret} = require("firebase-functions/params");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {loadActiveSessionCookie, saveSession, sessionDocRef, loadSessionOperator} = require("./sessionStore");
const {
  fetchRentalPage,
  fetchFullRentalData,
  updateWheelsysCheckin,
  searchRentalsByRes,
  searchLocalExitsByRes,
  rentalPreviewLooksEmpty,
  saveEntityNote,
  deleteEntityNote,
  parseInsuranceSummary,
  parseFormToPayload,
  mapCustomerFromRentalForm,
  WHEELSYS_DOMAINS,
  BASE_URL,
  zurichWheelSysNow,
  extractSessionWheelSysUserId,
} = require("./checkinSync");
const {
  fetchWheelSysFleetChart,
  findRentalEntityIdByPlate,
  buildFleetChartRequestBody,
  warmFleetChartPage,
  postFleetChartRequest,
  BASE_URL: WHEELSYS_BASE,
} = require("./fleetChart");
const {
  fetchJournalData,
  fetchJournalSnapshot,
  fetchJournalSnapshotWithFallback,
} = require("./journal");
const {fetchDailyViewTab, fetchDailyViewAll, verifyVehicleAvailableMileage} = require("./dailyView");
const {searchBookingsList} = require("./bookingsList");
const {fetchAllVehicleMaster} = require("./vehicleList");
const {runVehicleMasterSync} = require("./vehicleMasterSync");
const {
  saveVehicleMasterCache,
  loadVehicleMasterCache,
} = require("./vehicleMasterCache");
const {ERR: WHEELSYS_ERR, WheelsysClientError, buildOperationalDate} = require("./client");
const {
  fetchBookingPage,
  searchAvailableVehicles,
  assignVehicleToBooking,
  combineDateTimeLocal,
  resolveBookingEntityId,
  resolveBookingContextForAssign,
} = require("./bookingAssignment");
const {buildFleetAuthCookie, cookiePresenceLog} = require("./cookieJar");
const {
  getVehicleDamageHistory,
  resolveVehicleEntityId,
} = require("./vehicleDamageHistory");
const {
  buildPrecheckinContext,
  submitPrecheckin,
  parseCompleteRentalFormToPayload,
  mapRental,
  mapVehicle,
  mapCustomer,
  resolveCacheKey,
  fetchExistingDamages,
  validatePrecheckinForm,
  logPrecheckinSubmitFields,
  mapPrecheckinDamagesToHistory,
  parseRentalAttachments,
} = require("./precheckin");

const wheelsysApiKeySecret = defineSecret("WHEELSYS_API_KEY");

const REGION = "europe-west6";
const DEFAULT_FRANCHISE = "CH";

const callableOpts = {
  region: REGION,
  secrets: [wheelsysApiKeySecret],
};

/**
 * Derive AES key from configured Wheelsys API key (no extra secret required).
 * @return {string} 64-char hex
 */
function encryptionKeyHex() {
  const apiKey = String(wheelsysApiKeySecret.value() || "").trim();
  if (!apiKey) return "";
  return crypto.createHash("sha256").update(apiKey).digest("hex");
}

/**
 * @param {object} request
 * @param {string} key
 * @return {*}
 */
function reqData(request, key) {
  if (!request.data) return undefined;
  return request.data[key];
}

/**
 * @param {string} raw
 * @return {boolean}
 */
function isSwitzerlandFranchiseId(raw) {
  const fid = String(raw || "").trim().toUpperCase();
  if (!fid) return false;
  if (fid === "CH") return true;
  return fid.startsWith("CH_") || fid.startsWith("CH-");
}

/**
 * Resolve operational CH franchise for WheelSys callables.
 * Session franchiseId from the client wins over stale profile.franchiseId
 * (e.g. cross-branch staff logged into CH).
 * @param {object} profile
 * @param {object} request
 * @return {string|null}
 */
function resolveCHFranchiseId(profile, request) {
  const requestFid = String(reqData(request, "franchiseId") || "").trim().toUpperCase();
  const profileFid = String(profile.franchiseId || "").trim().toUpperCase();
  const countryCode = String(profile.countryCode || "").trim().toUpperCase();

  if (isSwitzerlandFranchiseId(requestFid)) return requestFid;
  if (isSwitzerlandFranchiseId(profileFid)) return profileFid;
  if (countryCode === "CH") {
    return requestFid || profileFid || DEFAULT_FRANCHISE;
  }
  return null;
}

/**
 * @param {object} request
 * @return {Promise<{uid: string, profile: object, franchiseId: string}>}
 */
async function assertCHStaff(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  const uid = request.auth.uid;
  const db = admin.firestore();
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("permission-denied", "User profile not found.");
  }
  const profile = userSnap.data() || {};
  let franchiseId = resolveCHFranchiseId(profile, request);

  if (!franchiseId) {
    const requestFid = String(reqData(request, "franchiseId") || "").trim().toUpperCase();
    const profileFid = String(profile.franchiseId || "").trim().toUpperCase();
    for (const candidate of [requestFid, profileFid]) {
      if (!candidate) continue;
      try {
        const snap = await db.collection("franchises").doc(candidate).get();
        if (snap.exists) {
          const cc = String((snap.data() || {}).countryCode || "").trim().toUpperCase();
          if (cc === "CH") {
            franchiseId = candidate;
            break;
          }
        }
      } catch (e) {
        console.warn("assertCHStaff franchise lookup", candidate, e.message);
      }
    }
  }

  if (!franchiseId || !isSwitzerlandFranchiseId(franchiseId)) {
    const cc = String(profile.countryCode || "").trim().toUpperCase();
    if (cc === "CH" && isSwitzerlandFranchiseId(String(reqData(request, "franchiseId") || DEFAULT_FRANCHISE))) {
      franchiseId = String(reqData(request, "franchiseId") || DEFAULT_FRANCHISE).trim().toUpperCase();
    } else if (cc === "CH") {
      franchiseId = DEFAULT_FRANCHISE;
    }
  }

  if (!franchiseId || !isSwitzerlandFranchiseId(franchiseId)) {
    throw new HttpsError("permission-denied", "WheelSys sync is CH-only.");
  }
  const role = String(profile.role || "").toLowerCase();
  if (role === "garage") {
    throw new HttpsError("permission-denied", "Garage role cannot use WheelSys sync.");
  }
  return {uid, profile, franchiseId};
}

/**
 * CH staff with franchise/global admin role (Vehicle Master apply).
 * @param {object} request
 * @return {Promise<{uid: string, profile: object, franchiseId: string}>}
 */
async function assertCHAdmin(request) {
  const ctx = await assertCHStaff(request);
  const role = String(ctx.profile.role || "").toLowerCase();
  const allowed = role === "globaladmin" ||
    role === "admin" ||
    role === "superadmin" ||
    role === "franchiseadmin";
  if (!allowed) {
    throw new HttpsError(
        "permission-denied",
        "Admin role required for Vehicle Master sync apply.",
    );
  }
  return ctx;
}

/**
 * Build creator display name from user profile.
 * @param {object} profile
 * @return {string}
 */
function profileCreatorFullName(profile) {
  const p = profile || {};
  const parts = [p.firstName, p.lastName].map((s) => String(s || "").trim()).filter(Boolean);
  if (parts.length) return parts.join(" ");
  return String(p.displayName || p.name || "").trim();
}

/**
 * Resolve WheelSys creator user id from request / rental / profile.
 * @param {object} opts
 * @return {number|string|null}
 */
function resolveCreatorId({checkInUserId, profile, previewFields}) {
  const fromRequest = checkInUserId != null ? String(checkInUserId).trim() : "";
  if (fromRequest && /^\d+$/.test(fromRequest)) return Number(fromRequest);
  const fromRental = String(
      (previewFields && previewFields.checkInUserId) ||
      (previewFields && previewFields.userTo) ||
      "",
  ).trim();
  if (fromRental && /^\d+$/.test(fromRental)) return Number(fromRental);
  const fromProfile = profile && profile.wheelsysUserId != null ?
    String(profile.wheelsysUserId).trim() : "";
  if (fromProfile && /^\d+$/.test(fromProfile)) return Number(fromProfile);
  return null;
}

/**
 * @param {Error} e
 */
function throwWheelSysClientError(e) {
  if (e instanceof WheelsysClientError) {
    const code = e.code === WHEELSYS_ERR.SESSION_EXPIRED ?
      "WHEELSYS_SESSION_EXPIRED" :
      `WHEELSYS_${e.code}`;
    const status = e.code === WHEELSYS_ERR.SESSION_EXPIRED ?
      "failed-precondition" : "internal";
    throw new HttpsError(status, e.message, {
      code,
      httpStatus: e.httpStatus || null,
      debugPreview: e.debugPreview || null,
      wheelSysMessage: e.message,
    });
  }
  const msg = String(e && e.message ? e.message : e || "WheelSys update failed.")
      .slice(0, 1000);
  const isValidation = /Check-in user|mileage|date sequence|Fuel must|session expired|Missing WheelSys session|Invalid entityId|Invalid vehicleId|cannot be lower|did not confirm|required|WHEELSYS_API_KEY|Could not resolve Wheelsys vehicle/i
      .test(msg);
  throw new HttpsError(
      isValidation ? "failed-precondition" : "internal",
      msg,
      {wheelSysMessage: msg},
  );
}

/**
 * @param {object} p
 * @return {Promise<string>}
 */
async function resolveCookie(p) {
  const encKey = encryptionKeyHex();
  if (!encKey) {
    throw new HttpsError(
        "failed-precondition",
        "WHEELSYS_API_KEY is not configured on the server.",
    );
  }
  const station = String(p.station || "ZRH").toUpperCase();
  const uid = String(p.uid || p.userId || "").trim();
  if (!uid) {
    throw new HttpsError(
        "unauthenticated",
        "WheelSys session requires a signed-in user.",
    );
  }
  try {
    return await loadActiveSessionCookie({
      db: admin.firestore(),
      franchiseId: p.franchiseId,
      station,
      encryptionKeyHex: encKey,
      userId: uid,
      fallbackCookie: "",
    });
  } catch (e) {
    throw new HttpsError("failed-precondition", e.message);
  }
}

/**
 * Resolve WheelSys cookie for the authenticated Firebase user on this request.
 * @param {object} request
 * @param {string} franchiseId
 * @param {string} [station="ZRH"]
 * @return {Promise<string>}
 */
async function resolveCookieForRequest(request, franchiseId, station = "ZRH") {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return resolveCookie({
    franchiseId: String(franchiseId || DEFAULT_FRANCHISE).toUpperCase(),
    station: String(station || "ZRH").toUpperCase(),
    uid,
  });
}

/**
 * @param {object} entry
 */
async function writeUpdateLog(entry) {
  const db = admin.firestore();
  const franchiseId = String(entry.franchiseId || DEFAULT_FRANCHISE).toUpperCase();
  await db.collection("franchises").doc(franchiseId)
      .collection("wheelsysUpdateLogs").add({
        ...entry,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
}

/**
 * Convert dd/MM/yyyy check-in date to WheelSys operational day string.
 * @param {string} checkInDate
 * @param {Date} fallback
 * @return {string}
 */
function operationalDateFromCheckIn(checkInDate, fallback = new Date()) {
  const m = String(checkInDate || "").match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (m) return `${m[3]}-${m[2]}-${m[1]}T00:00:00.000`;
  return buildOperationalDate(fallback);
}

/**
 * Default check-in date/time in Europe/Zurich for WheelSys form fields.
 * @return {{date: string, time: string}}
 */
function zurichDefaultCheckInDateTime() {
  return zurichWheelSysNow();
}

/**
 * @param {object} rental
 */
async function upsertRentalCache(rental) {
  const db = admin.firestore();
  const franchiseId = String(rental.franchiseId || DEFAULT_FRANCHISE).toUpperCase();
  const entityId = String(rental.entityId);
  await db.collection("franchises").doc(franchiseId)
      .collection("wheelsysRentals").doc(entityId).set({
        entityId,
        raNo: rental.raNo || "",
        resNo: rental.resNo || "",
        plateNo: rental.plateNo || "",
        station: rental.station || "ZRH",
        mileageFrom: rental.mileageFrom != null ? rental.mileageFrom : null,
        mileageTo: rental.mileageTo != null ? rental.mileageTo : null,
        fuelTo: rental.fuelTo != null ? rental.fuelTo : null,
        rawJson: rental.rawJson || null,
        lastSyncedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
}

/**
 * Build RES/RNT lookup variants for cache queries.
 * @param {string} resQuery
 * @return {string[]}
 */
function resQueryVariants(resQuery) {
  const raw = String(resQuery || "").trim().toUpperCase();
  const digits = raw.replace(/[^0-9]/g, "");
  const variants = new Set([raw]);
  if (digits) {
    variants.add(`RES-${digits}`);
    variants.add(`RNT-${digits}`);
    variants.add(digits);
  }
  return [...variants].filter(Boolean);
}

/**
 * Whether a loaded WheelSys RES/RNT matches the expected reservation code.
 * @param {string} loadedRes
 * @param {string} expectedRes
 * @return {boolean}
 */
function resNoMatchesExpected(loadedRes, expectedRes) {
  const loaded = String(loadedRes || "").trim().toUpperCase();
  const expected = String(expectedRes || "").trim().toUpperCase();
  if (!expected || !loaded) return true;
  const variants = resQueryVariants(expected);
  if (variants.includes(loaded)) return true;
  return variants.some((v) => loaded.includes(v.replace(/^RES-|^RNT-/, "")));
}

/**
 * Strict rental entity candidate (never booking).
 * @param {object} fields
 * @param {object} full
 * @return {boolean}
 */
function isStrictRentalCandidate(fields, full) {
  const f = fields || {};
  const usageType = String(f.usageType || "").trim();
  const title = String(f.pageTitle || "").toUpperCase();
  const vehicleId = String(
      (full && full.vehicleEntityId) || f.vehicleEntityId || f.rdPlateNo_value || "",
  ).trim();
  const bookingLike = usageType === "1" || /REVIEW\s+BOOKING/i.test(String(f.pageTitle || ""));
  return usageType === "2" && title.includes("RNT") && Boolean(vehicleId) && !bookingLike;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {string} resQuery
 * @return {Promise<Array<object>>}
 */
async function searchCachedRentalsByRes(db, franchiseId, resQuery) {
  const col = db.collection("franchises").doc(franchiseId).collection("wheelsysRentals");
  const hits = [];
  const seen = new Set();
  for (const variant of resQueryVariants(resQuery)) {
    const snap = await col.where("resNo", "==", variant).limit(5).get().catch(() => ({docs: []}));
    snap.docs.forEach((d) => {
      if (seen.has(d.id)) return;
      seen.add(d.id);
      hits.push({entityId: d.id, ...(d.data() || {}), source: "cache"});
    });
  }
  return hits;
}

/** Search RES in Vehicle Sentinel exits + WheelSys list + cache. */
exports.wheelsysSearchRentalByRes = onCall(callableOpts, async (request) => {
  const {uid, franchiseId} = await assertCHStaff(request);
  const resQuery = String(
      reqData(request, "resQuery") || reqData(request, "resKodu") || "",
  ).trim();
  if (!resQuery) {
    throw new HttpsError("invalid-argument", "resQuery is required.");
  }
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const db = admin.firestore();

  const localExits = await searchLocalExitsByRes(db, franchiseId, resQuery);
  const cached = await searchCachedRentalsByRes(db, franchiseId, resQuery);

  let wheelsysHits = [];
  try {
    const cookie = await resolveCookieForRequest(request, franchiseId, station);
    wheelsysHits = await searchRentalsByRes(cookie, resQuery);
  } catch (e) {
    // List search optional when session missing — local exits still returned.
    console.warn("wheelsysSearchRentalByRes wheelsys list", e.message);
  }

  return {
    resQuery,
    localExits,
    cached,
    wheelsysHits,
    searchedBy: uid,
  };
});

/** Load current WheelSys rental form state for preview. */
exports.wheelsysGetRentalPreview = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const entityId = String(reqData(request, "entityId") || "").trim();
  if (!entityId) {
    throw new HttpsError("invalid-argument", "entityId is required.");
  }
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  const expectedRes = String(reqData(request, "expectedResNo") || "").trim().toUpperCase();
  const lockEntityId = reqData(request, "lockEntityId") === true;

  let activeEntityId = entityId;
  let full = await fetchFullRentalData(cookie, activeEntityId);
  let f = full.fields;

  if (rentalPreviewLooksEmpty(f)) {
    throw new HttpsError(
        "not-found",
        "Invalid WheelSys entity ID. Use the number from rental.aspx?entityId=… " +
        "(not the RES number). Example: 18781 for RES-16745.",
    );
  }

  if (!lockEntityId) {
    const loadedRes = String(f.resNo || "").trim().toUpperCase();
    const lookupRes = expectedRes || loadedRes;
    const candidateIds = [activeEntityId];

    if (lookupRes) {
      try {
        const hits = await searchRentalsByRes(cookie, lookupRes);
        for (const hit of hits.slice(0, 8)) {
          const id = String(hit && hit.entityId ? hit.entityId : "").trim();
          if (id && !candidateIds.includes(id)) candidateIds.push(id);
        }
      } catch (e) {
        console.warn("wheelsysGetRentalPreview searchRentalsByRes", e.message);
      }
    }

    let selected = null;
    for (const candidateId of candidateIds) {
      const candidateFull = candidateId === activeEntityId ?
        full :
        await fetchFullRentalData(cookie, candidateId);
      const candidateFields = candidateFull.fields || {};
      const candidateRes = String(candidateFields.resNo || "").trim().toUpperCase();
      if (expectedRes && !resNoMatchesExpected(candidateRes, expectedRes)) continue;
      if (isStrictRentalCandidate(candidateFields, candidateFull)) {
        selected = {id: candidateId, full: candidateFull};
        break;
      }
    }

    if (!selected) {
      throw new HttpsError(
          "failed-precondition",
          `Entity #${activeEntityId} is not a rental agreement (need rdUsageType=2, RNT title, and vehicle).`,
      );
    }
    if (selected.id !== activeEntityId) {
      console.warn(
          `wheelsysGetRentalPreview: corrected entity ${activeEntityId} -> ${selected.id} for ${lookupRes || "n/a"}`,
      );
    }
    activeEntityId = selected.id;
    full = selected.full;
    f = full.fields;
    if (expectedRes && !resNoMatchesExpected(f.resNo, expectedRes)) {
      throw new HttpsError(
          "failed-precondition",
          `Entity #${activeEntityId} is ${String(f.resNo || loadedRes).trim().toUpperCase()}, not ${expectedRes}.`,
      );
    }
  }

  await upsertRentalCache({
    franchiseId,
    entityId: activeEntityId,
    raNo: f.raNo,
    resNo: f.resNo,
    plateNo: f.plate,
    station,
    mileageFrom: Number(f.mileageFromHidden) || null,
    mileageTo: Number(f.mileageToHidden) || null,
    fuelTo: Number(f.tankToHidden) || null,
    rawJson: f,
  });

  const vm = full.vehicleMaster;
  const customer = full.customer || {};

  return {
    entityId: activeEntityId,
    fields: f,
    vehicleEntityId: full.vehicleEntityId,
    pageTitle: f.pageTitle || "",
    usageType: String(f.usageType || ""),
    mileageFrom: Number(f.mileageFromHidden) || 0,
    mileageTo: Number(f.mileageToHidden) || 0,
    fuelFrom: Number(f.tankFromHidden) || 0,
    fuelTo: Number(f.tankToHidden) || 0,
    milesDriven: Number(f.milesDrivenHidden) || 0,
    mileageFromText: f.mileageFromText || "",
    mileageToText: f.mileageToText || "",
    tankFromText: f.tankFromText || "",
    tankToText: f.tankToText || "",
    userTo: f.checkInUserId || "",
    checkInUserOptions: f.checkInUserOptions || [],
    dateFrom: f.dateFrom,
    timeFrom: f.timeFrom,
    dateTo: f.dateTo,
    timeTo: f.timeTo,
    plate: f.plate,
    vehicleModel: f.vehicleModel || (vm && vm.model) || "",
    raNo: f.raNo,
    resNo: f.resNo,
    customerFirstName: customer.firstName || "",
    customerLastName: customer.lastName || "",
    customerName: customer.fullName || "",
    customerEmail: customer.email || "",
    customerSource: customer.source || "",
    insurance: full.insurance,
    rentalNotes: (full.notes && full.notes.rentalNotes) || [],
    vehicleNotes: (full.notes && full.notes.vehicleNotes) || [],
    checkoutMileageText: f.mileageFromText || "",
    checkinMileageText: f.mileageToText || "",
    vehicleMasterMileage: vm ? vm.mileage : null,
    vehicleMasterFuel: vm ? vm.tank : null,
    notes: full.notes,
    vehicleMaster: vm ? {
      mileage: vm.mileage,
      tank: vm.tank,
      mileageText: vm.mileageText,
      tankText: vm.tankText,
      model: vm.model,
      plate: vm.plate,
    } : null,
    mileage: full.mileage,
  };
});

/**
 * Write wheelsys sync status fields back to an exitIslemleri or iadeIslemleri doc.
 * Never writes cookie/session data — only result metadata.
 * @param {object} p
 */
async function writeWheelSysSyncStatus({
  db, franchiseId, firestoreCollection, firestoreDocId,
  entityId, resNo, raNo, plateNo,
  mileageFrom, mileageTo, milesDriven, fuelTo,
  syncStatus, syncError, responsePreview, syncedBy,
}) {
  if (!firestoreCollection || !firestoreDocId) return;
  const safeCollection = String(firestoreCollection || "").trim();
  const allowed = ["exitIslemleri", "iadeIslemleri", "checkInKayitlari"];
  if (!allowed.includes(safeCollection)) return;
  const payload = {
    wheelsysEntityId: String(entityId || ""),
    wheelsysResNo: String(resNo || ""),
    wheelsysRaNo: String(raNo || ""),
    wheelsysPlateNo: String(plateNo || ""),
    wheelsysMileageFrom: mileageFrom != null ? Number(mileageFrom) : null,
    wheelsysMileageTo: mileageTo != null ? Number(mileageTo) : null,
    wheelsysMilesDriven: milesDriven != null ? Number(milesDriven) : null,
    wheelsysFuelTo: fuelTo != null ? Number(fuelTo) : null,
    wheelsysSyncStatus: syncStatus,
    wheelsysSyncError: syncError ? String(syncError).slice(0, 1000) : null,
    wheelsysResponsePreview: responsePreview ? String(responsePreview).slice(0, 1000) : null,
    wheelsysLastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
    wheelsysSyncedBy: String(syncedBy || ""),
  };
  await db.collection("franchises").doc(franchiseId)
      .collection(safeCollection).doc(firestoreDocId).set(payload, {merge: true});
}

/** Push check-in mileage/fuel to WheelSys. */
exports.wheelsysCheckinUpdate = onCall(callableOpts, async (request) => {
  const {uid, profile, franchiseId} = await assertCHStaff(request);
  const entityId = String(reqData(request, "entityId") || "").trim();
  const checkInMileage = reqData(request, "checkInMileage");
  const checkInFuel = reqData(request, "checkInFuel");
  const checkInUserId = reqData(request, "checkInUserId") ||
    (profile.wheelsysUserId != null ? profile.wheelsysUserId : undefined);
  const checkInDate = reqData(request, "checkInDate");
  const checkInTime = reqData(request, "checkInTime");
  const resNo = String(reqData(request, "resNo") || "").trim();
  const plate = String(reqData(request, "plate") || "").trim();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  // Optional: link back to the Vehicle Sentinel Firestore record.
  const firestoreCollection = String(reqData(request, "firestoreCollection") || "").trim();
  const firestoreDocId = String(reqData(request, "firestoreDocId") || "").trim();
  const addNotes = reqData(request, "addNotes") === true;
  const rentalNoteText = String(reqData(request, "rentalNoteText") || "").trim();
  const vehicleNoteText = String(reqData(request, "vehicleNoteText") || "").trim();
  const vehicleEntityIdHint = String(
      reqData(request, "vehicleEntityId") || reqData(request, "vehicleEntityIdHint") || "",
  ).trim();
  const fleetCarIdHint = String(reqData(request, "fleetCarId") || "").trim();
  const entryPoint = String(reqData(request, "entryPoint") || "").trim();
  const correlationId = String(reqData(request, "correlationId") || "").trim() ||
    entryPoint ||
    `ws-${Date.now().toString(36)}`;
  const skipVehicleMasterSync = reqData(request, "skipVehicleMasterSync") !== false;
  const verifyDailyViewAvailable = reqData(request, "verifyDailyViewAvailable") !== false;

  if (!entityId) {
    throw new HttpsError("invalid-argument", "entityId is required.");
  }

  const zurichNow = zurichDefaultCheckInDateTime();
  const defaultDate = zurichNow.date;
  const defaultTime = zurichNow.time;

  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  const db = admin.firestore();

  let effectiveCheckInUserId = checkInUserId != null ?
    String(checkInUserId).trim() : "";
  if (!/^\d+$/.test(effectiveCheckInUserId)) {
    const sessionOp = await loadSessionOperator(db, franchiseId, station, uid);
    if (/^\d+$/.test(sessionOp.userId)) {
      effectiveCheckInUserId = sessionOp.userId;
    }
  }

  let resolvedEntityId = entityId;
  let resolvedFleetCarId = fleetCarIdHint;
  let entityIdFromRes = false;

  // Prefer RES search when resNo is provided — before fleet plate override.
  if (resNo) {
    try {
      const [cached, wheelsysHits] = await Promise.all([
        searchCachedRentalsByRes(db, franchiseId, resNo),
        searchRentalsByRes(cookie, resNo).catch(() => []),
      ]);
      const resHit = wheelsysHits[0] || cached[0];
      if (resHit && resHit.entityId) {
        resolvedEntityId = String(resHit.entityId);
        entityIdFromRes = true;
        console.info("wheelsysCheckinUpdate entityId from RES search", {
          resNo,
          requestedEntityId: entityId,
          resolvedEntityId,
          source: resHit.source || "res_search",
        });
      }
    } catch (e) {
      console.warn("wheelsysCheckinUpdate RES lookup skipped", e.message);
    }
  }

  // Fleet chart + rental preview in parallel (audit snapshot + fleet car id).
  const [fleetSettled, previewSettled] = await Promise.allSettled([
    plate ?
      fetchWheelSysFleetChart({wheelsysCookie: cookie, station}) :
      Promise.resolve(null),
    fetchRentalPage(cookie, resolvedEntityId),
  ]);

  if (fleetSettled.status === "fulfilled" && fleetSettled.value && plate) {
    try {
      const fleet = fleetSettled.value;
      const fleetEntityId = findRentalEntityIdByPlate(fleet, plate);
      const matchedVehicle = fleet.vehicles.find((v) =>
        String(v.plate || "").replace(/\s+/g, "").toUpperCase() ===
        String(plate).replace(/\s+/g, "").toUpperCase(),
      );
      if (matchedVehicle && matchedVehicle.vehicleId) {
        resolvedFleetCarId = String(matchedVehicle.vehicleId);
      }
      // Fleet plate override only when RES did not resolve the rental entity.
      if (fleetEntityId && !entityIdFromRes) {
        if (String(fleetEntityId) !== resolvedEntityId) {
          console.info("wheelsysCheckinUpdate entityId corrected via fleet plate", {
            plate,
            requestedEntityId: entityId,
            previousEntityId: resolvedEntityId,
            fleetEntityId,
            vehicleId: matchedVehicle ? matchedVehicle.vehicleId : null,
          });
        }
        resolvedEntityId = String(fleetEntityId);
      }
    } catch (e) {
      console.warn("wheelsysCheckinUpdate fleet plate lookup skipped", e.message);
    }
  } else if (fleetSettled.status === "rejected") {
    const fleetErr = fleetSettled.reason;
    console.warn(
        "wheelsysCheckinUpdate fleet chart skipped",
        fleetErr && fleetErr.message ? fleetErr.message : fleetErr,
    );
  }

  // Snapshot current WheelSys values for the audit log (not required for save).
  let previewFields = {};
  if (previewSettled.status === "fulfilled") {
    previewFields = previewSettled.value.fields || {};
  } else {
    const previewErr = previewSettled.reason;
    console.warn(
        "wheelsysCheckinUpdate pre-snapshot",
        previewErr && previewErr.message ? previewErr.message : previewErr,
    );
  }
  const oldMileage = Number(previewFields.mileageToHidden) || null;
  const oldFuel = Number(previewFields.tankToHidden) || null;
  const resolvedResNo = resNo || String(previewFields.resNo || "");
  const resolvedRaNo = String(previewFields.raNo || "");
  const resolvedPlate = plate || String(previewFields.plate || "");

  let result;
  try {
    const selectedOperationalDate = operationalDateFromCheckIn(
        checkInDate || defaultDate,
        new Date(),
    );
    result = await updateWheelsysCheckin({
      entityId: resolvedEntityId,
      checkInMileage,
      checkInFuel,
      checkInUserId: effectiveCheckInUserId || undefined,
      checkInDate: checkInDate || defaultDate,
      checkInTime: checkInTime || defaultTime,
      wheelsysCookie: cookie,
      checkInCondition: reqData(request, "checkInCondition"),
      verifyAfterSave: true,
      plate: resolvedPlate || plate,
      fleetCarIdHint: resolvedFleetCarId,
      vehicleEntityIdHint: vehicleEntityIdHint || String(previewFields.vehicleEntityId || ""),
      skipVehicleMasterSync,
      verifyDailyViewAvailable: skipVehicleMasterSync && verifyDailyViewAvailable,
      correlationId,
      dailyViewVerifyOpts: {
        selectedDate: selectedOperationalDate,
        station,
      },
      verifyDailyViewFn: skipVehicleMasterSync && verifyDailyViewAvailable ?
        (opts) => verifyVehicleAvailableMileage(cookie, {
          ...opts,
          station,
          selectedDate: selectedOperationalDate,
        }) :
        null,
    });
  } catch (e) {
    const errMsg = String(e.message || e).slice(0, 1000);
    await Promise.allSettled([
      writeUpdateLog({
        franchiseId, entityId: resolvedEntityId,
        resNo: resolvedResNo, plateNo: resolvedPlate,
        updateType: "checkin",
        oldMileage, newMileage: checkInMileage,
        oldFuel, newFuel: checkInFuel,
        responseSuccess: false,
        responsePreview: errMsg,
        createdBy: uid,
      }),
      writeWheelSysSyncStatus({
        db, franchiseId,
        firestoreCollection, firestoreDocId,
        entityId: resolvedEntityId, resNo: resolvedResNo, raNo: resolvedRaNo, plateNo: resolvedPlate,
        mileageFrom: oldMileage, mileageTo: checkInMileage,
        milesDriven: null, fuelTo: checkInFuel,
        syncStatus: "failed",
        syncError: errMsg,
        responsePreview: errMsg,
        syncedBy: uid,
      }),
    ]);
    throwWheelSysClientError(e);
  }

  await Promise.allSettled([
    writeUpdateLog({
      franchiseId, entityId: resolvedEntityId,
      plateNo: resolvedPlate,
      updateType: "checkin",
      operationType: "return_checkin_mileage_update",
      entryPoint: entryPoint || "unknown",
      rentalId: resolvedEntityId,
      raNo: resolvedRaNo,
      resNo: resolvedResNo,
      vehicleId: result.vehicleEntityId || vehicleEntityIdHint || null,
      plate: resolvedPlate,
      checkoutMileage: result.mileageFrom,
      checkinMileage: result.mileageTo,
      milesDriven: result.milesDriven,
      checkoutFuel: oldFuel,
      checkinFuel: result.fuelTo,
      userTo: result.checkInUserId || effectiveCheckInUserId || null,
      station,
      checkInDateTime: `${checkInDate || defaultDate} ${checkInTime || defaultTime}`,
      saveSuccess: result.saveSuccess,
      dailyViewAvailableVerified: result.dailyViewAvailableVerified,
      verificationAttempts: result.verificationAttempts,
      oldMileage, newMileage: result.mileageTo,
      oldFuel, newFuel: result.fuelTo,
      responseSuccess: result.success,
      responsePreview: result.responsePreview,
      errorMessage: result.errorMessage || null,
      createdBy: uid,
    }),
    result.success ? upsertRentalCache({
      franchiseId, entityId: resolvedEntityId, station,
      resNo: resolvedResNo, raNo: resolvedRaNo, plateNo: resolvedPlate,
      mileageFrom: result.mileageFrom,
      mileageTo: result.mileageTo,
      fuelTo: result.fuelTo,
    }) : Promise.resolve(),
    writeWheelSysSyncStatus({
      db, franchiseId,
      firestoreCollection, firestoreDocId,
      entityId: resolvedEntityId, resNo: resolvedResNo, raNo: resolvedRaNo, plateNo: resolvedPlate,
      mileageFrom: result.mileageFrom,
      mileageTo: result.mileageTo,
      milesDriven: result.milesDriven,
      fuelTo: result.fuelTo,
      syncStatus: result.success ? "success" : "failed",
      syncError: result.success ? null : result.errorMessage,
      responsePreview: result.responsePreview,
      syncedBy: uid,
    }),
  ]);

  if (!result.success) {
    const errMsg = result.errorMessage || "WheelSys did not confirm success. Check audit log.";
    throw new HttpsError(
        "failed-precondition",
        errMsg,
        {wheelSysMessage: errMsg},
    );
  }

  const savedNotes = {rentalNote: null, vehicleNote: null, errors: []};
  if (addNotes) {
    const creatorId = resolveCreatorId({
      checkInUserId: result.checkInUserId || effectiveCheckInUserId,
      profile,
      previewFields,
    });
    const creatorFullName = profileCreatorFullName(profile);
    if (creatorId != null && creatorFullName) {
      const autoRentalNote = rentalNoteText ||
        `Mileage updated to ${result.mileageTo} km and tank updated to ${result.fuelTo}/8 from app.`;
      const autoVehicleNote = vehicleNoteText ||
        (rentalNoteText ?
          rentalNoteText :
          `Vehicle mileage updated from rental ${resolvedRaNo || resolvedResNo}.`);

      try {
        savedNotes.rentalNote = await saveEntityNote(cookie, {
          entityKey: resolvedEntityId,
          domain: WHEELSYS_DOMAINS.rental,
          noteText: autoRentalNote,
          creatorId,
          creatorFullName,
        });
      } catch (e) {
        console.warn("wheelsysCheckinUpdate rental note save", e.message);
        savedNotes.errors.push(`rental: ${e.message}`);
      }

      const vehicleId = result.vehicleEntityId || resolvedFleetCarId;
      if (!skipVehicleMasterSync && vehicleId && /^\d+$/.test(String(vehicleId))) {
        try {
          savedNotes.vehicleNote = await saveEntityNote(cookie, {
            entityKey: String(vehicleId),
            domain: WHEELSYS_DOMAINS.vehicle,
            noteText: autoVehicleNote,
            creatorId,
            creatorFullName,
          });
        } catch (e) {
          console.warn("wheelsysCheckinUpdate vehicle note save", e.message);
          savedNotes.errors.push(`vehicle: ${e.message}`);
        }
      }
    } else {
      console.warn("wheelsysCheckinUpdate addNotes skipped: missing creatorId or name");
      savedNotes.errors.push("missing WheelSys creator id");
    }
  }

  const verificationWarning = result.verificationPending ?
    (result.errorMessage || "Return saved, vehicle mileage verification pending.") :
    "";

  return {
    success: true,
    message: verificationWarning ||
      (savedNotes.errors.length ?
        "WheelSys check-in saved. Some notes could not be saved." :
        "WheelSys check-in saved successfully."),
    result: {
      entityId: result.entityId,
      mileageFrom: result.mileageFrom,
      mileageTo: result.mileageTo,
      milesDriven: result.milesDriven,
      fuelTo: result.fuelTo,
      verifiedMileageTo: result.verifiedMileageTo,
      vehicleEntityId: result.vehicleEntityId,
      vehicleMasterSynced: result.vehicleMasterSynced,
      vehicleMileageVerified: result.vehicleMileageVerified,
      vehicleFuelVerified: result.vehicleFuelVerified,
      dailyViewAvailableVerified: result.dailyViewAvailableVerified,
      verificationAttempts: result.verificationAttempts,
      verificationPending: result.verificationPending,
      saveSuccess: result.saveSuccess,
      vehicleMaster: result.vehicleMaster,
    },
    notes: addNotes ? savedNotes : undefined,
  };
});

/** Manual note add from iOS (rental or vehicle domain). */
exports.wheelsysSaveNote = onCall(callableOpts, async (request) => {
  const {profile, franchiseId} = await assertCHStaff(request);
  const entityKey = String(reqData(request, "entityKey") || reqData(request, "entityId") || "").trim();
  const domain = Number(reqData(request, "domain"));
  const noteText = String(reqData(request, "noteText") || "").trim();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();

  if (!entityKey) {
    throw new HttpsError("invalid-argument", "entityKey is required.");
  }
  if (!noteText) {
    throw new HttpsError("invalid-argument", "noteText is required.");
  }
  if (domain !== WHEELSYS_DOMAINS.vehicle && domain !== WHEELSYS_DOMAINS.rental) {
    throw new HttpsError(
        "invalid-argument",
        `domain must be ${WHEELSYS_DOMAINS.vehicle} (vehicle) or ${WHEELSYS_DOMAINS.rental} (rental).`,
    );
  }

  const creatorId = resolveCreatorId({
    checkInUserId: reqData(request, "creatorId"),
    profile,
    previewFields: null,
  });
  const creatorFullName = String(reqData(request, "creatorFullName") || "").trim() ||
    profileCreatorFullName(profile);

  if (creatorId == null) {
    throw new HttpsError(
        "failed-precondition",
        "WheelSys user id not found. Set wheelsysUserId on profile or pass creatorId.",
    );
  }
  if (!creatorFullName) {
    throw new HttpsError("failed-precondition", "creatorFullName is required.");
  }

  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  try {
    const saved = await saveEntityNote(cookie, {
      entityKey,
      domain,
      noteText,
      creatorId,
      creatorFullName,
      notify: reqData(request, "notify") === true,
      email: reqData(request, "email") === true,
      notificationRecipientId: reqData(request, "notificationRecipientId") || null,
      notificationRecipientFullName: reqData(request, "notificationRecipientFullName") || null,
    });
    return {success: true, note: saved};
  } catch (e) {
    throw new HttpsError("internal", e.message || "Failed to save WheelSys note.");
  }
});

/** Delete a WheelSys entity note (rental or vehicle domain). */
exports.wheelsysDeleteNote = onCall(callableOpts, async (request) => {
  const {franchiseId} = await assertCHStaff(request);
  const entityKey = String(reqData(request, "entityKey") || reqData(request, "entityId") || "").trim();
  const domain = Number(reqData(request, "domain"));
  const noteId = String(reqData(request, "noteId") || reqData(request, "id") || "").trim();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();

  if (!entityKey) {
    throw new HttpsError("invalid-argument", "entityKey is required.");
  }
  if (!noteId) {
    throw new HttpsError("invalid-argument", "noteId is required.");
  }
  if (domain !== WHEELSYS_DOMAINS.vehicle && domain !== WHEELSYS_DOMAINS.rental) {
    throw new HttpsError(
        "invalid-argument",
        `domain must be ${WHEELSYS_DOMAINS.vehicle} (vehicle) or ${WHEELSYS_DOMAINS.rental} (rental).`,
    );
  }

  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  try {
    await deleteEntityNote(cookie, {entityKey, domain, noteId});
    return {success: true};
  } catch (e) {
    throw new HttpsError("internal", e.message || "Failed to delete WheelSys note.");
  }
});

/** Admin: store encrypted WheelSys session cookie (never returned to client). */
exports.wheelsysSaveSession = onCall(callableOpts, async (request) => {
  const {uid, franchiseId} = await assertCHStaff(request);

  const cookieRaw = String(reqData(request, "sessionCookie") || "").trim();
  if (!cookieRaw || cookieRaw.length < 20) {
    throw new HttpsError("invalid-argument", "sessionCookie is required.");
  }

  const {buildFleetAuthCookie} = require("./cookieJar");
  const cookiePlain = buildFleetAuthCookie(cookieRaw) || cookieRaw;
  if (!cookiePlain.includes(".wheelsys=") || !cookiePlain.includes("__Secure-SID=")) {
    throw new HttpsError(
        "invalid-argument",
        "sessionCookie must include .wheelsys and __Secure-SID values.",
    );
  }

  const encKey = encryptionKeyHex();
  if (!encKey) {
    throw new HttpsError(
        "failed-precondition",
        "WHEELSYS_API_KEY is not configured on the server.",
    );
  }

  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const ttlHours = Math.min(
      72,
      Math.max(1, Number(reqData(request, "ttlHours")) || 12),
  );
  const wheelSysUserId = String(reqData(request, "wheelSysUserId") || "").trim();
  const wheelSysUserName = String(reqData(request, "wheelSysUserName") || "").trim();

  let storedUserId = /^\d+$/.test(wheelSysUserId) ? wheelSysUserId : "";
  const storedUserName = wheelSysUserName;
  if (!storedUserId) {
    try {
      const probe = await fetch(`${BASE_URL}/ui/manage/master/rentals.aspx`, {
        headers: {"Cookie": cookiePlain, "User-Agent": "VehicleSentinel/1.0"},
        redirect: "follow",
      });
      const html = String(await probe.text());
      if (probe.ok) {
        storedUserId = extractSessionWheelSysUserId(html) || "";
      }
    } catch (e) {
      console.warn("wheelsysSaveSession user probe", e.message);
    }
  }

  await saveSession({
    db: admin.firestore(),
    franchiseId,
    station,
    cookiePlain,
    encryptionKeyHex: encKey,
    createdBy: uid,
    ttlHours,
    wheelSysUserId: storedUserId || undefined,
    wheelSysUserName: storedUserName || undefined,
  });

  return {
    success: true,
    station,
    expiresInHours: ttlHours,
    wheelSysUserId: storedUserId || null,
  };
});

/** Check whether an encrypted WheelSys session exists and still works. */
exports.wheelsysSessionStatus = onCall(callableOpts, async (request) => {
  const {uid} = await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const db = admin.firestore();
  const snap = await sessionDocRef(db, franchiseId, station, uid).get();
  if (!snap.exists) {
    return {hasSession: false, isValid: false, station};
  }
  const data = snap.data() || {};
  const expiresAtMs = data.expiresAt && data.expiresAt.toMillis ?
    data.expiresAt.toMillis() : null;
  if (data.isActive === false || !data.cookieEncrypted) {
    return {hasSession: false, isValid: false, station, expiresAtMs};
  }
  if (expiresAtMs && expiresAtMs <= Date.now()) {
    return {hasSession: false, isValid: false, station, expiresAtMs};
  }

  let isValid = false;
  let fleetChartValid = false;
  try {
    const cookie = await resolveCookieForRequest(request, franchiseId, station);
    const probe = await fetch(`${BASE_URL}/ui/manage/master/rentals.aspx`, {
      headers: {"Cookie": cookie, "User-Agent": "VehicleSentinel/1.0"},
      redirect: "follow",
    });
    const html = String(await probe.text());
    isValid = probe.ok &&
      !( /login|sign.?in/i.test(html) && !html.includes("/ui/manage/") );
    fleetChartValid = await probeFleetChartAccess(cookie);
    const wheelSysUserId = isValid ?
      extractSessionWheelSysUserId(html) || null : null;
    let resolvedUserId = wheelSysUserId;
    if (!resolvedUserId && data.wheelSysUserId) {
      const stored = String(data.wheelSysUserId).trim();
      if (/^\d+$/.test(stored)) resolvedUserId = stored;
    }
    return {
      hasSession: true,
      isValid,
      fleetChartValid,
      station,
      expiresAtMs,
      wheelSysUserId: resolvedUserId,
    };
  } catch (e) {
    console.warn("wheelsysSessionStatus probe", e.message);
  }

  return {hasSession: true, isValid, fleetChartValid, station, expiresAtMs};
});

/**
 * @param {string} cookie
 * @return {Promise<boolean>}
 */
async function probeFleetChartAccess(cookie) {
  try {
    let authCookie = buildFleetAuthCookie(cookie);
    if (!authCookie) return false;

    authCookie = await warmFleetChartPage(authCookie);
    const pageUrl = `${WHEELSYS_BASE}/ui/dashboards/fleetchart.aspx`;
    const dataUrl = `${WHEELSYS_BASE}/ui/dashboards/fleetchart.aspx/GetFleetchartData`;
    const {res, outer} = await postFleetChartRequest(
        authCookie,
        pageUrl,
        dataUrl,
        buildFleetChartRequestBody({station: "ZRH"}),
    );
    const pageOk = res.ok;
    const dataOk = Boolean(outer && outer.d && outer.d.success === true);
    return pageOk && dataOk;
  } catch (e) {
    console.warn("wheelsysSessionStatus fleet probe", e.message);
    return false;
  }
}

/** Fleet Chart — read-only vehicle/event sync from WheelSys. */
exports.wheelsysGetFleetChart = onCall(callableOpts, async (request) => {
  const {uid, franchiseId} = await assertCHStaff(request);
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();

  const db = admin.firestore();
  let fleet;
  let syncError = null;
  let syncCode = null;

  try {
    // Prefer live cookie from iOS WKWebView (passed per-request); fall back to stored session.
    const passedCookie = reqData(request, "sessionCookie");
    const hasPassedCookie = typeof passedCookie === "string" && passedCookie.length > 20;

    if (hasPassedCookie) {
      if (!passedCookie.includes(".wheelsys=") ||
          !passedCookie.includes("__Secure-SID=")) {
        throw new HttpsError(
            "failed-precondition",
            "WheelSys session cookie is incomplete. Please log in again.",
            {code: "WHEELSYS_SESSION_MISSING"},
        );
      }
    }

    const cookie = hasPassedCookie ?
      passedCookie :
      await resolveCookieForRequest(request, franchiseId, station);

    // Log only presence — never the value.
    console.info("wheelsysGetFleetChart cookie source", {
      source: hasPassedCookie ? "ios_webview" : "stored_session",
      ...cookiePresenceLog(cookie),
      station,
      uid,
    });

    fleet = await fetchWheelSysFleetChart({
      wheelsysCookie: cookie,
      station,
    });
  } catch (e) {
    syncError = String(e.message || e).slice(0, 500);
    syncCode = e.code || "WHEELSYS_FLEET_ERROR";
    console.warn("wheelsysGetFleetChart failed", {
      code: syncCode,
      httpStatus: e.httpStatus || null,
      message: syncError,
      wheelSysMessage: e.wheelSysMessage || null,
      debugPreview: String(e.debugPreview || "").slice(0, 500),
      station,
      uid,
    });
    await db.collection("franchises").doc(franchiseId)
        .collection("wheelsysSyncLogs").add({
          syncType: "fleet_chart",
          station,
          success: false,
          code: syncCode,
          message: syncError,
          httpStatus: e.httpStatus || null,
          vehiclesCount: 0,
          eventsCount: 0,
          createdBy: uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }).catch(() => null);

    if (syncCode === "WHEELSYS_SESSION_EXPIRED" ||
        syncCode === "WHEELSYS_SESSION_MISSING") {
      throw new HttpsError("failed-precondition", syncError, {code: syncCode});
    }
    // Use failed-precondition so iOS receives the message (internal hides it).
    throw new HttpsError("failed-precondition", syncError, {
      code: syncCode,
      httpStatus: e.httpStatus || null,
      wheelSysMessage: e.wheelSysMessage || null,
      debugPreview: String(e.debugPreview || "").slice(0, 500),
    });
  }

  await db.collection("franchises").doc(franchiseId)
      .collection("wheelsysSyncLogs").add({
        syncType: "fleet_chart",
        station,
        success: true,
        code: null,
        message: null,
        vehiclesCount: fleet.vehiclesCount,
        eventsCount: fleet.eventsCount,
        startDate: fleet.startDate,
        endDate: fleet.endDate,
        createdBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }).catch(() => null);

  return {
    success: true,
    resourcesCount: fleet.resourcesCount || fleet.vehiclesCount,
    ...fleet,
  };
});

/** Daily journal (checkouts + returns + unassigned bookings) from Fleet Chart. */
exports.wheelsysGetJournal = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const selectedDay = String(reqData(request, "selectedDay") || "").trim();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  try {
    const journal = await fetchJournalData(cookie, {
      selectedDay: selectedDay || undefined,
      station,
    });
    return {success: true, ...journal};
  } catch (e) {
    throw new HttpsError("internal", e.message || "Journal fetch failed.");
  }
});

/** Journal snapshot from journal.aspx API (fleet-chart fallback server-side). */
exports.wheelsysGetJournalSnapshot = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const selectedDate = String(
      reqData(request, "selectedDate") ||
      reqData(request, "selectedDay") ||
      "",
  ).trim();
  const useFallback = reqData(request, "useFallback") !== false;
  const passedCookie = reqData(request, "sessionCookie");
  const hasPassedCookie = typeof passedCookie === "string" && passedCookie.length > 20;
  const cookie = hasPassedCookie ?
    passedCookie :
    await resolveCookieForRequest(request, franchiseId, station);
  try {
    const journal = useFallback ?
      await fetchJournalSnapshotWithFallback(cookie, {selectedDate, station}) :
      await fetchJournalSnapshot(cookie, {selectedDate, station});
    return {success: true, ...journal};
  } catch (e) {
    throwWheelSysClientError(e);
  }
});

/** Single Daily View tab (checkouts|checkins|precheckins|cancellations|nonrevenue|available|bookings). */
exports.wheelsysGetDailyView = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const tab = String(reqData(request, "tab") || "").trim().toLowerCase();
  const selectedDate = String(reqData(request, "selectedDate") || "").trim();
  if (!tab) {
    throw new HttpsError("invalid-argument", "tab is required.");
  }
  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  try {
    const result = await fetchDailyViewTab(cookie, tab, {
      selectedDate: selectedDate || undefined,
      station,
      pendingOnly: reqData(request, "pendingOnly") === true,
      forExport: reqData(request, "forExport") === true,
    });
    return {success: true, ...result};
  } catch (e) {
    throwWheelSysClientError(e);
  }
});

/** All Daily View tabs in one round-trip. */
exports.wheelsysGetDailyViewAll = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const selectedDate = String(reqData(request, "selectedDate") || "").trim();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  try {
    const result = await fetchDailyViewAll(cookie, {
      selectedDate: selectedDate || undefined,
      station,
      pendingOnly: reqData(request, "pendingOnly") === true,
      forExport: reqData(request, "forExport") === true,
    });
    return {success: true, ...result};
  } catch (e) {
    throwWheelSysClientError(e);
  }
});

/** Paged booking grid search (mainviewex bookingview). */
exports.wheelsysSearchBookingsList = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  try {
    const result = await searchBookingsList(cookie, {
      station,
      page: reqData(request, "page"),
      pageSize: reqData(request, "pageSize"),
      sortField: reqData(request, "sortField") || reqData(request, "sort"),
      sortDir: reqData(request, "sortDir"),
      searchText: reqData(request, "searchText") || reqData(request, "query"),
      filter: reqData(request, "filter"),
      viewName: reqData(request, "viewName"),
      pendingOnly: reqData(request, "pendingOnly") === true,
    });
    return {success: true, ...result};
  } catch (e) {
    throwWheelSysClientError(e);
  }
});

/** Read booking.aspx form state for preview / assignment prep. */
exports.wheelsysGetBookingPreview = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const hintId = String(reqData(request, "entityId") || "").trim();
  if (!hintId) {
    throw new HttpsError("invalid-argument", "entityId is required.");
  }
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const resNo = String(reqData(request, "resNo") || "").trim();
  const displayDocNo = String(reqData(request, "displayDocNo") || "").trim();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);

  const resolved = await resolveBookingEntityId(cookie, hintId, {resNo, displayDocNo});
  const page = await fetchBookingPage(cookie, resolved.entityId);
  const f = page.fields;
  const form = parseFormToPayload(page.html);
  const customer = mapCustomerFromRentalForm(form);
  const attachmentRows = parseRentalAttachments(form);
  const attachments = attachmentRows.map((row, index) => ({
    attachmentId: `${resolved.entityId}-${index}`,
    uid: String(row.Uid || row.uid || "").trim(),
    fileName: String(row.FileName || row.OriginalFileName || "").trim(),
    fileSize: Number(row.FileSize) || 0,
    uploadedOn: String(row.UploadedOn || "").trim(),
    domain: String(row.Domain || "5").trim(),
  })).filter((a) => a.fileName);
  return {
    success: true,
    entityId: resolved.entityId,
    resolvedFrom: resolved.source,
    resNo: f.resNo || resolved.resNo,
    raNo: f.raNo,
    plate: f.plate,
    carGroup: f.carGroup,
    stationFrom: f.stationFrom,
    stationTo: f.stationTo,
    dateFrom: f.dateFrom,
    timeFrom: f.timeFrom,
    dateTo: f.dateTo,
    timeTo: f.timeTo,
    usageType: f.usageType,
    carId: f.carId,
    modelId: f.modelId,
    modelText: f.modelText,
    chargeTotal: f.chargeTotal,
    dateFromIso: combineDateTimeLocal(f.dateFrom, f.timeFrom),
    dateToIso: combineDateTimeLocal(f.dateTo, f.timeTo),
    isAssigned: Boolean(f.plate && f.carId),
    insurance: parseInsuranceSummary(f),
    driverName: customer.fullName || f.driver || "",
    customerFirstName: customer.firstName || "",
    customerLastName: customer.lastName || "",
    customerName: customer.fullName || f.driver || "",
    customerEmail: customer.email || "",
    cacheKey: f.cacheKey || "",
    attachments,
  };
});

/** Search available vehicles for a booking period (RentalCarSearch QueryData). */
exports.wheelsysSearchAvailableVehicles = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const hintId = reqData(request, "rentalId") ||
    reqData(request, "bookingEntityId") ||
    reqData(request, "entityId");
  if (!hintId) {
    throw new HttpsError("invalid-argument", "rentalId is required.");
  }
  const resNo = String(reqData(request, "resNo") || "").trim();
  const displayDocNo = String(reqData(request, "displayDocNo") || "").trim();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);

  const resolved = await resolveBookingEntityId(cookie, hintId, {resNo, displayDocNo});
  const rentalId = Number(resolved.entityId);

  const requestedCarGroup = String(reqData(request, "carGroup") || "").trim();
  let vehicles = await searchAvailableVehicles(cookie, {
    stationFrom: reqData(request, "stationFrom") || station,
    stationTo: reqData(request, "stationTo") || station,
    dateFrom: reqData(request, "dateFrom"),
    dateTo: reqData(request, "dateTo"),
    carGroup: requestedCarGroup,
    usageType: reqData(request, "usageType") || 1,
    rentalId,
    plateMask: reqData(request, "plateMask") || "",
    modelId: reqData(request, "modelId"),
    entireFleet: reqData(request, "entireFleet") === true,
  });
  const entireFleet = reqData(request, "entireFleet") === true;
  if (requestedCarGroup && requestedCarGroup !== "-" && !entireFleet) {
    const groupLower = requestedCarGroup.toLowerCase();
    vehicles = vehicles.filter(
        (v) => String(v.carGroup || "").trim().toLowerCase() === groupLower,
    );
  }
  return {
    success: true,
    bookingEntityId: rentalId,
    resolvedFrom: resolved.source,
    vehicles,
  };
});

/** Resolve booking entity + cacheKey for assignment flow. */
exports.wheelsysResolveBookingContext = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const hintId = reqData(request, "bookingEntityId") ||
    reqData(request, "entityId") ||
    reqData(request, "rentalId");
  const resNo = String(reqData(request, "resNo") || "").trim();
  const displayDocNo = String(reqData(request, "displayDocNo") || "").trim();
  const correlationId = String(reqData(request, "correlationId") || "").trim() ||
    `assign-${Date.now().toString(36)}`;

  if (!hintId && !resNo && !displayDocNo) {
    throw new HttpsError(
        "invalid-argument",
        "bookingEntityId or (resNo/displayDocNo) is required.",
    );
  }

  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  console.info("[WheelSys][Assign] resolve context start", {
    cid: correlationId,
    hintId: hintId != null ? String(hintId) : "",
    hasResNo: Boolean(resNo),
    hasDisplayDocNo: Boolean(displayDocNo),
    station,
  });

  try {
    const context = await resolveBookingContextForAssign(cookie, {
      bookingEntityId: hintId,
      resNo,
      displayDocNo,
      station,
    });
    console.info("[WheelSys][Assign] resolve context success", {
      cid: correlationId,
      bookingEntityId: context.bookingEntityId,
      source: context.source,
      hasCacheKey: Boolean(context.cacheKey),
    });
    return {
      success: true,
      correlationId,
      ...context,
    };
  } catch (e) {
    console.warn("[WheelSys][Assign] resolve context failed", {
      cid: correlationId,
      message: e && e.message ? e.message : String(e),
    });
    throw new HttpsError(
        "failed-precondition",
        e && e.message ? e.message : "Failed to resolve booking context.",
    );
  }
});

/**
 * Full vehicle assignment: canUseCar → CalcRates → booking save.
 * Optionally links result to exitIslemleri.
 */
exports.wheelsysAssignVehicleToBooking = onCall(callableOpts, async (request) => {
  const {uid, profile, franchiseId} = await assertCHStaff(request);
  const bookingEntityId = String(
      reqData(request, "bookingEntityId") || reqData(request, "entityId") || "",
  ).trim();
  const plateNo = String(reqData(request, "plateNo") || reqData(request, "plate") || "").trim();
  const carId = Number(reqData(request, "carId") || reqData(request, "vehicleId"));
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const resNo = String(reqData(request, "resNo") || "").trim();
  const displayDocNo = String(reqData(request, "displayDocNo") || "").trim();
  const firestoreCollection = String(reqData(request, "firestoreCollection") || "").trim();
  const firestoreDocId = String(reqData(request, "firestoreDocId") || "").trim();
  const checkOutMileage = Number(reqData(request, "checkOutMileage") || 0);
  const checkOutFuel = reqData(request, "checkOutFuel");
  const preResolvedCacheKey = String(reqData(request, "preResolvedCacheKey") || "").trim();
  const preResolvedBookingEntityId = String(
      reqData(request, "preResolvedBookingEntityId") || "",
  ).trim();
  const correlationId = String(reqData(request, "correlationId") || "").trim() ||
    `assign-${Date.now().toString(36)}`;

  if (!bookingEntityId) {
    throw new HttpsError("invalid-argument", "bookingEntityId is required.");
  }
  if (!plateNo || !carId) {
    throw new HttpsError("invalid-argument", "carId and plateNo are required.");
  }

  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  const db = admin.firestore();
  console.info("[WheelSys][Assign] assign start", {
    cid: correlationId,
    bookingEntityId,
    preResolvedBookingEntityId,
    hasPreResolvedCacheKey: Boolean(preResolvedCacheKey),
    carId,
    plateNo,
  });

  let result;
  try {
    result = await assignVehicleToBooking(cookie, {
      bookingEntityId,
      resNo,
      displayDocNo,
      selectedVehicle: {
        id: carId,
        plateNo,
        carGroup: reqData(request, "carGroup"),
        modelId: reqData(request, "modelId"),
        modelName: reqData(request, "modelName"),
      },
      checkOutMileage,
      checkOutFuel: checkOutFuel != null ? Number(checkOutFuel) : null,
      preResolvedContext: {
        bookingEntityId: preResolvedBookingEntityId,
        cacheKey: preResolvedCacheKey,
        resNo,
        source: "callable_pre_resolved",
      },
    });
  } catch (e) {
    if (firestoreCollection && firestoreDocId) {
      await writeWheelSysSyncStatus({
        db, franchiseId, firestoreCollection, firestoreDocId,
        entityId: bookingEntityId,
        resNo,
        plateNo,
        syncStatus: "failed",
        syncError: e.message,
        syncedBy: uid,
      }).catch(() => null);
    }
    console.warn("[WheelSys][Assign] assign failed", {
      cid: correlationId,
      bookingEntityId,
      message: e && e.message ? e.message : String(e),
    });
    throw new HttpsError("failed-precondition", e.message || "Vehicle assignment failed.");
  }

  if (firestoreCollection && firestoreDocId) {
    await writeWheelSysSyncStatus({
      db, franchiseId, firestoreCollection, firestoreDocId,
      entityId: String(result.bookingEntityId || bookingEntityId),
      resNo: result.resNo || resNo,
      raNo: result.raNo || "",
      plateNo,
      mileageFrom: checkOutMileage || null,
      fuelTo: checkOutFuel != null ? Number(checkOutFuel) : null,
      syncStatus: "success",
      syncError: null,
      responsePreview: JSON.stringify({
        carId: result.carId,
        totalCharge: result.calcRates && result.calcRates.totalCharge,
        resolvedFrom: result.resolvedFrom,
      }).slice(0, 500),
      syncedBy: uid,
    }).catch(() => null);
  }

  return {
    success: true,
    message: "Vehicle assigned to booking in WheelSys.",
    result,
    correlationId,
    assignedBy: uid,
    profileWheelsysUserId: profile.wheelsysUserId || null,
  };
});

/** Vehicle View — read-only full fleet master list. */
exports.wheelsysGetVehicleFleet = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);
  try {
    const fleet = await fetchAllVehicleMaster(cookie, {station});
    await saveVehicleMasterCache(admin.firestore(), franchiseId, station, fleet).catch(() => null);
    return {
      success: true,
      station,
      vehicles: fleet.vehicles.map((v) => ({
        id: v.id,
        wheelsysVehicleId: v.wheelsysVehicleId,
        plateNo: v.plateNo,
        normalizedPlate: v.normalizedPlate,
        status: v.status,
        carGroup: v.carGroup,
        categoryName: v.categoryName,
        effectiveCategory: v.effectiveCategory,
        brandName: v.brandName,
        modelName: v.modelName,
        mileage: v.mileage,
        fuel: v.fuel,
        station: v.station,
        vin: v.vin,
        isDefleeted: v.isDefleeted,
      })),
      stats: fleet.stats,
      duplicateWarnings: fleet.duplicateWarnings,
      allRowsCount: fleet.allRowsCount,
      totalCount: fleet.totalCount,
      truncated: fleet.truncated === true,
      pagesFetched: fleet.pagesFetched,
      noPlateCount: fleet.noPlateCount,
    };
  } catch (e) {
    throwWheelSysClientError(e);
  }
});

/** Vehicle Master sync — dry-run match report. */
exports.wheelsysPreviewVehicleMasterSync = onCall(callableOpts, async (request) => {
  const {uid} = await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);

  let fleet;
  try {
    fleet = await fetchAllVehicleMaster(cookie, {station});
    await saveVehicleMasterCache(admin.firestore(), franchiseId, station, fleet).catch(() => null);
  } catch (e) {
    throwWheelSysClientError(e);
  }

  const sync = await runVehicleMasterSync({
    franchiseId,
    wheelsysVehicles: fleet.vehicles,
    apply: false,
  });

  return {
    success: true,
    station,
    previewedBy: uid,
    fleetFromCache: false,
    stats: fleet.stats,
    summary: sync.summary,
    samples: {
      categoryFixes: sync.report.matched
          .filter((r) => r.categoryMismatch)
          .slice(0, 20),
      unmatchedFirebase: sync.report.unmatchedFirebase.slice(0, 20),
      wheelsysOnly: sync.report.wheelsysOnly.slice(0, 20),
      ambiguous: sync.report.ambiguousFirebase.slice(0, 10),
    },
    duplicateWarnings: fleet.duplicateWarnings,
    truncated: fleet.truncated === true,
    report: {
      matchedCount: sync.report.matchedCount,
      unmatchedFirebaseCount: sync.report.unmatchedFirebaseCount,
      wheelsysOnlyCount: sync.report.wheelsysOnlyCount,
      ambiguousFirebaseCount: sync.report.ambiguousFirebaseCount,
      categoryMismatchCount: sync.report.categoryMismatchCount,
    },
  };
});

/** Vehicle Master sync — apply safe partial merges (admin only). */
exports.wheelsysApplyVehicleMasterSync = onCall(
    Object.assign({}, callableOpts, {timeoutSeconds: 300}),
    async (request) => {
      const {uid} = await assertCHAdmin(request);
      const franchiseId = String(
          reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
      ).toUpperCase();
      const station = String(reqData(request, "station") || "ZRH").toUpperCase();
      const cookie = await resolveCookieForRequest(request, franchiseId, station);
      const db = admin.firestore();
      const preferCache = reqData(request, "useCachedFleet") !== false;

      let fleet = null;
      let fleetFromCache = false;
      if (preferCache) {
        fleet = await loadVehicleMasterCache(db, franchiseId, station);
        fleetFromCache = Boolean(fleet);
        if (fleetFromCache) {
          console.info(
              `[WheelSys][VehicleMaster] apply using cache vehicles=${fleet.vehicles.length}`,
          );
        }
      }

      if (!fleet) {
        try {
          fleet = await fetchAllVehicleMaster(cookie, {station});
          await saveVehicleMasterCache(db, franchiseId, station, fleet).catch(() => null);
        } catch (e) {
          throwWheelSysClientError(e);
        }
      }

      const sync = await runVehicleMasterSync({
        db,
        franchiseId,
        wheelsysVehicles: fleet.vehicles,
        apply: true,
      });

      const failedWrites = sync.apply && sync.apply.failedWrites != null ?
        sync.apply.failedWrites : 0;

      await db.collection("franchises").doc(franchiseId)
          .collection("wheelsysSyncLogs").add({
            syncType: "vehicle_master",
            station,
            success: failedWrites === 0,
            matched: sync.summary.matched,
            unmatchedFirebase: sync.summary.unmatchedFirebase,
            unmatchedWheelSys: sync.summary.unmatchedWheelSys,
            categoryFixes: sync.summary.categoryFixes,
            vehicleWrites: sync.apply ? sync.apply.vehicleWrites : 0,
            categoryWrites: sync.apply ? sync.apply.categoryWrites : 0,
            failedWrites,
            createdBy: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }).catch(() => null);

      return {
        success: failedWrites === 0,
        partialFailure: failedWrites > 0,
        station,
        appliedBy: uid,
        fleetFromCache,
        summary: sync.summary,
        apply: sync.apply,
        stats: fleet.stats,
        duplicateWarnings: fleet.duplicateWarnings,
        truncated: fleet.truncated === true,
      };
    },
);

/** Start first-party web login (iframe proxy scratch session). */
exports.wheelsysStartWebLogin = onCall(callableOpts, async (request) => {
  const {uid, franchiseId} = await assertCHStaff(request);
  const {startWebLoginSession} = require("./webLoginProxy");
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  return startWebLoginSession({uid, franchiseId, station});
});

/** Poll web login proxy — saves encrypted session when WheelSys login completes. */
exports.wheelsysPollWebLogin = onCall(callableOpts, async (request) => {
  const {uid} = await assertCHStaff(request);
  const sid = String(reqData(request, "sid") || "").trim();
  if (!sid) {
    throw new HttpsError("invalid-argument", "sid is required.");
  }
  const encKey = encryptionKeyHex();
  if (!encKey) {
    throw new HttpsError(
        "failed-precondition",
        "WHEELSYS_API_KEY is not configured on the server.",
    );
  }
  const {pollWebLogin} = require("./webLoginProxy");
  return pollWebLogin({sid, uid, encryptionKeyHex: encKey});
});

/** Vehicle master damage history from car.aspx (CH only). */
exports.wheelsysGetVehicleDamageHistory = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const plate = String(reqData(request, "plate") || reqData(request, "plateNo") || "").trim();
  const rentalId = String(reqData(request, "rentalId") || "").trim();
  const wheelsysVehicleId = String(
      reqData(request, "vehicleEntityId") ||
      reqData(request, "wheelsysVehicleId") ||
      "",
  ).trim();

  const encKey = encryptionKeyHex();
  const cookie = await resolveCookieForRequest(request, franchiseId, station);

  // Rental-scoped GetDamages avoids Fleet Chart / car.aspx vehicle resolution.
  if (/^\d+$/.test(rentalId)) {
    try {
      const page = await fetchRentalPage(cookie, rentalId);
      const form = parseCompleteRentalFormToPayload(page.html);
      const cacheKey = resolveCacheKey(page.html, form);
      const vehicle = mapVehicle(form);
      const vehicleId = vehicle.vehicleId || (/^\d+$/.test(wheelsysVehicleId) ? Number(wheelsysVehicleId) : 0);
      const rows = await fetchExistingDamages(cookie, {
        rentalId,
        cacheKey,
        vehicleId,
        plateNo: vehicle.plateNo || plate,
        encryptionKeyHex: encKey,
        franchiseId,
        station,
      });
      const damages = mapPrecheckinDamagesToHistory(rows, {
        vehicleId,
        plateNo: vehicle.plateNo || plate,
      });
      return {
        success: true,
        franchiseId,
        station,
        resolvedVehicleEntityId: vehicleId ? String(vehicleId) : null,
        plateNo: vehicle.plateNo || plate || null,
        vehicleId: vehicleId || 0,
        damages,
        damageCount: damages.length,
        syncedAt: new Date().toISOString(),
        source: "wheelsys.rental.GetDamages",
      };
    } catch (e) {
      console.warn("wheelsysGetVehicleDamageHistory rental-scoped failed", e.message);
      if (!plate && !/^\d+$/.test(wheelsysVehicleId)) {
        throwWheelSysClientError(e);
      }
    }
  }

  // Prefer plate → vehicle master lookup (WHEELSYS-REPORT §3 / §27.5) over stale app hints.
  let vehicleId = null;
  if (plate) {
    vehicleId = await resolveVehicleEntityId({
      db: admin.firestore(),
      franchiseId,
      station,
      plate,
      wheelsysCookie: cookie,
    });
  }
  if (!vehicleId && /^\d+$/.test(wheelsysVehicleId)) {
    vehicleId = wheelsysVehicleId;
  }
  if (!vehicleId) {
    throw new HttpsError(
        "not-found",
        "Could not resolve Wheelsys vehicle entity id for this vehicle.",
    );
  }

  try {
    const result = await getVehicleDamageHistory({
      vehicleId: Number(vehicleId),
      wheelsysCookie: cookie,
      encryptionKeyHex: encKey,
      franchiseId,
      station,
    });
    return {
      success: true,
      franchiseId,
      station,
      resolvedVehicleEntityId: String(vehicleId),
      plateNo: plate || null,
      ...result,
    };
  } catch (e) {
    throwWheelSysClientError(e);
  }
});

/** Build the read-only Pre-check-in context for a rental (CH only). */
exports.wheelsysGetPrecheckinContext = onCall(
    Object.assign({}, callableOpts, {timeoutSeconds: 120, memory: "512MiB"}),
    async (request) => {
      await assertCHStaff(request);
      const franchiseId = String(
          reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
      ).toUpperCase();
      const station = String(reqData(request, "station") || "ZRH").toUpperCase();
      const rentalId = String(reqData(request, "rentalId") || "").trim();
      const resNo = String(reqData(request, "resNo") || "").trim();
      const rntNo = String(reqData(request, "rntNo") || "").trim();
      const plateNo = String(
          reqData(request, "plateNo") || reqData(request, "plate") || "",
      ).trim();
      const date = String(reqData(request, "date") || "").trim();

      if (!rentalId && !resNo && !rntNo) {
        throw new HttpsError(
            "invalid-argument",
            "Provide rentalId, resNo or rntNo.",
        );
      }

      const encKey = encryptionKeyHex();
      const cookie = await resolveCookieForRequest(request, franchiseId, station);

      try {
        return await buildPrecheckinContext({
          db: admin.firestore(),
          cookie,
          encryptionKeyHex: encKey,
          franchiseId,
          station,
          rentalId,
          resNo,
          rntNo,
          plateNo,
          date,
        });
      } catch (e) {
        throwWheelSysClientError(e);
      }
    },
);

/** Submit PRECHECKIN for a rental (CH only). Never closes the rental. */
exports.wheelsysSubmitPrecheckin = onCall(
    Object.assign({}, callableOpts, {timeoutSeconds: 120, memory: "512MiB"}),
    async (request) => {
      const {uid, profile, franchiseId} = await assertCHStaff(request);
      const station = String(reqData(request, "station") || "ZRH").toUpperCase();
      const rentalId = String(reqData(request, "rentalId") || "").trim();
      const confirmCustomer = reqData(request, "confirmCustomer") === true;
      const confirmVehicle = reqData(request, "confirmVehicle") === true;
      const confirmDamagesReviewed = reqData(request, "confirmDamagesReviewed") === true;
      const confirmInsuranceReviewed = reqData(request, "confirmInsuranceReviewed") === true;
      const notes = String(reqData(request, "notes") || "").trim();
      const checkInMileageRaw = reqData(request, "checkInMileage");
      const checkInFuelRaw = reqData(request, "checkInFuel");
      const checkInMileage = checkInMileageRaw != null && checkInMileageRaw !== "" ?
    Number(checkInMileageRaw) : null;
      const checkInFuel = checkInFuelRaw != null && checkInFuelRaw !== "" ?
    Number(checkInFuelRaw) : null;
      const checkInUserIdRaw = reqData(request, "checkInUserId");
      const checkInUserId = checkInUserIdRaw != null && checkInUserIdRaw !== "" ?
    String(checkInUserIdRaw).trim() : "";
      const syncedAt = new Date().toISOString();

      console.info(
          "[WheelSys][Precheckin] wheelsysSubmitPrecheckin " +
          `rentalId=${rentalId} checkInMileage=${checkInMileage} checkInFuel=${checkInFuel}`,
      );

      /**
   * @param {string} message
   * @param {object} [extra]
   * @return {object}
   */
      function precheckinFailureResponse(message, extra = {}) {
        return {
          success: false,
          message,
          rentalId: Number(rentalId),
          rntNo: extra.rntNo || null,
          resNo: extra.resNo || null,
          operation: "PRECHECKIN",
          afterSave: null,
          syncedAt,
          retryable: extra.retryable !== false,
          warnings: extra.warnings || [],
          debug: extra.debug || null,
          missingRequiredFields: extra.missingRequiredFields || [],
        };
      }

      if (!/^\d+$/.test(rentalId)) {
        throw new HttpsError("invalid-argument", "A numeric rentalId is required.");
      }
      if (!confirmCustomer || !confirmVehicle ||
      !confirmDamagesReviewed || !confirmInsuranceReviewed) {
        throw new HttpsError(
            "failed-precondition",
            "All pre-check-in confirmations (customer, vehicle, damages, insurance) are required.",
        );
      }

      const cookie = await resolveCookieForRequest(request, franchiseId, station);
      const warnings = [];
      const sessionOp = await loadSessionOperator(
          admin.firestore(), franchiseId, station, uid,
      );
      const storedSessionUserId = sessionOp.userId || "";
      let effectiveCheckInUserId = checkInUserId;
      if (!/^\d+$/.test(effectiveCheckInUserId) && /^\d+$/.test(storedSessionUserId)) {
        effectiveCheckInUserId = storedSessionUserId;
      }

      let page;
      let form;
      let rntNo = null;
      let resNo = null;
      try {
        page = await fetchRentalPage(cookie, rentalId);
        form = parseCompleteRentalFormToPayload(page.html);
      } catch (e) {
        const errMsg = String(e && e.message ? e.message : e).slice(0, 1000);
        console.warn(`[WheelSys][Precheckin] submit rental.aspx load failed: ${errMsg}`);
        await writeUpdateLog({
          franchiseId, entityId: rentalId,
          updateType: "precheckin", operationType: "PRECHECKIN",
          rentalId, rntNo: null, resNo: null,
          responseSuccess: false, responsePreview: errMsg,
          createdBy: uid,
        }).catch((err) => console.warn("wheelsysSubmitPrecheckin log", err.message));
        return precheckinFailureResponse(
            errMsg || "Could not load rental.aspx for pre-check-in.",
            {retryable: /session expired|sign in/i.test(errMsg)},
        );
      }

      const vehicle = mapVehicle(form);
      const customer = mapCustomer(form);
      const vehicleId = Number(vehicle.vehicleId);
      const plateNo = String(vehicle.plateNo || "").trim();
      const driverId = Number(customer.driverId);
      const rental = mapRental(form, rentalId);
      rntNo = rental.rntNo;
      resNo = rental.resNo;

      if (!vehicleId || !plateNo) {
        const message = "Vehicle is missing in rental.aspx.";
        await writeUpdateLog({
          franchiseId, entityId: rentalId,
          updateType: "precheckin", operationType: "PRECHECKIN",
          rentalId, rntNo, resNo,
          responseSuccess: false, responsePreview: message,
          createdBy: uid,
        }).catch((err) => console.warn("wheelsysSubmitPrecheckin log", err.message));
        return precheckinFailureResponse(message, {rntNo, resNo, retryable: false});
      }
      if (!driverId) {
        const message = "Driver is missing in rental.aspx.";
        await writeUpdateLog({
          franchiseId, entityId: rentalId,
          updateType: "precheckin", operationType: "PRECHECKIN",
          rentalId, rntNo, resNo,
          responseSuccess: false, responsePreview: message,
          createdBy: uid,
        }).catch((err) => console.warn("wheelsysSubmitPrecheckin log", err.message));
        return precheckinFailureResponse(message, {rntNo, resNo, retryable: false});
      }

      const validation = validatePrecheckinForm(form, page.html);
      if (!validation.ready) {
        const blockers = (validation.blockers || []).join(", ");
        const message = `Pre-check-in blocked: missing ${blockers || "required fields"}.`;
        await writeUpdateLog({
          franchiseId, entityId: rentalId,
          updateType: "precheckin", operationType: "PRECHECKIN",
          rentalId, rntNo, resNo,
          responseSuccess: false, responsePreview: message,
          createdBy: uid,
        }).catch((err) => console.warn("wheelsysSubmitPrecheckin log", err.message));
        return precheckinFailureResponse(message, {
          rntNo,
          resNo,
          retryable: false,
          missingRequiredFields: validation.missingRequiredFields || [],
        });
      }

      logPrecheckinSubmitFields(form, rentalId);

      let result;
      try {
        result = await submitPrecheckin({
          cookie,
          rentalId,
          page,
          form,
          validation,
          checkInMileage: Number.isFinite(checkInMileage) ? checkInMileage : null,
          checkInFuel: Number.isFinite(checkInFuel) ? checkInFuel : null,
          checkInUserId: effectiveCheckInUserId || null,
          storedSessionUserId: storedSessionUserId || null,
        });
      } catch (e) {
        const errMsg = String(e && e.message ? e.message : e).slice(0, 1000);
        await writeUpdateLog({
          franchiseId, entityId: rentalId,
          updateType: "precheckin", operationType: "PRECHECKIN",
          rentalId, rntNo, resNo,
          responseSuccess: false, responsePreview: errMsg,
          createdBy: uid,
        }).catch((err) => console.warn("wheelsysSubmitPrecheckin log", err.message));
        return precheckinFailureResponse(
            errMsg || "Pre-check-in submit failed.",
            {rntNo, resNo, warnings},
        );
      }

      let noteSaved = null;
      if (result.success && notes) {
        const creatorId = resolveCreatorId({profile, previewFields: {}});
        const creatorFullName = profileCreatorFullName(profile);
        if (creatorId != null && creatorFullName) {
          try {
            noteSaved = await saveEntityNote(cookie, {
              entityKey: rentalId,
              domain: WHEELSYS_DOMAINS.rental,
              noteText: notes,
              creatorId,
              creatorFullName,
            });
          } catch (err) {
            console.warn("wheelsysSubmitPrecheckin note save", err.message);
          }
        }
      }

      const debug = result.debug ? {
        httpStatus: result.debug.httpStatus,
        responseLength: result.debug.responseLength,
        containsAfterSave: result.debug.containsAfterSave,
        containsPrecheckin: result.debug.containsPrecheckin,
        containsRecordChanged: result.debug.containsRecordChanged,
        containsValidation: result.debug.containsValidation,
        containsRequiredError: result.debug.containsRequiredError,
        postbackSource: result.debug.postbackSource || null,
        missingRequiredFields: result.missingRequiredFields ||
      result.debug.missingRequiredFields || [],
        requiredErrorSnippets: (result.debug.requiredErrorSnippets || [])
            .map((s) => String(s).slice(0, 300)),
        sanitizedSnippet: result.debug.sanitizedSnippet ?
      String(result.debug.sanitizedSnippet).slice(0, 500) : null,
      } : null;

      await writeUpdateLog({
        franchiseId, entityId: rentalId,
        updateType: "precheckin", operationType: "PRECHECKIN",
        rentalId, rntNo, resNo,
        responseSuccess: result.success,
        responsePreview: result.message || (result.success ? "PRECHECKIN ok" : "PRECHECKIN failed"),
        errorMessage: result.success ? null : (result.message || null),
        noteSaved: Boolean(noteSaved),
        createdBy: uid,
      }).catch((err) => console.warn("wheelsysSubmitPrecheckin log", err.message));

      if (!result.success) {
        return {
          success: false,
          message: result.message || "WheelSys pre-check-in was not confirmed.",
          rentalId: Number(rentalId),
          rntNo,
          resNo,
          operation: "PRECHECKIN",
          afterSave: result.afterSave || null,
          syncedAt,
          retryable: Boolean(result.retryable),
          warnings,
          debug,
          missingRequiredFields: result.missingRequiredFields ||
        (result.debug && result.debug.missingRequiredFields) || [],
        };
      }

      return {
        success: true,
        message: result.message || "Pre-check-in completed.",
        rentalId: Number(rentalId),
        rntNo,
        resNo,
        operation: "PRECHECKIN",
        afterSave: result.afterSave || null,
        syncedAt,
        warnings,
        debug,
      };
    });

module.exports.callableOpts = callableOpts;
