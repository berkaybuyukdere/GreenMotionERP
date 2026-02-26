#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");

function safeReadJson(filePath) {
  if (!fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    return {error: `Failed to parse JSON: ${error.message}`};
  }
}

function safeReadText(filePath) {
  if (!fs.existsSync(filePath)) return null;
  return fs.readFileSync(filePath, "utf8");
}

const firestoreBackfill = safeReadJson(
    path.resolve(__dirname, "firestore-backfill-report.json"),
);
const parity = safeReadJson(
    path.resolve(__dirname, "scoped-parity-report.json"),
);
const storage = safeReadText(
    path.resolve(__dirname, "storage-backfill-report.txt"),
);

const manifest = {
  generatedAt: new Date().toISOString(),
  defaultFranchiseId: "ch",
  reports: {
    firestoreBackfill,
    parity,
    storageSummary: storage,
  },
};

const outputPath = path.resolve(__dirname, "franchise-migration-manifest.json");
fs.writeFileSync(outputPath, JSON.stringify(manifest, null, 2));
console.log(`Manifest generated: ${outputPath}`);
