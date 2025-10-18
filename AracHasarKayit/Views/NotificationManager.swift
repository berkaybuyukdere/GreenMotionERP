import Foundation
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var fcmToken: String?
    
    private let db = Firestore.firestore()
    
    override init() {
        super.init()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Permission Request
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                
                if granted {
                    print("✅ Notification permission granted")
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                } else {
                    print("❌ Notification permission denied")
                }
                
                if let error = error {
                    print("❌ Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - FCM Token Management
    func saveFCMToken(_ token: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No user logged in, can't save FCM token")
            return
        }
        
        self.fcmToken = token
        
        // Save token to Firestore
        db.collection("users").document(userId).setData([
            "fcmToken": token,
            "lastTokenUpdate": Timestamp(date: Date())
        ], merge: true) { error in
            if let error = error {
                print("❌ Error saving FCM token: \(error.localizedDescription)")
            } else {
                print("✅ FCM token saved: \(token)")
            }
        }
    }
    
    // MARK: - Send Notifications
    func sendDamageRecordNotification(carPlate: String, resCode: String, userName: String) {
        sendNotificationToAll(
            title: "🚗 New Damage Record",
            body: "\(userName) added damage record \(resCode) for vehicle \(carPlate)",
            data: [
                "type": "damage_added",
                "plate": carPlate,
                "resCode": resCode
            ]
        )
    }
    
    func sendDamageCompletedNotification(carPlate: String, resCode: String, userName: String) {
        sendNotificationToAll(
            title: "✅ Damage Completed",
            body: "\(userName) marked damage \(resCode) as done for vehicle \(carPlate)",
            data: [
                "type": "damage_completed",
                "plate": carPlate,
                "resCode": resCode
            ]
        )
    }
    
    func sendReturnNotification(carPlate: String, userName: String) {
        sendNotificationToAll(
            title: "🔄 Vehicle Return",
            body: "\(userName) processed return for vehicle \(carPlate)",
            data: [
                "type": "return_processed",
                "plate": carPlate
            ]
        )
    }
    
    private func sendNotificationToAll(title: String, body: String, data: [String: String]) {
        // Get all FCM tokens from users collection
        db.collection("users").getDocuments { [weak self] snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            let tokens = documents.compactMap { $0.data()["fcmToken"] as? String }
            
            // Create notification payload
            let notification: [String: Any] = [
                "title": title,
                "body": body,
                "data": data,
                "tokens": tokens,
                "timestamp": Timestamp(date: Date())
            ]
            
            // Save to Firestore for Cloud Function to process
            self?.db.collection("notifications").addDocument(data: notification) { error in
                if let error = error {
                    print("❌ Error queuing notification: \(error.localizedDescription)")
                } else {
                    print("✅ Notification queued: \(title)")
                }
            }
        }
    }
    
    // MARK: - Local Notification (for testing)
    func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Local notification error: \(error.localizedDescription)")
            } else {
                print("✅ Local notification sent")
            }
        }
    }
}

// MARK: - MessagingDelegate
extension NotificationManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("🔑 FCM Token received: \(token)")
        saveFCMToken(token)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📱 Notification received in foreground")
        // Show notification even when app is open
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("👆 Notification tapped: \(userInfo)")
        
        // Handle notification tap based on type
        if let type = userInfo["type"] as? String {
            handleNotificationTap(type: type, data: userInfo)
        }
        
        completionHandler()
    }
    
    private func handleNotificationTap(type: String, data: [AnyHashable: Any]) {
        // You can use NotificationCenter to notify other parts of the app
        NotificationCenter.default.post(
            name: NSNotification.Name("NotificationTapped"),
            object: nil,
            userInfo: ["type": type, "data": data]
        )
    }
}
