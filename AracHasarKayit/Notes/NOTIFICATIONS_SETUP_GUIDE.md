# 🔔 Push Notifications - Complete Setup Guide

This guide will walk you through setting up push notifications for your iOS app with Firebase Cloud Messaging (FCM).

---

## 📋 Part 1: Apple Developer Portal Setup

### Step 1.1: Create APNs Authentication Key

1. **Go to Apple Developer Portal:** https://developer.apple.com/account/
2. Click **Certificates, Identifiers & Profiles**
3. In the left menu, click **Keys**
4. Click the **"+"** button (top right)
5. Enter a **Key Name** (e.g., "AracHasarKayit Push Notifications")
6. Check ✅ **Apple Push Notifications service (APNs)**
7. Click **Continue** → **Register**
8. Click **Download** to download the `.p8` file
9. **SAVE THESE VALUES:**
   - **Key ID** (e.g., ABC123DEFG) - displayed on the page
   - **Team ID** (top right corner of the page)
   - The downloaded **.p8 file** - SAVE THIS SECURELY, you can't download it again!

⚠️ **IMPORTANT:** Keep the .p8 file in a safe place. You cannot download it again after leaving this page.

---

## 📋 Part 2: Firebase Console Setup

### Step 2.1: Upload APNs Key to Firebase

1. **Go to Firebase Console:** https://console.firebase.google.com/
2. Select your project
3. Click **⚙️ Settings** (top left) → **Project settings**
4. Go to the **Cloud Messaging** tab
5. Scroll down to **Apple app configuration**
6. Click **Upload** (under APNs Authentication Key)
7. Select the **.p8 file** you downloaded
8. Enter the **Key ID** (from Step 1.1)
9. Enter the **Team ID** (from Step 1.1)
10. Click **Upload**

✅ You should see "APNs Authentication Key uploaded successfully"

### Step 2.2: Install Firebase CLI and Setup Functions

Open Terminal and run:

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Login to Firebase
firebase login

# Navigate to your project directory
cd /Users/berkaybuyukdere/Desktop/AracHasarKayitv10_BEST

# Initialize Firebase Functions
firebase init functions
```

When prompted:
- Select: **Use an existing project** → Choose your Firebase project
- Language: **JavaScript** (or TypeScript if you prefer)
- ESLint: **Yes**
- Install dependencies: **Yes**

This creates a `functions/` folder in your project.

### Step 2.3: Install Firebase Admin SDK

```bash
cd functions
npm install firebase-admin
npm install firebase-functions
```

### Step 2.4: Create Cloud Function for Notifications

Create or edit `functions/index.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

// Listen for new notifications in Firestore
exports.sendNotification = functions.firestore
    .document('notifications/{notificationId}')
    .onCreate(async (snap, context) => {
        const data = snap.data();
        
        // Extract notification data
        const title = data.title || 'Green Motion';
        const body = data.body || 'New notification';
        const tokens = data.tokens || [];
        const notificationData = data.data || {};
        
        if (tokens.length === 0) {
            console.log('No tokens to send to');
            return null;
        }
        
        // Create message payload
        const message = {
            notification: {
                title: title,
                body: body,
            },
            data: notificationData,
            tokens: tokens,
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
            // Send to multiple devices
            const response = await admin.messaging().sendMulticast(message);
            console.log(`Successfully sent ${response.successCount} notifications`);
            console.log(`Failed to send ${response.failureCount} notifications`);
            
            // Delete the notification document after sending
            await snap.ref.delete();
            
            return response;
        } catch (error) {
            console.error('Error sending notification:', error);
            return null;
        }
    });
```

### Step 2.5: Deploy Cloud Functions

```bash
# Make sure you're in the project root
cd /Users/berkaybuyukdere/Desktop/AracHasarKayitv10_BEST

# Deploy functions
firebase deploy --only functions
```

You should see:
```
✔ functions[sendNotification(us-central1)] Successful create operation.
```

---

## 📋 Part 3: Xcode Project Setup

### Step 3.1: Add Push Notifications Capability

1. Open Xcode
2. Select **AracHasarKayit** project in left panel
3. Select **AracHasarKayit** target
4. Go to **Signing & Capabilities** tab
5. Click **"+ Capability"** button
6. Add **Push Notifications**
7. Click **"+ Capability"** again
8. Add **Background Modes**
9. In Background Modes, check:
   - ✅ **Remote notifications**
   - ✅ **Background fetch**

### Step 3.2: Add Firebase Messaging Package

1. In Xcode, go to **File** → **Add Package Dependencies**
2. Paste URL: `https://github.com/firebase/firebase-ios-sdk.git`
3. Version: **Up to Next Major Version 10.0.0**
4. Click **Add Package**
5. Select these products:
   - ✅ **FirebaseMessaging**
6. Click **Add Package**

### Step 3.3: Update Info.plist

