/**
 * Callable endpoints for WheelSys check-in sync (CH only).
 */
/* eslint-disable max-len */

const crypto = require("crypto");
const admin = require("firebase-admin");
const {defineSecret} = require("firebase-functions/params");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {loadActiveSessionCookie, saveSession, sessionDocRef} = require("./sessionStore");
const {
  fetchRentalPage,
  fetchFullRentalData,
  updateWheelsysCheckin,
  searchRentalsByRes,
  searchLocalExitsByRes,
  rentalPreviewLooksEmpty,
  saveEntityNote,
  parseInsuranceSummary,
  WHEELSYS_DOMAINS,
  BASE_URL,
} = require("./checkinSync");
const {
  fetchWheelSysFleetChart,
  findRentalEntityIdByPlate,
  FLEET_CHART_REQUEST_BODY,
  BASE_URL: WHEELSYS_BASE,
} = require("./fleetChart");
const {
  fetchJournalData,
  fetchJournalSnapshot,
  fetchJournalSnapshotWithFallback,
} = require("./journal");
const {fetchDailyViewTab, fetchDailyViewAll} = require("./dailyView");
const {searchBookingsList} = require("./bookingsList");
const {ERR: WHEELSYS_ERR, WheelsysClientError} = require("./client");
const {
  fetchBookingPage,
  searchAvailableVehicles,
  assignVehicleToBooking,
  combineDateTimeLocal,
  resolveBookingEntityId,
  resolveBookingContextForAssign,
} = require("./bookingAssignment");
const {buildFleetAuthCookie, cookiePresenceLog} = require("./cookieJar");

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
 * @param {object} request
 * @return {Promise<{uid: string, profile: object}>}
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
  const franchiseId = String(
      profile.franchiseId ||
      (request.data && request.data.franchiseId) ||
      DEFAULT_FRANCHISE,
  ).toUpperCase();
  if (!franchiseId.startsWith("CH")) {
    throw new HttpsError("permission-denied", "WheelSys sync is CH-only.");
  }
  const role = String(profile.role || "").toLowerCase();
  if (role === "garage") {
    throw new HttpsError("permission-denied", "Garage role cannot use WheelSys sync.");
  }
  return {uid, profile, franchiseId};
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
    });
  }
  throw e;
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
  try {
    return await loadActiveSessionCookie({
      db: admin.firestore(),
      franchiseId: p.franchiseId,
      station,
      encryptionKeyHex: encKey,
      fallbackCookie: "",
    });
  } catch (e) {
    throw new HttpsError("failed-precondition", e.message);
  }
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
    const cookie = await resolveCookie({franchiseId, station});
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
  const cookie = await resolveCookie({franchiseId, station});

  const full = await fetchFullRentalData(cookie, entityId);
  const f = full.fields;
  const expectedRes = String(reqData(request, "expectedResNo") || "").trim().toUpperCase();

  if (rentalPreviewLooksEmpty(f)) {
    throw new HttpsError(
        "not-found",
        "Invalid WheelSys entity ID. Use the number from rental.aspx?entityId=… " +
        "(not the RES number). Example: 18781 for RES-16745.",
    );
  }

  if (expectedRes && f.resNo) {
    const loaded = String(f.resNo).trim().toUpperCase();
    const variants = resQueryVariants(expectedRes);
    if (!variants.includes(loaded) && !variants.some((v) => loaded.includes(v.replace(/^RES-|^RNT-/, "")))) {
      throw new HttpsError(
          "failed-precondition",
          `Entity #${entityId} is ${loaded}, not ${expectedRes}. Check the entity ID.`,
      );
    }
  }

  await upsertRentalCache({
    franchiseId,
    entityId,
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

  return {
    entityId,
    fields: f,
    vehicleEntityId: full.vehicleEntityId,
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
    dateTo: f.dateTo,
    timeTo: f.timeTo,
    plate: f.plate,
    vehicleModel: f.vehicleModel || (vm && vm.model) || "",
    raNo: f.raNo,
    resNo: f.resNo,
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

  if (!entityId) {
    throw new HttpsError("invalid-argument", "entityId is required.");
  }

  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  const defaultDate =
    `${pad(now.getDate())}/${pad(now.getMonth() + 1)}/${now.getFullYear()}`;
  const defaultTime = `${pad(now.getHours())}:${pad(now.getMinutes())}`;

  const cookie = await resolveCookie({franchiseId, station});
  const db = admin.firestore();

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
    result = await updateWheelsysCheckin({
      entityId: resolvedEntityId,
      checkInMileage,
      checkInFuel,
      checkInUserId,
      checkInDate: checkInDate || defaultDate,
      checkInTime: checkInTime || defaultTime,
      wheelsysCookie: cookie,
      checkInCondition: reqData(request, "checkInCondition"),
      verifyAfterSave: true,
      plate: resolvedPlate || plate,
      fleetCarIdHint: resolvedFleetCarId,
      vehicleEntityIdHint: vehicleEntityIdHint || String(previewFields.vehicleEntityId || ""),
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
    throw new HttpsError("internal", e.message || "WheelSys update failed.");
  }

  await Promise.allSettled([
    writeUpdateLog({
      franchiseId, entityId: resolvedEntityId,
      resNo: resolvedResNo, plateNo: resolvedPlate,
      updateType: "checkin",
      oldMileage, newMileage: result.mileageTo,
      oldFuel, newFuel: result.fuelTo,
      responseSuccess: result.success,
      responsePreview: result.responsePreview,
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
    throw new HttpsError(
        "unknown",
        result.errorMessage || "WheelSys did not confirm success. Check audit log.",
    );
  }

  const savedNotes = {rentalNote: null, vehicleNote: null, errors: []};
  if (addNotes) {
    const creatorId = resolveCreatorId({
      checkInUserId: result.checkInUserId || checkInUserId,
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
          `Vehicle master synced from rental ${resolvedRaNo || resolvedResNo}.`);

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
      if (vehicleId && /^\d+$/.test(String(vehicleId))) {
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

  return {
    success: true,
    message: savedNotes.errors.length ?
      "WheelSys check-in saved. Some notes could not be saved." :
      "WheelSys check-in and vehicle master sync successful.",
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

  const cookie = await resolveCookie({franchiseId, station});
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

/** Admin: store encrypted WheelSys session cookie (never returned to client). */
exports.wheelsysSaveSession = onCall(callableOpts, async (request) => {
  const {uid, franchiseId} = await assertCHStaff(request);

  const cookiePlain = String(reqData(request, "sessionCookie") || "").trim();
  if (!cookiePlain || cookiePlain.length < 20) {
    throw new HttpsError("invalid-argument", "sessionCookie is required.");
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

  await saveSession({
    db: admin.firestore(),
    franchiseId,
    station,
    cookiePlain,
    encryptionKeyHex: encKey,
    createdBy: uid,
    ttlHours,
  });

  return {success: true, station, expiresInHours: ttlHours};
});

/** Check whether an encrypted WheelSys session exists and still works. */
exports.wheelsysSessionStatus = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const db = admin.firestore();
  const snap = await sessionDocRef(db, franchiseId, station).get();
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
    const cookie = await resolveCookie({franchiseId, station});
    const probe = await fetch(`${BASE_URL}/ui/manage/master/rentals.aspx`, {
      headers: {"Cookie": cookie, "User-Agent": "VehicleSentinel/1.0"},
      redirect: "follow",
    });
    const html = String(await probe.text());
    isValid = probe.ok &&
      !( /login|sign.?in/i.test(html) && !html.includes("/ui/manage/") );
    fleetChartValid = await probeFleetChartAccess(cookie);
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
    const authCookie = buildFleetAuthCookie(cookie);
    if (!authCookie) return false;

    const pageUrl = `${WHEELSYS_BASE}/ui/dashboards/fleetchart.aspx`;
    const dataUrl = `${WHEELSYS_BASE}/ui/dashboards/fleetchart.aspx/GetFleetchartData`;
    const probeRes = await fetch(dataUrl, {
      method: "POST",
      headers: {
        "Accept": "*/*",
        "Content-Type": "application/json; charset=UTF-8",
        "X-Requested-With": "XMLHttpRequest",
        "Origin": WHEELSYS_BASE,
        "Referer": pageUrl,
        "User-Agent": "Mozilla/5.0",
        "Cookie": authCookie,
      },
      body: JSON.stringify(FLEET_CHART_REQUEST_BODY),
    });
    const probeText = String(await probeRes.text());
    let outer = null;
    try {
      outer = JSON.parse(probeText);
    } catch (_) {
      outer = null;
    }
    const pageOk = probeRes.ok;
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
      await resolveCookie({franchiseId, station});

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
  const cookie = await resolveCookie({franchiseId, station});
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
  const cookie = await resolveCookie({franchiseId, station});
  try {
    const journal = useFallback ?
      await fetchJournalSnapshotWithFallback(cookie, {selectedDate, station}) :
      await fetchJournalSnapshot(cookie, {selectedDate, station});
    return {success: true, ...journal};
  } catch (e) {
    throwWheelSysClientError(e);
  }
});

/** Single Daily View tab (checkouts|checkins|nonrevenue|available|bookings). */
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
  const cookie = await resolveCookie({franchiseId, station});
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

/** All five Daily View tabs in one round-trip. */
exports.wheelsysGetDailyViewAll = onCall(callableOpts, async (request) => {
  await assertCHStaff(request);
  const franchiseId = String(
      reqData(request, "franchiseId") || DEFAULT_FRANCHISE,
  ).toUpperCase();
  const station = String(reqData(request, "station") || "ZRH").toUpperCase();
  const selectedDate = String(reqData(request, "selectedDate") || "").trim();
  const cookie = await resolveCookie({franchiseId, station});
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
  const cookie = await resolveCookie({franchiseId, station});
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
  const cookie = await resolveCookie({franchiseId, station});

  const resolved = await resolveBookingEntityId(cookie, hintId, {resNo, displayDocNo});
  const page = await fetchBookingPage(cookie, resolved.entityId);
  const f = page.fields;
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
    driverName: f.driver || "",
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
  const cookie = await resolveCookie({franchiseId, station});

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
  if (requestedCarGroup && requestedCarGroup !== "-") {
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

  const cookie = await resolveCookie({franchiseId, station});
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

  const cookie = await resolveCookie({franchiseId, station});
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

module.exports.callableOpts = callableOpts;
