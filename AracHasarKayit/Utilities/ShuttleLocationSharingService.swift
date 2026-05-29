import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Combine

/// Opt-in shuttle live location: publishes only while Shuttle Map tab is visible and sharing toggle is ON.
final class ShuttleLocationSharingService: NSObject, ObservableObject {
    static let shared = ShuttleLocationSharingService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isSharingEnabled = false
    @Published private(set) var activeDrivers: [ShuttleDriverLocation] = []
    @Published private(set) var lastLocalFix: CLLocation?
    @Published private(set) var publishError: String?

    private let locationManager = CLLocationManager()
    private var mapTabVisible = false
    private var driversListener: ListenerRegistration?
    private var lastWrittenLocation: CLLocation?
    private var lastWriteAt: Date?
    private let minWriteInterval: TimeInterval = 25
    private let minMovementMeters: CLLocationDistance = 45
    private var loginPermissionRequested = false

    func resetSession() {
        stopObservingActiveDrivers()
        stopPublishing(markSharingOff: true, reason: .sessionReset)
        mapTabVisible = false
        isSharingEnabled = false
        loginPermissionRequested = false
        pendingEnableAfterAuth = false
        activeDriverName = ""
        DispatchQueue.main.async {
            self.activeDrivers = []
            self.lastLocalFix = nil
            self.publishError = nil
        }
    }

    /// Stops sharing when app backgrounds or terminates (privacy: no background tracking).
    func handleAppBackgrounded() {
        guard isSharingEnabled || mapTabVisible else { return }
        isSharingEnabled = false
        stopPublishing(markSharingOff: true, reason: .appBackgrounded)
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
        authorizationStatus = locationManager.authorizationStatus
    }

    var isShuttleDriver: Bool {
        // Resolved by caller via profile; keep helper for map UI
        false
    }

    // MARK: - Login permission (shuttle role only)

    func requestLocationPermissionAtLoginIfNeeded(isShuttleRole: Bool) {
        guard isShuttleRole, !loginPermissionRequested else { return }
        loginPermissionRequested = true
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Map tab lifecycle

    func setMapTabVisible(_ visible: Bool) {
        mapTabVisible = visible
        if visible {
            startObservingActiveDrivers()
            resumePublishingIfNeeded()
        } else {
            stopObservingActiveDrivers()
            stopPublishing(markSharingOff: true, reason: .leftMapTab)
        }
    }

    func setSharingEnabled(_ enabled: Bool, driverName: String, notifyOnEnable: Bool = true) {
        guard Auth.auth().currentUser != nil else { return }
        if !driverName.isEmpty { activeDriverName = driverName }

        if enabled {
            switch authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                isSharingEnabled = true
                resumePublishingIfNeeded()
                if notifyOnEnable {
                    NotificationManager.shared.sendShuttleLocationSharingOnNotification(driverName: driverName)
                }
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
                pendingEnableAfterAuth = true
                activeDriverName = driverName
            case .denied, .restricted:
                publishError = "Location permission denied. Enable in Settings.".localized
                isSharingEnabled = false
            @unknown default:
                isSharingEnabled = false
            }
        } else {
            isSharingEnabled = false
            stopPublishing(markSharingOff: true, reason: .userToggleOff)
        }
    }

    private var pendingEnableAfterAuth = false
    private var activeDriverName = ""

    // MARK: - Observe other drivers

