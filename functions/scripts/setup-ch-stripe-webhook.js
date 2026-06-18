#!/usr/bin/env node
/**
 * Registers Stripe webhook for CH franchise (mail order + disputes).
 * Requires STRIPE_CH_SECRET_KEY in env (or firebase functions:secrets:access).
 *
 *   cd functions
 *   STRIPE_CH_SECRET_KEY="$(firebase functions:secrets:access ...)" \
 *     node scripts/setup-ch-stripe-webhook.js
 */

const WEBHOOK_URL =
  "https://europe-west6-greenmotionapp-33413.cloudfunctions.net/stripeCHWebhook";

const ENABLED_EVENTS = [
  "checkout.session.completed",
  "charge.dispute.created",
  "charge.dispute.updated",
  "charge.dispute.closed",
  "charge.dispute.funds_withdrawn",
  "charge.dispute.funds_reinstated",
];

/**
 * @return {Promise<void>}
 */
async function main() {
  const key = String(process.env.STRIPE_CH_SECRET_KEY || "").trim();
  if (!key.startsWith("sk_")) {
    console.error("Missing STRIPE_CH_SECRET_KEY (sk_live_... or sk_test_...)");
    process.exit(1);
  }

  const Stripe = require("stripe");
  const stripe = new Stripe(key, {apiVersion: "2024-11-20.acacia"});

  const existing = await stripe.webhookEndpoints.list({limit: 100});
  const match = existing.data.find((w) => w.url === WEBHOOK_URL);

  let endpoint;
  let signingSecret;

  if (match) {
    endpoint = await stripe.webhookEndpoints.update(match.id, {
      enabled_events: ENABLED_EVENTS,
      disabled: false,
    });
    console.log("Updated existing webhook:", endpoint.id);
    console.log(
        "NOTE: Signing secret is only shown at creation. " +
        "If webhooks fail, delete and recreate in Stripe Dashboard.",
    );
    signingSecret = process.env.STRIPE_CH_WEBHOOK_SECRET || "";
  } else {
    const created = await stripe.webhookEndpoints.create({
      url: WEBHOOK_URL,
      enabled_events: ENABLED_EVENTS,
      description: "Green Motion CH — mail order + chargebacks",
      metadata: {franchiseId: "CH"},
    });
    endpoint = created;
    signingSecret = created.secret || "";
    console.log("Created webhook:", endpoint.id);
    if (signingSecret) {
      console.log("Signing secret (set in Firebase):", signingSecret);
    }
  }

  console.log("URL:", WEBHOOK_URL);
  console.log("Events:", ENABLED_EVENTS.join(", "));

  if (signingSecret && signingSecret.startsWith("whsec_")) {
    const {spawnSync} = require("child_process");
    const root = require("path").join(__dirname, "..", "..");
    const setSecret = spawnSync(
        "firebase",
        ["functions:secrets:set", "STRIPE_CH_WEBHOOK_SECRET"],
        {
          input: signingSecret,
          stdio: ["pipe", "inherit", "inherit"],
          cwd: root,
        },
    );
    if (setSecret.status !== 0) {
      throw new Error("Failed to set STRIPE_CH_WEBHOOK_SECRET");
    }
    console.log("STRIPE_CH_WEBHOOK_SECRET updated in Firebase.");
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
