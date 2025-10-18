/**
 * Firebase Cloud Functions for Push Notifications
 * 
 * This file should be placed in: functions/index.js
 * After creating Firebase Functions with: firebase init functions
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Sends push notifications when a new document is created in the 'notifications' collection
 * 
 * Triggered by: Firestore onCreate event
 * Collection: notifications
 * 
 * Document structure expected:
 * {
 *   title: string,
 *   body: string,
 *   tokens: string[],  // Array of FCM tokens
 *   data: object,      // Custom data (type, plate, resCode, etc.)
 *   timestamp: Timestamp
 * }
 */
exports.sendNotification = functions.firestore
    .document('notifications/{notificationId}')
    .onCreate(async (snap, context) => {
        const data = snap.data();
        const notificationId = context.params.notificationId;
        
        console.log(`📬 New notification request: ${notificationId}`);
        
        // Extract notification data
        const title = data.title || 'Green Motion';
        const body = data.body || 'New notification';
        const tokens = data.tokens || [];
        const notificationData = data.data || {};
        
        // Validate tokens
        if (!tokens || tokens.length === 0) {
            console.log('⚠️ No FCM tokens found. Skipping notification.');
            await snap.ref.delete();
            return null;
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
                // Ensure all values are strings (FCM requirement)
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            tokens: tokens,
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                        'content-available': 1,
                    },
                },
            },
        };
        
        try {
            // Send to multiple devices
            const response = await admin.messaging().sendMulticast(message);
            
            console.log(`✅ Successfully sent ${response.successCount} notifications`);
            
            if (response.failureCount > 0) {
                console.log(`❌ Failed to send ${response.failureCount} notifications`);
                
                // Log detailed errors
                response.responses.forEach((resp, idx) => {
                    if (!resp.success) {
                        console.error(`Error for token ${idx}:`, resp.error);
                        
                        // Remove invalid tokens from Firestore
                        if (resp.error.code === 'messaging/invalid-registration-token' ||
                            resp.error.code === 'messaging/registration-token-not-registered') {
                            const invalidToken = tokens[idx];
                            console.log(`🗑️ Removing invalid token: ${invalidToken}`);
                            
                            // Remove token from users collection
                            admin.firestore()
                                .collection('users')
                                .where('fcmToken', '==', invalidToken)
                                .get()
                                .then(snapshot => {
                                    snapshot.forEach(doc => {
                                        doc.ref.update({
                                            fcmToken: admin.firestore.FieldValue.delete()
                                        });
                                    });
                                })
                                .catch(err => console.error('Error removing invalid token:', err));
                        }
                    }
                });
            }
            
            // Delete the notification document after processing
            await snap.ref.delete();
            console.log(`🗑️ Deleted notification document: ${notificationId}`);
            
            return response;
            
        } catch (error) {
            console.error('❌ Error sending notification:', error);
            
            // Don't delete the document if there was an error
            // This allows for manual inspection and retry
            return null;
        }
    });

/**
 * Clean up expired FCM tokens
 * Runs daily at midnight UTC
 */
exports.cleanupExpiredTokens = functions.pubsub
    .schedule('0 0 * * *')
    .timeZone('UTC')
    .onRun(async (context) => {
        console.log('🧹 Starting cleanup of expired FCM tokens');
        
        try {
            const usersSnapshot = await admin.firestore()
                .collection('users')
                .where('lastTokenUpdate', '<', admin.firestore.Timestamp.fromDate(
                    new Date(Date.now() - 90 * 24 * 60 * 60 * 1000) // 90 days ago
                ))
                .get();
            
            let deletedCount = 0;
            const batch = admin.firestore().batch();
            
            usersSnapshot.forEach(doc => {
                batch.update(doc.ref, {
                    fcmToken: admin.firestore.FieldValue.delete(),
                    lastTokenUpdate: admin.firestore.FieldValue.delete()
                });
                deletedCount++;
            });
            
            if (deletedCount > 0) {
                await batch.commit();
                console.log(`✅ Cleaned up ${deletedCount} expired tokens`);
            } else {
                console.log('✅ No expired tokens to clean up');
            }
            
            return null;
            
        } catch (error) {
            console.error('❌ Error during token cleanup:', error);
            return null;
        }
    });

/**
 * Optional: Send a welcome notification when a new user is created
 */
exports.sendWelcomeNotification = functions.firestore
    .document('users/{userId}')
    .onCreate(async (snap, context) => {
        const userData = snap.data();
        const fcmToken = userData.fcmToken;
        
        if (!fcmToken) {
            console.log('⚠️ No FCM token for new user, skipping welcome notification');
            return null;
        }
        
        const message = {
            notification: {
                title: '👋 Welcome to Green Motion!',
                body: `Hi ${userData.fullName || 'there'}! Your account has been created successfully.`,
            },
            token: fcmToken,
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1,
                    },
                },
            },
        };
        
        try {
            await admin.messaging().send(message);
            console.log(`✅ Welcome notification sent to ${userData.email}`);
        } catch (error) {
            console.error('❌ Error sending welcome notification:', error);
        }
        
        return null;
    });

