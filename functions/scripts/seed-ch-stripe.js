#!/usr/bin/env node
/**
 * Seeds CH Stripe PUBLIC config in Firestore (publishable key only).
 *
 * Secret key (sk_live_…) — NEVER in Firestore or repo:
 *   firebase functions:secrets:set STRIPE_CH_SECRET_KEY
 *
 * Webhook signing secret (optional, from Stripe Dashboard):
 *   firebase functions:secrets:set STRIPE_CH_WEBHOOK_SECRET
 *
 * Example:
 *   cd functions && npm run seed:ch-stripe
 */

const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const FRANCHISE = "CH";

const PUBLISHABLE_KEY = (
  process.env.STRIPE_CH_PUBLISHABLE_KEY || ""
).trim();

/**
 * @return {Promise<void>}
 */
async function main() {
  if (!PUBLISHABLE_KEY.startsWith("pk_")) {
    console.error(
        "Set STRIPE_CH_PUBLISHABLE_KEY=pk_live_... (must start with pk_)",
    );
    process.exit(1);
  }

  await db.collection("franchises").doc(FRANCHISE).set({
    franchiseId: FRANCHISE,
    countryCode: "CH",
    isActive: true,
    stripeMailOrderEnabled: true,
    stripeChargebacksEnabled: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  await db.collection("franchises").doc(FRANCHISE)
      .collection("stripeConfig").doc("public")
      .set({
        franchiseId: FRANCHISE,
        mode: "live",
        publishableKey: PUBLISHABLE_KEY,
        features: ["mail_order", "chargebacks"],
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

  console.log(
      "Seeded franchises/CH/stripeConfig/public (publishable key only)",
  );
  console.log("Next:");
  console.log("  firebase functions:secrets:set STRIPE_CH_SECRET_KEY");
  console.log(
      "  firebase functions:secrets:set STRIPE_CH_WEBHOOK_SECRET",
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
