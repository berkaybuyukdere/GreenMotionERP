#!/usr/bin/env node
/**
 * franchises/{franchise}/userPresence dokümanlarını listeler veya (ağır risk) siler.
 *
 * Varsayılan: salt okunur dry-run (liste + sayım).
 * Silme için: önce Firestore export tamamlanmış olmalı; aşağıdaki tüm bayraklar gerekir.
 *
 * Silme örneği:
 *   node scripts/firestore_cleanup_user_presence.mjs \
 *     --franchise=CH \
 *     --export-uri=gs://your-bucket/firestore-backups/20260330-1530 \
 *     --execute \
 *     --confirm=PRESENCE_DELETE_AFTER_BACKUP
 *
 * Tüm franchise’lar + kök (legacy) subcollection:
 *   node scripts/firestore_cleanup_user_presence.mjs --all-franchises --include-root-legacy ...
 */

import { execSync } from 'node:child_process';

const BASE = (project) =>
  `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`;

function parseArgs() {
  const o = {
    project: null,
    franchise: null,
    allFranchises: false,
    includeRootLegacy: false,
    exportUri: null,
    execute: false,
    confirm: null,
  };
  for (const a of process.argv.slice(2)) {
    if (a.startsWith('--project=')) o.project = a.slice('--project='.length);
    else if (a.startsWith('--franchise=')) o.franchise = a.slice('--franchise='.length);
    else if (a === '--all-franchises') o.allFranchises = true;
    else if (a === '--include-root-legacy') o.includeRootLegacy = true;
    else if (a.startsWith('--export-uri=')) o.exportUri = a.slice('--export-uri='.length);
    else if (a === '--execute') o.execute = true;
    else if (a.startsWith('--confirm=')) o.confirm = a.slice('--confirm='.length);
  }
  return o;
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
    throw new Error(`${init.method || 'GET'} ${url} -> ${res.status} ${text.slice(0, 500)}`);
  }
  return text ? JSON.parse(text) : {};
}

async function listRootUserPresenceDocs(project, token) {
  const rel = `/documents/userPresence`;
  const docs = [];
  let pageToken = '';
  for (;;) {
    const q = new URLSearchParams({ pageSize: '300' });
    if (pageToken) q.set('pageToken', pageToken);
    const j = await rest(project, token, `${rel}?${q}`);
    for (const d of j.documents || []) {
      const name = d.name || '';
      const id = name.split('/').pop();
      if (id) docs.push({ name, id, scope: 'root' });
    }
    pageToken = j.nextPageToken;
    if (!pageToken) break;
  }
  return docs;
}

async function listUserPresenceDocs(project, token, franchiseId) {
  const rel = `/documents/franchises/${encodeURIComponent(franchiseId)}/userPresence`;
  const docs = [];
  let pageToken = '';
  for (;;) {
    const q = new URLSearchParams({ pageSize: '300' });
    if (pageToken) q.set('pageToken', pageToken);
    const j = await rest(project, token, `${rel}?${q}`);
    for (const d of j.documents || []) {
      const name = d.name || '';
      const id = name.split('/').pop();
      if (id) docs.push({ name, id, scope: `franchises/${franchiseId}` });
    }
    pageToken = j.nextPageToken;
    if (!pageToken) break;
  }
  return docs;
}

/** fullName: projects/PROJECT/databases/(default)/documents/... */
async function deleteDoc(token, fullName) {
  const urlPath = fullName.split('/').map(encodeURIComponent).join('/');
  const url = `https://firestore.googleapis.com/v1/${urlPath}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`DELETE ${url} -> ${res.status} ${t.slice(0, 200)}`);
  }
}

async function main() {
  const args = parseArgs();
  const project = args.project || gcloudProject();
  if (!project) {
    console.error('gcloud config set project YOUR_ID');
    process.exit(1);
  }
  if (!args.allFranchises && !args.franchise) {
    console.error('Required: --franchise=ID or --all-franchises');
    process.exit(1);
  }
  if (args.allFranchises && args.franchise) {
    console.error('Use either --all-franchises or --franchise=, not both');
    process.exit(1);
  }

  const token = accessToken();
  let franchises = args.allFranchises ? await listFranchiseDocIds(project, token) : [args.franchise];
  if (args.allFranchises) {
    console.log(`Franchise documents to scan: ${franchises.length ? franchises.join(', ') : '(none)'}`);
  }

  /** @type {{name:string,id:string,scope:string}[]} */
  let docs = [];
  for (const fid of franchises) {
    const sub = await listUserPresenceDocs(project, token, fid);
    docs = docs.concat(sub);
  }
  if (args.includeRootLegacy) {
    const root = await listRootUserPresenceDocs(project, token);
    docs = docs.concat(root);
  }

  const byScope = new Map();
  for (const d of docs) {
    const k = d.scope;
    if (!byScope.has(k)) byScope.set(k, []);
    byScope.get(k).push(d);
  }
  for (const [scope, arr] of [...byScope.entries()].sort()) {
    console.log(`${scope}: userPresence documents: ${arr.length}`);
    for (const d of arr) console.log(`  - ${d.id}`);
  }

  if (!args.execute) {
    console.log(`\nTotal: ${docs.length} document(s). Dry-run only.`);
    console.log(
      'To delete after export: --export-uri=gs://... --execute --confirm=PRESENCE_DELETE_AFTER_BACKUP'
    );
    return;
  }

  if (!args.exportUri || !args.exportUri.startsWith('gs://')) {
    console.error('Delete requires --export-uri=gs://bucket/path-from-your-export');
    process.exit(1);
  }
  if (args.confirm !== 'PRESENCE_DELETE_AFTER_BACKUP') {
    console.error('Delete requires --confirm=PRESENCE_DELETE_AFTER_BACKUP (exact string)');
    process.exit(1);
  }

  console.error('\n*** DELETING userPresence DOCUMENTS ***\n');
  for (const d of docs) {
    await deleteDoc(token, d.name);
    console.error(`Deleted [${d.scope}] ${d.id}`);
  }
  console.error(`\nDone. ${docs.length} document(s) removed.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
