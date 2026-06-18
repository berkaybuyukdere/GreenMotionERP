#!/usr/bin/env node
/**
 * Verifies CH Stripe Firestore config + Stripe API connectivity.
 */

const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const FRANCHISE = "CH";

/**
 * @return {Promise<void>}
 */
async function main() {
  const db = admin.firestore();
  const configSnap = await db.collection("franchises").doc(FRANCHISE)
      .collection("stripeConfig").doc("public")
      .get();

  if (!configSnap.exists) {
    console.error("MISSING: franchises/CH/stripeConfig/public");
    process.exit(1);
  }

  const cfg = configSnap.data();
  const pk = String(cfg.publishableKey || "");
  console.log("Firestore CH stripeConfig/public:");
  console.log("  mode:", cfg.mode);
  console.log("  publishableKey:", pk.slice(0, 12) + "…" + pk.slice(-4));
  console.log("  features:", (cfg.features || []).join(", "));

  if (!pk.startsWith("pk_live_")) {
    console.warn("WARN: publishable key is not pk_live_");
  }

  const key = String(process.env.STRIPE_CH_SECRET_KEY || "").trim();
  if (key.startsWith("sk_")) {
    const Stripe = require("stripe");
    const stripe = new Stripe(key, {apiVersion: "2024-11-20.acacia"});
    const account = await stripe.accounts.retrieve();
    console.log("Stripe API OK — account:", account.id || "platform");
    const disputes = await stripe.disputes.list({limit: 3});
    console.log("Recent disputes:", disputes.data.length);
  } else {
    console.log("Skip Stripe API test (no STRIPE_CH_SECRET_KEY in env)");
  }

  console.log("CH Stripe setup verification passed.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
