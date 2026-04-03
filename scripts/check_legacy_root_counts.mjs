#!/usr/bin/env node
/**
 * Kök (root) Firestore koleksiyonlarında kaç doküman olduğunu sayar.
 * Scoped migration sonrası root'un boş olması beklenir.
 *
 * Kurulum: `cd functions && npm install` (firebase-admin)
 * Çalıştır: `GOOGLE_APPLICATION_CREDENTIALS=... node scripts/check_legacy_root_counts.mjs`
 * veya: `npx firebase login` + `firebase use` ile proje seçip aynı dizinde admin SDK ile.
 *
 * Çıktı: her domain koleksiyon için root doc sayısı. Toplam > 0 ise
 * `node scripts/backfill_firestore_scoped.js --dry-run` ile kontrol,
 * ardından dry-run kaldırarak migrate edin.
 */
/* eslint-disable no-console */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const mapPath = join(__dirname, "franchise-migration-map.json");
const migrationMap = JSON.parse(readFileSync(mapPath, "utf8"));

let admin;
try {
  const mod = await import("firebase-admin");
  admin = mod.default || mod;
} catch {
  const { createRequire } = await import("node:module");
  const require = createRequire(import.meta.url);
  admin = require(join(__dirname, "../functions/node_modules/firebase-admin"));
}

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function main() {
  const unique = [...new Set(migrationMap.domainFirestoreCollections)];

  console.log("Legacy root collection document counts\n");
  let anyNonZero = false;
  for (const name of unique.sort()) {
    const snap = await db.collection(name).limit(5000).get();
    const n = snap.size;
    if (n > 0) anyNonZero = true;
    console.log(`${name}: ${n}${n >= 5000 ? " (>=5000, capped sample)" : ""}`);
  }
  console.log(
    anyNonZero
      ? "\n⚠️ Root'ta veri var. Önce backfill çalıştırın: scripts/backfill_firestore_scoped.js"
      : "\n✅ Root domain koleksiyonları boş (veya örnek üst sınırına takılmadı).",
  );
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
