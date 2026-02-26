/**
 * Firebase Cloud Functions for Push Notifications
 * Version 2 API (firebase-functions v6)
 *
 * This file should be placed in: functions/index.js
 * After creating Firebase Functions with: firebase init functions
 */

const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();

// Firestore reference
const db = admin.firestore();

/**
 * Builds deterministic idempotency lock key.
 * @param {string} type lock type prefix
 * @param {string} rawKey source uniqueness payload
 * @return {string} lock document id
 */
function makeIdempotencyKey(type, rawKey) {
  const hash = crypto.createHash("sha256").update(String(rawKey)).digest("hex");
  return `${type}_${hash}`;
}

/**
 * Attempts to claim a one-time processing lock.
 * @param {string} type lock type prefix
 * @param {string} rawKey source uniqueness payload
 * @param {Object} context debug metadata
 * @return {Promise<{created: boolean, key: string}>} lock result
 */
async function claimIdempotency(type, rawKey, context = {}) {
  const key = makeIdempotencyKey(type, rawKey);
  const ref = db.collection("_functionLocks").doc(key);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const created = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      return false;
    }
    tx.set(ref, {
      type,
      rawKey: String(rawKey).slice(0, 1024),
      context,
      createdAt: now,
    });
    return true;
  });

  return {created, key};
}

/**
 * Sends push notifications when a new document
 * is created in the 'notifications' collection
 * @param {*} event Firestore trigger event
 * @param {string} source legacy or scoped trigger
 * @return {Promise} processing result
 */
async function processNotificationEvent(event, source) {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("No data associated with the event");
    return null;
  }

  const data = snapshot.data();
  const notificationId = event.params.notificationId;
  const rawKey = data.idempotencyKey ||
    `${notificationId}|${data.franchiseId || "CH"}|${source}`;
  const lock = await claimIdempotency("notification", rawKey, {
    source,
    notificationId,
  });
  if (!lock.created) {
    console.log(`⏭️ [CF] Duplicate notification skipped (${lock.key})`);
    await snapshot.ref.delete();
    return null;
  }

  console.log("📬 [CF] ========== Cloud Function Triggered ==========");
  console.log(`📬 [CF] Notification ID: ${notificationId}`);
  console.log(`📬 [CF] Data received:`, JSON.stringify(data, null, 2));

  const title = data.title || "Green Motion";
  const body = data.body || "New notification";
  const tokens = data.tokens || [];
  const notificationData = data.data || {};

  if (!tokens || tokens.length === 0) {
    console.log("⚠️ [CF] No FCM tokens found. Skipping notification.");
    await snapshot.ref.delete();
    return null;
  }

  const message = {
    notification: {title, body},
    data: {
      ...notificationData,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    tokens,
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          "sound": "default",
          "badge": 1,
          "content-available": 1,
          "mutable-content": 1,
        },
      },
    },
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    if (response.failureCount > 0) {
      response.responses.forEach((resp, idx) => {
        if (!resp.success && resp.error) {
          const isInvalidToken =
            resp.error.code === "messaging/invalid-registration-token";
          const isNotRegistered =
            resp.error.code === "messaging/registration-token-not-registered";
          if (isInvalidToken || isNotRegistered) {
            const invalidToken = tokens[idx];
            admin.firestore()
                .collection("users")
                .where("fcmToken", "==", invalidToken)
                .get()
                .then((userSnapshot) => {
                  userSnapshot.forEach((doc) => {
                    doc.ref.update({
                      fcmToken: admin.firestore.FieldValue.delete(),
                    });
                  });
                })
                .catch((err) => {
                  console.error("❌ [CF] Error removing token:", err);
                });
          }
        }
      });
    }

    await snapshot.ref.delete();
    return response;
  } catch (error) {
    console.error("❌ [CF] Error sending notification:", error);
    return null;
  }
}

exports.sendNotification = onDocumentCreated(
    "notifications/{notificationId}",
    async (event) => processNotificationEvent(event, "legacy"),
);

exports.sendNotificationScoped = onDocumentCreated(
    "franchises/{franchiseId}/notifications/{notificationId}",
    async (event) => processNotificationEvent(event, "scoped"),
);

/**
 * Sends queued return emails using SMTP configuration stored in Firestore.
 * Triggered when a document is created under outgoingEmails.
 * @param {*} event Firestore trigger event
 * @param {string} source legacy or scoped trigger
 * @return {Promise} no response payload
 */
