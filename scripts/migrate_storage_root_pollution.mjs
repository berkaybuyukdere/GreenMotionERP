#!/usr/bin/env node
/**
 * Migrates legacy Storage root folders into franchises/{franchiseId}/...
 *
 * Defaults to dry-run (no writes). Use --apply to execute copy/delete.
 *
 * Example:
 *   node scripts/migrate_storage_root_pollution.mjs --project=greenmotionapp-33413 --bucket=greenmotionapp-33413.firebasestorage.app --dry-run
 *   node scripts/migrate_storage_root_pollution.mjs --project=greenmotionapp-33413 --bucket=greenmotionapp-33413.firebasestorage.app --apply --delete-source
 */

import { execSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..');

const TARGET_PREFIXES = [
  'exit_fotograflari',
  'iade_fotograflari',
  'office_operations',
  'hasar_fotograflari',
  'office_Return',
  'iade_signatures',
  'return_pdfs',
];

const DEFAULTS = {
  project: null,
  bucket: 'greenmotionapp-33413.firebasestorage.app',
  defaultFranchiseId: 'CH',
  dryRun: true,
  deleteSource: false,
  reportPath: null,
};

function parseArgs() {
  const cfg = { ...DEFAULTS };
  for (const arg of process.argv.slice(2)) {
    if (arg === '--apply') cfg.dryRun = false;
    else if (arg === '--dry-run') cfg.dryRun = true;
    else if (arg === '--delete-source') cfg.deleteSource = true;
    else if (arg.startsWith('--project=')) cfg.project = arg.slice('--project='.length);
    else if (arg.startsWith('--bucket=')) cfg.bucket = arg.slice('--bucket='.length);
    else if (arg.startsWith('--default-franchise=')) cfg.defaultFranchiseId = arg.slice('--default-franchise='.length).toUpperCase();
    else if (arg.startsWith('--report=')) cfg.reportPath = arg.slice('--report='.length);
  }
  return cfg;
}

function nowStamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function getProjectId() {
  return execSync('gcloud config get-value project', { encoding: 'utf8' }).trim();
}

function accessToken() {
  return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
}

async function storageGetJson(token, pathAndQuery) {
  const url = `https://storage.googleapis.com/storage/v1${pathAndQuery}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const text = await res.text();
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status} ${text.slice(0, 400)}`);
  return text ? JSON.parse(text) : {};
}

async function storagePostJson(token, pathAndQuery) {
  const url = `https://storage.googleapis.com/storage/v1${pathAndQuery}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`POST ${url} -> ${res.status} ${text.slice(0, 400)}`);
  return text ? JSON.parse(text) : {};
}

async function storageDelete(token, pathAndQuery) {
  const url = `https://storage.googleapis.com/storage/v1${pathAndQuery}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return false;
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`DELETE ${url} -> ${res.status} ${text.slice(0, 400)}`);
  }
  return true;
}

async function listObjects(bucket, token, prefix) {
  const out = [];
  let pageToken = '';
  for (;;) {
    const q = new URLSearchParams({
      prefix: `${prefix}/`,
      maxResults: '1000',
      fields: 'nextPageToken,items(name,metadata,size,updated,contentType)',
    });
    if (pageToken) q.set('pageToken', pageToken);
    const data = await storageGetJson(token, `/b/${encodeURIComponent(bucket)}/o?${q.toString()}`);
    for (const item of data.items || []) out.push(item);
    pageToken = data.nextPageToken;
    if (!pageToken) break;
  }
  return out;
}

function looksLikeFranchiseId(token) {
  return /^[a-z0-9_-]{2,8}$/i.test(token || '');
}

function inferFranchiseId(obj, defaultFranchiseId) {
  const meta = obj?.metadata || {};
  const metaCandidates = [
    meta.franchiseId,
    meta.franchiseID,
    meta.franchise,
    meta.countryCode,
    meta.country,
  ].filter(Boolean);
  if (metaCandidates.length > 0) {
    return {
      franchiseId: String(metaCandidates[0]).trim().toUpperCase(),
      reason: 'metadata',
      dropLeadingPathSegment: false,
    };
  }

  const parts = String(obj?.name || '').split('/').filter(Boolean);
  if (parts.length >= 3) {
    const maybeFranchise = parts[1];
    if (looksLikeFranchiseId(maybeFranchise) && !maybeFranchise.includes('.')) {
      return {
        franchiseId: maybeFranchise.toUpperCase(),
        reason: 'path-segment',
        dropLeadingPathSegment: true,
      };
    }
  }

  return {
    franchiseId: defaultFranchiseId,
    reason: 'default',
    dropLeadingPathSegment: false,
  };
}

