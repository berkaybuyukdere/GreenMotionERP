/**
 * Short-lived WheelSys vehicle master cache (avoid back-to-back GetData 500s).
 */
const admin = require("firebase-admin");

const CACHE_DOC = "vehicleMasterCache";
const DEFAULT_TTL_MS = 20 * 60 * 1000;

/**
 * @param {object[]} vehicles
 * @return {object[]}
 */
function slimVehicles(vehicles) {
  return (vehicles || []).map((v) => ({
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
    isDefleeted: v.isDefleeted,
  }));
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {string} station
 * @param {object} fleet
 */
async function saveVehicleMasterCache(db, franchiseId, station, fleet) {
  const fid = String(franchiseId || "CH").toUpperCase();
  const st = String(station || "ZRH").toUpperCase();
  await db.collection("franchises").doc(fid)
      .collection("wheelsysScratch").doc(CACHE_DOC)
      .set({
        station: st,
        vehicles: slimVehicles(fleet.vehicles),
        stats: fleet.stats || null,
        duplicateWarnings: fleet.duplicateWarnings || [],
        truncated: fleet.truncated === true,
        totalCount: fleet.totalCount || (fleet.vehicles || []).length,
        cachedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + DEFAULT_TTL_MS,
        ),
      });
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {string} station
 * @param {number} [maxAgeMs]
 * @return {Promise<object|null>}
 */
async function loadVehicleMasterCache(
    db, franchiseId, station, maxAgeMs = DEFAULT_TTL_MS,
) {
  const fid = String(franchiseId || "CH").toUpperCase();
  const st = String(station || "ZRH").toUpperCase();
  const snap = await db.collection("franchises").doc(fid)
      .collection("wheelsysScratch").doc(CACHE_DOC)
      .get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  if (String(data.station || "").toUpperCase() !== st) return null;
  const expiresMs = data.expiresAt && data.expiresAt.toMillis ?
    data.expiresAt.toMillis() : 0;
  if (expiresMs && expiresMs <= Date.now()) return null;
  const cachedAtMs = data.cachedAt && data.cachedAt.toMillis ?
    data.cachedAt.toMillis() : 0;
  if (cachedAtMs && Date.now() - cachedAtMs > maxAgeMs) return null;
  const vehicles = Array.isArray(data.vehicles) ? data.vehicles : [];
  if (!vehicles.length) return null;
  return {
    station: st,
    vehicles,
    stats: data.stats || null,
    duplicateWarnings: data.duplicateWarnings || [],
    truncated: data.truncated === true,
    totalCount: data.totalCount || vehicles.length,
    fromCache: true,
    cachedAtMs,
  };
}

module.exports = {
  saveVehicleMasterCache,
  loadVehicleMasterCache,
  CACHE_DOC,
};
