/**
 * Read-only spot check using firebase-admin + Application Default Credentials.
 * Run: gcloud auth application-default login
 * Then: cd functions && node scripts/firestore_readonly_inventory_admin.cjs
 */
const admin = require('firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'greenmotionapp-33413';

admin.initializeApp({ projectId });
const db = admin.firestore();

async function countCol(ref) {
  const snap = await ref.count().get();
  return snap.data().count;
}

async function main() {
  const rootArac = db.collection('araclar');
  const scopedArac = db.collection('franchises').doc('CH').collection('araclar');
  const [r, s] = await Promise.all([countCol(rootArac), countCol(scopedArac)]);
  console.log(JSON.stringify({ projectId, root_araclar: r, franchises_CH_araclar: s }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