function destinationForObject(objName, prefix, inferred) {
  const full = String(objName || '');
  const rootPrefix = `${prefix}/`;
  if (!full.startsWith(rootPrefix)) return null;
  let remainder = full.slice(rootPrefix.length);
  if (inferred.dropLeadingPathSegment) {
    const parts = remainder.split('/').filter(Boolean);
    remainder = parts.slice(1).join('/');
  }
  if (!remainder) return null;
  return `franchises/${inferred.franchiseId}/${prefix}/${remainder}`;
}

async function rewriteObject(token, bucket, fromName, toName) {
  let rewriteToken = '';
  for (;;) {
    const q = new URLSearchParams();
    if (rewriteToken) q.set('rewriteToken', rewriteToken);
    const result = await storagePostJson(
      token,
      `/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(fromName)}/rewriteTo/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(toName)}?${q.toString()}`
    );
    if (result.done) return result;
    rewriteToken = result.rewriteToken;
    if (!rewriteToken) throw new Error(`rewrite did not complete for ${fromName}`);
  }
}

async function main() {
  const cfg = parseArgs();
  cfg.project = cfg.project || getProjectId();
  if (!cfg.project) throw new Error('No GCP project configured. Use --project=...');
  const token = accessToken();

  const report = {
    generatedAt: new Date().toISOString(),
    project: cfg.project,
    bucket: cfg.bucket,
    dryRun: cfg.dryRun,
    deleteSource: cfg.deleteSource,
    defaultFranchiseId: cfg.defaultFranchiseId,
    prefixes: {},
    totals: {
      discovered: 0,
      planned: 0,
      copied: 0,
      deleted: 0,
      skippedAlreadyScoped: 0,
      failed: 0,
    },
  };

  for (const prefix of TARGET_PREFIXES) {
    const objects = await listObjects(cfg.bucket, token, prefix);
    const prefixStats = {
      discovered: objects.length,
      planned: 0,
      copied: 0,
      deleted: 0,
      skippedAlreadyScoped: 0,
      failed: 0,
      byReason: { metadata: 0, 'path-segment': 0, default: 0 },
      sampleActions: [],
    };
    report.totals.discovered += objects.length;

    for (const obj of objects) {
      const source = obj.name;
      if (!source || source.startsWith('franchises/')) {
        prefixStats.skippedAlreadyScoped += 1;
        report.totals.skippedAlreadyScoped += 1;
        continue;
      }

      const inferred = inferFranchiseId(obj, cfg.defaultFranchiseId);
      prefixStats.byReason[inferred.reason] += 1;
      const destination = destinationForObject(source, prefix, inferred);
      if (!destination) {
        prefixStats.failed += 1;
        report.totals.failed += 1;
        continue;
      }

      prefixStats.planned += 1;
      report.totals.planned += 1;

      if (prefixStats.sampleActions.length < 10) {
        prefixStats.sampleActions.push({
          source,
          destination,
          inferredBy: inferred.reason,
        });
      }

      if (cfg.dryRun) continue;

      try {
        await rewriteObject(token, cfg.bucket, source, destination);
        prefixStats.copied += 1;
        report.totals.copied += 1;
        if (cfg.deleteSource) {
          const deleted = await storageDelete(
            token,
            `/b/${encodeURIComponent(cfg.bucket)}/o/${encodeURIComponent(source)}`
          );
          if (deleted) {
            prefixStats.deleted += 1;
            report.totals.deleted += 1;
          }
        }
      } catch (error) {
        prefixStats.failed += 1;
        report.totals.failed += 1;
      }
    }

    report.prefixes[prefix] = prefixStats;
  }

  const reportFile = cfg.reportPath || join(REPO_ROOT, 'scripts', `storage-root-migration-report-${nowStamp()}.json`);
  mkdirSync(dirname(reportFile), { recursive: true });
  writeFileSync(reportFile, JSON.stringify(report, null, 2), 'utf8');

  console.log(JSON.stringify({
    ok: true,
    reportFile,
    totals: report.totals,
    dryRun: cfg.dryRun,
    bucket: cfg.bucket,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
