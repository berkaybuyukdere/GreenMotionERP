#!/usr/bin/env node
/**
 * Damage count audit — compares two data sources:
 *   1. Nested  : franchises/CH/araclar[*].hasarKayitlari  (what iOS app uses)
 *   2. TopLevel: franchises/CH/hasarKayitlari collection  (what AnalyticsDashboard may use)
 *
 * Auth: gcloud auth login (uses user access token, read-only)
 * Usage: node scripts/check_damage_counts.mjs
 */

import { execSync } from 'node:child_process';

function gcloudProject() {
  return execSync('gcloud config get-value project', { encoding: 'utf8' }).trim();
}

function accessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

const BASE = (project) =>
  `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`;

async function rest(project, token, path, init = {}) {
  const url = `${BASE(project)}${path}`;
  const res = await fetch(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...init.headers,
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${init.method || 'GET'} ${url} -> ${res.status}: ${text.slice(0, 500)}`);
  return text ? JSON.parse(text) : {};
}

/** Read ALL documents from a collection (handles pagination). */
async function listAllDocs(project, token, collectionPath) {
  const docs = [];
  let pageToken = '';
  for (;;) {
    const q = pageToken ? `?pageToken=${encodeURIComponent(pageToken)}` : '';
    const j = await rest(project, token, `/documents/${collectionPath}${q}`);
    for (const d of j.documents || []) docs.push(d);
    pageToken = j.nextPageToken;
    if (!pageToken) break;
  }
  return docs;
}

/** Convert Firestore value object to a JS primitive / Date. */
function fsVal(v) {
  if (!v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return new Date(v.timestampValue);
  if ('nullValue' in v) return null;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fsVal);
  if ('mapValue' in v) {
    const out = {};
    for (const [k, mv] of Object.entries(v.mapValue.fields || {})) out[k] = fsVal(mv);
    return out;
  }
  return null;
}

/** Flatten a Firestore REST document to plain JS object. */
function flatDoc(doc) {
  const out = { _id: doc.name.split('/').pop() };
  for (const [k, v] of Object.entries(doc.fields || {})) out[k] = fsVal(v);
  return out;
}

/** Calendar-month boundaries (local midnight). */
function monthBounds(year, month /* 0-based */) {
  const start = new Date(year, month, 1, 0, 0, 0, 0);
  const end   = new Date(year, month + 1, 0, 23, 59, 59, 999); // last day of month
  return { start, end };
}

function fmt(d) {
  return d.toISOString().slice(0, 10);
}

async function main() {
  const project = gcloudProject();
  console.log(`Project : ${project}`);
  console.log(`Run at  : ${new Date().toISOString()}\n`);

  const token = accessToken();

  // ── Date ranges ──────────────────────────────────────────────────────────────
  const now = new Date();
  const curBounds  = monthBounds(now.getFullYear(), now.getMonth());
  const prevBounds = monthBounds(
    now.getMonth() === 0 ? now.getFullYear() - 1 : now.getFullYear(),
    now.getMonth() === 0 ? 11 : now.getMonth() - 1
  );

  console.log(`Current month : ${fmt(curBounds.start)} → ${fmt(curBounds.end)}`);
  console.log(`Previous month: ${fmt(prevBounds.start)} → ${fmt(prevBounds.end)}\n`);

  // ── SOURCE 1: nested hasarKayitlari inside each vehicle ─────────────────────
  console.log('📦 Loading franchises/CH/araclar …');
  const aracDocs = await listAllDocs(project, token, 'franchises/CH/araclar');
  console.log(`   → ${aracDocs.length} vehicle documents\n`);

  let nested = {
    totalAll: 0,
    totalNonDeleted: 0,
    currentMonth: 0,
    previousMonth: 0,
    deletedVehiclesDamages: 0,
    vehiclesWithDamage: 0,
    perVehicle: [],
  };

  for (const doc of aracDocs) {
    const v = flatDoc(doc);
    const isDeleted = v.isDeleted === true;
    const damages   = Array.isArray(v.hasarKayitlari) ? v.hasarKayitlari : [];

    nested.totalAll += damages.length;
    if (isDeleted) {
      nested.deletedVehiclesDamages += damages.length;
      continue; // soft-deleted → skip from counts (mirror iOS filter)
    }

    nested.totalNonDeleted += damages.length;
    if (damages.length > 0) nested.vehiclesWithDamage++;

    let curCount = 0, prevCount = 0;
    for (const hasar of damages) {
      const tarih = hasar.tarih instanceof Date ? hasar.tarih : null;
      if (!tarih || isNaN(tarih)) continue;
      if (tarih >= curBounds.start  && tarih <= curBounds.end)  { curCount++;  nested.currentMonth++;  }
      if (tarih >= prevBounds.start && tarih <= prevBounds.end) { prevCount++; nested.previousMonth++; }
    }

    if (damages.length > 0) {
      nested.perVehicle.push({
        plaka: v.plaka || v._id,
        total: damages.length,
        curMonth: curCount,
        prevMonth: prevCount,
      });
    }
  }

  // ── SOURCE 2: top-level franchises/CH/hasarKayitlari collection ─────────────
  console.log('📂 Loading franchises/CH/hasarKayitlari collection …');
  let topLevel = { total: 0, currentMonth: 0, previousMonth: 0 };
  try {
    const topDocs = await listAllDocs(project, token, 'franchises/CH/hasarKayitlari');
    topLevel.total = topDocs.length;

    for (const doc of topDocs) {
      const h = flatDoc(doc);
      // top-level docs may have 'tarih' as a Timestamp or date string
      const tarih = h.tarih instanceof Date ? h.tarih : (h.tarih ? new Date(h.tarih) : null);
      if (!tarih || isNaN(tarih)) continue;
      if (tarih >= curBounds.start  && tarih <= curBounds.end)  topLevel.currentMonth++;
      if (tarih >= prevBounds.start && tarih <= prevBounds.end) topLevel.previousMonth++;
    }
  } catch (e) {
    console.error(`   ⚠️  Could not load top-level hasarKayitlari: ${e.message}`);
    topLevel = null;
  }

  // ── RESULTS ─────────────────────────────────────────────────────────────────
  console.log('\n════════════════════════════════════════════════════════');
  console.log('  DAMAGE COUNT AUDIT RESULTS');
  console.log('════════════════════════════════════════════════════════\n');

  console.log('SOURCE 1 — Nested (araclar[*].hasarKayitlari)');
  console.log('  This is what the iOS app and Reports screen count from.\n');
  console.log(`  Vehicles loaded            : ${aracDocs.length}`);
  console.log(`  Vehicles with damage       : ${nested.vehiclesWithDamage}`);
  console.log(`  Total damages (ALL incl deleted vehicles) : ${nested.totalAll}`);
  console.log(`  Damages on DELETED vehicles: ${nested.deletedVehiclesDamages}`);
  console.log(`  Total damages (non-deleted vehicles)      : ${nested.totalNonDeleted}`);
  console.log(`  Current month  (${fmt(curBounds.start)} – ${fmt(curBounds.end)}): ${nested.currentMonth}`);
  console.log(`  Previous month (${fmt(prevBounds.start)} – ${fmt(prevBounds.end)}): ${nested.previousMonth}`);

  const change = nested.currentMonth - nested.previousMonth;
  const changeStr = change === 0 ? '0' : change > 0 ? `+${change}` : `${change}`;
  console.log(`\n  ► Dashboard metric would show: ${nested.currentMonth} (${changeStr} vs prev month)`);

  if (topLevel) {
    console.log('\n────────────────────────────────────────────────────────');
    console.log('SOURCE 2 — Top-level (franchises/CH/hasarKayitlari)');
    console.log('  Used by AnalyticsDashboard when topLevelHasarKayitlari is non-empty.\n');
    console.log(`  Total documents            : ${topLevel.total}`);
    console.log(`  Current month  (${fmt(curBounds.start)} – ${fmt(curBounds.end)}): ${topLevel.currentMonth}`);
    console.log(`  Previous month (${fmt(prevBounds.start)} – ${fmt(prevBounds.end)}): ${topLevel.previousMonth}`);

    const delta = nested.totalNonDeleted - topLevel.total;
    console.log(`\n  ► Difference (nested non-deleted vs top-level total): ${delta > 0 ? '+' : ''}${delta}`);
    if (delta !== 0) {
      console.log(`  ⚠️  MISMATCH — the two sources disagree by ${Math.abs(delta)} records!`);
      console.log(`     This can cause different counts on different screens/devices.`);
    } else {
      console.log(`  ✅ Both sources agree on total count.`);
    }
  }

  console.log('\n────────────────────────────────────────────────────────');
  console.log('TOP 10 VEHICLES BY DAMAGE COUNT (non-deleted):');
  nested.perVehicle
    .sort((a, b) => b.total - a.total)
    .slice(0, 10)
    .forEach((v, i) =>
      console.log(`  ${i + 1}. ${v.plaka.padEnd(15)} total=${v.total}  cur=${v.curMonth}  prev=${v.prevMonth}`)
    );

  console.log('\n════════════════════════════════════════════════════════\n');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
