#!/usr/bin/env node
/**
 * Firestore tam export (yedek) — ücretli GCS yazımı yapar.
 *
 * Güvenlik kapıları (hepsi zorunlu):
 *   --destination=gs://BUCKET/firestore-backups/UNIQUE_FOLDER
 *   --acknowledge-cost
 *   --confirm=I_HAVE_AUTHORIZATION
 *
 * Örnek:
 *   node scripts/firestore_export_backup.mjs \
 *     --destination=gs://MY_SECURE_BUCKET/firestore-backups/20260330-1530 \
 *     --acknowledge-cost \
 *     --confirm=I_HAVE_AUTHORIZATION
 *
 * Önkoşul: gcloud auth login; bucket’ta Firestore service account export izni.
 */

import { execSync, spawnSync } from 'child_process';

function parseArgs() {
  const o = { destination: null, project: null, acknowledgeCost: false, confirm: null };
  for (const a of process.argv.slice(2)) {
    if (a.startsWith('--destination=')) o.destination = a.slice('--destination='.length);
    else if (a.startsWith('--project=')) o.project = a.slice('--project='.length);
    else if (a === '--acknowledge-cost') o.acknowledgeCost = true;
    else if (a.startsWith('--confirm=')) o.confirm = a.slice('--confirm='.length);
  }
  return o;
}

function gcloudProject() {
  return execSync('gcloud config get-value project', { encoding: 'utf8' }).trim();
}

function main() {
  const args = parseArgs();
  const project = args.project || gcloudProject();
  if (!project) {
    console.error('Set project: gcloud config set project YOUR_ID');
    process.exit(1);
  }
  if (!args.destination || !args.destination.startsWith('gs://')) {
    console.error('Required: --destination=gs://BUCKET/path/to/export-folder');
    process.exit(1);
  }
  if (!args.acknowledgeCost) {
    console.error('Required: --acknowledge-cost (export has billing / storage cost)');
    process.exit(1);
  }
  if (args.confirm !== 'I_HAVE_AUTHORIZATION') {
    console.error(
      'Required: --confirm=I_HAVE_AUTHORIZATION (typos rejected — copy exact value)'
    );
    process.exit(1);
  }

  console.error('\n*** FIRESTORE EXPORT TO GCS — WILL WRITE TO BUCKET ***\n');
  console.error('Destination:', args.destination);
  console.error('Project:', project);
  console.error('');

  const r = spawnSync(
    'gcloud',
    ['firestore', 'export', args.destination, '--database=(default)', `--project=${project}`],
    { stdio: 'inherit' }
  );
  process.exit(r.status === null ? 1 : r.status);
}

main();
