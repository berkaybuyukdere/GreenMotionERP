#!/usr/bin/env node
/**
 * Upserts smtpConfigurations for TR Sabiha ids + TR_NEVSEHIR (Gmail SMTP).
 * Same credentials per doc; matches iOS + Cloud Functions SMTP resolution.
 *
 * Prerequisites: same as seed-ch-smtp.js (firebase login or
 * GOOGLE_APPLICATION_CREDENTIALS).
 *
 * From `functions/` (password only in the shell, never in git):
 *
 *   GMAIL_APP_PASSWORD='…' npm run seed:tr-smtp:gmail
 *
 * Optional: GMAIL_USER (default berkaybdere@gmail.com),
 * SMTP_SEED_SENDER_NAME (default Green Motion).
 * Strips spaces from app passwords before saving.
 */

const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/** @type {string[]} */
const DOC_IDS = [
  "TR_SABIHAGOKCEN",
  "TR_IST_SABIHA",
  "TR_NEVSEHIR",
];

/**
 * Upserts one smtp doc.
 * @param {string} docId Firestore document id
 * @param {Object} payload fields
 * @return {Promise<void>}
 */
async function upsert(docId, payload) {
  await db.collection("smtpConfigurations").doc(docId).set(payload, {
    merge: true,
  });
  console.log(`OK: smtpConfigurations/${docId}`);
}

/**
 * Entry point.
 * @return {Promise<void>}
 */
async function main() {
  const gmailUser = (process.env.GMAIL_USER || "berkaybdere@gmail.com").trim();
  const rawPass = process.env.GMAIL_APP_PASSWORD || "";
  const password = String(rawPass).replace(/\s+/g, "").trim();
  const senderName = (
    process.env.SMTP_SEED_SENDER_NAME || "Green Motion"
  ).trim();

  if (!password || password.length < 8) {
    console.error(
        "Missing GMAIL_APP_PASSWORD (Gmail 16-char app password). " +
        "Never commit passwords.",
    );
    process.exit(1);
  }
  if (!gmailUser.includes("@")) {
    console.error("GMAIL_USER must be a full email address.");
    process.exit(1);
  }

  const base = {
    host: "smtp.gmail.com",
    port: 587,
    username: gmailUser,
    password,
    senderName,
    senderEmail: gmailUser,
    useTLS: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  for (const docId of DOC_IDS) {
    await upsert(docId, {...base, franchiseId: docId});
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
