/**
 * Front-desk kiosk callables (unauthenticated intake + GRT for TR branches).
 * Ported from green-motion-web — region us-central1 (iOS + web kiosk).
 */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");
const {resolveOperationalFranchiseId} = require("./franchiseIdResolve");
const {
  buildKioskRentalTermsPdfForIntake,
  loadBundledLegalText,
} = require("./kioskRentalTermsPdf");

const KIOSK_REGION = "us-central1";
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const rateBucket = new Map();

/**
 * @param {string} key
 * @param {number} maxPerWindow
 * @param {number} windowMs
 */
function rateLimit(key, maxPerWindow, windowMs) {
  const now = Date.now();
  let bucket = rateBucket.get(key);
  if (!bucket || now - bucket.start > windowMs) {
    bucket = {start: now, n: 0};
    rateBucket.set(key, bucket);
  }
  bucket.n += 1;
  if (bucket.n > maxPerWindow) {
    throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Try again shortly.",
    );
  }
}

/**
 * @param {string} raw
 * @return {string}
 */
function normalizeFranchiseId(raw) {
  const s = String(raw || "").trim();
  if (!s || s.length > 80 || s === "." || s === ".." || s.includes("/")) {
    throw new HttpsError("invalid-argument", "Invalid franchiseId");
  }
  return resolveOperationalFranchiseId(s);
}

/**
 * @param {string} phone
 * @return {string}
 */
function normalizePhoneDigits(phone) {
  return String(phone || "").replace(/\D/g, "");
}

/**
 * @param {string} franchiseId
 * @param {string} phone
 * @param {number} submittedAtMillis
 * @return {string}
 */
function dedupeKey(franchiseId, phone, submittedAtMillis) {
  const day = new Date(submittedAtMillis).toISOString().slice(0, 10);
  return `${franchiseId}|${normalizePhoneDigits(phone)}|${day}`;
}

/**
 * @param {string} email
 * @return {boolean}
 */
function validateEmail(email) {
  const s = String(email || "").trim();
  if (s.length < 5 || s.length > 254) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}

/**
 * @param {string} email
 * @return {string}
 */