1. Right-click **Info.plist** in Xcode
2. Open As → **Source Code**
3. Add this inside `<dict>`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
<key>FirebaseMessagingAutoInitEnabled</key>
<true/>
```

---

## 📋 Part 4: Build and Test

### Step 4.1: Build the Project

```bash
cd /Users/berkaybuyukdere/Desktop/AracHasarKayitv10_BEST
xcodebuild -project AracHasarKayit.xcodeproj -scheme AracHasarKayit -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

⚠️ **NOTE:** Push notifications don't work on Simulator. You need a real device!

### Step 4.2: Run on Real Device

1. Connect your iPhone via USB
2. In Xcode, select your device from the device list
3. Click **Run** (▶️ button)
4. When the app launches, you should see an alert asking for notification permission
5. Click **Allow**

### Step 4.3: Check Console for FCM Token

In Xcode console, you should see:
```
✅ App initialized with authManager injected to viewModel
✅ Notification permission granted
📱 Device token received
🔑 FCM Token received: [long token string]
✅ FCM token saved: [token]
```

### Step 4.4: Test Notifications

1. **Login to the app** on your device
2. **Add a damage record** for a vehicle
   - Go to a vehicle
   - Add a new damage
   - After saving, a notification should be sent

3. **Check Firebase Console:**
   - Go to Firestore Database
   - Check the `notifications` collection (should be empty after sending)
   - Check the `users` collection → your user document → should have `fcmToken` field

4. **Mark damage as done:**
   - Open a damage record
   - Click "Mark as Done"
   - A notification should be sent

5. **Process a return:**
   - Go to Reports → Returns
   - Process a return
   - A notification should be sent

---

## 🧪 Testing with Manual Notification (Optional)

You can send a test notification from Firebase Console:

1. **Go to Firebase Console** → **Cloud Messaging**
2. Click **Send your first message**
3. Enter notification title and text
4. Click **Send test message**
5. Paste your FCM token (from Xcode console)
6. Click **Test**

---

## 📊 Notification Flow

```
User Action (Add Damage / Mark Done / Return)
    ↓
NotificationManager.sendNotification()
    ↓
Creates document in Firestore 'notifications' collection
    ↓
Cloud Function 'sendNotification' triggered
    ↓
Reads all user FCM tokens
    ↓
Sends push notification via Firebase Admin SDK
    ↓
APNs delivers to user devices
    ↓
Users receive notification! 🎉
```

---

## 🔍 Troubleshooting

### Problem: "No FCM token received"

**Solution:**
1. Check internet connection
2. Make sure Firebase is initialized: `FirebaseApp.configure()` in AppDelegate
3. Check Xcode console for errors
4. Try restarting the app

### Problem: "Notifications not arriving"

**Solution:**
1. Check APNs key is uploaded correctly in Firebase Console
2. Check Cloud Function is deployed: `firebase functions:list`
3. Check Cloud Function logs: `firebase functions:log`
4. Make sure app has notification permission: Settings → App → Notifications
5. **Must use real device** - Simulator doesn't support push notifications

### Problem: "Build failed"

**Solution:**
1. Clean build folder: Xcode → Product → Clean Build Folder
2. Close Xcode and delete DerivedData:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
3. Re-open project and build

### Problem: "Cloud Function not triggering"

**Solution:**
1. Check Firestore rules allow write to `notifications` collection
2. Check Firebase console → Functions → Logs for errors
3. Test manually creating a document in `notifications` collection

---

## 📱 What Notifications Look Like

### When someone adds a damage:
```
🚗 New Damage Record
John Doe added damage record RES-123 for vehicle ZH 12345
```

### When someone marks damage as done:
```
✅ Damage Completed
John Doe marked damage RES-123 as done for vehicle ZH 12345
```

### When someone processes a return:
```
🔄 Vehicle Return
John Doe processed return for vehicle ZH 12345
```

---

## 🎉 You're All Set!

Your app now has fully functional push notifications! All users will be notified when:
- ✅ Someone adds a new damage record
- ✅ Someone marks a damage as done
- ✅ Someone processes a vehicle return

---

## 📝 Important Notes

1. **Real Device Required:** Push notifications only work on real iOS devices, not simulators
2. **Production Certificate:** For production, you may need to create a Production APNs certificate
3. **User Consent:** Users must grant notification permission
4. **Firebase Costs:** Cloud Functions have a free tier, but may incur costs with high usage
5. **Token Refresh:** FCM tokens can change; the app handles this automatically

---

## 🔐 Security Considerations

- ✅ FCM tokens are stored securely in Firestore
- ✅ Only authenticated users can trigger notifications
- ✅ Notification data is validated before sending
- ✅ APNs .p8 key should never be committed to git
- ✅ Firebase rules should restrict access to sensitive collections

---

## 📞 Need Help?

If you encounter issues:
1. Check Xcode console for error messages
2. Check Firebase Console → Functions → Logs
3. Check Firebase Console → Cloud Messaging → Reports
4. Verify all setup steps are completed

---

**Created:** October 2025  
**Version:** 1.0  
**Last Updated:** October 2025

