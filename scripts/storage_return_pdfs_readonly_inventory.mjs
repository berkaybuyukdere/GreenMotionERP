#!/usr/bin/env node
/**
 * Read-only GCS inventory for return PDF prefixes (legacy + franchises/{id}/return_pdfs).
 * Auth: `gcloud auth print-access-token`. No writes, no deletes.
 *
 * Uses Storage JSON API (same token as Firestore inventory). gsutil not required.
 *
 * Usage:
 *   node scripts/storage_return_pdfs_readonly_inventory.mjs [--bucket=NAME] [--project=ID] [--out=path.md]
 *
 * Default bucket matches app config: greenmotionapp-33413.firebasestorage.app
 */

import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..');

const DEFAULT_BUCKET = 'greenmotionapp-33413.firebasestorage.app';

function parseArgs() {
  const out = { project: null, bucket: null, out: null };
  for (const a of process.argv.slice(2)) {
    if (a.startsWith('--project=')) out.project = a.slice('--project='.length);
    else if (a.startsWith('--bucket=')) out.bucket = a.slice('--bucket='.length);
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

async function storageGet(token, pathAndQuery) {
  const url = `https://storage.googleapis.com/storage/v1${pathAndQuery}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`GET ${url} -> ${res.status} ${text.slice(0, 400)}`);
  }
  return text ? JSON.parse(text) : {};
}

/** Paginated object count under prefix (object metadata rows only). */
async function countObjectsWithPrefix(bucket, token, prefix) {
  let total = 0;
  let pageToken = '';
  for (;;) {
    const q = new URLSearchParams({
      prefix,
      maxResults: '1000',
      fields: 'nextPageToken,items(name)',
    });
    if (pageToken) q.set('pageToken', pageToken);
    const j = await storageGet(token, `/b/${encodeURIComponent(bucket)}/o?${q}`);
    total += (j.items || []).length;
    pageToken = j.nextPageToken;
    if (!pageToken) break;
  }
  return total;
}

/** List immediate "folders" under prefix (uses / delimiter). */
async function listPrefixes(bucket, token, prefix) {
  const q = new URLSearchParams({
    prefix,
    delimiter: '/',
    maxResults: '1000',
    fields: 'prefixes,nextPageToken',
  });
  const prefixes = [];
  let pageToken = '';
  for (;;) {
    const qq = new URLSearchParams(q);
    if (pageToken) qq.set('pageToken', pageToken);
    const j = await storageGet(token, `/b/${encodeURIComponent(bucket)}/o?${qq}`);
    for (const p of j.prefixes || []) prefixes.push(p);
    pageToken = j.nextPageToken;
    if (!pageToken) break;
  }
  return [...new Set(prefixes)].sort();
}

function franchiseIdFromPrefix(full) {
  // franchises/CH/ -> CH
  const m = full.match(/^franchises\/([^/]+)\/$/);
  return m ? m[1] : null;
}

function nowStamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
}

async function main() {
  const args = parseArgs();
  const project = args.project || gcloudProject();
  const bucket = args.bucket || DEFAULT_BUCKET;
  if (!project) {
    console.error('No GCP project. gcloud config set project YOUR_ID');
    process.exit(1);
  }
  const token = accessToken();
  const lines = [];
  const log = (s) => {
    lines.push(s);
    console.log(s);
  };

  log(`# Storage return_pdfs — read-only inventory`);
  log(``);
  log(`- **Generated:** ${new Date().toISOString()}`);
  log(`- **GCP project:** \`${project}\``);
  log(`- **Bucket:** \`${bucket}\``);
  log(`- **Method:** gcloud user token + Storage JSON API (no writes)`);
  log(``);

  log(`## Legacy prefix`);
  log(``);
  log(`| Prefix | Object count |`);
  log(`|--------|----------------|`);
  const legacyCount = await countObjectsWithPrefix(bucket, token, 'return_pdfs/');
  log(`| \`return_pdfs/\` | ${legacyCount} |`);
  log(``);

  log(`## Scoped prefixes (franchises/{id}/return_pdfs/)`);
  log(``);
  log(`| Franchise | Prefix | Object count |`);
  log(`|-----------|--------|--------------|`);

  const franchisePrefixes = await listPrefixes(bucket, token, 'franchises/');
  const franchiseIds = franchisePrefixes.map(franchiseIdFromPrefix).filter(Boolean);
  if (!franchiseIds.length) {
    log(`| _none_ | — | — |`);
  } else {
    for (const fid of franchiseIds) {
      const pref = `franchises/${fid}/return_pdfs/`;
      const n = await countObjectsWithPrefix(bucket, token, pref);
      log(`| \`${fid}\` | \`${pref}\` | ${n} |`);
    }
  }
  log(``);

  log(`## Notes`);
  log(``);
  log(`- PDF yolları uygulama / Cloud Functions içinde çoklu aday olarak denenir; envanter yalnızca nesne sayısıdır.`);
  log(`- Büyük bucket’larda sayım süresi pagination ile uzayabilir.`);

  const outName = args.out || join(REPO_ROOT, 'docs', `live-storage-inventory-${nowStamp()}.md`);
  writeFileSync(outName, lines.join('\n'), 'utf8');
  console.error(`\nWrote: ${outName}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