function customerRememberDocIdFromEmail(email) {
  return String(email || "")
      .trim()
      .toLowerCase()
      .replace(/\//g, "_")
      .replace(/#/g, "_")
      .replace(/\?/g, "_");
}

/**
 * @param {string} franchiseId
 * @return {boolean}
 */
function isTurkeyFranchiseId(franchiseId) {
  return String(franchiseId || "").trim().toUpperCase().startsWith("TR");
}

/**
 * @param {string} franchiseId
 * @return {boolean}
 */
function isSwissFrontDeskFranchise(franchiseId) {
  return /^CH/i.test(String(franchiseId || "").trim());
}

const SWISS_FD_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * @param {*} value
 * @return {string|null}
 */
function normalizeLegalText(value) {
  const txt = String(value || "").trim();
  return txt.length ? txt : null;
}

/**
 * @param {string} bucketName
 * @param {string} objectPath
 * @param {string} token
 * @return {string}
 */
function buildFirebaseStorageDownloadUrl(bucketName, objectPath, token) {
  const endpoint =
    process.env.FIREBASE_STORAGE_EMULATOR_HOST ||
    process.env.STORAGE_EMULATOR_HOST ||
    "https://firebasestorage.googleapis.com";
  const base = String(endpoint).replace(/\/$/, "");
  return `${base}/v0/b/${bucketName}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
}

/**
 * @param {import('firebase-admin/storage').File} file
 * @return {Promise<string>}
 */
async function ensureStorageDownloadToken(file) {
  const [meta] = await file.getMetadata();
  const raw = meta?.metadata?.firebaseStorageDownloadTokens;
  const existing = String(raw || "")
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean)[0];
  if (existing) return existing;
  const token = crypto.randomUUID();
  await file.setMetadata({
    metadata: {
      ...(meta.metadata || {}),
      firebaseStorageDownloadTokens: token,
    },
  });
  return token;
}

/**
 * @param {string} franchiseId
 * @param {string} customerDocId
 * @param {Buffer} pdfBuffer
 * @return {Promise<{pdfUrl: string, storagePath: string}>}
 */
async function uploadKioskRentalTermsPdfBuffer(
    franchiseId,
    customerDocId,
    pdfBuffer,
) {
  const storagePath =
    `franchises/${franchiseId}/kiosk-rental-terms/${customerDocId}.pdf`;
  const bucket = admin.storage().bucket();
  const file = bucket.file(storagePath);
  const downloadToken = crypto.randomUUID();
  await file.save(pdfBuffer, {
    metadata: {
      contentType: "application/pdf",
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
      },
    },
    resumable: false,
  });
  const pdfUrl = buildFirebaseStorageDownloadUrl(
      bucket.name,
      storagePath,
      downloadToken,
  );
  return {pdfUrl, storagePath};
}

/**
 * @param {string} pdfUrl
 * @param {string} storagePath
 * @param {string} languageCodeRaw
 * @return {object}
 */
function kioskRentalTermsFirestoreFields(pdfUrl, storagePath, languageCodeRaw) {
  const languageCode =
    String(languageCodeRaw || "tr").trim().toLowerCase() === "en" ? "en" : "tr";
  const docEntry = {
    url: pdfUrl,
    storagePath,
    source: "kiosk",
    uploadedAt: admin.firestore.Timestamp.now(),
  };
  return {
    "kioskRentalTermsPdfUrl": pdfUrl,
    "kioskRentalTermsPdfStoragePath": storagePath,
    "kioskRentalTermsSignedAt": admin.firestore.FieldValue.serverTimestamp(),
    "kioskRentalTermsLanguage": languageCode,
    "customerDocuments.generalRentalTerms":
      admin.firestore.FieldValue.arrayUnion(docEntry),
    languageCode,
  };
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} franchiseId
 * @param {object} fields
 * @return {Promise<void>}
 */
async function upsertCustomerContactRememberMerge(db, franchiseId, fields) {
  const email = String(fields.email || "").trim().toLowerCase();
  if (!validateEmail(email)) return;
  const docId = customerRememberDocIdFromEmail(email);
  const ref = db
      .collection("franchises")
      .doc(franchiseId)
      .collection("customerContactRemember")
      .doc(docId);
  const payload = {
    franchiseId,
    email,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const optionalKeys = [
    "firstName",
    "familyName",
    "lastName",
    "phone",
    "phoneDialCca2",
    "phoneNationalDigits",
    "addressLine",
    "city",
    "postalCode",
    "country",
    "lastSource",
  ];
  for (const k of optionalKeys) {
    const v = fields[k];
    if (v == null) continue;
    const s = typeof v === "string" ? v.trim() : v;
    if (s !== "" && s != null) payload[k] = s;
  }
  if (!payload.familyName && fields.lastName) {
    payload.familyName = String(fields.lastName).trim();
  }
  await ref.set(payload, {merge: true});
}

/**
 * @param {string} franchiseId
 * @param {string} customerDocId
 * @param {string} pdfBase64
 * @param {string} languageCodeRaw
 * @param {object} options
 * @return {Promise<{pdfUrl: string}>}
 */
async function persistKioskRentalTermsPdf(
    franchiseId,
    customerDocId,
    pdfBase64,
    languageCodeRaw,
    options = {},
) {
  const allowOverwrite = options.allowOverwrite === true;
  const pdf = String(pdfBase64 || "").trim();
  if (!pdf || pdf.length < 100) {
    throw new HttpsError("invalid-argument", "Empty PDF data");
  }
  if (pdf.length > 4200000) {
    throw new HttpsError("invalid-argument", "PDF too large");
  }
  if (!UUID_RE.test(customerDocId)) {
    throw new HttpsError("invalid-argument", "Invalid customerDocId");
  }

  const db = admin.firestore();
  const docRef = db
      .collection("franchises")
      .doc(franchiseId)
      .collection("frontDeskCustomers")
      .doc(customerDocId);

  const snap = await docRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Customer record not found");
  }
  const existing = snap.data() || {};
  if (existing.kioskRentalTermsPdfUrl && !allowOverwrite) {
    return {pdfUrl: existing.kioskRentalTermsPdfUrl};
  }

  const pdfBuffer = Buffer.from(pdf, "base64");
  const {pdfUrl, storagePath} = await uploadKioskRentalTermsPdfBuffer(
      franchiseId,
      customerDocId,
      pdfBuffer,
  );
  const fields = kioskRentalTermsFirestoreFields(
      pdfUrl,
      storagePath,
      languageCodeRaw,
  );
  delete fields.languageCode;
  await docRef.update(fields);
  return {pdfUrl};
}

/**
 * @param {import('firebase-functions/v2/https').CallableRequest} request
 * @return {Promise<object>}
 */
async function runGetFrontDeskLegalDocs(request) {
  const franchiseId = normalizeFranchiseId(request.data?.franchiseId);
  const db = admin.firestore();
  const snap = await db.collection("franchises").doc(franchiseId).get();
  const turkeyKiosk = isTurkeyFranchiseId(franchiseId);
  const bundledTr = turkeyKiosk ? loadBundledLegalText("tr") : "";
  const bundledEn = turkeyKiosk ? loadBundledLegalText("en") : "";

  if (!snap.exists) {
    return {
      franchiseId,
      termsConditionsTr: turkeyKiosk ? bundledTr || null : null,
      termsConditionsEn: turkeyKiosk ? bundledEn || null : null,
      termsConditionsDe: null,
      privacyPolicyTr: null,
      privacyPolicyEn: null,
      privacyPolicyDe: null,
      pdfLegalTextTr: turkeyKiosk ? bundledTr || null : null,
      pdfLegalTextEn: turkeyKiosk ? bundledEn || null : null,
    };
  }

  const data = snap.data() || {};
  return {
    franchiseId,
    termsConditionsTr: turkeyKiosk ?
      bundledTr || normalizeLegalText(data.termsConditionsTr) : null,
    termsConditionsEn: turkeyKiosk ?
      bundledEn || normalizeLegalText(data.termsConditionsEn) : null,
    termsConditionsDe: normalizeLegalText(data.termsConditionsDe),
    privacyPolicyTr: normalizeLegalText(data.privacyPolicyTr),
    privacyPolicyEn: normalizeLegalText(data.privacyPolicyEn),
    privacyPolicyDe: normalizeLegalText(data.privacyPolicyDe),
    pdfLegalTextTr: turkeyKiosk ?
      bundledTr || normalizeLegalText(data.pdfLegalTextTr) : null,
    pdfLegalTextEn: turkeyKiosk ?
      bundledEn || normalizeLegalText(data.pdfLegalTextEn) : null,
  };
}

/**
 * @param {import('firebase-functions/v2/https').CallableRequest} request
 * @return {Promise<object>}
 */
async function runLookupCustomerContactRemember(request) {
  const ip = String(
      request.rawRequest?.headers?.["x-forwarded-for"]?.split(",")[0] ||
      request.rawRequest?.socket?.remoteAddress ||
      "na",
  );
  rateLimit(`reml:${ip}`, 80, 3600000);
  const franchiseId = normalizeFranchiseId(request.data?.franchiseId);
  const email = String(request.data?.email || "").trim().toLowerCase();
  if (!validateEmail(email)) {
    throw new HttpsError("invalid-argument", "Invalid email");
  }
  const docId = customerRememberDocIdFromEmail(email);
  const snap = await admin
      .firestore()
      .collection("franchises")
      .doc(franchiseId)
      .collection("customerContactRemember")
      .doc(docId)
      .get();
  if (!snap.exists) {
    return {found: false};
  }
  const d = snap.data() || {};
  return {
    found: true,
    firstName: d.firstName || "",
    familyName: d.familyName || d.lastName || "",
    phone: d.phone || "",
    phoneDialCca2: d.phoneDialCca2 || "",
    phoneNationalDigits: d.phoneNationalDigits || "",
    addressLine: d.addressLine || "",
    city: d.city || "",
    postalCode: d.postalCode || "",
    country: d.country || "",
  };
}

/**
 * @param {import('firebase-functions/v2/https').CallableRequest} request
 * @return {Promise<object>}
 */
async function runSubmitFrontDeskIntake(request) {
  const ip = String(
      request.rawRequest?.headers?.["x-forwarded-for"]?.split(",")[0] ||
      request.rawRequest?.socket?.remoteAddress ||
      "na",
  );
  rateLimit(`sub:${ip}`, 25, 3600000);

  const franchiseId = normalizeFranchiseId(request.data?.franchiseId);
  const clientSubmissionId = String(request.data?.clientSubmissionId || "").trim();
  if (!UUID_RE.test(clientSubmissionId)) {
    throw new HttpsError("invalid-argument", "Invalid clientSubmissionId");
  }

  const rentalTermsAttempt =
    Array.isArray(request.data?.rentalTermsSignatures) &&
    request.data.rentalTermsSignatures.some((s) => String(s || "").trim().length > 40);
  if (rentalTermsAttempt && !isTurkeyFranchiseId(franchiseId)) {
    throw new HttpsError(
        "failed-precondition",
        "General Rental Terms (GRT) can only be signed at Türkiye kiosk branches.",
    );
  }

  const firstNameIn = String(request.data?.firstName || "").trim();
  const lastNameIn = String(request.data?.lastName || "").trim();
  let fullName = String(request.data?.fullName || "").trim();
  if (firstNameIn.length >= 1 && lastNameIn.length >= 1) {
    fullName = `${firstNameIn} ${lastNameIn}`.trim();
  }
  if (fullName.length < 2) {
    fullName = "Pending customer";
  }
  const phone = String(request.data?.phone || "").trim();
  const email = String(request.data?.email || "").trim().toLowerCase();
  const addressLine = String(request.data?.addressLine || "").trim();
  const city = String(request.data?.city || "").trim();
  const postalCode = String(request.data?.postalCode || "").trim();
  const country = String(request.data?.country || "").trim();
  const termsAccepted = request.data?.termsAccepted === true;
  const privacyAccepted = request.data?.privacyAccepted === true;

  if (fullName.length > 120) {
    throw new HttpsError("invalid-argument", "Invalid full name");
  }
  if (normalizePhoneDigits(phone).length < 6) {
    throw new HttpsError("invalid-argument", "Invalid telephone");
  }
  if (!validateEmail(email)) {
    throw new HttpsError("invalid-argument", "Invalid email");
  }
  if (addressLine.length < 2 || addressLine.length > 200) {
    throw new HttpsError("invalid-argument", "Invalid street / number");
  }
  if (city.length < 1 || city.length > 100) {
    throw new HttpsError("invalid-argument", "Invalid city");
  }
  if (postalCode.length < 2 || postalCode.length > 20) {
    throw new HttpsError("invalid-argument", "Invalid postal code");
  }
  if (country.length < 2 || country.length > 80) {
    throw new HttpsError("invalid-argument", "Invalid country");
  }
  if (!termsAccepted || !privacyAccepted) {
    throw new HttpsError(
        "invalid-argument",
        "Terms and Privacy Policy must be accepted",
    );
  }

  const now = Date.now();
  const key = dedupeKey(franchiseId, phone, now);
  const db = admin.firestore();
  const col = db
      .collection("franchises")
      .doc(franchiseId)
      .collection("frontDeskCustomers");
  const docRef = col.doc(clientSubmissionId);
  const turkeyKioskIntake = isTurkeyFranchiseId(franchiseId);
  const rentalTermsSignaturesEarly =
    turkeyKioskIntake && Array.isArray(request.data?.rentalTermsSignatures) ?
      request.data.rentalTermsSignatures
          .map((s) => String(s || "").trim())
          .filter((s) => s.length > 40) :
      [];
  const rentalTermsLangEarly = turkeyKioskIntake ?
    request.data?.rentalTermsLanguageCode || request.data?.languageCode :
    null;

  const existing = await docRef.get();
  if (existing.exists) {
    let kioskRentalTermsPdfUrl = null;
    if (rentalTermsSignaturesEarly.length > 0) {
      try {
        const pdfBuffer = await buildKioskRentalTermsPdfForIntake(
            db,
            franchiseId,
            {
              signatures: rentalTermsSignaturesEarly,
              languageCode: rentalTermsLangEarly,
              firstName: firstNameIn,
              lastName: lastNameIn,
              email,
              callOk: request.data?.callOk === true,
              emailOk: request.data?.emailOk === true,
              smsOk: request.data?.smsOk === true,
            },
        );
        const saved = await persistKioskRentalTermsPdf(
            franchiseId,
            clientSubmissionId,
            pdfBuffer.toString("base64"),
            rentalTermsLangEarly,
            {allowOverwrite: true},
        );
        kioskRentalTermsPdfUrl = saved.pdfUrl;
      } catch (e) {
        console.error(
            "[submitFrontDeskIntake] duplicate retry PDF failed:",
            e?.message || e,
        );
      }
    }
    return {
      success: true,
      id: clientSubmissionId,
      duplicate: true,
      kioskRentalTermsPdfUrl,
    };
  }

  try {
    const dupSnap = await col
        .where("dedupeKey", "==", key)
        .where(
            "submittedAt",
            ">",
            admin.firestore.Timestamp.fromMillis(now - 120000),
        )
        .limit(1)
        .get();
    if (!dupSnap.empty) {
      throw new HttpsError(
          "already-exists",
          "A submission was just received from this number. Please wait before trying again.",
      );
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error(
        "[submitFrontDeskIntake] duplicate query failed:",
        e?.message || e,
    );
    throw new HttpsError(
        "unavailable",
        "Could not verify duplicate status. Please retry.",
    );
  }

  const payload = {
    franchiseId,
    fullName,
    firstName: firstNameIn.length ? firstNameIn : null,
    lastName: lastNameIn.length ? lastNameIn : null,
    phone,
    email,
    addressLine,
    city,
    postalCode,
    country,
    clientSubmissionId,
    dedupeKey: key,
    status: "awaiting_staff",
    resCode: null,
    vehiclePlate: null,
    completedAt: null,
    submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    termsAccepted: true,
    privacyAccepted: true,
    legalAcceptedAt: admin.firestore.FieldValue.serverTimestamp(),
    callOk: request.data?.callOk === true,
    emailOk: request.data?.emailOk === true,
    smsOk: request.data?.smsOk === true,
  };
  if (isSwissFrontDeskFranchise(franchiseId)) {
    payload.retentionExpiresAt = admin.firestore.Timestamp.fromMillis(
        now + SWISS_FD_RETENTION_MS,
    );
    payload.swissFrontDeskRetentionPolicy = "CH-FADP-INTAKE-7D";
  }

  const rentalTermsSignatures =
    turkeyKioskIntake && Array.isArray(request.data?.rentalTermsSignatures) ?
      request.data.rentalTermsSignatures
          .map((s) => String(s || "").trim())
          .filter((s) => s.length > 40) :
      [];
  const rentalTermsLang = turkeyKioskIntake ?
    request.data?.rentalTermsLanguageCode || request.data?.languageCode :
    null;
  let kioskRentalTermsPdfUrl = null;
  if (rentalTermsSignatures.length > 0) {
    try {
      const pdfBuffer = await buildKioskRentalTermsPdfForIntake(
          db,
          franchiseId,
          {
            signatures: rentalTermsSignatures,
            languageCode: rentalTermsLang,
            firstName: firstNameIn,
            lastName: lastNameIn,
            email,
            callOk: request.data?.callOk === true,
            emailOk: request.data?.emailOk === true,
            smsOk: request.data?.smsOk === true,
          },
      );
      const {pdfUrl, storagePath} = await uploadKioskRentalTermsPdfBuffer(
          franchiseId,
          clientSubmissionId,
          pdfBuffer,
      );
      const grtFields = kioskRentalTermsFirestoreFields(
          pdfUrl,
          storagePath,
          rentalTermsLang,
      );
      delete grtFields.languageCode;
      Object.assign(payload, grtFields);
      kioskRentalTermsPdfUrl = pdfUrl;
    } catch (e) {
      console.error(
          "[submitFrontDeskIntake] rental terms PDF failed:",
          e?.message || e,
      );
      if (rentalTermsSignatures.length > 0) {
        throw new HttpsError(
            "internal",
            "General Rental Terms PDF could not be stored. Please try again.",
        );
      }
    }
  }

  await docRef.set(payload);

  try {
    await upsertCustomerContactRememberMerge(db, franchiseId, {
      email,
      firstName: firstNameIn || null,
      lastName: lastNameIn || null,
      phone,
      addressLine,
      city,
      postalCode,
      country,
      lastSource: "kiosk",
    });
  } catch (e) {
    console.warn(
        "[submitFrontDeskIntake] customerContactRemember",
        e?.message || e,
    );
  }

  return {
    success: true,
    id: clientSubmissionId,
    duplicate: false,
    kioskRentalTermsPdfUrl,
  };
}

/**
 * @param {import('firebase-functions/v2/https').CallableRequest} request
 * @return {Promise<object>}
 */
async function runGetKioskRentalTermsSignedUrl(request) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const franchiseId = normalizeFranchiseId(request.data?.franchiseId);
  if (!isTurkeyFranchiseId(franchiseId)) {
    throw new HttpsError(
        "failed-precondition",
        "General Rental Terms (GRT) kiosk PDFs are Turkey-only.",
    );
  }
  const customerDocId = String(request.data?.customerDocId || "").trim();
  if (!UUID_RE.test(customerDocId)) {
    throw new HttpsError("invalid-argument", "Invalid customerDocId");
  }

  const db = admin.firestore();
  const userSnap = await db.collection("users").doc(request.auth.uid).get();
  if (!userSnap.exists) {
    throw new HttpsError("permission-denied", "User profile missing");
  }
  const profile = userSnap.data() || {};
  if (profile.isActive === false) {
    throw new HttpsError("permission-denied", "Account inactive");
  }

  const fidUpper = String(franchiseId || "").trim().toUpperCase();
  const role = String(profile.role || "")
      .toLowerCase()
      .trim()
      .replace(/[\s_-]+/g, "");
  const isPlatformAdmin =
    role === "globaladmin" ||
    (role === "superadmin" && profile.isGlobalAdmin === true);
  const allowed = (() => {
    if (isPlatformAdmin) return true;
    const rs = profile.roleScope;
    if (rs && typeof rs === "object" && !Array.isArray(rs)) {
      const level = String(rs.level || "").toLowerCase().trim();
      if (level === "global") return true;
      const ids = Array.isArray(rs.franchiseIds) ?
        rs.franchiseIds
            .map((x) => String(x || "").trim().toUpperCase())
            .filter(Boolean) :
        [];
      if ((level === "franchise" || level === "country") && ids.includes(fidUpper)) {
        return true;
      }
      if (level === "country" && ids.length === 0) return true;
    }
    const scope = String(profile.scopeLevel || "single").toLowerCase().trim();
    if (scope === "country_all" || scope === "global") return true;
    const primary = String(profile.franchiseId || "").trim().toUpperCase();
    if (primary === fidUpper) return true;
    const mem = profile.franchiseMemberships;
    if (mem && typeof mem === "object") {
      for (const [k, v] of Object.entries(mem)) {
        if (v === true && String(k).trim().toUpperCase() === fidUpper) return true;
      }
    }
    return false;
  })();
  if (!allowed) {
    throw new HttpsError("permission-denied", "No access to this franchise");
  }

  const docRef = db
      .collection("franchises")
      .doc(franchiseId)
      .collection("frontDeskCustomers")
      .doc(customerDocId);
  const docSnap = await docRef.get();
  if (!docSnap.exists) {
    throw new HttpsError("not-found", "Front desk record not found");
  }
  const fdData = docSnap.data() || {};
  const storedPath = String(fdData.kioskRentalTermsPdfStoragePath || "").trim();
  const fallbackPath =
    `franchises/${franchiseId}/kiosk-rental-terms/${customerDocId}.pdf`;
  const objectPath = storedPath || fallbackPath;

  const bucket = admin.storage().bucket();
  const file = bucket.file(objectPath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("not-found", "Kiosk GRT PDF not found in storage");
  }
  const token = await ensureStorageDownloadToken(file);
  const signedUrl = buildFirebaseStorageDownloadUrl(
      bucket.name,
      objectPath,
      token,
  );
  const languageCode =
    String(fdData.kioskRentalTermsLanguage || "tr").toLowerCase() === "en" ?
      "en" :
      "tr";
  return {
    signedUrl,
    expiresAt: Date.now() + 60 * 60 * 1000,
    storagePath: objectPath,
    languageCode,
  };
}

const frontDeskIntakeOpts = {
  region: KIOSK_REGION,
  cors: true,
  invoker: "public",
  memory: "512MiB",
  timeoutSeconds: 120,
};

const frontDeskKioskExports = {
  submitFrontDeskIntake: onCall(frontDeskIntakeOpts, runSubmitFrontDeskIntake),
  frontDeskIntake: onCall(frontDeskIntakeOpts, runSubmitFrontDeskIntake),
  getFrontDeskLegalDocs: onCall(frontDeskIntakeOpts, runGetFrontDeskLegalDocs),
  lookupCustomerContactRemember: onCall(
      frontDeskIntakeOpts,
      runLookupCustomerContactRemember,
  ),
  getKioskRentalTermsSignedUrl: onCall(
      {region: KIOSK_REGION, cors: true, memory: "256MiB"},
      runGetKioskRentalTermsSignedUrl,
  ),
};

module.exports = frontDeskKioskExports;
