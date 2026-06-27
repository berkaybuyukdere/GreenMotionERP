/**
 * WheelSys Vehicle Master ↔ Firebase araclar partial sync (safe merge only).
 */
/* eslint-disable max-len */

const admin = require("firebase-admin");
const {canonicalPlate} = require("./plateNormalize");

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
 * @param {string} franchiseId
 * @return {Promise<object[]>}
 */
async function loadFirebaseVehicles(firestore, franchiseId) {
  const snap = await firestore
      .collection("franchises").doc(String(franchiseId).toUpperCase())
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
 * @param {string} franchiseId
 * @return {Promise<string[]>}
 */
async function loadFirebaseCategories(firestore, franchiseId) {
  const snap = await firestore
      .collection("franchises").doc(String(franchiseId).toUpperCase())
      .collection("vehicleCategories")
      .orderBy("name")
      .get();
  return snap.docs.map((doc) => {
    const d = doc.data() || {};
    return normalizeCategory(d.name || doc.id);
  }).filter(Boolean);
}

/**
 * @param {object} vehicle WheelSys vehicle master row
 * @return {string}
 */
function wheelsysCategoryFromVehicle(vehicle) {
  const fromName = normalizeCategory(vehicle.categoryName);
  if (fromName) return fromName;
  return normalizeCategory(vehicle.carGroup || vehicle.effectiveCategory);
}

/**
 * @param {object[]} wheelsysVehicles resolved vehicle master rows
 * @param {object[]} firebaseVehicles
 * @return {object}
 */
function buildMatchReport(wheelsysVehicles, firebaseVehicles) {
  const activeFirebase = firebaseVehicles.filter((v) => !v.isDeleted);
  const wheelsysByPlate = new Map();
  for (const v of wheelsysVehicles) {
    const key = v.normalizedPlate || canonicalPlate(v.plateNo);
    if (!key) continue;
    if (!wheelsysByPlate.has(key)) wheelsysByPlate.set(key, []);
    wheelsysByPlate.get(key).push(v);
  }

  const matched = [];
  const unmatchedFirebase = [];
  const ambiguousFirebase = [];
  const categoryMismatches = [];
  const idMismatches = [];

  for (const arac of activeFirebase) {
    const matches = wheelsysByPlate.get(arac.plateCanonical) || [];
    if (matches.length === 0) {
      unmatchedFirebase.push(arac);
      continue;
    }
    if (matches.length > 1) {
      ambiguousFirebase.push({arac, wheelsysCandidates: matches});
      continue;
    }
    const ws = matches[0];
    const wheelsysCategory = wheelsysCategoryFromVehicle(ws);
    const entry = {
      aracDocId: arac.docId,
      plate: arac.plaka,
      plateCanonical: arac.plateCanonical,
      firebaseCategory: normalizeCategory(arac.kategori),
      wheelsysCategory,
      wheelsysVehicleId: String(ws.wheelsysVehicleId || ws.id),
      wheelsysModel: ws.modelName || "",
      wheelsysBrand: ws.brandName || "",
      wheelsysCarGroup: ws.carGroup || "",
      categoryMismatch: wheelsysCategory !== normalizeCategory(arac.kategori),
      idMismatch: arac.wheelsysVehicleId &&
        arac.wheelsysVehicleId !== String(ws.wheelsysVehicleId || ws.id),
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
  const wheelsysOnly = wheelsysVehicles.filter((v) => {
    const key = v.normalizedPlate || canonicalPlate(v.plateNo);
    return key && !firebasePlateSet.has(key);
  });

  const wheelsysCategories = [...new Set(
      wheelsysVehicles.map(wheelsysCategoryFromVehicle).filter(Boolean),
  )].sort();

  return {
    wheelsysVehicleCount: wheelsysVehicles.length,
    firebaseActiveCount: activeFirebase.length,
    matchedCount: matched.length,
    unmatchedFirebaseCount: unmatchedFirebase.length,
    ambiguousFirebaseCount: ambiguousFirebase.length,
    wheelsysOnlyCount: wheelsysOnly.length,
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
    ambiguousFirebase: ambiguousFirebase.map(({arac, wheelsysCandidates}) => ({
      docId: arac.docId,
      plaka: arac.plaka,
      candidates: wheelsysCandidates.map((c) => ({
        wheelsysVehicleId: c.wheelsysVehicleId || c.id,
        plateNo: c.plateNo,
        carGroup: c.carGroup,
        status: c.status,
      })),
    })),
    wheelsysOnly: wheelsysOnly.map((v) => ({
      wheelsysVehicleId: v.wheelsysVehicleId || v.id,
      plateNo: v.plateNo,
      carGroup: v.carGroup,
      categoryName: v.categoryName,
      modelName: v.modelName,
      status: v.status,
      isDefleeted: v.isDefleeted,
    })),
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
 * @param {object} p
 * @return {Promise<object>}
 */
async function applySafeSync(p) {
  const db = p.db || admin.firestore();
  const franchiseId = String(p.franchiseId || "CH").toUpperCase();
  const report = p.report;
  let vehicleWrites = 0;
  let categoryWrites = 0;
  let failedWrites = 0;
  const writeErrors = [];
  const BATCH_LIMIT = 400;

  let batch = db.batch();
  let batchOps = 0;

  const flushBatch = async () => {
    if (batchOps === 0) return;
    try {
      await batch.commit();
    } catch (e) {
      failedWrites += batchOps;
      writeErrors.push(String(e.message || e).slice(0, 300));
    } finally {
      batch = db.batch();
      batchOps = 0;
    }
  };

  const queueSet = async (ref, payload) => {
    try {
      batch.set(ref, payload, {merge: true});
      batchOps += 1;
      if (batchOps >= BATCH_LIMIT) await flushBatch();
      return true;
    } catch (e) {
      failedWrites += 1;
      writeErrors.push(String(e.message || e).slice(0, 300));
      return false;
    }
  };

  const firebaseCategories = p.firebaseCategories ||
    await loadFirebaseCategories(db, franchiseId);
  const missingCats = missingCategoryDocs(report, firebaseCategories);

  for (const name of missingCats) {
    const ref = db.collection("franchises").doc(franchiseId)
        .collection("vehicleCategories").doc(categoryDocId(name));
    const ok = await queueSet(ref, {
      id: categoryDocId(name),
      name,
      franchiseId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "wheelsys_vehicle_master",
    });
    if (ok) categoryWrites += 1;
  }

  for (const row of report.matched) {
    const ref = db.collection("franchises").doc(franchiseId)
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
    const ok = await queueSet(ref, payload);
    if (ok) vehicleWrites += 1;
  }

  for (const row of report.unmatchedFirebase) {
    const ref = db.collection("franchises").doc(franchiseId)
        .collection("araclar").doc(row.docId);
    const ok = await queueSet(ref, {
      wheelsysEntitySyncStatus: "unmatched",
      wheelsysEntityVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (ok) vehicleWrites += 1;
  }

  await flushBatch();

  return {
    vehicleWrites,
    categoryWrites,
    missingCats,
    failedWrites,
    writeErrors,
  };
}

/**
 * Preview or apply vehicle master sync.
 * @param {object} p
 * @return {Promise<object>}
 */
async function runVehicleMasterSync(p) {
  const db = p.db || admin.firestore();
  const franchiseId = String(p.franchiseId || "CH").toUpperCase();
  const wheelsysVehicles = p.wheelsysVehicles || [];
  const apply = p.apply === true;

  const firebaseVehicles = await loadFirebaseVehicles(db, franchiseId);
  const firebaseCategories = await loadFirebaseCategories(db, franchiseId);
  const report = buildMatchReport(wheelsysVehicles, firebaseVehicles);
  const missingCats = missingCategoryDocs(report, firebaseCategories);

  const summary = {
    franchise: franchiseId,
    wheelsysVehicleCount: report.wheelsysVehicleCount,
    firebaseActiveCount: report.firebaseActiveCount,
    matched: report.matchedCount,
    unmatchedFirebase: report.unmatchedFirebaseCount,
    unmatchedWheelSys: report.wheelsysOnlyCount,
    ambiguous: report.ambiguousFirebaseCount,
    categoryFixes: report.categoryMismatchCount,
    idMismatches: report.idMismatchCount,
    missingCategoryDocs: missingCats,
    wheelsysCategories: report.wheelsysCategories,
  };

  console.info(
      `[WheelSys][VehicleMasterSync] firebaseVehicles=${report.firebaseActiveCount} ` +
      `wheelSysVehicles=${report.wheelsysVehicleCount} matched=${report.matchedCount} ` +
      `unmatchedFirebase=${report.unmatchedFirebaseCount} unmatchedWheelSys=${report.wheelsysOnlyCount} ` +
      `written=0 failedWrites=0`,
  );

  let applyResult = null;
  if (apply) {
    applyResult = await applySafeSync({
      db,
      franchiseId,
      report,
      firebaseCategories,
    });
    console.info(
        `[WheelSys][VehicleMasterSync] firebaseVehicles=${report.firebaseActiveCount} ` +
        `wheelSysVehicles=${report.wheelsysVehicleCount} matched=${report.matchedCount} ` +
        `unmatchedFirebase=${report.unmatchedFirebaseCount} unmatchedWheelSys=${report.wheelsysOnlyCount} ` +
        `written=${applyResult.vehicleWrites + applyResult.categoryWrites} ` +
        `failedWrites=${applyResult.failedWrites}`,
    );
  }

  return {
    summary,
    report,
    apply: applyResult,
    dryRun: !apply,
  };
}

module.exports = {
  canonicalPlate,
  normalizeCategory,
  categoryDocId,
  loadFirebaseVehicles,
  loadFirebaseCategories,
  wheelsysCategoryFromVehicle,
  buildMatchReport,
  missingCategoryDocs,
  applySafeSync,
  runVehicleMasterSync,
};
