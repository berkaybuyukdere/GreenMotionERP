/**
 * Firebase Cloud Functions for Push Notifications
 * Version 2 API (firebase-functions v6)
 *
 * This file should be placed in: functions/index.js
 * After creating Firebase Functions with: firebase init functions
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Sends push notifications when a new document
 * is created in the 'notifications' collection
 */
exports.sendNotification = onDocumentCreated(
    "notifications/{notificationId}",
    async (event) => {
      const snapshot = event.data;
      if (!snapshot) {
        console.log("No data associated with the event");
        return;
      }

      const data = snapshot.data();
      const notificationId = event.params.notificationId;

      console.log(`📬 New notification request: ${notificationId}`);

      // Extract notification data
      const title = data.title || "Green Motion";
      const body = data.body || "New notification";
      const tokens = data.tokens || [];
      const notificationData = data.data || {};

      // Validate tokens
      if (!tokens || tokens.length === 0) {
        console.log("⚠️ No FCM tokens found. Skipping notification.");
        await snapshot.ref.delete();
        return;
      }

      console.log(`📤 Sending to ${tokens.length} devices`);

      // Create message payload
      const message = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          ...notificationData,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        tokens: tokens,
        apns: {
          payload: {
            aps: {
              "sound": "default",
              "badge": 1,
              "content-available": 1,
            },
          },
        },
      };

      try {
        // Send to multiple devices
        const response = await admin.messaging().sendEachForMulticast(message);

        const successMsg = `✅ Successfully sent ${response.successCount}`;
        console.log(successMsg + " notifications");

        if (response.failureCount > 0) {
          const failMsg = `❌ Failed to send ${response.failureCount}`;
          console.log(failMsg + " notifications");

          // Log detailed errors
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              console.error(`Error for token ${idx}:`, resp.error);

              // Remove invalid tokens from Firestore
              const isInvalidToken =
                resp.error.code === "messaging/invalid-registration-token";
              const isNotRegistered = resp.error.code ===
                "messaging/registration-token-not-registered";
              if (isInvalidToken || isNotRegistered) {
                const invalidToken = tokens[idx];
                console.log(`🗑️ Removing invalid token: ${invalidToken}`);

                // Remove token from users collection
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
                      console.error("Error removing token:", err);
                    });
              }
            }
          });
        }

        // Delete the notification document after processing
        await snapshot.ref.delete();
        console.log(`🗑️ Deleted notification document: ${notificationId}`);

        return response;
      } catch (error) {
        console.error("❌ Error sending notification:", error);
        return null;
      }
    },
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
