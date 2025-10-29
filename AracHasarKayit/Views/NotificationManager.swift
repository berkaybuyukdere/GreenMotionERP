import Foundation
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

class NotificationManager: NSObject, ObservableObject, MessagingDelegate {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var fcmToken: String?
    
    private let db = Firestore.firestore()
    
    override init() {
        super.init()
        // Delegate assignments are thread-safe and can be done synchronously
        // Token I/O operations are handled on background queue to avoid main thread hangs
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
        print("🔔 Sending notification: \(title)")
        
        // Prevent duplicate notifications by checking recent notifications
        let notificationKey = "\(title)_\(body)_\(data["plate"] ?? "")"
        let lastNotificationKey = UserDefaults.standard.string(forKey: "lastNotificationKey")
        let lastNotificationTime = UserDefaults.standard.double(forKey: "lastNotificationTime")
        let currentTime = Date().timeIntervalSince1970
        
        // If same notification was sent within last 5 seconds, skip it
        if lastNotificationKey == notificationKey && (currentTime - lastNotificationTime) < 5.0 {
            print("⚠️ Duplicate notification prevented: \(title)")
            return
        }
        
        // Save current notification info
        UserDefaults.standard.set(notificationKey, forKey: "lastNotificationKey")
        UserDefaults.standard.set(currentTime, forKey: "lastNotificationTime")
        
        // Get all FCM tokens from users collection
        db.collection("users").getDocuments { [weak self] snapshot, error in
            if let error = error {
                print("❌ Error fetching users: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("❌ No user documents found")
                return
            }
            
            let tokens = documents.compactMap { $0.data()["fcmToken"] as? String }
            print("📱 Found \(tokens.count) FCM tokens")
            
            if tokens.isEmpty {
                print("⚠️ No FCM tokens found - skipping notification")
                return
            }
            
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
                    print("✅ Notification queued successfully: \(title)")
                    print("📤 Cloud Function will process this notification")
                }
            }
        }
    }
    
    
    // MARK: - Shuttle Notifications
    
    func sendShuttleStartNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Shuttle Service Started",
            body: "\(driverName) started a shuttle session",
            data: [
                "type": "shuttle_start",
                "driverName": driverName
            ]
        )
    }
    
    func sendShuttleEndNotification(driverName: String, totalCustomers: Int) {
        sendNotificationToAll(
            title: "🚐 Shuttle Service Ended",
            body: "\(driverName) completed shuttle session • \(totalCustomers) customers",
            data: [
                "type": "shuttle_end",
                "driverName": driverName,
                "totalCustomers": "\(totalCustomers)"
            ]
        )
    }
    
    func sendShuttleCustomerNotification(driverName: String, customerCount: Int) {
        sendNotificationToAll(
            title: "🚐 Customer Pickup",
            body: "\(driverName) picked up \(customerCount) customer(s)",
            data: [
                "type": "shuttle_customer",
                "driverName": driverName,
                "customerCount": "\(customerCount)"
            ]
        )
    }
    
    func sendShuttleETANotification(driverName: String, minutesRemaining: Int) {
        sendNotificationToAll(
            title: "🚐 Shuttle Arriving Soon",
            body: "\(driverName) will arrive in \(minutesRemaining) minutes",
            data: [
                "type": "shuttle_eta",
                "driverName": driverName,
                "minutesRemaining": "\(minutesRemaining)"
            ]
        )
    }
    
    func sendShuttleCustomerAvailableNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Customer Available",
            body: "\(driverName) has customers waiting",
            data: [
                "type": "shuttle_customer_available",
                "driverName": driverName
            ]
        )
    }
    
    func sendShuttleCustomerPickedUpNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Müşteri Alındı",
            body: "\(driverName) müşteriyi aldı",
            data: [
                "type": "shuttle_customer_picked_up",
                "driverName": driverName
            ]
        )
    }
    
    func sendShuttleCustomerDroppedOffNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Müşteri Bırakıldı",
            body: "\(driverName) müşteriyi bıraktı",
            data: [
                "type": "shuttle_customer_dropped_off",
                "driverName": driverName
            ]
        )
    }
    
    // MARK: - Service Reminder Notifications
    
    /// Schedule a notification for service reminder (1 day before delivery date)
    func scheduleServiceReminder(servisId: String, carPlate: String, serviceName: String, deliveryDate: Date) {
        // Calculate notification date (1 day before delivery)
        let calendar = Calendar.current
        guard let notificationDate = calendar.date(byAdding: .day, value: -1, to: deliveryDate) else {
            print("❌ Could not calculate notification date")
            return
        }
        
        // Check if notification date is in the future
        guard notificationDate > Date() else {
            print("⚠️ Notification date is in the past, skipping")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "🔧 Service Reminder"
        content.body = "Vehicle \(carPlate) will be returned from \(serviceName) tomorrow"
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "type": "service_reminder",
            "servisId": servisId,
            "carPlate": carPlate,
            "serviceName": serviceName
        ]
        
        // Create date components for trigger
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: "service_reminder_\(servisId)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Service reminder scheduling error: \(error.localizedDescription)")
            } else {
                print("✅ Service reminder scheduled for \(notificationDate)")
                
                // Also send to all users via Firebase
                self.sendServiceReminderToAll(carPlate: carPlate, serviceName: serviceName, deliveryDate: deliveryDate)
            }
        }
    }
    
    /// Cancel scheduled service reminder
    func cancelServiceReminder(servisId: String) {
        let identifier = "service_reminder_\(servisId)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("✅ Service reminder cancelled: \(identifier)")
    }
    
    /// Send service reminder to all users via Firebase
    private func sendServiceReminderToAll(carPlate: String, serviceName: String, deliveryDate: Date) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        sendNotificationToAll(
            title: "🔧 Service Reminder",
            body: "Vehicle \(carPlate) will be returned from \(serviceName) on \(formatter.string(from: deliveryDate))",
            data: [
                "type": "service_reminder",
                "carPlate": carPlate,
                "serviceName": serviceName,
                "deliveryDate": formatter.string(from: deliveryDate)
            ]
        )
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
extension NotificationManager {
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
