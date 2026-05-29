#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * Local runner for legacy → scoped Firestore migration.
 * Uses the same logic as Cloud Function `migrateLegacyToScoped`.
 *
 * Usage:
 *   node scripts/backfill_firestore_scoped.js --dry-run
 *   node scripts/backfill_firestore_scoped.js --batch-limit=200
 *   DEFAULT_FRANCHISE_ID=CH node scripts/backfill_firestore_scoped.js
 *
 * For production, prefer the callable after deploying functions:
 *   firebase functions:call migrateLegacyToScoped --data '{"dryRun":true}'
 */
const fs = require("fs");
const path = require("path");

let admin;
try {
  admin = require("firebase-admin");
} catch (error) {
  admin = require(path.resolve(__dirname, "../functions/node_modules/firebase-admin"));
}

const legacyMigration = require(path.resolve(
    __dirname,
    "../functions/legacyScopedMigration.js",
));

const dryRun = process.argv.includes("--dry-run");
const batchLimit = Number(
    (process.argv.find((a) => a.startsWith("--batch-limit=")) || "")
        .split("=")[1] || process.env.BATCH_SIZE || 200,
);

admin.initializeApp();
const db = admin.firestore();

async function main() {
  const map = legacyMigration.loadMigrationMap();
  const defaultFranchiseId = process.env.DEFAULT_FRANCHISE_ID ||
    map.defaultFranchiseId ||
    "CH";

  console.log(`Firestore scoped backfill (dryRun=${dryRun}, batch=${batchLimit})`);
  console.log(`Default franchiseId for orphan docs: ${defaultFranchiseId}`);

  let startAfter = null;
  let pass = 0;
  const allResults = [];

  do {
    pass++;
    const payload = await legacyMigration.runMigrateLegacyToScoped(db, {
      dryRun,
      batchLimit,
      defaultFranchiseId,
      startAfter: startAfter || undefined,
      verifyAfterCopy: true,
    });

    for (const row of payload.collectionResults) {
      console.log(
          `${row.collection}: scanned=${row.scanned} copied=${row.copied} ` +
          `verified_skip=${row.skippedVerified} conflicts=${row.skippedConflict}`,
      );
    }

    allResults.push(...payload.collectionResults);
    startAfter = payload.nextStartAfter;
    if (startAfter) {
      console.log(`Pass ${pass} complete; continuing with cursor...`);
    }
  } while (startAfter && pass < 500);

  const output = {
    generatedAt: new Date().toISOString(),
    dryRun,
    defaultFranchiseId,
    passes: pass,
    results: allResults,
  };

  const outPath = path.resolve(__dirname, "firestore-backfill-report.json");
  fs.writeFileSync(outPath, JSON.stringify(output, null, 2));
  console.log(`Report written: ${outPath}`);
}

main().catch((error) => {
  console.error("Backfill failed:", error);
  process.exitCode = 1;
});
