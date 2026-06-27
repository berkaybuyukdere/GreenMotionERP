#!/usr/bin/env node
/* eslint-disable max-len */
/**
 * WheelSys fleet chart inventory + Firebase araclar / vehicleCategories parity.
 *
 * Read-only by default. Pass --apply to write safe partial merges:
 *   - wheelsysVehicleId, wheelsysPlateCanonical, wheelsysEntitySyncStatus (entity link)
 *   - kategori from WheelSys fleet group (only when changed)
 *   - missing vehicleCategories docs for WheelSys groups
 *
 * Never overwrites hasarKayitlari, checkInKayitlari, or other operational fields.
 *
 * Usage:
 *   cd functions
 *   export WHEELSYS_API_KEY="$(firebase functions:secrets:access WHEELSYS_API_KEY)"
 *   node scripts/wheelsys-fleet-inventory.js
 *   node scripts/wheelsys-fleet-inventory.js --apply
 *   node scripts/wheelsys-fleet-inventory.js --json /tmp/wheelsys-fleet.json
 */

const crypto = require("crypto");
const admin = require("firebase-admin");
const {fetchWheelSysFleetChart} = require("../wheelsys/fleetChart");
const {loadActiveSessionCookie} = require("../wheelsys/sessionStore");

const PROJECT_ID = process.env.GCLOUD_PROJECT ||
  process.env.GCP_PROJECT || "greenmotionapp-33413";
const FRANCHISE = (process.env.WHEELSYS_FRANCHISE || "CH").toUpperCase();
const STATION = (process.env.WHEELSYS_STATION || "ZRH").toUpperCase();

if (!admin.apps.length) {
  admin.initializeApp({projectId: PROJECT_ID});
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
 * Mirror iOS WheelSysPlateNormalizer.canonical
 * @param {string} raw
 * @return {string}
 */
function canonicalPlate(raw) {
  return String(raw || "")
      .normalize("NFKC")
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, "");
}

/**
 * Mirror VehicleCategory.normalizeName
 * @param {string} raw
 * @return {string}
 */
function normalizeCategory(raw) {
  return String(raw || "")
      .trim()
      .replace(/\s+/g, " ")
      .toUpperCase();
}

/**
 * @param {string} name
 * @return {string}
 */
