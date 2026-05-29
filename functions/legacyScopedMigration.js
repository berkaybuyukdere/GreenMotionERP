/**
 * Safe legacy root → franchises/{franchiseId}/ scoped Firestore migration.
 *
 * Principles:
 * - COPY first (never move/delete legacy until scoped copy is verified).
 * - Idempotent: re-run skips or re-verifies existing scoped docs.
 * - Batched with dry-run and per-invocation limits for callable timeouts.
 *
 * Invoke via Cloud Functions:
 *   migrateLegacyToScoped, cleanupVerifiedLegacyDocs, getLegacyScopedParity
 * Or locally:
 *   node scripts/backfill_firestore_scoped.js [--dry-run]
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const admin = require("firebase-admin");

const MIGRATION_META_FIELD = "_migration";
const LEGACY_MARKER_FIELD = "_migrationLegacy";

const MAP_PATH = path.resolve(
    __dirname,
    "../scripts/franchise-migration-map.json",
);

/**
 * @return {object}
 */
function loadMigrationMap() {
  return JSON.parse(fs.readFileSync(MAP_PATH, "utf8"));
}

/**
 * @param {string} raw
 * @param {string} fallback
 * @return {string}
 */
function normalizeFranchiseId(raw, fallback) {
  const value = String(raw || fallback || "CH").trim();
  return value ? value.toUpperCase() : "CH";
}

/**
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @param {string} uid caller uid
 * @return {Promise<object>} role and allowed flag
 */
async function assertMigrationCaller(db, uid) {
  const callerDoc = await db.collection("users").doc(uid).get();
  const role = callerDoc.exists && callerDoc.data().role ?
    String(callerDoc.data().role).toLowerCase() :
    null;
  const allowed = role === "superadmin" || role === "globaladmin";
  return {role, allowed};
}

/**
 * @param {*} value
 * @return {*}
 */
function serializeForCompare(value) {
  if (value === null || value === undefined) {
    return value;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return {_tsMillis: value.toMillis()};
  }
  if (value instanceof Date) {
    return {_tsMillis: value.getTime()};
  }
  if (Array.isArray(value)) {
    return value.map(serializeForCompare);
  }
  if (typeof value === "object") {
    const keys = Object.keys(value).sort();
    const out = {};
    for (const key of keys) {
      if (key === MIGRATION_META_FIELD || key === LEGACY_MARKER_FIELD) {
        continue;
      }
      out[key] = serializeForCompare(value[key]);
    }
    return out;
  }
  return value;
}

/**
 * @param {object} a
 * @param {object} b
 * @return {boolean}
 */
function payloadsMatch(a, b) {
  const left = serializeForCompare(a || {});
  const right = serializeForCompare(b || {});
  return JSON.stringify(left) === JSON.stringify(right);
}

/**
 * @param {object} data
 * @return {string}
 */
function payloadFingerprint(data) {
  const normalized = serializeForCompare(data || {});
  return crypto
      .createHash("sha256")
      .update(JSON.stringify(normalized))
      .digest("hex")
      .slice(0, 16);
}

/**
 * @param {string} collectionName
 * @param {string} docId
 * @return {string}
 */
function legacySourcePath(collectionName, docId) {
  return `${collectionName}/${docId}`;
}

/**
 * @param {string} franchiseId
 * @param {string} collectionName
 * @param {string} docId
 * @return {string}
 */
function scopedTargetPath(franchiseId, collectionName, docId) {
  return `franchises/${franchiseId}/${collectionName}/${docId}`;
}

/**
 * @param {FirebaseFirestore.DocumentSnapshot} legacySnap
 * @param {string} defaultFranchiseId
 * @return {string}
 */
function resolveDocFranchiseId(legacySnap, defaultFranchiseId) {
  const data = legacySnap.data() || {};
  return normalizeFranchiseId(data.franchiseId, defaultFranchiseId);
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} collectionName
 * @param {object} options
 * @return {Promise<object>}
 */
