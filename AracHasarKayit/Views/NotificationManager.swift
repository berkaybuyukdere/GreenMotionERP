import Foundation
import UserNotifications
import FirebaseMessaging
import FirebaseAuth
import FirebaseFirestore

class NotificationManager: NSObject, ObservableObject, MessagingDelegate {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    @Published var fcmToken: String?
    
    private func maskedToken(_ token: String) -> String {
        if token.count <= 8 { return "***" }
        return "\(token.prefix(4))...\(token.suffix(4))"
    }
    
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
            print("⚠️ [FCM] No authenticated user")
            return
        }
        
        self.fcmToken = token
        print("🔑 [FCM] Saving token for user \(userId)")
        
        // Save token to Firestore (users is a global collection)
        FirebaseService.shared.getCollectionReference("users").document(userId).setData([
            "fcmToken": token,
            "lastTokenUpdate": Timestamp(date: Date())
        ], merge: true) { error in
            if let error = error {
                print("❌ [FCM] Error saving FCM token: \(error.localizedDescription)")
            } else {
                print("✅ [FCM] Token saved (\(self.maskedToken(token)))")
            }
        }
    }
    
    func checkNotificationSettings() {
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        let damageEnabled = defaults.bool(forKey: "damageNotificationsEnabled")
        let returnEnabled = defaults.bool(forKey: "returnNotificationsEnabled")
        let shuttleEnabled = defaults.bool(forKey: "shuttleNotificationsEnabled")
        let serviceEnabled = defaults.bool(forKey: "serviceReminderNotificationsEnabled")
        
        print("🔔 [SETTINGS] Notification Settings Check:")
        print("   - Notifications Enabled: \(notificationsEnabled)")
        print("   - Damage Notifications: \(damageEnabled)")
        print("   - Return Notifications: \(returnEnabled)")
        print("   - Shuttle Notifications: \(shuttleEnabled)")
        print("   - Service Reminders: \(serviceEnabled)")
    }
    
    // MARK: - Send Notifications
    func sendDamageRecordNotification(carPlate: String, resCode: String, userName: String) {
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .damageRecord) else { return }

        InAppNotificationManager.shared.showAfterDelay(
            2.0,
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            title: "New Damage Record",
            body: "\(carPlate) — \(userName)"
        )
        sendNotificationToAll(
            title: "🚗 New Damage Record",
            body: "\(userName) added damage record \(resCode) for vehicle \(carPlate)",
            data: ["type": "damage_added", "plate": carPlate, "resCode": resCode]
        )
    }

    func sendDamageCompletedNotification(carPlate: String, resCode: String, userName: String) {
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .damageRecord) else { return }

        InAppNotificationManager.shared.showAfterDelay(
            2.0,
            icon: "checkmark.seal.fill",
            iconColor: .green,
            title: "Damage Completed",
            body: "\(carPlate) — \(resCode)"
        )
        sendNotificationToAll(
            title: "✅ Damage Completed",
            body: "\(userName) marked damage \(resCode) as done for vehicle \(carPlate)",
            data: ["type": "damage_completed", "plate": carPlate, "resCode": resCode]
        )
    }

    func sendReturnNotification(carPlate: String, userName: String) {
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .vehicleReturn) else { return }

        InAppNotificationManager.shared.showAfterDelay(
            2.0,
            icon: "arrow.uturn.left.circle.fill",
            iconColor: .blue,
            title: "Vehicle Return",
            body: "\(carPlate) — \(userName)"
        )
        sendNotificationToAll(
            title: "🔄 Vehicle Return",
            body: "\(userName) processed return for vehicle \(carPlate)",
            data: ["type": "return_processed", "plate": carPlate]
        )
    }

    func sendExitNotification(carPlate: String, userName: String) {
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .vehicleReturn) else { return }

        InAppNotificationManager.shared.showAfterDelay(
            2.0,
            icon: "arrow.right.circle.fill",
            iconColor: .orange,
            title: "Vehicle Check Out",
            body: "\(carPlate) — \(userName)"
        )
        sendNotificationToAll(
            title: "🚪 Vehicle Check Out",
            body: "\(userName) processed check out for vehicle \(carPlate)",
            data: ["type": "exit_processed", "plate": carPlate]
        )
    }
    
    private func sendNotificationToAll(title: String, body: String, data: [String: String]) {
        print("🔔 [NOTIF] Queueing notification: \(title)")
        
        // Check if notifications are enabled in settings (default: true if not set)
        let defaults = UserDefaults.standard
        let notificationsEnabled: Bool
        if defaults.object(forKey: "notificationsEnabled") == nil {
            // Key doesn't exist, use default value (true)
            notificationsEnabled = true
            // default true
        } else {
            notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        }
        
        guard notificationsEnabled else {
            print("⚠️ [NOTIF] Notifications are disabled in settings")
            return
        }
        
        // Prevent duplicate notifications by checking recent notifications
        let notificationKey = "\(title)_\(body)_\(data["plate"] ?? "")"
        let lastNotificationKey = UserDefaults.standard.string(forKey: "lastNotificationKey")
        let lastNotificationTime = UserDefaults.standard.double(forKey: "lastNotificationTime")
        let currentTime = Date().timeIntervalSince1970
        
        // If same notification was sent within last 5 seconds, skip it
        if lastNotificationKey == notificationKey && (currentTime - lastNotificationTime) < 5.0 {
            print("⚠️ [NOTIF] Duplicate notification prevented: \(title)")
            return
        }
        
        // Save current notification info
        UserDefaults.standard.set(notificationKey, forKey: "lastNotificationKey")
        UserDefaults.standard.set(currentTime, forKey: "lastNotificationTime")
        
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let expiresAt = Timestamp(date: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date().addingTimeInterval(14 * 24 * 3600))
        
        // Create notification payload (Cloud Function resolves tenant tokens securely)
            let idempotencyKey = "\(title)|\(body)|\(data["plate"] ?? "")|\(franchiseId)"
            let notification: [String: Any] = [
                "title": title,
                "body": body,
                "data": data,
                "franchiseId": franchiseId,
                "idempotencyKey": idempotencyKey,
                "timestamp": Timestamp(date: Date()),
                "expiresAt": expiresAt
            ]
            
            Firestore.firestore()
                .collection("franchises")
                .document(franchiseId)
                .collection("notifications")
                .addDocument(data: notification) { error in
                    if let error {
                        print("❌ [NOTIF] Error queuing notification: \(error.localizedDescription)")
                    } else {
                        print("✅ [NOTIF] Notification queued (scoped)")
                    }
                }
    }
    
    
    // MARK: - Shuttle Notifications
    
    func sendShuttleLocationSharingOnNotification(driverName: String) {
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else { return }
        sendNotificationToAll(
            title: "🚐 Shuttle driver location sharing ON",
            body: "\(driverName) started sharing live location on Shuttle Map",
            data: [
                "type": "shuttle_location_sharing_on",
                "driverName": driverName
            ]
        )
    }

    /// Staff tapped a shuttle driver on the map — push only to that driver.
    func sendShuttleCustomerWaitingNotification(
        targetDriverUid: String,
        driverName: String,
        requestedBy: String
    ) {
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else { return }
        queueScopedNotification(
            title: "🚐 Customer waiting",
            body: "\(requestedBy) needs shuttle — customer at your location on the map",
            data: [
                "type": "shuttle_customer_waiting",
                "driverName": driverName,
                "requestedBy": requestedBy
            ],
            targetUserIds: [targetDriverUid]
        )
    }

    private func queueScopedNotification(
        title: String,
        body: String,
        data: [String: String],
        targetUserIds: [String]? = nil
    ) {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let expiresAt = Timestamp(date: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date().addingTimeInterval(14 * 24 * 3600))
        var notification: [String: Any] = [
            "title": title,
            "body": body,
            "data": data,
            "franchiseId": franchiseId,
            "idempotencyKey": "\(title)|\(body)|\(data["type"] ?? "")|\(franchiseId)|\(targetUserIds?.joined(separator: ",") ?? "all")",
            "timestamp": Timestamp(date: Date()),
            "expiresAt": expiresAt
        ]
        if let targetUserIds, !targetUserIds.isEmpty {
            notification["targetUserIds"] = targetUserIds
        }
        Firestore.firestore()
            .collection("franchises")
            .document(franchiseId)
            .collection("notifications")
            .addDocument(data: notification)
    }

    func sendShuttleStartNotification(driverName: String) {
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else {
            print("⚠️ Shuttle notifications are disabled in settings")
            return
        }
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
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else {
            print("⚠️ Shuttle notifications are disabled in settings")
            return
        }
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
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else {
            print("⚠️ Shuttle notifications are disabled in settings")
            return
        }
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
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else {
            print("⚠️ Shuttle notifications are disabled in settings")
            return
        }
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
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else {
            print("⚠️ Shuttle notifications are disabled in settings")
            return
        }
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
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else {
            print("⚠️ Shuttle notifications are disabled in settings")
            return
        }
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
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .shuttle) else {
            print("⚠️ Shuttle notifications are disabled in settings")
            return
        }
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
        // Check if service reminder notifications are enabled
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .serviceReminder) else {
            print("⚠️ Service reminder notifications are disabled in settings")
            return
        }
        
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
        // Check if service reminder notifications are enabled
        guard NotificationSettingsManager.shared.shouldSendNotification(type: .serviceReminder) else {
            print("⚠️ Service reminder notifications are disabled in settings")
            return
        }
        
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
    
    // MARK: - Daily Summary Notification (20:00 every day)
    func scheduleDailySummaryNotification(returnsCount: Int, checkoutsCount: Int, damageCount: Int) {
        let identifier = "daily_summary_notification"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])

        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Today's Summary"
        content.body = "\(returnsCount) returns · \(checkoutsCount) checkouts · \(damageCount) damage records"
        content.sound = .default
        content.userInfo = ["type": "daily_summary"]

        var components = DateComponents()
        components.hour = 20
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Daily summary scheduling error: \(error.localizedDescription)")
            } else {
                print("✅ Daily summary notification scheduled at 20:00")
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
extension NotificationManager {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("🔑 FCM Token received: \(maskedToken(token))")
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
        // In-app banner system is used while app is active.
        // Suppress legacy system banner to avoid duplicate notifications.
        completionHandler([])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
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