function categoryDocId(name) {
  return normalizeCategory(name)
      .replace(/ /g, "_")
      .replace(/\//g, "-");
}

/**
 * @param {FirebaseFirestore.Firestore} firestore
 * @return {Promise<object[]>}
 */
async function loadFirebaseVehicles(firestore) {
  const snap = await firestore
      .collection("franchises").doc(FRANCHISE)
      .collection("araclar")
      .get();
  return snap.docs.map((doc) => {
    const d = doc.data() || {};
    return {
      docId: doc.id,
      id: d.id || doc.id,
      plaka: String(d.plaka || ""),
      marka: String(d.marka || ""),
      model: String(d.model || ""),
      kategori: String(d.kategori || ""),
      isDeleted: d.isDeleted === true,
      wheelsysVehicleId: d.wheelsysVehicleId != null ?
        String(d.wheelsysVehicleId) : null,
      wheelsysPlateCanonical: d.wheelsysPlateCanonical != null ?
        String(d.wheelsysPlateCanonical) : null,
      wheelsysEntitySyncStatus: d.wheelsysEntitySyncStatus != null ?
        String(d.wheelsysEntitySyncStatus) : null,
      hasarCount: Array.isArray(d.hasarKayitlari) ? d.hasarKayitlari.length : 0,
      checkInCount: Array.isArray(d.checkInKayitlari) ?
        d.checkInKayitlari.length : 0,
      plateCanonical: canonicalPlate(d.plaka),
    };
  });
}

/**
 * @param {FirebaseFirestore.Firestore} firestore
 * @return {Promise<string[]>}
 */
async function loadFirebaseCategories(firestore) {
  const snap = await firestore
      .collection("franchises").doc(FRANCHISE)
      .collection("vehicleCategories")
      .orderBy("name")
      .get();
  return snap.docs.map((doc) => {
    const d = doc.data() || {};
    return normalizeCategory(d.name || doc.id);
  }).filter(Boolean);
}

/**
 * @param {object[]} fleetVehicles
 * @param {object[]} firebaseVehicles
 * @return {object}
 */
function buildMatchReport(fleetVehicles, firebaseVehicles) {
  const activeFirebase = firebaseVehicles.filter((v) => !v.isDeleted);
  const fleetByPlate = new Map();
  for (const v of fleetVehicles) {
    const key = canonicalPlate(v.plate);
    if (!key) continue;
    if (!fleetByPlate.has(key)) fleetByPlate.set(key, []);
    fleetByPlate.get(key).push(v);
  }

  const fleetById = new Map(
      fleetVehicles.map((v) => [String(v.vehicleId), v]),
  );

  const matched = [];
  const unmatchedFirebase = [];
  const ambiguousFirebase = [];
  const categoryMismatches = [];
  const idMismatches = [];

  for (const arac of activeFirebase) {
    const matches = fleetByPlate.get(arac.plateCanonical) || [];
    if (matches.length === 0) {
      unmatchedFirebase.push(arac);
      continue;
    }
    if (matches.length > 1) {
      ambiguousFirebase.push({arac, fleetCandidates: matches});
      continue;
    }
    const fleet = matches[0];
    const fleetCategory = normalizeCategory(fleet.group);
    const entry = {
      aracDocId: arac.docId,
      plate: arac.plaka,
      plateCanonical: arac.plateCanonical,
      firebaseCategory: normalizeCategory(arac.kategori),
      wheelsysCategory: fleetCategory,
      wheelsysVehicleId: String(fleet.vehicleId),
      wheelsysModel: fleet.model,
      categoryMismatch: fleetCategory !== normalizeCategory(arac.kategori),
      idMismatch: arac.wheelsysVehicleId &&
        arac.wheelsysVehicleId !== String(fleet.vehicleId),
      storedVehicleId: arac.wheelsysVehicleId,
      hasarCount: arac.hasarCount,
      checkInCount: arac.checkInCount,
    };
    matched.push(entry);
    if (entry.categoryMismatch) categoryMismatches.push(entry);
    if (entry.idMismatch) idMismatches.push(entry);
  }

  const firebasePlateSet = new Set(
      activeFirebase.map((v) => v.plateCanonical).filter(Boolean),
  );
  const fleetOnly = fleetVehicles.filter((v) => {
    const key = canonicalPlate(v.plate);
    return key && !firebasePlateSet.has(key);
  });

  const wheelsysCategories = [...new Set(
      fleetVehicles.map((v) => normalizeCategory(v.group)).filter(Boolean),
  )].sort();

  return {
    fleetVehicleCount: fleetVehicles.length,
    firebaseActiveCount: activeFirebase.length,
    matchedCount: matched.length,
    unmatchedFirebaseCount: unmatchedFirebase.length,
    ambiguousFirebaseCount: ambiguousFirebase.length,
    fleetOnlyCount: fleetOnly.length,
    categoryMismatchCount: categoryMismatches.length,
    idMismatchCount: idMismatches.length,
    wheelsysCategories,
    matched,
    unmatchedFirebase: unmatchedFirebase.map((a) => ({
      docId: a.docId,
      plaka: a.plaka,
      kategori: a.kategori,
      wheelsysVehicleId: a.wheelsysVehicleId,
      hasarCount: a.hasarCount,
    })),
    ambiguousFirebase: ambiguousFirebase.map(({arac, fleetCandidates}) => ({
      docId: arac.docId,
      plaka: arac.plaka,
      candidates: fleetCandidates.map((c) => ({
        vehicleId: c.vehicleId,
        plate: c.plate,
        group: c.group,
      })),
    })),
    fleetOnly: fleetOnly.map((v) => ({
      vehicleId: v.vehicleId,
      plate: v.plate,
      group: v.group,
      model: v.model,
    })),
    fleetByIdSize: fleetById.size,
  };
}

/**
 * @param {object} report
 * @param {string[]} firebaseCategories
 * @return {string[]}
 */
function missingCategoryDocs(report, firebaseCategories) {
  const existing = new Set(firebaseCategories.map(normalizeCategory));
  return report.wheelsysCategories.filter((c) => !existing.has(c));
}

/**
 * @param {object} report
 * @return {Promise<object>}
 */
async function applySafeSync(report) {
  const batchLimit = 400;
  let batch = db.batch();
  let ops = 0;
  let vehicleWrites = 0;
  let categoryWrites = 0;

  const commitIfNeeded = async (force = false) => {
    if (ops === 0) return;
    if (!force && ops < batchLimit) return;
    await batch.commit();
    batch = db.batch();
    ops = 0;
  };

  const firebaseCategories = await loadFirebaseCategories(db);
  const missingCats = missingCategoryDocs(report, firebaseCategories);
  for (const name of missingCats) {
    const ref = db.collection("franchises").doc(FRANCHISE)
        .collection("vehicleCategories").doc(categoryDocId(name));
    batch.set(ref, {
      id: categoryDocId(name),
      name,
      franchiseId: FRANCHISE,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "wheelsys_fleet_inventory",
    }, {merge: true});
    ops += 1;
    categoryWrites += 1;
    await commitIfNeeded();
  }

  for (const row of report.matched) {
    const ref = db.collection("franchises").doc(FRANCHISE)
        .collection("araclar").doc(row.aracDocId);
    const payload = {
      wheelsysVehicleId: row.wheelsysVehicleId,
      wheelsysPlateCanonical: row.plateCanonical,
      wheelsysEntitySyncStatus: "matched",
      wheelsysEntityVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (row.categoryMismatch && row.wheelsysCategory) {
      payload.kategori = row.wheelsysCategory;
      payload.wheelsysCategorySyncedAt =
        admin.firestore.FieldValue.serverTimestamp();
    }
    batch.set(ref, payload, {merge: true});
    ops += 1;
    vehicleWrites += 1;
    await commitIfNeeded();
  }

  for (const row of report.unmatchedFirebase) {
    const ref = db.collection("franchises").doc(FRANCHISE)
        .collection("araclar").doc(row.docId);
    batch.set(ref, {
      wheelsysEntitySyncStatus: "unmatched",
      wheelsysEntityVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    ops += 1;
    vehicleWrites += 1;
    await commitIfNeeded();
  }

  await commitIfNeeded(true);

  return {vehicleWrites, categoryWrites, missingCats};
}

/**
 * @return {Promise<void>}
 */
async function main() {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const jsonPath = (() => {
    const idx = args.indexOf("--json");
    return idx >= 0 ? args[idx + 1] : null;
  })();

  const encKey = encryptionKeyHex();
  if (!encKey) {
    console.error("Missing WHEELSYS_API_KEY (decrypt session cookie).");
    process.exit(1);
  }

  console.log(`[wheelsys-fleet-inventory] project=${PROJECT_ID} franchise=${FRANCHISE} station=${STATION}`);

  const cookie = await loadActiveSessionCookie({
    db,
    franchiseId: FRANCHISE,
    station: STATION,
    encryptionKeyHex: encKey,
  });

  console.log("[wheelsys-fleet-inventory] fetching fleet chart…");
  const fleet = await fetchWheelSysFleetChart({
    wheelsysCookie: cookie,
    station: STATION,
  });

  const firebaseVehicles = await loadFirebaseVehicles(db);
  const firebaseCategories = await loadFirebaseCategories(db);
  const report = buildMatchReport(fleet.vehicles, firebaseVehicles);
  const missingCats = missingCategoryDocs(report, firebaseCategories);

  const summary = {
    generatedAt: new Date().toISOString(),
    franchise: FRANCHISE,
    station: STATION,
    fleet: {
      vehicles: report.fleetVehicleCount,
      events: fleet.eventsCount,
      categories: report.wheelsysCategories,
    },
    firebase: {
      activeVehicles: report.firebaseActiveCount,
      categories: firebaseCategories,
      missingCategoryDocs: missingCats,
    },
    matching: {
      matched: report.matchedCount,
      unmatchedFirebase: report.unmatchedFirebaseCount,
      ambiguousFirebase: report.ambiguousFirebaseCount,
      fleetOnly: report.fleetOnlyCount,
      categoryMismatches: report.categoryMismatchCount,
      storedIdMismatches: report.idMismatchCount,
    },
    samples: {
      categoryMismatches: report.matched
          .filter((r) => r.categoryMismatch)
          .slice(0, 15)
          .map((r) => ({
            plate: r.plate,
            firebase: r.firebaseCategory,
            wheelsys: r.wheelsysCategory,
          })),
      unmatchedFirebase: report.unmatchedFirebase.slice(0, 15),
      fleetOnly: report.fleetOnly.slice(0, 15),
      ambiguousFirebase: report.ambiguousFirebase.slice(0, 5),
    },
  };

  console.log(JSON.stringify(summary, null, 2));

  if (jsonPath) {
    const fs = require("fs");
    fs.writeFileSync(jsonPath, JSON.stringify({
      summary,
      fleetVehicles: fleet.vehicles,
      report,
    }, null, 2));
    console.log(`[wheelsys-fleet-inventory] wrote ${jsonPath}`);
  }

  if (apply) {
    console.log("[wheelsys-fleet-inventory] applying safe partial merges…");
    const result = await applySafeSync(report);
    console.log(JSON.stringify({apply: true, ...result}, null, 2));
  } else {
    console.log("[wheelsys-fleet-inventory] dry-run only (pass --apply to write merges)");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
