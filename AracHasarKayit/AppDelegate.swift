import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // Firebase is configured in App init
        
        // Request notification permissions with all options (including background notifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .provisional]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Notification permission granted")
                    // Register for remote notifications
                    UIApplication.shared.registerForRemoteNotifications()
                    // Enable background refresh
                    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
                } else {
                    print("❌ Notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
        
        // Set messaging delegate to NotificationManager (not AppDelegate)
        // Note: Delegate assignment is safe on main thread, but token I/O operations are moved to background
        Messaging.messaging().delegate = NotificationManager.shared
        
        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Set user offline when app terminates
        UserPresenceManager.shared.setOffline()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Set user offline when app goes to background
        UserPresenceManager.shared.setOffline()
        
        // Remove shuttle location when app goes to background
        ShuttleManager.shared.markLocationInactive()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Set user online when app comes to foreground (if authenticated)
        if Auth.auth().currentUser != nil {
            UserPresenceManager.shared.setOnline()
            
            // If user has active shuttle session, make location visible again
            if ShuttleManager.shared.currentSession != nil {
                ShuttleManager.shared.markLocationActive()
            }
        }
    }
    
    // MARK: - Remote Notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("📱 APNS Device token received: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
        
        // Move Firebase Messaging operations to background queue to avoid main thread I/O
        DispatchQueue.global(qos: .utility).async {
            Messaging.messaging().apnsToken = deviceToken
            
            // Request FCM token on background queue
            Messaging.messaging().token { token, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Error fetching FCM token after APNS: \(error.localizedDescription)")
                    } else if let token = token {
                        print("🔑 FCM Token received after APNS: \(token)")
                        NotificationManager.shared.saveFCMToken(token)
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
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Always show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

