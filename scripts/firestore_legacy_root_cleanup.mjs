#!/usr/bin/env node
/**
 * Kök (legacy) araclar / activities: scoped CH ile karşılaştırıp güvenli silme.
 *
 * Silme kuralları (tümü sağlanmalı):
 * - Aynı document ID `franchises/CH/{collection}/{id}` altında varsa → kök kopya (duplicate) silinir.
 * - Scoped'ta yok ama kök dokümanda franchiseId alanı CH/ch ile uyumluysa → uygulama scoped-only; kök yetim sayılır, silinir.
 * - Scoped'ta yok ve franchiseId CH değilse veya yoksa → veri kaybı riski; silinmez (raporlanır).
 *
 * Auth: gcloud auth print-access-token
 *
 * Dry-run (varsayılan):
 *   node scripts/firestore_legacy_root_cleanup.mjs
 *
 * Uygulama:
 *   node scripts/firestore_legacy_root_cleanup.mjs --execute --confirm=LEGACY_ROOT_CLEANUP_CH \
 *     --export-uri=gs://bucket/path-from-latest-export
 */

import { execSync } from 'node:child_process';

const BASE = (p) => `https://firestore.googleapis.com/v1/projects/${p}/databases/(default)`;

function parseArgs() {
  const o = {
    project: null,
    franchise: 'CH',
    execute: false,
    confirm: null,
    exportUri: null,
  };
  for (const a of process.argv.slice(2)) {
    if (a.startsWith('--project=')) o.project = a.slice('--project='.length);
    else if (a.startsWith('--franchise=')) o.franchise = a.slice('--franchise='.length);
    else if (a === '--execute') o.execute = true;
    else if (a.startsWith('--confirm=')) o.confirm = a.slice('--confirm='.length);
    else if (a.startsWith('--export-uri=')) o.exportUri = a.slice('--export-uri='.length);
  }
  return o;
}

function gcloudProject() {
  return execSync('gcloud config get-value project', { encoding: 'utf8' }).trim();
}

function accessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

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
    throw new Error(`${init.method || 'GET'} ${url} -> ${res.status} ${text.slice(0, 400)}`);
  }
  return text ? JSON.parse(text) : {};
}

async function listCollectionDocMeta(project, token, collectionId, parentPath = null) {
  const rel = parentPath
    ? `/documents/${parentPath}/${collectionId}`
    : `/documents/${collectionId}`;
  const out = [];
  let pageToken = '';
  for (;;) {
    const q = new URLSearchParams({ pageSize: '500' });
    if (pageToken) q.set('pageToken', pageToken);
    const j = await rest(project, token, `${rel}?${q}`);
    for (const d of j.documents || []) {
      const name = d.name || '';
      const id = name.split('/').pop();
      const fields = d.fields || {};
      const franchiseField = fields.franchiseId;
      let franchiseId = null;
      if (franchiseField?.stringValue != null) franchiseId = franchiseField.stringValue;
      out.push({ name, id, franchiseId, fields });
    }
    pageToken = j.nextPageToken;
    if (!pageToken) break;
  }
  return out;
}

async function docExists(project, token, pathFromDocuments) {
  const enc = pathFromDocuments.split('/').map(encodeURIComponent).join('/');
  const url = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${enc}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return false;
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`HEAD doc ${pathFromDocuments} -> ${res.status} ${t.slice(0, 200)}`);
  }
  return true;
}

function franchiseMatchesCH(fid, targetUpper) {
  if (fid == null) return false;
  return String(fid).toUpperCase() === targetUpper;
}

async function deleteDoc(token, fullName) {
  const urlPath = fullName.split('/').map(encodeURIComponent).join('/');
  const url = `https://firestore.googleapis.com/v1/${urlPath}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`DELETE -> ${res.status} ${t.slice(0, 200)}`);
  }
}

async function planCollection(project, token, collectionId, franchiseUpper) {
  const scopedParent = `franchises/${franchiseUpper}`;
  const rootDocs = await listCollectionDocMeta(project, token, collectionId, null);
  const decisions = [];

  for (const doc of rootDocs) {
    const scopedPath = `${scopedParent}/${collectionId}/${doc.id}`;
    const hasScoped = await docExists(project, token, scopedPath);
    const chFranchise = franchiseMatchesCH(doc.franchiseId, franchiseUpper);

    let action = 'skip';
    let reason = '';
    if (hasScoped) {
      action = 'delete_duplicate';
      reason = 'same doc id exists under franchises/' + franchiseUpper;
    } else if (chFranchise) {
      action = 'delete_orphan_ch';
      reason = 'no scoped copy; franchiseId matches CH — legacy orphan (app uses scoped path)';
    } else {
      reason = `no scoped copy; franchiseId=${doc.franchiseId ?? 'missing'} — not auto-deleted`;
    }

    decisions.push({ ...doc, hasScoped, action, reason });
  }
  return decisions;
}

async function main() {
  const args = parseArgs();
  const project = args.project || gcloudProject();
  const F = args.franchise.toUpperCase();
  if (!project) {
    console.error('gcloud config set project');
    process.exit(1);
  }

  const token = accessToken();
  const collections = ['araclar', 'activities'];

  console.log(`Project ${project}, scoped franchise ${F} (uppercase)\n`);

  const all = [];
  for (const col of collections) {
    const rows = await planCollection(project, token, col, F);
    console.log(`## Root \`${col}\` (${rows.length} document(s))`);
    for (const r of rows) {
      console.log(`- id=${r.id} scoped=${r.hasScoped} franchiseId=${r.franchiseId ?? '—'}`);
      console.log(`  → ${r.action}: ${r.reason}`);
    }
    console.log('');
    all.push(...rows.map((r) => ({ collection: col, ...r })));
  }

  const toDelete = all.filter((r) => r.action === 'delete_duplicate' || r.action === 'delete_orphan_ch');
  const skip = all.filter((r) => r.action === 'skip');

  console.log(`Summary: delete=${toDelete.length}, skip=${skip.length}`);

  if (!args.execute) {
    console.log('\nDry-run. To apply: --execute --confirm=LEGACY_ROOT_CLEANUP_CH --export-uri=gs://...');
    return;
  }

  if (args.confirm !== 'LEGACY_ROOT_CLEANUP_CH') {
    console.error('Need --confirm=LEGACY_ROOT_CLEANUP_CH');
    process.exit(1);
  }
  if (!args.exportUri || !args.exportUri.startsWith('gs://')) {
    console.error('Need --export-uri=gs://... (recent full export)');
    process.exit(1);
  }

  console.error('\n*** DELETING root legacy documents ***\n');
  for (const r of toDelete) {
    await deleteDoc(token, r.name);
    console.error(`Deleted root/${r.collection}/${r.id} (${r.action})`);
  }
  console.error(`\nDone. Removed ${toDelete.length} document(s).`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
