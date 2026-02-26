#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
let admin;
try {
  admin = require("firebase-admin");
} catch (error) {
  admin = require(path.resolve(__dirname, "../functions/node_modules/firebase-admin"));
}

const mapPath = path.resolve(__dirname, "franchise-migration-map.json");
const migrationMap = JSON.parse(fs.readFileSync(mapPath, "utf8"));

const defaultFranchiseId = process.env.DEFAULT_FRANCHISE_ID ||
  migrationMap.defaultFranchiseId ||
  "ch";
const dryRun = process.argv.includes("--dry-run");
const batchSize = Number(process.env.BATCH_SIZE || 400);

admin.initializeApp();
const db = admin.firestore();

async function copyCollection(collectionName) {
  const snapshot = await db.collection(collectionName).get();
  let copied = 0;
  let skipped = 0;
  let batch = db.batch();
  let opCount = 0;

  for (const docSnap of snapshot.docs) {
    const data = docSnap.data() || {};
    const franchiseId = data.franchiseId || defaultFranchiseId;
    const scopedRef = db.collection("franchises")
        .doc(franchiseId)
        .collection(collectionName)
        .doc(docSnap.id);

    const payload = {
      ...data,
      franchiseId,
      _migration: {
        legacyCollection: collectionName,
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    };

    if (dryRun) {
      copied++;
      continue;
    }

    batch.set(scopedRef, payload, {merge: true});
    copied++;
    opCount++;

    if (opCount >= batchSize) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }
  }

  if (!dryRun && opCount > 0) {
    await batch.commit();
  }

  if (snapshot.empty) {
    skipped = 1;
  }

  return {
    collection: collectionName,
    total: snapshot.size,
    copied,
    skipped,
  };
}

async function main() {
  const results = [];
  console.log(`Starting Firestore scoped backfill (dryRun=${dryRun})`);
  console.log(`Default franchiseId for orphan docs: ${defaultFranchiseId}`);

  for (const collectionName of migrationMap.domainFirestoreCollections) {
    console.log(`- Processing ${collectionName}...`);
    const result = await copyCollection(collectionName);
    results.push(result);
    console.log(`  done: total=${result.total}, copied=${result.copied}`);
  }

  const output = {
    generatedAt: new Date().toISOString(),
    dryRun,
    defaultFranchiseId,
    results,
  };

  const outPath = path.resolve(__dirname, "firestore-backfill-report.json");
  fs.writeFileSync(outPath, JSON.stringify(output, null, 2));
  console.log(`Report written: ${outPath}`);
}

main().catch((error) => {
  console.error("Backfill failed:", error);
  process.exitCode = 1;
});
