const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const FRANCHISE_SCOPED_STORAGE_PREFIXES = new Set([
  "traffic_fines",
  "banking_transactions",
  "semesInvoices",
  "semesinvoices",
  "protocolTemplates",
  "hasar_fotograflari",
  "iade_fotograflari",
  "exit_fotograflari",
  "office_operations",
  "office_Return",
  "iade_signatures",
  "return_pdfs",
  "frontDeskCustomers",
  "fileLibrary",
]);

const MAX_PHOTO_BYTES = 12 * 1024 * 1024;

/**
 * @param {string} franchiseId
 * @return {string}
 */
function activeFranchiseId(franchiseId) {
  return String(franchiseId || "CH").trim().toUpperCase();
}

/**
 * @param {string} path
 * @return {string}
 */
function normalizeStoragePath(path) {
  return String(path || "")
      .trim()
      .replace(/^gs:\/\/[^/]+\//, "")
      .replace(/^\/+/, "");
}

/**
 * @param {string} path
 * @return {string[]}
 */
function expandPhotoPathAliases(path) {
  const normalized = normalizeStoragePath(path);
  if (!normalized) {
    return [];
  }
  const variants = new Set([normalized]);
  if (normalized.startsWith("fotograflari/")) {
    const tail = normalized.slice("fotograflari/".length);
    variants.add(`hasar_fotograflari/${tail}`);
  }
  return Array.from(variants);
}

/**
 * @param {string} path
 * @param {string} franchiseId
 * @return {string}
 */
function toScopedStoragePath(path, franchiseId) {
  const normalized = normalizeStoragePath(path);
  if (!normalized) {
    return normalized;
  }
  if (normalized.startsWith("franchises/")) {
    return normalized;
  }
  const rootPrefix = normalized.split("/")[0];
  if (!FRANCHISE_SCOPED_STORAGE_PREFIXES.has(rootPrefix)) {
    return normalized;
  }
  return `franchises/${activeFranchiseId(franchiseId)}/${normalized}`;
}

/**
 * @param {string} path
 * @param {string} franchiseId
 * @return {string[]}
 */
function getStoragePathCandidates(path, franchiseId) {
  const aliases = expandPhotoPathAliases(path);
  const all = new Set();
  for (const alias of aliases) {
    const normalized = normalizeStoragePath(alias);
    if (!normalized) {
      continue;
    }
    if (normalized.startsWith("franchises/")) {
      const parts = normalized.split("/");
      if (parts.length > 3) {
        const currentFranchise = parts[1] || "";
        const remainder = parts.slice(2).join("/");
        [
          normalized,
          `franchises/${currentFranchise.toUpperCase()}/${remainder}`,
          `franchises/${currentFranchise.toLowerCase()}/${remainder}`,
          remainder,
        ].forEach((item) => all.add(item));
      } else {
        all.add(normalized);
      }
      continue;
    }
    const scoped = toScopedStoragePath(normalized, franchiseId);
    all.add(scoped);
    all.add(normalized);
  }
  return Array.from(all).filter(Boolean);
}

/**
 * @param {string} urlString
 * @return {string|null}
 */
function extractFirebaseStoragePath(urlString) {
  try {
    const url = new URL(urlString);
    if (!url.hostname.includes("firebasestorage.googleapis.com")) {
      return null;
    }
    const match = url.pathname.match(/\/o\/(.+)$/);
    if (!match || !match[1]) {
      return null;
    }
    return decodeURIComponent(match[1]);
  } catch (err) {
    return null;
  }
}

/**
 * @param {string} input
 * @param {string} franchiseId
 * @return {string[]}
 */
function storagePathCandidatesForPhotoRef(input, franchiseId) {
  const raw = String(input || "").trim();
  if (!raw || raw.startsWith("data:")) {
    return [];
  }
  if (raw.startsWith("http://") || raw.startsWith("https://")) {
    const storagePath = extractFirebaseStoragePath(raw);
    if (!storagePath) {
      return [];
    }
    return getStoragePathCandidates(storagePath, franchiseId);
  }
  return getStoragePathCandidates(raw, franchiseId);
}

/**
 * @param {*} db Firestore
 * @param {string} uid auth uid
 * @param {string} franchiseId franchise code
 * @return {Promise<boolean>}
 */
async function callerCanAccessFranchiseStorage(db, uid, franchiseId) {
  const fid = activeFranchiseId(franchiseId);
  if (!fid || !uid) {
    return false;
  }
  const snap = await db.collection("users").doc(uid).get();
  if (!snap.exists) {
    return false;
  }
  const d = snap.data() || {};
  if (String(d.role || "") === "globaladmin") {
    return true;
  }
  const inactive =
    d.isActive === false || d.isActive === 0 || d.isActive === "0";
  if (inactive) {
    return false;
  }
  const userFid = String(d.franchiseId || "").trim().toUpperCase();
  if (userFid === fid) {
    return true;
  }
  const scope =
    d.roleScope && typeof d.roleScope === "object" ? d.roleScope : {};
  const ids = Array.isArray(scope.franchiseIds) ? scope.franchiseIds : [];
  return ids.some((id) => activeFranchiseId(id) === fid);
}

/**
 * Server-side photo bytes for web PDF export (bypasses Storage bucket CORS).
 * @param {*} db Firestore
 * @return {Function} callable HTTPS function
 */
function createFetchPdfPhotoBytesCallable(db) {
  return onCall(
      {region: "us-central1", timeoutSeconds: 60, memory: "512MiB"},
      async (request) => {
        if (!request.auth) {
          throw new HttpsError("unauthenticated", "Authentication required");
        }
        const data = request.data || {};
        const photoRef = String(data.photoRef || "").trim();
        const franchiseId = activeFranchiseId(data.franchiseId);
        if (!photoRef) {
          throw new HttpsError("invalid-argument", "photoRef required");
        }
        if (!await callerCanAccessFranchiseStorage(
            db,
            request.auth.uid,
            franchiseId,
        )) {
          throw new HttpsError("permission-denied", "Franchise access denied");
        }

        const candidates =
          storagePathCandidatesForPhotoRef(photoRef, franchiseId);
        if (!candidates.length) {
          return {base64: null, mimeType: null, path: null};
        }

        const bucket = admin.storage().bucket();
        for (const candidate of candidates) {
          try {
            const file = bucket.file(candidate);
            const [exists] = await file.exists();
            if (!exists) {
              continue;
            }
            const [metadata] = await file.getMetadata();
            const size = Number(metadata.size || 0);
            if (size <= 0 || size > MAX_PHOTO_BYTES) {
              continue;
            }
            const [buf] = await file.download();
            return {
              base64: buf.toString("base64"),
              mimeType: metadata.contentType || "image/jpeg",
              path: candidate,
            };
          } catch (err) {
            /* try next candidate */
          }
        }

        return {base64: null, mimeType: null, path: null};
      },
  );
}

module.exports = {
  createFetchPdfPhotoBytesCallable,
  getStoragePathCandidates,
  storagePathCandidatesForPhotoRef,
};