async function processQueuedEmailEvent(event, source) {
  const snapshot = event.data;
  if (!snapshot) return null;

  const emailId = event.params.emailId;
  const payload = snapshot.data();
  const franchiseId = (payload.franchiseId || "CH").toUpperCase();
  const rawKey = payload.idempotencyKey ||
    `${payload.returnId || emailId}|${payload.to || ""}|${franchiseId}`;
  const lock = await claimIdempotency("outgoing_email", rawKey, {
    source,
    emailId,
    franchiseId,
  });
  if (!lock.created) {
    console.log(`⏭️ [CF] Duplicate email skipped (${lock.key})`);
    await snapshot.ref.update({
      status: "duplicate_skipped",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return null;
  }

  try {
    const configDoc = await db.collection("smtpConfigurations")
        .doc(franchiseId)
        .get();

    if (!configDoc.exists) {
      await snapshot.ref.update({
        status: "failed",
        error: "Missing SMTP configuration",
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return null;
    }

    const smtp = configDoc.data();
    const transporter = nodemailer.createTransport({
      host: smtp.host,
      port: smtp.port,
      secure: smtp.useTLS === true && Number(smtp.port) === 465,
      requireTLS: smtp.useTLS === true,
      auth: {
        user: smtp.username,
        pass: smtp.password,
      },
    });

    const attachments = [];
    let pdfBuffer = null;
    if (payload.pdfURL) {
      const response = await fetch(payload.pdfURL);
      if (!response.ok) {
        throw new Error(`PDF download failed: HTTP ${response.status}`);
      }
      const arrayBuffer = await response.arrayBuffer();
      pdfBuffer = Buffer.from(arrayBuffer);
    } else if (payload.returnId) {
      const scopedFallbackPath =
        `franchises/${franchiseId}/return_pdfs/${payload.returnId}.pdf`;
      const legacyFallbackPath = `return_pdfs/${payload.returnId}.pdf`;
      const scopedFile = admin.storage().bucket().file(scopedFallbackPath);
      const legacyFile = admin.storage().bucket().file(legacyFallbackPath);
      const scopedExists = await scopedFile.exists();
      if (scopedExists[0]) {
        const downloaded = await scopedFile.download();
        pdfBuffer = downloaded[0];
      } else {
        const legacyExists = await legacyFile.exists();
        if (legacyExists[0]) {
          const downloaded = await legacyFile.download();
          pdfBuffer = downloaded[0];
        }
      }
    }

    if (!pdfBuffer) {
      throw new Error("Missing PDF content for queued return email");
    }

    attachments.push({
      filename: `return_${payload.vehiclePlate || "document"}.pdf`,
      content: pdfBuffer,
      contentType: "application/pdf",
    });

    const htmlBody = `
      <p>${payload.body || ""}</p>
      <p>This document serves as proof that the vehicle has been delivered.</p>
    `;

    await transporter.sendMail({
      from: `"${smtp.senderName || "ERPX"}" <${smtp.senderEmail}>`,
      to: payload.to,
      subject: payload.subject || "Return Confirmation",
      text: payload.body || "",
      html: htmlBody,
      attachments,
    });

    await snapshot.ref.update({
      status: "sent",
      error: admin.firestore.FieldValue.delete(),
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`✅ Email sent for queue item ${emailId}`);
    return null;
  } catch (error) {
    console.error(`❌ Email send failed for ${emailId}:`, error);
    await snapshot.ref.update({
      status: "failed",
      error: error.message || "Unknown email error",
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return null;
  }
}

exports.sendQueuedEmail = onDocumentCreated(
    "outgoingEmails/{emailId}",
    async (event) => processQueuedEmailEvent(event, "legacy"),
);

exports.sendQueuedEmailScoped = onDocumentCreated(
    "franchises/{franchiseId}/outgoingEmails/{emailId}",
    async (event) => processQueuedEmailEvent(event, "scoped"),
);

/**
 * Clean up expired FCM tokens
 * Runs daily at midnight UTC
 */
exports.cleanupExpiredTokens = onSchedule("0 0 * * *", async () => {
  console.log("🧹 Starting cleanup of expired FCM tokens");

  try {
    const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
    const usersSnapshot = await admin.firestore()
        .collection("users")
        .where("lastTokenUpdate", "<",
            admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
        .get();

    let deletedCount = 0;
    const batch = admin.firestore().batch();

    usersSnapshot.forEach((doc) => {
      batch.update(doc.ref, {
        fcmToken: admin.firestore.FieldValue.delete(),
        lastTokenUpdate: admin.firestore.FieldValue.delete(),
      });
      deletedCount++;
    });

    if (deletedCount > 0) {
      await batch.commit();
      console.log(`✅ Cleaned up ${deletedCount} expired tokens`);
    } else {
      console.log("✅ No expired tokens to clean up");
    }

    return null;
  } catch (error) {
    console.error("❌ Error during token cleanup:", error);
    return null;
  }
});

/**
 * Optional: Send a welcome notification when a new user is created
 */
exports.sendWelcomeNotification = onDocumentCreated(
    "users/{userId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      const userData = snapshot.data();
      const fcmToken = userData.fcmToken;

      if (!fcmToken) {
        const msg = "⚠️ No FCM token for new user";
        console.log(msg + ", skipping welcome notification");
        return;
      }

      const userName = userData.fullName || "there";
      const welcomeMsg = `Hi ${userName}! Your account has been created.`;

      const message = {
        notification: {
          title: "👋 Welcome to Green Motion!",
          body: welcomeMsg,
        },
        token: fcmToken,
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      try {
        await admin.messaging().send(message);
        console.log(`✅ Welcome notification sent to ${userData.email}`);
      } catch (error) {
        console.error("❌ Error sending welcome notification:", error);
      }

      return null;
    },
);

// ============================================================================
// MULTI-FRANCHISE MANAGEMENT FUNCTIONS
// ============================================================================

/**
 * Cleanup expired demo accounts
 * Runs daily at 2:00 AM UTC
 * Deactivates users whose demoExpiresAt has passed
 */
exports.cleanupExpiredDemos = onSchedule("0 2 * * *", async () => {
  console.log("🧹 [Demo Cleanup] Starting cleanup of expired demo accounts");

  try {
    const now = admin.firestore.Timestamp.now();

    // Find all expired demo users
    const expiredUsersSnapshot = await db
        .collection("users")
        .where("isDemo", "==", true)
        .where("demoExpiresAt", "<", now)
        .where("isActive", "==", true)
        .get();

    if (expiredUsersSnapshot.empty) {
      console.log("✅ [Demo Cleanup] No expired demo accounts found");
      return null;
    }

    console.log(`🔍 [Demo Cleanup] Found ${expiredUsersSnapshot.size} ` +
      "expired demo accounts");

    const batch = db.batch();
    const franchiseUpdates = {};
    let deactivatedCount = 0;

    expiredUsersSnapshot.forEach((userDoc) => {
      const userData = userDoc.data();

      // Deactivate the user
      batch.update(userDoc.ref, {
        isActive: false,
        updatedAt: now,
        updatedBy: "system:demo_cleanup",
      });

      // Track franchise user count decrease
      const franchiseId = userData.franchiseId;
      if (franchiseId) {
        franchiseUpdates[franchiseId] =
          (franchiseUpdates[franchiseId] || 0) + 1;
      }

      deactivatedCount++;
      console.log(`🚫 [Demo Cleanup] Deactivating: ${userData.email}`);
    });

    await batch.commit();

    // Update franchise user counts
    for (const [franchiseId, count] of Object.entries(franchiseUpdates)) {
      const franchiseRef = db.collection("franchises").doc(franchiseId);
      await franchiseRef.update({
        currentUserCount: admin.firestore.FieldValue.increment(-count),
        updatedAt: now,
      });
      console.log(`📊 [Demo Cleanup] Updated franchise ${franchiseId}: ` +
        `decreased by ${count}`);
    }

    console.log(`✅ [Demo Cleanup] Deactivated ${deactivatedCount} ` +
      "expired demo accounts");

    // Also clean up demo franchise data if needed (optional)
    // This would delete old demo data after expiration

    return null;
  } catch (error) {
    console.error("❌ [Demo Cleanup] Error:", error);
    return null;
  }
});

/**
 * Send demo expiration warning emails
 * Runs daily at 9:00 AM UTC
 * Sends warning to users with 7, 3, and 1 days remaining
 */
exports.sendDemoExpirationWarning = onSchedule("0 9 * * *", async () => {
  console.log("📧 [Demo Warning] Starting demo expiration warning check");

  try {
    const now = new Date();
    const warningDays = [7, 3, 1];

    for (const days of warningDays) {
      const targetDate = new Date(now);
      targetDate.setDate(targetDate.getDate() + days);

      // Set to start of day
      targetDate.setHours(0, 0, 0, 0);
      const targetStart = admin.firestore.Timestamp.fromDate(targetDate);

      // Set to end of day
      const targetEnd = new Date(targetDate);
      targetEnd.setHours(23, 59, 59, 999);
      const targetEndTs = admin.firestore.Timestamp.fromDate(targetEnd);

      const usersSnapshot = await db
          .collection("users")
          .where("isDemo", "==", true)
          .where("isActive", "==", true)
          .where("demoExpiresAt", ">=", targetStart)
          .where("demoExpiresAt", "<=", targetEndTs)
          .get();

      if (!usersSnapshot.empty) {
        console.log(`📧 [Demo Warning] ${usersSnapshot.size} users ` +
          `expiring in ${days} days`);

        usersSnapshot.forEach((userDoc) => {
          const userData = userDoc.data();
          console.log(`📧 [Demo Warning] Would notify: ${userData.email} ` +
            `(${days} days remaining)`);
          // TODO: Send actual email notification
          // Could integrate with SendGrid, Mailgun, or Firebase Extensions
        });
      }
    }

    console.log("✅ [Demo Warning] Completed warning check");
    return null;
  } catch (error) {
    console.error("❌ [Demo Warning] Error:", error);
    return null;
  }
});

/**
 * Update franchise user count when a user is created
 */
exports.onUserCreated = onDocumentCreated(
    "users/{userId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      const userData = snapshot.data();
      const franchiseId = userData.franchiseId;

      if (!franchiseId) {
        console.log("📊 [User Count] No franchise ID for user, skipping");
        return null;
      }

      console.log(`📊 [User Count] User created in franchise: ${franchiseId}`);

      try {
        const franchiseRef = db.collection("franchises").doc(franchiseId);
        const franchiseDoc = await franchiseRef.get();

        if (!franchiseDoc.exists) {
          // Try to find by franchiseId field
          const franchiseQuery = await db
              .collection("franchises")
              .where("franchiseId", "==", franchiseId)
              .limit(1)
              .get();

          if (!franchiseQuery.empty) {
            await franchiseQuery.docs[0].ref.update({
              currentUserCount: admin.firestore.FieldValue.increment(1),
              updatedAt: admin.firestore.Timestamp.now(),
            });
            console.log(`✅ [User Count] Incremented count for ${franchiseId}`);
          }
        } else {
          await franchiseRef.update({
            currentUserCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.Timestamp.now(),
          });
          console.log(`✅ [User Count] Incremented count for ${franchiseId}`);
        }

        return null;
      } catch (error) {
        console.error("❌ [User Count] Error updating franchise count:", error);
        return null;
      }
    },
);

/**
 * Update franchise user count when a user is deleted
 */
exports.onUserDeleted = onDocumentDeleted(
    "users/{userId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      const userData = snapshot.data();
      const franchiseId = userData.franchiseId;

      if (!franchiseId) {
        console.log("📊 [User Count] No franchise ID for deleted user");
        return null;
      }

      // Only decrement if user was active
      if (userData.isActive === false) {
        console.log("📊 [User Count] Deleted user was inactive, skipping");
        return null;
      }

      console.log(`📊 [User Count] User deleted from franchise: ${franchiseId}`);

      try {
        const franchiseRef = db.collection("franchises").doc(franchiseId);
        const franchiseDoc = await franchiseRef.get();

        if (!franchiseDoc.exists) {
          const franchiseQuery = await db
              .collection("franchises")
              .where("franchiseId", "==", franchiseId)
              .limit(1)
              .get();

          if (!franchiseQuery.empty) {
            await franchiseQuery.docs[0].ref.update({
              currentUserCount: admin.firestore.FieldValue.increment(-1),
              updatedAt: admin.firestore.Timestamp.now(),
            });
            console.log(`✅ [User Count] Decremented count for ${franchiseId}`);
          }
        } else {
          await franchiseRef.update({
            currentUserCount: admin.firestore.FieldValue.increment(-1),
            updatedAt: admin.firestore.Timestamp.now(),
          });
          console.log(`✅ [User Count] Decremented count for ${franchiseId}`);
        }

        return null;
      } catch (error) {
        console.error("❌ [User Count] Error updating franchise count:", error);
        return null;
      }
    },
);

/**
 * Update franchise user count when a user status changes
 * (activated or deactivated)
 */
exports.onUserStatusChanged = onDocumentUpdated(
    "users/{userId}",
    async (event) => {
      const beforeData = event.data.before.data();
      const afterData = event.data.after.data();

      // Check if isActive changed
      if (beforeData.isActive === afterData.isActive) {
        return null;
      }

      const franchiseId = afterData.franchiseId;
      if (!franchiseId) {
        return null;
      }

      const wasActive = beforeData.isActive !== false;
      const isNowActive = afterData.isActive !== false;

      // Determine increment (1 if activated, -1 if deactivated)
      const incrementValue = isNowActive ? 1 : -1;

      // Only update if there's an actual change
      if (wasActive === isNowActive) {
        return null;
      }

      console.log(`📊 [User Status] User ${afterData.email} ` +
        `${isNowActive ? "activated" : "deactivated"}`);

      try {
        const franchiseRef = db.collection("franchises").doc(franchiseId);
        const franchiseDoc = await franchiseRef.get();

        if (!franchiseDoc.exists) {
          const franchiseQuery = await db
              .collection("franchises")
              .where("franchiseId", "==", franchiseId)
              .limit(1)
              .get();

          if (!franchiseQuery.empty) {
            await franchiseQuery.docs[0].ref.update({
              currentUserCount:
                admin.firestore.FieldValue.increment(incrementValue),
              updatedAt: admin.firestore.Timestamp.now(),
            });
          }
        } else {
          await franchiseRef.update({
            currentUserCount:
              admin.firestore.FieldValue.increment(incrementValue),
            updatedAt: admin.firestore.Timestamp.now(),
          });
        }

        console.log(`✅ [User Status] Updated franchise count by ` +
          `${incrementValue}`);
        return null;
      } catch (error) {
        console.error("❌ [User Status] Error:", error);
        return null;
      }
    },
);

/**
 * Recalculate all franchise user counts
 * Can be called manually via HTTP trigger if counts get out of sync
 * Runs weekly on Sunday at 3:00 AM UTC
 */
exports.recalculateFranchiseCounts = onSchedule("0 3 * * 0", async () => {
  console.log("🔄 [Recalculate] Starting franchise count recalculation");

  try {
    const franchisesSnapshot = await db.collection("franchises").get();

    for (const franchiseDoc of franchisesSnapshot.docs) {
      const franchiseData = franchiseDoc.data();
      const franchiseId = franchiseData.franchiseId || franchiseDoc.id;

      // Count active users in this franchise
      const usersSnapshot = await db
          .collection("users")
          .where("franchiseId", "==", franchiseId)
          .where("isActive", "==", true)
          .get();

      const actualCount = usersSnapshot.size;
      const storedCount = franchiseData.currentUserCount || 0;

      if (actualCount !== storedCount) {
        console.log(`📊 [Recalculate] ${franchiseId}: ` +
          `stored=${storedCount}, actual=${actualCount}`);

        await franchiseDoc.ref.update({
          currentUserCount: actualCount,
          updatedAt: admin.firestore.Timestamp.now(),
        });
      }
    }

    console.log("✅ [Recalculate] Completed franchise count recalculation");
    return null;
  } catch (error) {
    console.error("❌ [Recalculate] Error:", error);
    return null;
  }
});

/**
 * Check if a franchise has available user slots before creating a new user
 * This is a callable function that the web app uses before user creation
 */
exports.checkLicenseLimit = onCall(async (request) => {
  console.log("🔐 [License Check] Checking license limit");

  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is super admin (by role)
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can check license",
    );
  }

  const {franchiseId} = request.data;

  if (!franchiseId) {
    throw new HttpsError("invalid-argument", "franchiseId is required");
  }

  try {
    // Find the franchise
    let franchiseDoc;
    const franchiseRef = db.collection("franchises").doc(franchiseId);
    franchiseDoc = await franchiseRef.get();

    if (!franchiseDoc.exists) {
      // Try finding by franchiseId field
      const franchiseQuery = await db
          .collection("franchises")
          .where("franchiseId", "==", franchiseId)
          .limit(1)
          .get();

      if (franchiseQuery.empty) {
        throw new HttpsError("not-found", "Franchise not found");
      }
      franchiseDoc = franchiseQuery.docs[0];
    }

    const franchiseData = franchiseDoc.data();
    const currentCount = franchiseData.currentUserCount || 0;
    const maxUsers = franchiseData.maxUsers || 0;
    const isActive = franchiseData.isActive !== false;

    // Check if franchise is active
    if (!isActive) {
      return {
        canCreateUser: false,
        reason: "Franchise is inactive",
        currentCount,
        maxUsers,
        availableSlots: 0,
      };
    }

    // Check license limit
    const availableSlots = maxUsers - currentCount;
    const canCreateUser = availableSlots > 0;

    console.log(`🔐 [License Check] ${franchiseId}: ` +
      `${currentCount}/${maxUsers}, can create: ${canCreateUser}`);

    return {
      canCreateUser,
      reason: canCreateUser ? "OK" : "License limit reached",
      currentCount,
      maxUsers,
      availableSlots: Math.max(0, availableSlots),
    };
  } catch (error) {
    console.error("❌ [License Check] Error:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * Enforce license limit before user creation
 * Returns whether the user can be created
 */
exports.enforceLicenseLimit = onCall(async (request) => {
  console.log("🔐 [Enforce License] Pre-create check");

  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is super admin (by role)
  const enfCallerUid = request.auth.uid;
  const enfCallerDoc = await db.collection("users").doc(enfCallerUid).get();
  const enfCallerRole = enfCallerDoc.exists ?
    enfCallerDoc.data().role : null;
  if (enfCallerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can create users",
    );
  }

  // eslint-disable-next-line no-unused-vars
  const {franchiseId, email, firstName, lastName, role, isDemo} = request.data;

  if (!franchiseId || !email) {
    throw new HttpsError(
        "invalid-argument",
        "franchiseId and email are required",
    );
  }

  try {
    // Find the franchise
    let franchiseDoc;
    let franchiseRef;
    const directRef = db.collection("franchises").doc(franchiseId);
    franchiseDoc = await directRef.get();

    if (!franchiseDoc.exists) {
      const franchiseQuery = await db
          .collection("franchises")
          .where("franchiseId", "==", franchiseId)
          .limit(1)
          .get();

      if (franchiseQuery.empty) {
        throw new HttpsError("not-found", "Franchise not found");
      }
      franchiseDoc = franchiseQuery.docs[0];
      franchiseRef = franchiseDoc.ref;
    } else {
      franchiseRef = directRef; // eslint-disable-line no-unused-vars
    }

    const franchiseData = franchiseDoc.data();
    const currentCount = franchiseData.currentUserCount || 0;
    const maxUsers = franchiseData.maxUsers || 0;

    // Check license limit
    if (currentCount >= maxUsers) {
      console.log(`🚫 [Enforce License] ${franchiseId}: limit reached ` +
        `(${currentCount}/${maxUsers})`);
      throw new HttpsError(
          "resource-exhausted",
          `License limit reached. Current: ${currentCount}, Max: ${maxUsers}`,
      );
    }

    console.log(`✅ [Enforce License] ${franchiseId}: ` +
      `can create (${currentCount}/${maxUsers})`);

    return {
      allowed: true,
      currentCount,
      maxUsers,
      remainingSlots: maxUsers - currentCount - 1, // -1 for the new user
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error("❌ [Enforce License] Error:", error);
    throw new HttpsError("internal", error.message);
  }
});

/**
 * Utility function to set countryCode for specific users
 * Can be called with custom users list or uses default list
 */
exports.setUserCountryCodes = onCall(async (request) => {
  // Accept custom users list or use default
  const defaultUsers = [
    {email: "admin@gmail.com", countryCode: "CH"},
    {email: "front@gmail.com", countryCode: "CH"},
  ];
  const usersToUpdate = (request.data && request.data.users) ?
    request.data.users :
    defaultUsers;

  const results = [];

  for (const user of usersToUpdate) {
    try {
      const snapshot = await db.collection("users")
          .where("email", "==", user.email)
          .get();

      if (snapshot.empty) {
        results.push({email: user.email, status: "not_found"});
        continue;
      }

      for (const doc of snapshot.docs) {
        await doc.ref.update({
          countryCode: user.countryCode,
        });
        results.push({
          email: user.email,
          uid: doc.id,
          countryCode: user.countryCode,
          status: "updated",
        });
      }
    } catch (error) {
      results.push({
        email: user.email,
        status: "error",
        message: error.message,
      });
    }
  }

  console.log("setUserCountryCodes results:", results);
  return {success: true, results};
});

/**
 * Sync all users' countryCode based on their franchiseId
 * This fixes users created from web without countryCode
 */
/**
 * Assign roles to all users
 * admin@gmail.com -> superadmin, others get 'staff' if no role exists
 */
exports.assignUserRoles = onCall(async (request) => {
  const results = [];

  try {
    const usersSnapshot = await db.collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const email = userData.email || "unknown";

      if (email === "admin@gmail.com") {
        // Always set admin@gmail.com to superadmin
        await userDoc.ref.update({role: "superadmin"});
        results.push({email, status: "set_superadmin"});
      } else if (!userData.role) {
        // Set default role for users without a role
        await userDoc.ref.update({role: "staff"});
        results.push({email, status: "set_staff"});
      } else {
        results.push({
          email,
          role: userData.role,
          status: "already_has_role",
        });
      }
    }
  } catch (error) {
    console.error("assignUserRoles error:", error);
    throw new HttpsError("internal", error.message);
  }

  console.log("assignUserRoles results:", results);
  return {success: true, results};
});

// ============================================================================
// FRANCHISE DATA ISOLATION - MIGRATION FUNCTION
// ============================================================================

/**
 * Migration: Add franchiseId to all existing documents
 * Adds franchiseId: "CH" (Switzerland) to all documents that don't have it
 * Uses batch writes for performance (max 500 per batch)
 * Safe to run multiple times - only updates docs without franchiseId
 */
exports.migrateAddFranchiseId = onCall(async (request) => {
  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  // Verify caller is superadmin
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can run migrations",
    );
  }

  const FRANCHISE_COLLECTIONS = [
    "araclar", "servisler", "iadeIslemleri", "exitIslemleri", "activities",
    "servisFirmalari", "office_operations", "office_Return",
    "workSchedules", "vacationTimes", "assistantCompanies",
    "protocols", "shuttleEntries", "shuttleSessions", "shuttleReports",
    "trafficFines", "bankingTransactions", "additionalSales",
    "semesInvoices", "audit_logs",
  ];

  const defaultFranchiseId = (request.data && request.data.franchiseId) ||
    "CH";
  const results = [];
  let totalUpdated = 0;
  let totalSkipped = 0;

  console.log(`🔄 [Migration] Starting franchiseId migration ` +
    `(default: "${defaultFranchiseId}")`);

  for (const collectionName of FRANCHISE_COLLECTIONS) {
    try {
      const snapshot = await db.collection(collectionName).get();
      let updated = 0;
      let skipped = 0;
      let batchCount = 0;
      let batch = db.batch();

      for (const docSnap of snapshot.docs) {
        const data = docSnap.data();

        // Only update docs that don't already have franchiseId
        if (!data.franchiseId) {
          batch.update(docSnap.ref, {franchiseId: defaultFranchiseId});
          updated++;
          batchCount++;

          // Firestore batch limit is 500
          if (batchCount >= 450) {
            await batch.commit();
            batch = db.batch();
            batchCount = 0;
          }
        } else {
          skipped++;
        }
      }

      // Commit remaining batch
      if (batchCount > 0) {
        await batch.commit();
      }

      totalUpdated += updated;
      totalSkipped += skipped;

      results.push({
        collection: collectionName,
        total: snapshot.size,
        updated,
        skipped,
        status: "success",
      });

      console.log(`✅ [Migration] ${collectionName}: ` +
        `${updated} updated, ${skipped} skipped (total: ${snapshot.size})`);
    } catch (error) {
      results.push({
        collection: collectionName,
        status: "error",
        message: error.message,
      });
      console.error(`❌ [Migration] ${collectionName}: ${error.message}`);
    }
  }

  console.log(`🏁 [Migration] Complete: ${totalUpdated} updated, ` +
    `${totalSkipped} skipped`);

  return {
    success: true,
    defaultFranchiseId,
    totalUpdated,
    totalSkipped,
    results,
  };
});

/**
 * Debug & Fix: Verify and repair user documents
 * for Firestore rules compatibility.
 * Checks all user docs for required fields.
 * Adds missing fields with sensible defaults.
 */
exports.fixUserDocuments = onCall(async (request) => {
  // Verify authentication
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }

  const dryRun = request.data && request.data.dryRun === true;
  const results = [];
  let fixedCount = 0;

  try {
    const usersSnapshot = await db.collection("users").get();
    console.log(`🔍 [FixUsers] Checking ${usersSnapshot.size} user documents`);

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const docId = userDoc.id;
      const email = userData.email || "unknown";
      const fixes = {};
      const missing = [];

      // Check franchiseId
      if (userData.franchiseId === undefined || userData.franchiseId === null) {
        missing.push("franchiseId");
        fixes.franchiseId = "CH"; // Default franchise
      }

      // Check isDemoAccount
      if (userData.isDemoAccount === undefined ||
          userData.isDemoAccount === null) {
        missing.push("isDemoAccount");
        fixes.isDemoAccount = userData.isDemo === true ? true : false;
      }

      // Check role
      if (!userData.role) {
        missing.push("role");
        if (email === "admin@gmail.com") {
          fixes.role = "superadmin";
        } else {
          fixes.role = "staff";
        }
      }

      // Check countryCode
      if (!userData.countryCode) {
        missing.push("countryCode");
        fixes.countryCode = "CH";
      }

      // Apply fixes if needed
      if (Object.keys(fixes).length > 0) {
        if (!dryRun) {
          await userDoc.ref.update(fixes);
        }
        fixedCount++;
        results.push({
          email,
          docId,
          status: dryRun ? "would_fix" : "fixed",
          missing,
          fixes,
          existingFields: {
            franchiseId: userData.franchiseId,
            isDemoAccount: userData.isDemoAccount,
            isDemo: userData.isDemo,
            role: userData.role,
            countryCode: userData.countryCode,
          },
        });
      } else {
        results.push({
          email,
          docId,
          status: "ok",
          fields: {
            franchiseId: userData.franchiseId,
            isDemoAccount: userData.isDemoAccount,
            role: userData.role,
            countryCode: userData.countryCode,
          },
        });
      }
    }

    console.log(`🏁 [FixUsers] Done: ${fixedCount} users ` +
      `${dryRun ? "would be" : ""} fixed out of ${usersSnapshot.size}`);
  } catch (error) {
    console.error("❌ [FixUsers] Error:", error);
    throw new HttpsError("internal", error.message);
  }

  return {
    success: true,
    dryRun,
    totalUsers: results.length,
    fixedCount,
    results,
  };
});

exports.syncUserCountryCodes = onCall(async (request) => {
  const results = [];

  try {
    // Get all franchises to build franchiseId -> countryCode mapping
    const franchisesSnapshot = await db.collection("franchises").get();
    const franchiseMap = {};

    franchisesSnapshot.forEach((doc) => {
      const data = doc.data();
      if (data.franchiseId && data.countryCode) {
        franchiseMap[data.franchiseId] = data.countryCode;
      }
      // Also map by document id
      if (data.countryCode) {
        franchiseMap[doc.id] = data.countryCode;
      }
    });

    console.log("Franchise mapping:", franchiseMap);

    // Get all users without countryCode or with missing countryCode
    const usersSnapshot = await db.collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      const email = userData.email || "unknown";

      // Check if user needs countryCode update
      if (!userData.countryCode && userData.franchiseId) {
        const countryCode = franchiseMap[userData.franchiseId];

        if (countryCode) {
          await userDoc.ref.update({
            countryCode: countryCode,
          });
          results.push({
            email: email,
            uid: userId,
            franchiseId: userData.franchiseId,
            countryCode: countryCode,
            status: "updated",
          });
        } else {
          results.push({
            email: email,
            uid: userId,
            franchiseId: userData.franchiseId,
            status: "no_franchise_mapping",
          });
        }
      } else if (!userData.countryCode) {
        results.push({
          email: email,
          uid: userId,
          status: "no_franchise_id",
        });
      } else {
        results.push({
          email: email,
          uid: userId,
          countryCode: userData.countryCode,
          status: "already_has_countryCode",
        });
      }
    }
  } catch (error) {
    console.error("syncUserCountryCodes error:", error);
    throw new HttpsError("internal", error.message);
  }

  console.log("syncUserCountryCodes results:", results);
  return {success: true, results};
});

/**
 * Migration monitoring endpoint for staged cutover.
 * Returns queue and lock health for legacy+scoped paths.
 */
exports.getMigrationHealth = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated");
  }
  const callerUid = request.auth.uid;
  const callerDoc = await db.collection("users").doc(callerUid).get();
  const callerRole = callerDoc.exists ? callerDoc.data().role : null;
  if (callerRole !== "superadmin") {
    throw new HttpsError(
        "permission-denied",
        "Only superadmin can read migration health",
    );
  }

  const franchiseId = ((request.data && request.data.franchiseId) || "CH")
      .toUpperCase();

  const [
    legacyEmails,
    scopedEmails,
    legacyNotifications,
    scopedNotifications,
    locks,
  ] =
    await Promise.all([
      db.collection("outgoingEmails").where("status", "==", "queued").get(),
      db.collection("franchises").doc(franchiseId)
          .collection("outgoingEmails").where("status", "==", "queued").get(),
      db.collection("notifications").get(),
      db.collection("franchises").doc(franchiseId)
          .collection("notifications").get(),
      db.collection("_functionLocks")
          .orderBy("createdAt", "desc")
          .limit(200)
          .get(),
    ]);

  return {
    franchiseId,
    generatedAt: new Date().toISOString(),
    queues: {
      legacyOutgoingEmailsQueued: legacyEmails.size,
      scopedOutgoingEmailsQueued: scopedEmails.size,
      legacyNotificationsTotal: legacyNotifications.size,
      scopedNotificationsTotal: scopedNotifications.size,
    },
    functionLocksRecent: locks.size,
  };
});
