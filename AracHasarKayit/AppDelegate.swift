import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
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
        
        // Set messaging delegate
        Messaging.messaging().delegate = self
        
        // Set notification center delegate
        UNUserNotificationCenter.current().delegate = self
        
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
        print("📱 Device token received")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔑 FCM Token received: \(fcmToken ?? "nil")")
        if let token = fcmToken {
            NotificationManager.shared.saveFCMToken(token)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Always show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

