#!/usr/bin/env node
/**
 * Scoped franchise (default CH) içinde **yalnızca açıkça gereksiz** kopyaları temizler.
 *
 * Kurallar (hepsi aynı anda sağlanmalı — şüphede işlem YOK):
 *
 * 1) exitIslemleri / iadeIslemleri — `createdAt` alanı yoksa, sırasıyla `exitTarihi` / `iadeTarihi`
 *    ile PATCH (iOS zaten decode’da fallback yapar; Firebase şemasını düzeltir).
 *
 * 2) exitIslemleri / iadeIslemleri — duplicate grupta (web ile aynı anahtar) yalnızca tüm alan
 *    parmak izi eşleşiyorsa ve **tutulacak** belge seçilebiliyorsa sil:
 *    - Parmak izi: JSON.stringify({ fotograflar, notlar, status, km | checklist… })
 *    - Tutulan: `documentId === iç id` (string) olan; birden fazlaysa `createdAt` en eski.
 *    - Hiçbiri id eşleşmiyorsa: grup **atlanır** (manuel inceleme).
 *
 * 3) araclar — Aynı plakada **boş kabuk** (`hasarKayitlari` ve `checkInKayitlari` boş): en az bir
 *    dolu kayıt varsa tüm boş kopyalar silinir; hepsi boşsa `docId===iç id` tercih, yoksa en küçük doc id tutulur.
 *
 * 4) İç içe hasar (opt-in: --nested-damages): aynı araçta `normalize(resKodu)+tarih(saniye)` tekrarı;
 *    dizide ilk kayıt tutulur; PATCH `hasarKayitlari`.
 *
 * Auth: gcloud auth print-access-token
 *
 * Dry-run (varsayılan):
 *   node scripts/firestore_safe_duplicate_cleanup.mjs
 *
 * Uygulama:
 *   node scripts/firestore_safe_duplicate_cleanup.mjs --execute --confirm=SAFE_DUP_CLEANUP_CH
 *
 * Sadece belirli adımlar:
 *   node scripts/firestore_safe_duplicate_cleanup.mjs --only=createdAt,duplicateExits,duplicateReturns,emptyAraclar
 */

import { execSync } from 'node:child_process';

function parseArgs() {
  const o = {
    project: null,
    franchise: 'CH',
    execute: false,
    confirm: null,
    only: null,
    nestedDamages: false,
  };
  for (const a of process.argv.slice(2)) {
    if (a.startsWith('--project=')) o.project = a.slice('--project='.length);
    else if (a.startsWith('--franchise=')) o.franchise = a.slice('--franchise='.length);
    else if (a === '--execute') o.execute = true;
    else if (a.startsWith('--confirm=')) o.confirm = a.slice('--confirm='.length);
    else if (a.startsWith('--only=')) o.only = a.slice('--only='.length);
    else if (a === '--nested-damages') o.nestedDamages = true;
  }
  return o;
}

function gcloudProject() {
  return execSync('gcloud config get-value project', { encoding: 'utf8' }).trim();
}

function accessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

const BASE = (p) => `https://firestore.googleapis.com/v1/projects/${p}/databases/(default)`;

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
  if (!res.ok) {
    throw new Error(`${init.method || 'GET'} ${url} -> ${res.status} ${text.slice(0, 500)}`);
  }
  return text ? JSON.parse(text) : {};
}

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

function flatDoc(doc) {
  const out = { _id: doc.name.split('/').pop(), _name: doc.name };
  for (const [k, v] of Object.entries(doc.fields || {})) out[k] = fsVal(v);
  return out;
}

function normalizePlaka(p) {
  return String(p || '')
    .toUpperCase()
    .replace(/\s+/g, '');
}

function normalizeRes(r) {
  return String(r || '')
    .trim()
    .toUpperCase()
    .replace(/^RES[-\s]*/i, '');
}

function tsSeconds(v) {
  if (v instanceof Date && !isNaN(v)) return Math.floor(v.getTime() / 1000);
  if (v && typeof v === 'object' && 'seconds' in v) return Number(v.seconds);
  return String(v ?? '');
}

/** ISO 8601 for Firestore timestampValue */
function toTimestampValue(d) {
  if (!(d instanceof Date) || isNaN(d)) return null;
  return d.toISOString().replace(/(\.\d{3})Z$/, 'Z');
}

function jsToFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') {
    if (Number.isInteger(val)) return { integerValue: String(val) };
    return { doubleValue: val };
  }
  if (typeof val === 'string') return { stringValue: val };
  if (val instanceof Date) {
    const iso = toTimestampValue(val);
    return iso ? { timestampValue: iso } : { nullValue: null };
  }
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map((x) => jsToFirestoreValue(x)) } };
  }
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = jsToFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

async function patchFields(project, token, docPathFromDocuments, fieldsObj, fieldPaths) {
  const encPath = docPathFromDocuments.split('/').map(encodeURIComponent).join('/');
  const mask = fieldPaths.map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join('&');
  const url = `${BASE(project)}/documents/${encPath}?${mask}`;
  await rest(project, token, url, {
    method: 'PATCH',
    body: JSON.stringify({ fields: fieldsObj }),
  });
}

async function deleteDocByName(token, fullName) {
  const urlPath = fullName.split('/').map(encodeURIComponent).join('/');
  const url = `https://firestore.googleapis.com/v1/${urlPath}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`DELETE -> ${res.status} ${t.slice(0, 300)}`);
  }
}

function exitDupKey(d) {
  return `${d.aracId}_${tsSeconds(d.exitTarihi)}_${d.resKodu || ''}`;
}

function exitFingerprint(d) {
  return JSON.stringify({
    fotograflar: d.fotograflar || [],
    notlar: d.notlar || '',
    resKodu: d.resKodu || '',
    status: d.status || '',
    km: d.km ?? null,
    aracPlaka: d.aracPlaka || '',
  });
}

function iadeDupKey(d) {
  return `${d.aracId}_${tsSeconds(d.iadeTarihi)}`;
}

function iadeFingerprint(d) {
  return JSON.stringify({
    fotograflar: d.fotograflar || [],
    notlar: d.notlar || '',
    status: d.status || '',
    checklist: d.checklist || null,
    hasarSayisi: d.hasarSayisi ?? null,
    fotografSayisi: d.fotografSayisi ?? null,
  });
}

function wants(onlySet, key) {
  if (!onlySet || onlySet.size === 0) return true;
  return onlySet.has(key);
}

async function planCreatedAtPatches(kind, docs, flatFn, sourceField, onlySet) {
  const plans = [];
  if (!wants(onlySet, 'createdAt')) return plans;
  for (const doc of docs) {
    const rawFields = doc.fields || {};
    if (rawFields.createdAt) continue;
    const src = rawFields[sourceField];
    if (!src) continue;
    const plain = flatFn(doc);
    const srcDate = plain[sourceField];
    if (!(srcDate instanceof Date) || isNaN(srcDate)) continue;
    const iso = toTimestampValue(srcDate);
    if (!iso) continue;
    const id = doc.name.split('/').pop();
    plans.push({
      action: 'patch',
      collection: kind,
      docId: id,
      path: doc.name.replace(/^projects\/[^/]+\/databases\/\(default\)\/documents\//, ''),
      fields: { createdAt: { timestampValue: iso } },
      mask: ['createdAt'],
      reason: `missing createdAt; set from ${sourceField}`,
    });
  }
  return plans;
}

function scoreArac(d) {
  const damages = Array.isArray(d.hasarKayitlari) ? d.hasarKayitlari.length : 0;
  const checks = Array.isArray(d.checkInKayitlari) ? d.checkInKayitlari.length : 0;
  const innerId = d.id != null ? String(d.id) : '';
  const docId = d._id;
  const idMatch = innerId && docId === innerId ? 1 : 0;
  return damages * 10000 + checks * 100 + idMatch * 50;
}

function isAracShellEmpty(d) {
  const dDam = Array.isArray(d.hasarKayitlari) ? d.hasarKayitlari.length : 0;
  const dCh = Array.isArray(d.checkInKayitlari) ? d.checkInKayitlari.length : 0;
  return dDam === 0 && dCh === 0;
}

function planEmptyDuplicateAraclar(flatList, franchisePath, onlySet) {
  const plans = [];
  if (!wants(onlySet, 'emptyAraclar')) return plans;

  const byPlate = new Map();
  for (const d of flatList) {
    const pk = normalizePlaka(d.plaka);
    if (!pk) continue;
    if (!byPlate.has(pk)) byPlate.set(pk, []);
    byPlate.get(pk).push(d);
  }

  for (const [, group] of byPlate) {
    if (group.length < 2) continue;
    const empties = group.filter(isAracShellEmpty);
    if (empties.length === 0) continue;

    const nonEmpties = group.filter((d) => !isAracShellEmpty(d));
    let keeper;
    if (nonEmpties.length > 0) {
      nonEmpties.sort((a, b) => scoreArac(b) - scoreArac(a));
      keeper = nonEmpties[0];
    } else {
      const idMatched = empties.filter((x) => x.id != null && String(x.id) === x._id);
      const pool = idMatched.length > 0 ? idMatched : empties;
      pool.sort((a, b) => a._id.localeCompare(b._id));
      keeper = pool[0];
    }

    for (const d of empties) {
      if (d._id === keeper._id) continue;
      plans.push({
        action: 'delete',
        collection: 'araclar',
        docId: d._id,
        path: `${franchisePath}/araclar/${d._id}`,
        fullName: d._name,
        reason: `empty duplicate vehicle; keeper=${keeper._id} plate=${normalizePlaka(d.plaka)}`,
      });
    }
  }
  return plans;
}

function planDocIdDuplicate(flatList, dupKeyFn, fingerprintFn, collection, franchisePath, onlyKey, onlySet) {
  const plans = [];
  if (!wants(onlySet, onlyKey)) return plans;

  const byKey = new Map();
  for (const row of flatList) {
    const k = dupKeyFn(row);
    if (!byKey.has(k)) byKey.set(k, []);
    byKey.get(k).push(row);
  }

  for (const [, group] of byKey) {
    if (group.length < 2) continue;
    const fp0 = fingerprintFn(group[0]);
    if (!group.every((g) => fingerprintFn(g) === fp0)) continue;

    const idMatched = group.filter((g) => g.id != null && String(g.id) === g._id);
    if (idMatched.length === 0) continue;

    idMatched.sort((a, b) => {
      const ca = a.createdAt instanceof Date ? a.createdAt.getTime() : 0;
      const cb = b.createdAt instanceof Date ? b.createdAt.getTime() : 0;
      return ca - cb;
    });
    const keeper = idMatched[0];

    for (const g of group) {
      if (g._id === keeper._id) continue;
      plans.push({
        action: 'delete',
        collection,
        docId: g._id,
        path: `${franchisePath}/${collection}/${g._id}`,
        fullName: g._name,
        reason: `duplicate logical record; keeper=${keeper._id} (inner id matches doc id)`,
      });
    }
  }
  return plans;
}

/** Aynı RES + tarih (saniye): dizide ilk kayıt tutulur — şüpheli tekrarları düşürür, sırayı korur. */
function dedupeNestedDamages(damages) {
  if (!Array.isArray(damages) || damages.length < 2) return { newArr: damages, removed: 0 };
  const seen = new Set();
  const out = [];
  let removed = 0;
  for (const h of damages) {
    const key = `${normalizeRes(h.resKodu)}_${tsSeconds(h.tarih)}`;
    if (seen.has(key)) {
      removed++;
      continue;
    }
    seen.add(key);
    out.push(h);
  }
  return { newArr: out, removed };
}

async function main() {
  const args = parseArgs();
  const project = args.project || gcloudProject();
  const F = args.franchise.toUpperCase();
  if (!project) {
    console.error('gcloud config set project');
    process.exit(1);
  }

  const onlySet = args.only
    ? new Set(
        args.only.split(',').map((s) => {
          const m = {
            createdat: 'createdAt',
            duplicateexits: 'duplicateExits',
            duplicatereturns: 'duplicateReturns',
            emptyaraclar: 'emptyAraclar',
            nesteddamages: 'nestedDamages',
          };
          const x = s.trim().toLowerCase();
          return m[x] || s.trim();
        })
      )
    : null;

  const token = accessToken();
  const franchisePath = `franchises/${F}`;

  console.log(`Project: ${project}, scope: ${franchisePath}\n`);

  const patchPlans = [];
  const deletePlans = [];
  const nestedPlans = [];

  // ── exitIslemleri ─────────────────────────────────────────────────────
  const exitDocs = await listAllDocs(project, token, `${franchisePath}/exitIslemleri`);
  const exitFlat = exitDocs.map((d) => {
    const x = flatDoc(d);
    x._name = d.name;
    return x;
  });
  patchPlans.push(
    ...(await planCreatedAtPatches('exitIslemleri', exitDocs, flatDoc, 'exitTarihi', onlySet))
  );
  deletePlans.push(
    ...planDocIdDuplicate(
      exitFlat,
      exitDupKey,
      exitFingerprint,
      'exitIslemleri',
      franchisePath,
      'duplicateExits',
      onlySet
    )
  );

  // ── iadeIslemleri ───────────────────────────────────────────────────────
  const iadeDocs = await listAllDocs(project, token, `${franchisePath}/iadeIslemleri`);
  const iadeFlat = iadeDocs.map((d) => {
    const x = flatDoc(d);
    x._name = d.name;
    return x;
  });
  patchPlans.push(
    ...(await planCreatedAtPatches('iadeIslemleri', iadeDocs, flatDoc, 'iadeTarihi', onlySet))
  );
  deletePlans.push(
    ...planDocIdDuplicate(
      iadeFlat,
      iadeDupKey,
      iadeFingerprint,
      'iadeIslemleri',
      franchisePath,
      'duplicateReturns',
      onlySet
    )
  );

  // ── araclar empty duplicates ───────────────────────────────────────────
  const aracDocs = await listAllDocs(project, token, `${franchisePath}/araclar`);
  const aracFlat = aracDocs.map((d) => {
    const x = flatDoc(d);
    x._name = d.name;
    return x;
  });
  deletePlans.push(...planEmptyDuplicateAraclar(aracFlat, franchisePath, onlySet));

  if (args.nestedDamages && wants(onlySet, 'nestedDamages')) {
    for (const doc of aracDocs) {
      const v = flatDoc(doc);
      const damages = Array.isArray(v.hasarKayitlari) ? v.hasarKayitlari : [];
      if (damages.length < 2) continue;
      const { newArr, removed } = dedupeNestedDamages(damages);
      if (removed <= 0) continue;
      nestedPlans.push({
        action: 'patch',
        collection: 'araclar',
        docId: v._id,
        path: `${franchisePath}/araclar/${v._id}`,
        fields: { hasarKayitlari: jsToFirestoreValue(newArr) },
        mask: ['hasarKayitlari'],
        reason:
          'dedupe nested damages: removed ' +
          removed +
          ' duplicate(s) (same RES+date second, first row kept)',
      });
    }
  }

  const printPlan = (label, rows) => {
    console.log(`## ${label} (${rows.length})`);
    for (const r of rows) {
      console.log(`- [${r.action}] ${r.collection} ${r.docId}`);
      console.log(`  ${r.reason}`);
    }
    console.log('');
  };

  printPlan('PATCH (createdAt)', patchPlans);
  printPlan('PATCH (nested hasarKayitlari)', nestedPlans);
  printPlan('DELETE', deletePlans);

  const totalPatch = patchPlans.length + nestedPlans.length;
  console.log(`Summary: patch=${totalPatch}, delete=${deletePlans.length}`);

  if (!args.execute) {
    console.log(
      '\nDry-run. Uygulama: --execute --confirm=SAFE_DUP_CLEANUP_CH\n' +
        'Iç hasar PATCH ayrıca: --nested-damages (opt-in; önce dry-run inceleyin).'
    );
    return;
  }

  if (args.confirm !== 'SAFE_DUP_CLEANUP_CH') {
    console.error('Need --confirm=SAFE_DUP_CLEANUP_CH');
    process.exit(1);
  }

  for (const p of patchPlans) {
    await patchFields(project, token, p.path, p.fields, p.mask);
    console.error(`PATCH ${p.path} (${p.reason})`);
  }
  for (const p of nestedPlans) {
    await patchFields(project, token, p.path, p.fields, p.mask);
    console.error(`PATCH ${p.path} (${p.reason})`);
  }
  for (const p of deletePlans) {
    await deleteDocByName(token, p.fullName);
    console.error(`DELETE ${p.path} (${p.reason})`);
  }

  console.error(`\nDone. patch=${totalPatch}, delete=${deletePlans.length}.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
