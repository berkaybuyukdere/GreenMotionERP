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
    /// Push token registration and Firestore binding require an authenticated user with franchise context.
    var isPushRegistrationAllowed: Bool {
        guard Auth.auth().currentUser != nil else { return false }
        let franchiseId = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return !franchiseId.isEmpty
    }

    func registerForPushIfAllowed() {
        guard isPushRegistrationAllowed else {
            print("🔔 [FCM] Push registration deferred — franchise context not set")
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                
                if granted {
                    print("✅ Notification permission granted")
                    self?.registerForPushIfAllowed()
                } else {
                    print("❌ Notification permission denied")
                }
                
                if let error = error {
                    print("❌ Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Re-request full banner/lock-screen delivery on every cold launch (never use provisional — it delivers quietly).
    func ensureProminentDeliveryOnLaunch() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["daily_summary_notification"]
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                switch settings.authorizationStatus {
                case .notDetermined:
                    self.requestAuthorization()
                case .authorized, .ephemeral:
                    self.isAuthorized = true
                    self.registerForPushIfAllowed()
                case .provisional:
                    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            self.isAuthorized = granted
                            if granted {
                                self.registerForPushIfAllowed()
                            }
                        }
                    }
                case .denied:
                    self.isAuthorized = false
                @unknown default:
                    break
                }

                if settings.authorizationStatus == .authorized,
                   settings.alertSetting == .disabled || settings.lockScreenSetting == .disabled {
                    print("⚠️ [NOTIF] Alerts/lock screen disabled — user may see Deliver Quietly in iOS Settings")
                }
            }
        }
    }
    
    // MARK: - FCM Token Management
    /// Re-register with APNs and persist FCM token after franchise context is active.
    func refreshPushRegistrationAfterAuth() {
        guard isPushRegistrationAllowed else {
            print("🔔 [FCM] Skipping push refresh — franchise context not set")
            return
        }
        print("🔔 [FCM] Refreshing push registration after auth")
        registerForPushIfAllowed()
        syncFCMTokenFranchiseBinding()
    }

    /// Re-persist the current FCM token with the active franchise id (e.g. after franchise switch).
    func syncFCMTokenFranchiseBinding() {
        guard isPushRegistrationAllowed else {
            print("⚠️ [FCM] Skipping franchise token sync — context not ready")
            return
        }
        if let token = fcmToken, !token.isEmpty {
            saveFCMToken(token)
            return
        }
        if Messaging.messaging().apnsToken != nil {
            Messaging.messaging().token { [weak self] token, error in
                if let error {
                    print("❌ [FCM] Token refresh failed: \(error.localizedDescription)")
                    return
                }
                if let token {
                    self?.saveFCMToken(token)
                } else {
                    print("⚠️ [FCM] Token refresh returned nil")
                }
            }
        } else {
            print("⚠️ [FCM] No APNS token yet — waiting for didRegisterForRemoteNotifications")
        }
    }

    func saveFCMToken(_ token: String) {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ [FCM] No authenticated user — token not saved")
            return
        }

        self.fcmToken = token

        let activeFranchise = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !activeFranchise.isEmpty else {
            print("⚠️ [FCM] Deferring token persist until franchise context is set")
            return
        }

        let userRef = FirebaseService.shared.getCollectionReference("users").document(userId)
        let normalized = activeFranchise
        print("🔑 [FCM] Saving token for user \(userId) franchise=\(normalized)")
        var payload: [String: Any] = [
            "fcmToken": token,
            "lastTokenUpdate": Timestamp(date: Date()),
            "franchiseId": normalized,
            "fcmFranchiseId": normalized
        ]
        userRef.setData(payload, merge: true) { error in
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
    func sendDamageRecordNotification(carPlate: String, resCode: String, userName: String, recordId: UUID) {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        queueFranchiseWideNotification(
            title: "🚗 New Damage Record",
            body: "\(userName) added damage record \(resCode) for vehicle \(carPlate)",
            data: ["type": "damage_added", "plate": carPlate, "resCode": resCode, "recordId": recordId.uuidString],
            idempotencyKey: "damage_added|\(recordId.uuidString)|\(franchiseId)",
            localType: .damageRecord
        )
    }

    func sendDamageCompletedNotification(carPlate: String, resCode: String, userName: String, recordId: UUID) {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        queueFranchiseWideNotification(
            title: "✅ Damage Completed",
            body: "\(userName) marked damage \(resCode) as done for vehicle \(carPlate)",
            data: ["type": "damage_completed", "plate": carPlate, "resCode": resCode, "recordId": recordId.uuidString],
            idempotencyKey: "damage_completed|\(recordId.uuidString)|\(franchiseId)",
            localType: .damageRecord
        )
    }

    func sendReturnNotification(carPlate: String, userName: String) {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        queueFranchiseWideNotification(
            title: "🔄 Vehicle Return",
            body: "\(userName) processed return for vehicle \(carPlate)",
            data: ["type": "return_processed", "plate": carPlate],
            idempotencyKey: "return_processed|\(carPlate)|\(franchiseId)",
            localType: .vehicleReturn
        )
    }

    func sendExitNotification(carPlate: String, userName: String) {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        queueFranchiseWideNotification(
            title: "🚪 Vehicle Check Out",
            body: "\(userName) processed check out for vehicle \(carPlate)",
            data: ["type": "exit_processed", "plate": carPlate],
            idempotencyKey: "exit_processed|\(carPlate)|\(franchiseId)",
            localType: .vehicleReturn
        )
    }

    func sendAnnouncementNotification(title: String, publisherName: String, announcementId: String) {
        let notifTitle = "📢 \(title)"
        let notifBody = String(format: "announcements.notif.body".localized, publisherName)
        queueFranchiseWideNotification(
            title: notifTitle,
            body: notifBody,
            data: [
                "type": "announcement",
                "announcementId": announcementId,
                "publisherName": publisherName
            ],
            idempotencyKey: "announcement|\(announcementId)|\(FirebaseService.shared.currentFranchiseId.uppercased())",
            localType: .announcement
        )
    }

    /// Automated 21:30 daily fleet summary — always delivered prominently to all franchise users.
    func sendDailyReportNotification(title: String, body: String, announcementId: String) {
        queueFranchiseWideNotification(
            title: "📊 \(title)",
            body: body,
            data: [
                "type": "daily_report",
                "announcementId": announcementId,
                "announcementKind": "daily_report",
            ],
            idempotencyKey: "daily_report|\(announcementId)|\(FirebaseService.shared.currentFranchiseId.uppercased())",
            localType: .dailyReport
        )
    }

    func sendTeamChatNotification(senderName: String, preview: String, messageId: String) {
        let notifTitle = "💬 \("announcements.tab.chat".localized)"
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty
            ? String(format: "announcements.chat.notif.body".localized, senderName)
            : "\(senderName): \(trimmed)"
        queueFranchiseWideNotification(
            title: notifTitle,
            body: body,
            data: [
                "type": "team_chat",
                "messageId": messageId,
                "senderName": senderName
            ],
            idempotencyKey: "team_chat|\(messageId)|\(FirebaseService.shared.currentFranchiseId.uppercased())",
            localType: nil
        )
    }

    /// Always queues to Firestore for every franchise user. Local banners on this device respect `localType` only.
    private func queueFranchiseWideNotification(
        title: String,
        body: String,
        data: [String: String],
        idempotencyKey: String,
        localType: NotificationType?
    ) {
        print("🔔 [NOTIF] Queueing franchise-wide notification: \(title)")

        let showLocal: Bool
        if localType == .dailyReport || localType == .announcement {
            showLocal = true
        } else if let localType {
            showLocal = NotificationSettingsManager.shared.shouldSendNotification(type: localType)
        } else {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "notificationsEnabled") == nil {
                showLocal = true
            } else {
                showLocal = defaults.bool(forKey: "notificationsEnabled")
            }
        }
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        var payload = data
        payload["franchiseId"] = franchiseId

        if showLocal {
            deliverLocalNotificationNow(title: title, body: body, userInfo: payload)
        }

        guard !franchiseId.isEmpty else {
            print("❌ [NOTIF] Missing franchiseId — push not queued")
            return
        }
        let expiresAt = Timestamp(date: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date().addingTimeInterval(14 * 24 * 3600))

        var notification: [String: Any] = [
            "title": title,
            "body": body,
            "data": payload,
            "franchiseId": franchiseId,
            "idempotencyKey": idempotencyKey,
            "timestamp": Timestamp(date: Date()),
            "expiresAt": expiresAt
        ]
        if let token = fcmToken, !token.isEmpty {
            notification["excludeFcmTokens"] = [token]
        }

        Firestore.firestore()
            .collection("franchises")
            .document(franchiseId)
            .collection("notifications")
            .addDocument(data: notification) { error in
                if let error {
                    print("❌ [NOTIF] Error queuing franchise-wide notification: \(error.localizedDescription)")
                } else {
                    print("✅ [NOTIF] Franchise-wide notification queued")
                }
            }
    }
    
    private func sendNotificationToAll(
        title: String,
        body: String,
        data: [String: String],
        localType: NotificationType
    ) {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let eventType = data["type"] ?? "event"
        let idempotencyKey = "\(eventType)|\(body)|\(franchiseId)"
        queueFranchiseWideNotification(
            title: title,
            body: body,
            data: data,
            idempotencyKey: idempotencyKey,
            localType: localType
        )
    }
    
    
    // MARK: - Shuttle Notifications
    
    func sendShuttleLocationSharingOnNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Shuttle driver location sharing ON",
            body: "\(driverName) started sharing live location on Shuttle Map",
            data: [
                "type": "shuttle_location_sharing_on",
                "driverName": driverName
            ],
            localType: .shuttle
        )
    }

    /// Staff tapped a shuttle driver on the map — push only to that driver.
    func sendShuttleCustomerWaitingNotification(
        targetDriverUid: String,
        driverName: String,
        requestedBy: String
    ) {
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
        var payload = data
        payload["franchiseId"] = franchiseId

        var notification: [String: Any] = [
            "title": title,
            "body": body,
            "data": payload,
            "franchiseId": franchiseId,
            "idempotencyKey": "\(title)|\(body)|\(payload["type"] ?? "")|\(franchiseId)|\(targetUserIds?.joined(separator: ",") ?? "all")",
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
        sendNotificationToAll(
            title: "🚐 Shuttle Service Started",
            body: "\(driverName) started a shuttle session",
            data: [
                "type": "shuttle_start",
                "driverName": driverName
            ],
            localType: .shuttle
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
            ],
            localType: .shuttle
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
            ],
            localType: .shuttle
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
            ],
            localType: .shuttle
        )
    }
    
    func sendShuttleCustomerAvailableNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Customer Available",
            body: "\(driverName) has customers waiting",
            data: [
                "type": "shuttle_customer_available",
                "driverName": driverName
            ],
            localType: .shuttle
        )
    }
    
    func sendShuttleCustomerPickedUpNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Müşteri Alındı",
            body: "\(driverName) müşteriyi aldı",
            data: [
                "type": "shuttle_customer_picked_up",
                "driverName": driverName
            ],
            localType: .shuttle
        )
    }
    
    func sendShuttleCustomerDroppedOffNotification(driverName: String) {
        sendNotificationToAll(
            title: "🚐 Müşteri Bırakıldı",
            body: "\(driverName) müşteriyi bıraktı",
            data: [
                "type": "shuttle_customer_dropped_off",
                "driverName": driverName
            ],
            localType: .shuttle
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
    
    /// Send service reminder to all users via Firebase (always queued; local prefs gate device banner only).
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
            ],
            localType: .serviceReminder
        )
    }
    
    /// Immediate audible notification on this device (works in foreground via willPresent).
    /// Immediate banner when a checkout/return customer email finishes after the user left the pipeline overlay.
    func postCustomerEmailDeliveryResult(
        success: Bool,
        kind: CustomerEmailPipelineKind,
        vehiclePlate: String?,
        recipient: String?,
        failureDetail: String? = nil
    ) {
        let plate = vehiclePlate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let to = recipient?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let franchiseId = FirebaseService.shared.currentFranchiseId

        let title: String
        let body: String
        if success {
            title = kind == .checkoutConfirmation
                ? "email.pipeline.notif.checkout_sent_title".localized
                : "email.pipeline.notif.return_sent_title".localized
            if !plate.isEmpty, !to.isEmpty {
                body = String(format: "email.pipeline.notif.sent_body".localized, plate, to)
            } else if !plate.isEmpty {
                body = String(format: "email.pipeline.notif.sent_body_plate".localized, plate)
            } else {
                body = "email.pipeline.sent_subtitle".localized
            }
        } else {
            title = kind == .checkoutConfirmation
                ? "email.pipeline.notif.checkout_failed_title".localized
                : "email.pipeline.notif.return_failed_title".localized
            body = failureDetail ?? "Email sending failed.".localized
        }

        deliverLocalNotificationNow(
            title: title,
            body: body,
            userInfo: [
                "type": "customer_email_result",
                "success": success ? "1" : "0",
                "kind": kind.rawValue,
                "franchiseId": franchiseId,
                "vehiclePlate": plate,
            ]
        )
    }

    private func deliverLocalNotificationNow(title: String, body: String, userInfo: [String: String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        content.userInfo = userInfo
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .active
            content.relevanceScore = 1.0
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.15, repeats: false)
        let request = UNNotificationRequest(
            identifier: "local_now_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("❌ [NOTIF] Local notification error: \(error.localizedDescription)")
            } else {
                print("🔔 [NOTIF] Local notification scheduled (audible)")
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

    /// Drop remote/local notifications meant for another franchise (defense in depth vs Cloud Function targeting).
    func shouldDisplayNotification(userInfo: [AnyHashable: Any]) -> Bool {
        let active = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !active.isEmpty else {
            print("🔕 [NOTIF] Suppressed — franchise context not set")
            return false
        }

        guard let payloadFranchise = (userInfo["franchiseId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              !payloadFranchise.isEmpty else {
            return true
        }
        if payloadFranchise == active { return true }
        let payloadRoot = payloadFranchise.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? payloadFranchise
        let activeRoot = active.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? active
        let matches = payloadRoot == activeRoot
        if !matches {
            print("🔕 [NOTIF] Suppressed cross-franchise alert payload=\(payloadFranchise) active=\(active)")
        }
        return matches
    }
}

// MARK: - MessagingDelegate
extension NotificationManager {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("🔑 FCM Token received: \(maskedToken(token))")
        guard isPushRegistrationAllowed else {
            self.fcmToken = token
            print("⚠️ [FCM] Token cached locally — waiting for franchise context before persist")
            return
        }
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
        guard shouldDisplayNotification(userInfo: notification.request.content.userInfo) else {
            completionHandler([])
            return
        }
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
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