async function migrateLegacyCollectionBatch(db, collectionName, options) {
  const {
    defaultFranchiseId,
    dryRun,
    batchLimit,
    franchiseFilter,
    startAfterDocId,
    verifyAfterCopy,
    forceOverwriteOnMismatch,
  } = options;

  let query = db.collection(collectionName)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(batchLimit);

  if (startAfterDocId) {
    query = query.startAfter(startAfterDocId);
  }

  const snapshot = await query.get();
  const stats = {
    collection: collectionName,
    scanned: snapshot.size,
    copied: 0,
    skippedVerified: 0,
    skippedConflict: 0,
    markedLegacy: 0,
    errors: [],
    lastDocId: null,
    hasMore: snapshot.size >= batchLimit,
  };

  if (snapshot.empty) {
    return stats;
  }

  let batch = db.batch();
  let batchOps = 0;
  const commitBatch = async () => {
    if (!dryRun && batchOps > 0) {
      await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  };

  for (const legacySnap of snapshot.docs) {
    stats.lastDocId = legacySnap.id;
    const franchiseId = resolveDocFranchiseId(legacySnap, defaultFranchiseId);

    if (franchiseFilter) {
      const filterId = normalizeFranchiseId(franchiseFilter, franchiseId);
      if (filterId !== franchiseId) {
        continue;
      }
    }

    const sourcePath = legacySourcePath(collectionName, legacySnap.id);
    const targetPath = scopedTargetPath(
        franchiseId,
        collectionName,
        legacySnap.id,
    );
    const scopedRef = db.doc(targetPath);
    const legacyData = legacySnap.data() || {};

    try {
      const scopedSnap = await scopedRef.get();
      const migrationMeta = {
        sourcePath,
        legacyCollection: collectionName,
        legacyDocId: legacySnap.id,
        franchiseId,
      };

      if (scopedSnap.exists) {
        const scopedData = scopedSnap.data() || {};
        const match = payloadsMatch(legacyData, scopedData);
        if (match) {
          stats.skippedVerified++;
          if (!dryRun) {
            batch.set(scopedRef, {
              [MIGRATION_META_FIELD]: {
                ...migrationMeta,
                migratedAt: admin.firestore.FieldValue.serverTimestamp(),
                verified: true,
                verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                contentFingerprint: payloadFingerprint(legacyData),
              },
              franchiseId,
            }, {merge: true});
            batch.set(legacySnap.ref, {
              [LEGACY_MARKER_FIELD]: {
                scopedPath: targetPath,
                copyVerified: true,
                verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
            }, {merge: true});
            batchOps += 2;
            stats.markedLegacy++;
          }
        } else if (forceOverwriteOnMismatch) {
          if (!dryRun) {
            const payload = buildScopedPayload(
                legacyData,
                franchiseId,
                migrationMeta,
                verifyAfterCopy,
            );
            batch.set(scopedRef, payload, {merge: false});
            batchOps++;
          }
          stats.copied++;
        } else {
          stats.skippedConflict++;
          stats.errors.push({
            docId: legacySnap.id,
            reason: "scoped_exists_content_mismatch",
            targetPath,
          });
        }
      } else {
        if (!dryRun) {
          const payload = buildScopedPayload(
              legacyData,
              franchiseId,
              migrationMeta,
              verifyAfterCopy,
          );
          batch.set(scopedRef, payload, {merge: true});
          batch.set(legacySnap.ref, {
            [LEGACY_MARKER_FIELD]: {
              scopedPath: targetPath,
              copyVerified: verifyAfterCopy === true,
              migratedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          }, {merge: true});
          batchOps += 2;
          stats.markedLegacy++;
        }
        stats.copied++;
      }

      if (batchOps >= 400) {
        await commitBatch();
      }
    } catch (error) {
      stats.errors.push({
        docId: legacySnap.id,
        reason: error.message,
      });
    }
  }

  await commitBatch();
  return stats;
}

/**
 * @param {object} legacyData
 * @param {string} franchiseId
 * @param {object} migrationMeta
 * @param {boolean} verifyAfterCopy
 * @return {object}
 */
function buildScopedPayload(
    legacyData,
    franchiseId,
    migrationMeta,
    verifyAfterCopy,
) {
  const payload = {
    ...legacyData,
    franchiseId,
    [MIGRATION_META_FIELD]: {
      ...migrationMeta,
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      verified: verifyAfterCopy === true,
      verifiedAt: verifyAfterCopy === true ?
        admin.firestore.FieldValue.serverTimestamp() :
        null,
      contentFingerprint: payloadFingerprint(legacyData),
    },
  };
  return payload;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} collectionName
 * @param {object} options
 * @return {Promise<object>}
 */
async function cleanupVerifiedLegacyBatch(db, collectionName, options) {
  const {
    defaultFranchiseId,
    dryRun,
    batchLimit,
    franchiseFilter,
    startAfterDocId,
    requireLegacyMarker,
  } = options;

  let query = db.collection(collectionName)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(batchLimit);

  if (startAfterDocId) {
    query = query.startAfter(startAfterDocId);
  }

  const snapshot = await query.get();
  const stats = {
    collection: collectionName,
    scanned: snapshot.size,
    deleted: 0,
    skipped: 0,
    errors: [],
    lastDocId: null,
    hasMore: snapshot.size >= batchLimit,
  };

  for (const legacySnap of snapshot.docs) {
    stats.lastDocId = legacySnap.id;
    const legacyData = legacySnap.data() || {};
    const franchiseId = resolveDocFranchiseId(legacySnap, defaultFranchiseId);

    if (franchiseFilter) {
      const filterId = normalizeFranchiseId(franchiseFilter, franchiseId);
      if (filterId !== franchiseId) {
        stats.skipped++;
        continue;
      }
    }

    const marker = legacyData[LEGACY_MARKER_FIELD];
    if (requireLegacyMarker && (!marker || marker.copyVerified !== true)) {
      stats.skipped++;
      continue;
    }

    const targetPath = scopedTargetPath(
        franchiseId,
        collectionName,
        legacySnap.id,
    );

    try {
      const scopedSnap = await db.doc(targetPath).get();
      if (!scopedSnap.exists) {
        stats.skipped++;
        stats.errors.push({
          docId: legacySnap.id,
          reason: "scoped_copy_missing",
          targetPath,
        });
        continue;
      }

      const scopedData = scopedSnap.data() || {};
      const migration = scopedData[MIGRATION_META_FIELD] || {};
      const verified = migration.verified === true ||
        payloadsMatch(legacyData, scopedData);

      if (!verified) {
        stats.skipped++;
        stats.errors.push({
          docId: legacySnap.id,
          reason: "scoped_copy_not_verified",
          targetPath,
        });
        continue;
      }

      if (!dryRun) {
        await legacySnap.ref.delete();
      }
      stats.deleted++;
    } catch (error) {
      stats.errors.push({
        docId: legacySnap.id,
        reason: error.message,
      });
    }
  }

  return stats;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} options
 * @return {Promise<object>}
 */
async function getLegacyScopedParity(db, options) {
  const map = loadMigrationMap();
  const defaultFranchiseId = normalizeFranchiseId(
      options.defaultFranchiseId,
      map.defaultFranchiseId,
  );
  const collections = options.collections ||
    map.domainFirestoreCollections;
  const franchiseFilter = options.franchiseId ?
    normalizeFranchiseId(options.franchiseId, defaultFranchiseId) :
    null;

  const results = [];

  for (const collectionName of collections) {
    const legacySnap = await db.collection(collectionName).get();
    let legacyCount = 0;
    let scopedCount = 0;
    let missingInScoped = 0;
    const missingSample = [];

    for (const doc of legacySnap.docs) {
      const fid = resolveDocFranchiseId(doc, defaultFranchiseId);
      if (franchiseFilter && fid !== franchiseFilter) {
        continue;
      }
      legacyCount++;
      const scopedRef = db.doc(scopedTargetPath(fid, collectionName, doc.id));
      const scopedDoc = await scopedRef.get();
      if (!scopedDoc.exists) {
        missingInScoped++;
        if (missingSample.length < 10) {
          missingSample.push({
            docId: doc.id,
            franchiseId: fid,
            sourcePath: legacySourcePath(collectionName, doc.id),
          });
        }
      }
    }

    if (franchiseFilter) {
      const scopedSnap = await db.collection("franchises")
          .doc(franchiseFilter)
          .collection(collectionName)
          .get();
      scopedCount = scopedSnap.size;
    } else {
      const franchisesSnap = await db.collection("franchises").get();
      for (const fr of franchisesSnap.docs) {
        const sub = await fr.ref.collection(collectionName).get();
        scopedCount += sub.size;
      }
    }

    results.push({
      collection: collectionName,
      legacyCount,
      scopedCount,
      missingInScoped,
      missingSample,
    });
  }

  return {
    generatedAt: new Date().toISOString(),
    defaultFranchiseId,
    franchiseFilter,
    results,
  };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} requestData
 * @return {Promise<object>}
 */
async function runMigrateLegacyToScoped(db, requestData) {
  const map = loadMigrationMap();
  const dryRun = requestData && requestData.dryRun === true;
  const batchLimit = Math.min(
      Math.max(Number(requestData && requestData.batchLimit) || 100, 1),
      450,
  );
  const defaultFranchiseId = normalizeFranchiseId(
      requestData && requestData.defaultFranchiseId,
      map.defaultFranchiseId,
  );
  const franchiseFilter = requestData && requestData.franchiseId ?
    normalizeFranchiseId(requestData.franchiseId, defaultFranchiseId) :
    null;
  const startAfter = requestData && requestData.startAfter ?
    requestData.startAfter :
    {};
  const collections = (requestData && requestData.collections &&
    Array.isArray(requestData.collections) &&
    requestData.collections.length > 0) ?
    requestData.collections :
    map.domainFirestoreCollections;

  const collectionResults = [];
  for (const collectionName of collections) {
    const cursor = startAfter[collectionName] || null;
    const result = await migrateLegacyCollectionBatch(db, collectionName, {
      defaultFranchiseId,
      dryRun,
      batchLimit,
      franchiseFilter,
      startAfterDocId: cursor,
      verifyAfterCopy: requestData && requestData.verifyAfterCopy !== false,
      forceOverwriteOnMismatch:
        requestData && requestData.forceOverwriteOnMismatch === true,
    });
    collectionResults.push(result);
  }

  const nextStartAfter = {};
  for (const row of collectionResults) {
    if (row.hasMore && row.lastDocId) {
      nextStartAfter[row.collection] = row.lastDocId;
    }
  }

  return {
    dryRun,
    defaultFranchiseId,
    franchiseFilter,
    batchLimit,
    collectionResults,
    nextStartAfter: Object.keys(nextStartAfter).length ?
      nextStartAfter :
      null,
  };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} requestData
 * @return {Promise<object>}
 */
async function runCleanupVerifiedLegacy(db, requestData) {
  const map = loadMigrationMap();
  const dryRun = requestData && requestData.dryRun === true;
  const batchLimit = Math.min(
      Math.max(Number(requestData && requestData.batchLimit) || 50, 1),
      200,
  );
  const defaultFranchiseId = normalizeFranchiseId(
      requestData && requestData.defaultFranchiseId,
      map.defaultFranchiseId,
  );
  const franchiseFilter = requestData && requestData.franchiseId ?
    normalizeFranchiseId(requestData.franchiseId, defaultFranchiseId) :
    null;
  const startAfter = requestData && requestData.startAfter ?
    requestData.startAfter :
    {};
  const collections = (requestData && requestData.collections &&
    Array.isArray(requestData.collections) &&
    requestData.collections.length > 0) ?
    requestData.collections :
    map.domainFirestoreCollections;

  const collectionResults = [];
  for (const collectionName of collections) {
    const cursor = startAfter[collectionName] || null;
    const result = await cleanupVerifiedLegacyBatch(db, collectionName, {
      defaultFranchiseId,
      dryRun,
      batchLimit,
      franchiseFilter,
      startAfterDocId: cursor,
      requireLegacyMarker:
        requestData && requestData.requireLegacyMarker === true,
    });
    collectionResults.push(result);
  }

  const nextStartAfter = {};
  for (const row of collectionResults) {
    if (row.hasMore && row.lastDocId) {
      nextStartAfter[row.collection] = row.lastDocId;
    }
  }

  return {
    dryRun,
    defaultFranchiseId,
    franchiseFilter,
    batchLimit,
    collectionResults,
    nextStartAfter: Object.keys(nextStartAfter).length ?
      nextStartAfter :
      null,
  };
}

module.exports = {
  loadMigrationMap,
  assertMigrationCaller,
  migrateLegacyCollectionBatch,
  cleanupVerifiedLegacyBatch,
  getLegacyScopedParity,
  runMigrateLegacyToScoped,
  runCleanupVerifiedLegacy,
  legacySourcePath,
  scopedTargetPath,
  payloadsMatch,
  MIGRATION_META_FIELD,
  LEGACY_MARKER_FIELD,
};