    private func startObservingActiveDrivers() {
        guard driversListener == nil else { return }
        let franchiseId = FirebaseService.shared.currentFranchiseId
        driversListener = FirebaseService.shared
            .getCollectionReference("shuttleDriverLocations")
            .whereField("franchiseId", isEqualTo: franchiseId)
            .limit(to: 12)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    DispatchQueue.main.async {
                        self.publishError = error.localizedDescription
                    }
                    return
                }
                let drivers = snapshot?.documents.compactMap { ShuttleDriverLocation.from(document: $0) } ?? []
                DispatchQueue.main.async {
                    self.activeDrivers = drivers
                }
            }
    }

    private func stopObservingActiveDrivers() {
        driversListener?.remove()
        driversListener = nil
        DispatchQueue.main.async {
            self.activeDrivers = []
        }
    }

    // MARK: - Publish own location

    private func resumePublishingIfNeeded() {
        guard mapTabVisible, isSharingEnabled else { return }
        guard CLLocationManager.locationServicesEnabled() else { return }
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            writeSharingState(isSharing: true)
        default:
            break
        }
    }

    private enum SharingStopReason: String {
        case leftMapTab, userToggleOff, appBackgrounded, sessionReset
    }

    private func stopPublishing(markSharingOff: Bool, reason: SharingStopReason) {
        locationManager.stopUpdatingLocation()
        if markSharingOff {
            writeSharingState(isSharing: false, stopReason: reason.rawValue)
        }
        lastWrittenLocation = nil
        lastWriteAt = nil
    }

    private func writeSharingState(isSharing: Bool, stopReason: String? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = FirebaseService.shared
            .getCollectionReference("shuttleDriverLocations")
            .document(uid)
        let name = activeDriverName.isEmpty ? (Auth.auth().currentUser?.displayName ?? "Shuttle") : activeDriverName
        var payload: [String: Any] = [
            "driverUid": uid,
            "driverName": name,
            "franchiseId": FirebaseService.shared.currentFranchiseId,
            "isSharing": isSharing,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if isSharing {
            if let loc = lastLocalFix {
                payload["latitude"] = loc.coordinate.latitude
                payload["longitude"] = loc.coordinate.longitude
            }
        } else {
            payload["sharingEndedAt"] = FieldValue.serverTimestamp()
            if let reason = stopReason {
                payload["sharingStopReason"] = reason
            }
            if let loc = lastWrittenLocation ?? lastLocalFix {
                payload["latitude"] = loc.coordinate.latitude
                payload["longitude"] = loc.coordinate.longitude
            }
        }
        ref.setData(payload, merge: true)
    }

    /// Viewer tapped shuttle pin — notify driver (out-of-app push via Cloud Function).
    func notifyDriverCustomerWaiting(driverUid: String, driverName: String, requestedBy: String) {
        guard let uid = Auth.auth().currentUser?.uid, uid != driverUid else { return }
        LiveActivityTracker.shared.record(
            .shuttleCustomerPing,
            title: "Customer waiting — shuttle ping",
            subtitle: "\(requestedBy) → \(driverName)",
            force: true
        )
        NotificationManager.shared.sendShuttleCustomerWaitingNotification(
            targetDriverUid: driverUid,
            driverName: driverName,
            requestedBy: requestedBy
        )
    }

    private func publishLocationIfNeeded(_ location: CLLocation) {
        guard mapTabVisible, isSharingEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let now = Date()
        if let last = lastWriteAt, now.timeIntervalSince(last) < minWriteInterval {
            if let prev = lastWrittenLocation, location.distance(from: prev) < minMovementMeters {
                return
            }
        }

        lastWriteAt = now
        lastWrittenLocation = location

        let name = activeDriverName.isEmpty ? (Auth.auth().currentUser?.displayName ?? "Shuttle") : activeDriverName
        let data: [String: Any] = [
            "driverUid": uid,
            "driverName": name,
            "franchiseId": FirebaseService.shared.currentFranchiseId,
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "isSharing": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        FirebaseService.shared
            .getCollectionReference("shuttleDriverLocations")
            .document(uid)
            .setData(data, merge: true) { [weak self] error in
                if let error {
                    DispatchQueue.main.async {
                        self?.publishError = error.localizedDescription
                    }
                }
            }
    }
}

extension ShuttleLocationSharingService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if self.pendingEnableAfterAuth,
               manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                self.pendingEnableAfterAuth = false
                self.setSharingEnabled(true, driverName: self.activeDriverName, notifyOnEnable: true)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.lastLocalFix = loc
        }
        publishLocationIfNeeded(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.publishError = error.localizedDescription
        }
    }
}
