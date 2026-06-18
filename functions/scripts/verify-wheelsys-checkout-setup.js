#!/usr/bin/env node
/**
 * Quick sanity check before CH checkout E2E tests.
 * Verifies encrypted WheelSys session + lists deployed callable names.
 *
 *   cd functions && node scripts/verify-wheelsys-checkout-setup.js
 */

const admin = require("firebase-admin");
const {sessionDocRef} = require("../wheelsys/sessionStore");

if (!admin.apps.length) {
  admin.initializeApp();
}

const FRANCHISE = String(process.env.WHEELSYS_FRANCHISE || "CH").toUpperCase();
const STATION = String(process.env.WHEELSYS_STATION || "ZRH").toUpperCase();

const CHECKOUT_CALLABLES = [
  "wheelsysGetJournal",
  "wheelsysGetBookingPreview",
  "wheelsysSearchAvailableVehicles",
  "wheelsysAssignVehicleToBooking",
];

/**
 * @return {Promise<void>}
 */
async function main() {
  const db = admin.firestore();
  const ref = sessionDocRef(db, FRANCHISE, STATION);
  const snap = await ref.get();

  console.log("WheelSys checkout preflight");
  console.log("  franchise:", FRANCHISE);
  console.log("  station:", STATION);
  console.log("");

  if (!snap.exists) {
    console.error("FAIL: No session at", ref.path);
    console.error("Run: npm run seed:wheelsys-session");
    process.exit(1);
  }

  const data = snap.data() || {};
  const expiresAt = data.expiresAt && data.expiresAt.toDate ?
    data.expiresAt.toDate() : null;
  const now = new Date();

  console.log("Session doc: OK");
  console.log("  updatedAt:", data.updatedAt && data.updatedAt.toDate ?
    data.updatedAt.toDate().toISOString() : "—");
  console.log("  expiresAt:", expiresAt ? expiresAt.toISOString() : "—");

  if (expiresAt && expiresAt < now) {
    console.warn("WARN: Session appears expired — re-seed before E2E test.");
  }

  console.log("");
  console.log("Expected Cloud Functions (europe-west6):");
  CHECKOUT_CALLABLES.forEach((name) => console.log("  -", name));
  console.log("");
  console.log("Deploy if missing:");
  console.log("  ../scripts/deploy_wheelsys_checkout_functions.sh");
  console.log("");
  console.log("E2E steps: docs/WHEELSYS_CHECKOUT_E2E_TEST.md");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
