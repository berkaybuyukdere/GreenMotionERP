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

admin.initializeApp();
const db = admin.firestore();

async function compareCollection(collectionName) {
  const legacy = await db.collection(collectionName).get();
  const scoped = await db.collection("franchises")
      .doc(defaultFranchiseId)
      .collection(collectionName)
      .get();

  const legacyIds = new Set(legacy.docs.map((d) => d.id));
  const scopedIds = new Set(scoped.docs.map((d) => d.id));
  const missing = [...legacyIds].filter((id) => !scopedIds.has(id));

  return {
    collection: collectionName,
    legacyCount: legacy.size,
    scopedCount: scoped.size,
    missingCount: missing.length,
    missingSample: missing.slice(0, 20),
  };
}

async function main() {
  const results = [];
  for (const collectionName of migrationMap.domainFirestoreCollections) {
    const result = await compareCollection(collectionName);
    results.push(result);
    console.log(
        `${collectionName}: legacy=${result.legacyCount},` +
        ` scoped=${result.scopedCount}, missing=${result.missingCount}`,
    );
  }

  const output = {
    generatedAt: new Date().toISOString(),
    defaultFranchiseId,
    results,
  };
  const outPath = path.resolve(__dirname, "scoped-parity-report.json");
  fs.writeFileSync(outPath, JSON.stringify(output, null, 2));
  console.log(`Parity report written: ${outPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
