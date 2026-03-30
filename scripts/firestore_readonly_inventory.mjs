#!/usr/bin/env node
/**
 * Read-only Firestore inventory: root + franchises/{id} subcollections + aggregate counts.
 * Auth: `gcloud auth print-access-token` (user must run `gcloud auth login`).
 * Does not write, delete, or export data.
 *
 * Usage: node scripts/firestore_readonly_inventory.mjs [--project=ID] [--out=path.md]
 */

import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..');

function parseArgs() {
  const out = { project: null, out: null };
  for (const a of process.argv.slice(2)) {
    if (a.startsWith('--project=')) out.project = a.slice('--project='.length);
    else if (a.startsWith('--out=')) out.out = a.slice('--out='.length);
  }
  return out;
}

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
  if (!res.ok) {
    throw new Error(`${init.method || 'GET'} ${url} -> ${res.status} ${text.slice(0, 500)}`);
  }
  return text ? JSON.parse(text) : {};
}

async function listRootCollectionIds(project, token) {
  const j = await rest(project, token, '/documents:listCollectionIds', {
    method: 'POST',
    body: JSON.stringify({}),
  });
  return j.collectionIds || [];
}

async function listFranchiseDocIds(project, token) {
  const ids = [];
  let pageToken = '';
  for (;;) {
    const q = pageToken ? `?pageToken=${encodeURIComponent(pageToken)}` : '';
    const j = await rest(project, token, `/documents/franchises${q}`);
    for (const d of j.documents || []) {
      const name = d.name || '';
      const id = name.split('/').pop();
      if (id) ids.push(id);
    }
    pageToken = j.nextPageToken;
    if (!pageToken) break;
  }
  return [...new Set(ids)].sort();
}

async function listSubcollectionIds(project, token, franchiseId) {
  const path = `/documents/franchises/${encodeURIComponent(franchiseId)}:listCollectionIds`;
  const j = await rest(project, token, path, { method: 'POST', body: JSON.stringify({}) });
  return j.collectionIds || [];
}

/** Firestore REST: runAggregationQuery with optional parent (scoped subcollection). */
async function countCollection(project, token, collectionId, parentDocPath = null) {
  const body = {
    structuredAggregationQuery: {
      structuredQuery: {
        from: [{ collectionId, allDescendants: false }],
      },
      aggregations: [{ alias: 'cnt', count: {} }],
    },
  };
  let path = '/documents:runAggregationQuery';
  if (parentDocPath) {
    const parent = `projects/${project}/databases/(default)/documents/${parentDocPath}`;
    path += `?parent=${encodeURIComponent(parent)}`;
  }
  const j = await rest(project, token, path, {
    method: 'POST',
    body: JSON.stringify(body),
  });
  const row = Array.isArray(j) ? j[0] : j;
  const v = row?.result?.aggregateFields?.cnt?.integerValue;
  return v != null ? Number(v) : null;
}

const COUNT_COLLECTIONS = [
  'araclar',
  'activities',
  'iadeIslemleri',
  'exitIslemleri',
  'office_operations',
  'servisFirmalari',
  'shuttleEntries',
  'shuttleSessions',
  'protocols',
  'assistantCompanies',
  'audit_logs',
];

function nowIso() {
  return new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
}

async function main() {
  const args = parseArgs();
  const project = args.project || gcloudProject();
  if (!project) {
    console.error('No GCP project. Set with: gcloud config set project YOUR_ID');
    process.exit(1);
  }
  const token = accessToken();
  const lines = [];
  const log = (s) => {
    lines.push(s);
    console.log(s);
  };

  log(`# Firestore read-only inventory`);
  log(``);
  log(`- **Generated:** ${new Date().toISOString()}`);
  log(`- **Project:** \`${project}\``);
  log(`- **Method:** gcloud user token + Firestore REST (no writes)`);
  log(``);

  log(`## Root collection IDs`);
  const rootIds = await listRootCollectionIds(project, token);
  log(``);
  log(rootIds.map((id) => `- \`${id}\``).join('\n'));
  log(``);

  log(`## Franchises documents`);
  const franchiseIds = await listFranchiseDocIds(project, token);
  log(``);
  log(franchiseIds.length ? franchiseIds.map((id) => `- \`${id}\``).join('\n') : '_none_');
  log(``);

  for (const fid of franchiseIds) {
    log(`### Subcollections under \`franchises/${fid}\``);
    const subs = await listSubcollectionIds(project, token, fid);
    log(``);
    log(subs.length ? subs.map((id) => `- \`${id}\``).join('\n') : '_none_');
    log(``);
  }

  log(`## Aggregate document counts (selected collections)`);
  log(``);
  log(`| Scope | Collection | Count |`);
  log(`|-------|------------|-------|`);

  for (const col of COUNT_COLLECTIONS) {
    try {
      const n = await countCollection(project, token, col, null);
      log(`| root | \`${col}\` | ${n} |`);
    } catch (e) {
      log(`| root | \`${col}\` | _error: ${String(e.message).slice(0, 80)}_ |`);
    }
  }

  for (const fid of franchiseIds) {
    const parentPath = `franchises/${fid}`;
    for (const col of COUNT_COLLECTIONS) {
      try {
        const n = await countCollection(project, token, col, parentPath);
        if (n === 0 || n > 0) {
          log(`| \`${parentPath}\` | \`${col}\` | ${n} |`);
        }
      } catch {
        // Subcollection may not exist — skip row
      }
    }
  }

  const countedScoped = new Set(COUNT_COLLECTIONS);
  log(``);
  log(`## Scoped-only counts (subcollections not in main table above)`);
  log(``);
  log(`| Scope | Collection | Count |`);
  log(`|-------|------------|-------|`);
  for (const fid of franchiseIds) {
    const parentPath = `franchises/${fid}`;
    let subs;
    try {
      subs = await listSubcollectionIds(project, token, fid);
    } catch {
      continue;
    }
    for (const col of subs.sort()) {
      if (countedScoped.has(col)) continue;
      try {
        const n = await countCollection(project, token, col, parentPath);
        if (n === 0 || n > 0) {
          log(`| \`${parentPath}\` | \`${col}\` | ${n} |`);
        }
      } catch (e) {
        log(`| \`${parentPath}\` | \`${col}\` | _error: ${String(e.message).slice(0, 60)}_ |`);
      }
    }
  }

  log(``);
  log(`## Firestore \`users\` documents (root)`);
  log(``);
  try {
    const u = await countCollection(project, token, 'users', null);
    log(`- **users (Firestore root) document count:** ${u}`);
  } catch (e) {
    log(`- **users count:** _error: ${String(e.message).slice(0, 120)}_`);
  }
  log(`- **Auth vs Firestore:** Firebase Console → Authentication → Users sayısını elle karşılaştırın (yetim profil kontrolü).`);
  log(``);
  log(`## Notes`);
  log(``);
  log(`- Compare **root** vs **franchises/{id}** counts for the same \`collectionId\` to see legacy vs scoped usage.`);
  log(`- Missing index errors on aggregate are unusual for simple count; row shows error snippet.`);
  log(``);

  const outName = args.out || join(REPO_ROOT, 'docs', `live-inventory-${nowIso()}.md`);
  writeFileSync(outName, lines.join('\n'), 'utf8');
  console.error(`\nWrote: ${outName}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
