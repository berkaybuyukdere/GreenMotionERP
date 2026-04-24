#!/usr/bin/env node
/**
 * Writes franchise SMTP to Firestore: smtpConfigurations/{SMTP_SEED_DOC_ID}
 *
 * - No secrets in the iOS repo. Run after `firebase login` or set
 *   GOOGLE_APPLICATION_CREDENTIALS to a service account with Firestore write.
 * - Functions may override password via SMTP_PASSWORD_<DOCID> (e.g.
 *   SMTP_PASSWORD_CH).
 *
 * Example (Switzerland / CH):
 *   cd functions
 *   SMTP_SEED_DOC_ID=CH \
 *   SMTP_SEED_USER='mandrill-smtp-username@your-domain' \
 *   SMTP_SEED_SENDER_EMAIL='no-reply@your-domain' \
 *   SMTP_SEED_SENDER_NAME='Your sender name' \
 *   SMTP_SEED_HOST='smtp.your-provider.com' \
 *   SMTP_SEED_PASSWORD='YOUR_SMTP_PASSWORD_OR_API_KEY' \
 *   npm run seed:ch-smtp
 *
 * Other franchises: set SMTP_SEED_DOC_ID=TR_XXX (merge only that doc).
 */

const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Upserts smtpConfigurations from process.env.
 * @return {Promise<void>}
 */
async function main() {
  const docId = (process.env.SMTP_SEED_DOC_ID || "CH").trim();
  const password = (process.env.SMTP_SEED_PASSWORD || "").trim();
  const username = (process.env.SMTP_SEED_USER || "").trim();
  const senderEmail = (process.env.SMTP_SEED_SENDER_EMAIL || "").trim();

  if (!password) {
    console.error("Missing SMTP_SEED_PASSWORD (never commit this).");
    process.exit(1);
  }
  if (!username || !senderEmail) {
    console.error("Missing SMTP_SEED_USER and/or SMTP_SEED_SENDER_EMAIL.");
    process.exit(1);
  }

  const host = (process.env.SMTP_SEED_HOST || "").trim();
  if (!host) {
    console.error("Missing SMTP_SEED_HOST (set your SMTP server hostname).");
    process.exit(1);
  }
  const portRaw = parseInt(process.env.SMTP_SEED_PORT || "587", 10);
  const port = Number.isFinite(portRaw) && portRaw > 0 ? portRaw : 587;
  const senderName = (
    process.env.SMTP_SEED_SENDER_NAME || "Green Motion"
  ).trim();
  const useTLS = process.env.SMTP_SEED_USE_TLS !== "false";

  const payload = {
    host,
    port,
    username,
    password,
    senderName,
    senderEmail,
    useTLS,
    franchiseId: docId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection("smtpConfigurations").doc(docId).set(payload, {
    merge: true,
  });
  console.log(
      `OK: smtpConfigurations/${docId} merged (password stored in Firestore).`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
