import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import UserNotifications

@objc class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        
        // Request notification permissions
        NotificationManager.shared.requestAuthorization()
        
        // Set messaging delegate
        Messaging.messaging().delegate = self
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Set user offline when app terminates
        UserPresenceManager.shared.setOffline()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Set user offline when app goes to background
        UserPresenceManager.shared.setOffline()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Set user online when app comes to foreground (if authenticated)
        if Auth.auth().currentUser != nil {
            UserPresenceManager.shared.setOnline()
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
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

