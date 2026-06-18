import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    private func maskedToken(_ token: String) -> String {
        if token.count <= 8 { return "***" }
        return "\(token.prefix(4))...\(token.suffix(4))"
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // Firebase is configured in App init
        
        // Request notification permissions — full alert/banner/sound (no provisional quiet delivery)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permission granted")
                    NotificationManager.shared.registerForPushIfAllowed()
                    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
                } else {
                    print("❌ Notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
                }
                NotificationManager.shared.ensureProminentDeliveryOnLaunch()
            }
        }
        
        // Set messaging delegate to NotificationManager (not AppDelegate)
        // Note: Delegate assignment is safe on main thread, but token I/O operations are moved to background
        Messaging.messaging().delegate = NotificationManager.shared
        
        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        return true
    }
    
    // MARK: - Background Notification Handling
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if NotificationManager.shared.shouldDisplayNotification(userInfo: userInfo) {
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // MARK: - Remote Notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 [APNS] Device token received: \(maskedToken(tokenString))")
        
        // Move Firebase Messaging operations to background queue to avoid main thread I/O
        DispatchQueue.global(qos: .utility).async {
            Messaging.messaging().apnsToken = deviceToken
            
            // Request FCM token on background queue
            Messaging.messaging().token { token, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ [APNS] Error fetching FCM token: \(error.localizedDescription)")
                    } else if let token = token {
                        print("🔑 [APNS] FCM Token received: \(self.maskedToken(token))")
                        NotificationManager.shared.saveFCMToken(token)
                    } else {
                        print("⚠️ [APNS] No FCM token received and no error")
                    }
                }
            }
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
        
        // For simulator testing - send a local notification instead
        #if targetEnvironment(simulator)
        print("📱 Running on simulator - push notifications not supported")
        sendTestLocalNotification()
        #endif
    }
    
    #if targetEnvironment(simulator)
    private func sendTestLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🔔 Test Notification"
        content.body = "Push notifications work! (Simulator test)"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "test", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send test notification: \(error)")
            } else {
                print("✅ Test notification scheduled")
            }
        }
    }
    #endif
    
    // MARK: - MessagingDelegate (moved to NotificationManager)
    
}

