/* eslint-disable require-jsdoc, max-len */
/**
 * Backfill shadow Timestamp fields for Apple-epoch legacy date doubles.
 *
 * Targets:
 * - office_operations: add `dateTs` (Timestamp) from legacy `date` Double
 * - vacationTimes: add `startDateTs`, `endDateTs`, `createdAtTs` from legacy doubles
 *
 * Idempotent:
 * - Skips docs that already have the shadow fields
 *
 * Supports both legacy flat path and scoped path:
 * - /{collection}/{docId}
 * - /franchises/{FRANCHISE}/ {collection}/{docId}
 *
 * Usage:
 *   cd functions
 *   node scripts/backfill_date_shadows.js --project greenmotionapp-33413 --franchise CH --dry-run
 *   node scripts/backfill_date_shadows.js --project greenmotionapp-33413 --franchise CH
 *
 * Auth:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
 */

const admin = require("firebase-admin");

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {project: "", franchise: "CH", dryRun: false, limit: 0};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--project") out.project = args[++i] || "";
    else if (a === "--franchise") out.franchise = (args[++i] || "CH").toUpperCase();
    else if (a === "--dry-run") out.dryRun = true;
    else if (a === "--limit") out.limit = Number(args[++i] || "0") || 0;
  }
  if (!out.project) {
    throw new Error("Missing --project <firebaseProjectId>");
  }
  return out;
}

function baseDate2001UnixSeconds() {
  // 2001-01-01T00:00:00Z in unix seconds
  return 978307200;
}

function legacyAppleDoubleToDate(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  // Legacy is seconds since 2001-01-01 (Apple epoch style used in this codebase).
  const unixSeconds = baseDate2001UnixSeconds() + n;
  const d = new Date(unixSeconds * 1000);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

async function backfillOfficeOperations(db, rootColRef, dryRun, limit) {
  let q = rootColRef;
  if (limit > 0) q = q.limit(limit);
  const snap = await q.get();
  let processed = 0;
  let updated = 0;
  const batchSize = 400;
  let batch = db.batch();
  let batchOps = 0;

  for (const doc of snap.docs) {
    processed++;
    const data = doc.data() || {};
    if (data.dateTs) continue;
    const d = legacyAppleDoubleToDate(data.date);
    if (!d) continue;
    updated++;
    if (!dryRun) {
      batch.set(doc.ref, {dateTs: admin.firestore.Timestamp.fromDate(d)}, {merge: true});
      batchOps++;
      if (batchOps >= batchSize) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }
  }
  if (!dryRun && batchOps > 0) {
    await batch.commit();
  }
  return {processed, updated};
}

async function backfillVacationTimes(db, rootColRef, dryRun, limit) {
  let q = rootColRef;
  if (limit > 0) q = q.limit(limit);
  const snap = await q.get();
  let processed = 0;
  let updated = 0;
  const batchSize = 400;
  let batch = db.batch();
  let batchOps = 0;

  for (const doc of snap.docs) {
    processed++;
    const data = doc.data() || {};
    const patch = {};

    if (!data.startDateTs) {
      const d = legacyAppleDoubleToDate(data.startDate);
      if (d) patch.startDateTs = admin.firestore.Timestamp.fromDate(d);
    }
    if (!data.endDateTs) {
      const d = legacyAppleDoubleToDate(data.endDate);
      if (d) patch.endDateTs = admin.firestore.Timestamp.fromDate(d);
    }
    if (!data.createdAtTs) {
      const d = legacyAppleDoubleToDate(data.createdAt);
      if (d) patch.createdAtTs = admin.firestore.Timestamp.fromDate(d);
    }

    const keys = Object.keys(patch);
    if (keys.length === 0) continue;

    updated++;
    if (!dryRun) {
      batch.set(doc.ref, patch, {merge: true});
      batchOps++;
      if (batchOps >= batchSize) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }
  }
  if (!dryRun && batchOps > 0) {
    await batch.commit();
  }
  return {processed, updated};
}

async function main() {
  const {project, franchise, dryRun, limit} = parseArgs();
  admin.initializeApp({projectId: project});
  const db = admin.firestore();

  const targets = [
    {name: "office_operations", fn: backfillOfficeOperations},
    {name: "vacationTimes", fn: backfillVacationTimes},
  ];

  for (const t of targets) {
    for (const mode of ["legacy", "scoped"]) {
      const ref = (mode === "legacy") ?
        db.collection(t.name) :
        db.collection("franchises").doc(franchise).collection(t.name);
      const res = await t.fn(db, ref, dryRun, limit);
      console.log(JSON.stringify({
        collection: t.name,
        pathMode: mode,
        franchise,
        dryRun,
        limit,
        ...res,
      }));
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

