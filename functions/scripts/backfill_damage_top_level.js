/* eslint-disable require-jsdoc, max-len */
/**
 * Backfill top-level damage records from legacy nested vehicle arrays.
 *
 * Source:
 * - /araclar/{vehicleId}.hasarKayitlari[]
 * - /franchises/{FRANCHISE}/araclar/{vehicleId}.hasarKayitlari[]   (scoped)
 *
 * Target:
 * - /hasarKayitlari/{damageId}   (legacy root)
 * - /franchises/{FRANCHISE}/hasarKayitlari/{damageId}   (scoped)
 *
 * Idempotent:
 * - Writes with merge=true; safe to rerun.
 *
 * Usage:
 *   cd functions
 *   node scripts/backfill_damage_top_level.js --project greenmotionapp-33413 --franchise CH --dry-run
 *   node scripts/backfill_damage_top_level.js --project greenmotionapp-33413 --franchise CH
 *
 * Auth:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 */

const admin = require("firebase-admin");

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {project: "", franchise: "CH", dryRun: false, limitVehicles: 0};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--project") out.project = args[++i] || "";
    else if (a === "--franchise") out.franchise = (args[++i] || "CH").toUpperCase();
    else if (a === "--dry-run") out.dryRun = true;
    else if (a === "--limit-vehicles") out.limitVehicles = Number(args[++i] || "0") || 0;
  }
  if (!out.project) throw new Error("Missing --project <firebaseProjectId>");
  return out;
}

async function backfillFromVehicles(db, vehiclesQuery, targetCollectionRef, franchise, dryRun) {
  const snap = await vehiclesQuery.get();
  let vehiclesProcessed = 0;
  let damagesFound = 0;
  let damagesWritten = 0;

  const batchSize = 350;
  let batch = db.batch();
  let ops = 0;

  for (const doc of snap.docs) {
    vehiclesProcessed++;
    const vehicleId = doc.id;
    const data = doc.data() || {};
    const arr = Array.isArray(data.hasarKayitlari) ? data.hasarKayitlari : [];
    for (const hasar of arr) {
      if (!hasar || !hasar.id) continue;
      damagesFound++;

      const damageId = String(hasar.id);
      const ref = targetCollectionRef.doc(damageId);
      const patch = {
        ...hasar,
        aracId: hasar.aracId || vehicleId,
        franchiseId: (hasar.franchiseId || franchise).toUpperCase(),
      };

      damagesWritten++;
      if (!dryRun) {
        batch.set(ref, patch, {merge: true});
        ops++;
        if (ops >= batchSize) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }
    }
  }

  if (!dryRun && ops > 0) await batch.commit();
  return {vehiclesProcessed, damagesFound, damagesWritten};
}

async function main() {
  const {project, franchise, dryRun, limitVehicles} = parseArgs();
  admin.initializeApp({projectId: project});
  const db = admin.firestore();

  const modes = ["legacy", "scoped"];
  for (const mode of modes) {
    const vehiclesRef = (mode === "legacy") ?
      db.collection("araclar") :
      db.collection("franchises").doc(franchise).collection("araclar");

    const targetDamages = (mode === "legacy") ?
      db.collection("hasarKayitlari") :
      db.collection("franchises").doc(franchise).collection("hasarKayitlari");

    let q = vehiclesRef;
    if (limitVehicles > 0) q = q.limit(limitVehicles);

    const res = await backfillFromVehicles(db, q, targetDamages, franchise, dryRun);
    console.log(JSON.stringify({
      mode,
      franchise,
      dryRun,
      limitVehicles,
      ...res,
    }));
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

