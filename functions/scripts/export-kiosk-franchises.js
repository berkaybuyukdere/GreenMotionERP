#!/usr/bin/env node
/**
 * Export kiosk-eligible franchises from Firestore `franchises` collection.
 * Writes public/kiosk-franchises.json for the front-desk branch picker.
 *
 * Usage (from functions/):
 *   npm run export:kiosk-franchises
 *
 * Requires: firebase login or GOOGLE_APPLICATION_CREDENTIALS
 */
/* eslint-disable max-len */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const OUT_PATH = path.resolve(__dirname, "../../public/kiosk-franchises.json");

/** Known id aliases (legacy doc ids → canonical franchise id). */
const ALIASES = {
  TR_IST_SABIHA: "TR_SABIHAGOKCEN",
  TR_SABIHA: "TR_SABIHAGOKCEN",
  TR_SABIHA_GOKCEN: "TR_SABIHAGOKCEN",
};

const COUNTRY_LABELS = {
  TR: "Türkiye",
  DE: "Deutschland",
  CH: "Schweiz",
};

/**
 * @param {string} franchiseId
 * @return {string|null}
 */
function inferCountryCode(franchiseId) {
  const id = String(franchiseId || "").trim().toUpperCase();
  if (!id) return null;
  if (id.startsWith("TR_") || id === "TR") return "TR";
  if (id.startsWith("DE_") || id === "DE") return "DE";
  if (id.startsWith("CH_") || id === "CH") return "CH";
  return null;
}

/**
 * @param {string} franchiseId
 * @return {boolean}
 */
function isKioskCountry(franchiseId) {
  return Boolean(inferCountryCode(franchiseId));
}

/**
 * @param {string} id
 * @param {object} data
 * @param {string} countryCode
 * @return {object|null}
 */
function branchEntry(id, data, countryCode) {
  const storageKey = String(id || "").trim().toUpperCase();
  if (!storageKey) return null;
  const displayName = String(
      data.name || data.franchiseName || data.displayName || storageKey,
  ).trim();
  return {
    storageKey,
    displayName: displayName || storageKey,
    countryCode,
  };
}

/**
 * Parse nested garage branches from a franchise document.
 * @param {object} data
 * @param {string} parentCountry
 * @return {Array<object>}
 */
function nestedGarageBranches(data, parentCountry) {
  const fields = [
    data.garageBranches,
    data.locations,
    data.branches,
    data.garageLocations,
  ];
  const out = [];
  for (const field of fields) {
    if (!Array.isArray(field)) continue;
    for (const row of field) {
      if (!row || typeof row !== "object") continue;
      const key = String(
          row.storageKey || row.storage_key || row.id || row.code ||
          row.branchId || row.franchiseId || "",
      ).trim().toUpperCase();
      if (!key) continue;
      const name = String(
          row.displayName || row.display_name || row.name || row.label || key,
      ).trim();
      const cc = String(
          row.countryCode || row.country_code || row.country || parentCountry || "",
      ).trim().toUpperCase() || parentCountry;
      if (!isKioskCountry(cc) && !isKioskCountry(key)) continue;
      out.push({
        storageKey: key,
        displayName: name || key,
        countryCode: inferCountryCode(key) || cc || parentCountry,
      });
    }
  }
  return out;
}

/**
 * @return {Promise<void>}
 */
async function main() {
  const snap = await db.collection("franchises").get();
  const byKey = new Map();

  snap.forEach((doc) => {
    const id = doc.id.trim().toUpperCase();
    const data = doc.data() || {};
    const country = inferCountryCode(id);

    if (country && isKioskCountry(id)) {
      const entry = branchEntry(id, data, country);
      if (entry) byKey.set(entry.storageKey, entry);
    }

    const parentCountry = country || "TR";
    for (const nested of nestedGarageBranches(data, parentCountry)) {
      if (isKioskCountry(nested.storageKey) || isKioskCountry(nested.countryCode)) {
        byKey.set(nested.storageKey, nested);
      }
    }
  });

  const franchises = [...byKey.values()].sort((a, b) => {
    const c = a.countryCode.localeCompare(b.countryCode);
    if (c !== 0) return c;
    return a.displayName.localeCompare(b.displayName, "tr");
  });

  const byCountry = {TR: [], DE: [], CH: []};
  for (const row of franchises) {
    const cc = row.countryCode;
    if (byCountry[cc]) byCountry[cc].push(row);
  }

  const payload = {
    generatedAt: new Date().toISOString(),
    source: "firestore/franchises",
    projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "greenmotionapp-33413",
    aliases: ALIASES,
    countryLabels: COUNTRY_LABELS,
    franchises,
    byCountry,
  };

  fs.writeFileSync(OUT_PATH, JSON.stringify(payload, null, 2) + "\n", "utf8");
  console.log(`Wrote ${franchises.length} kiosk franchises → ${OUT_PATH}`);
  for (const cc of ["TR", "DE", "CH"]) {
    console.log(`  ${cc}: ${byCountry[cc].length} → ${byCountry[cc].map((r) => r.storageKey).join(", ")}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
