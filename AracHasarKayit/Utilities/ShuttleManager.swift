import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import Combine

/// Manages shuttle operations, location tracking, and daily sessions
class ShuttleManager: NSObject, ObservableObject {
    static let shared = ShuttleManager()
    
    // MARK: - Published Properties
    @Published var currentSession: ShuttleSession?
    @Published var todayEntries: [ShuttleEntry] = []
    @Published var allSessions: [ShuttleSession] = []
    @Published var activeDriverLocations: [ShuttleLocation] = []
    @Published var currentLocation: CLLocation?
    @Published var isTrackingLocation = false
    @Published var etaToDestination: TimeInterval?
    @Published var distanceToDestination: CLLocationDistance?
    @Published var isHeadingToDestination = false
    
    // Main destination: Hofwisenstrasse 36, 8153 Rümlang
    private let mainDestination = CLLocation(latitude: 47.4458, longitude: 8.5235)
    private var lastDistanceToDestination: CLLocationDistance?
    private var has5MinuteNotificationBeenSent = false
    
    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private let locationManager = CLLocationManager()
    private var sessionListener: ListenerRegistration?
    private var entriesListener: ListenerRegistration?
    private var locationsListener: ListenerRegistration?
    private var locationUpdateTimer: Timer?
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 0 // Real-time precise tracking
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // CRITICAL FIX: Initialize session on app start
        initializeSession()
    }
    
    // MARK: - Session Initialization
    
    func initializeSession() {
        guard let user = Auth.auth().currentUser else { return }
        
        print("🔄 Initializing shuttle session for user: \(user.uid)")
        
        db.collection("shuttleSessions")
            .whereField("driverUID", isEqualTo: user.uid)
            .whereField("isActive", isEqualTo: true)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error loading active session: \(error)")
                    return
                }
                
                guard let doc = snapshot?.documents.first else {
                    print("ℹ️ No active session found")
                    return
                }
                
                do {
                    let session = try doc.data(as: ShuttleSession.self)
                    print("✅ Active session loaded: \(session.id ?? "unknown")")
                    
                    DispatchQueue.main.async {
                        self.currentSession = session
                        // Start location tracking for active session
                        self.startLocationTracking()
                        // Listen to entries
                        self.listenToTodayEntries()
                        // Listen to active drivers
                        self.listenToActiveDrivers()
                    }
                } catch {
                    print("❌ Error parsing session: \(error)")
                }
            }
    }
    
    // MARK: - Location Tracking
    
    func startLocationTracking() {
        // Check authorization status first
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("❌ Location permission denied")
            return
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        @unknown default:
            break
        }
        
        locationManager.startUpdatingLocation()
        isTrackingLocation = true
        
        // Update Firebase location every 5 seconds for real-time tracking
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateLocationInFirebase()
        }
        
        print("📍 Started location tracking")
    }
    
    func stopLocationTracking() {
        locationManager.stopUpdatingLocation()
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        
        // Mark as inactive in Firebase
        markLocationInactive()
        
        // Update on main thread
        DispatchQueue.main.async {
            self.isTrackingLocation = false
        }
        
        print("📍 Stopped location tracking")
    }
    
    private func updateLocationInFirebase() {
        // Only the authorized session driver should push location updates
        guard currentSession != nil else { return }
        guard let user = Auth.auth().currentUser,
              let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first else {
            print("❌ No authenticated user for location update")
            return
        }
        
        // CRITICAL FIX: Use last known location if current is nil
        guard let location = currentLocation else {
            print("⚠️ No current location, retrying in 2 seconds...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.updateLocationInFirebase()
            }
            return
        }
        
        let locationData = ShuttleLocation(
            driverName: driverName,
            driverUID: user.uid,
            location: GeoPointData(coordinate: location.coordinate),
            timestamp: Date(),
            isActive: true,
            speed: location.speed >= 0 ? Double(location.speed * 3.6) : nil, // m/s to km/h
            heading: location.course >= 0 ? Double(location.course) : nil
        )
        
        // Convert to Firestore-compatible format
        let locationDict: [String: Any] = [
            "driverName": locationData.driverName,
            "driverUID": locationData.driverUID,
            "driverEmail": user.email?.lowercased() ?? "",
            "location": [
                "latitude": locationData.location.latitude,
                "longitude": locationData.location.longitude
            ],
            "timestamp": Timestamp(date: locationData.timestamp),
            "isActive": locationData.isActive,
            "speed": locationData.speed as Any,
            "heading": locationData.heading as Any
        ]
        
        db.collection("shuttleLocations")
            .document(user.uid)
            .setData(locationDict, merge: true) { error in
                if let error = error {
                    print("❌ Error updating location: \(error)")
                } else {
                    print("📍 Location updated in Firebase")
                }
            }
    }
    
    func markLocationActive() {
        // Only mark active for the authorized driver (has active session)
        guard let user = Auth.auth().currentUser, currentSession != nil else { return }
        
        // Use current location if available, otherwise use a default location (Zürich)
        let coordinate: CLLocationCoordinate2D
        if let location = currentLocation {
            coordinate = location.coordinate
        } else {
            // Default to Zürich, Switzerland
            coordinate = CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417)
        }
        
        let locationData = ShuttleLocation(
            driverName: user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Unknown",
            driverUID: user.uid,
            location: GeoPointData(coordinate: coordinate),
            timestamp: Date(),
            isActive: true,
            speed: currentLocation?.speed ?? 0 >= 0 ? Double((currentLocation?.speed ?? 0) * 3.6) : nil,
            heading: currentLocation?.course ?? 0 >= 0 ? Double(currentLocation?.course ?? 0) : nil
        )
        
        let locationDict: [String: Any] = [
            "driverName": locationData.driverName,
            "driverUID": locationData.driverUID,
            "driverEmail": user.email?.lowercased() ?? "",
            "location": [
                "latitude": locationData.location.latitude,
                "longitude": locationData.location.longitude
            ],
            "timestamp": Timestamp(date: locationData.timestamp),
            "isActive": locationData.isActive,
            "speed": locationData.speed as Any,
            "heading": locationData.heading as Any
        ]
        
        db.collection("shuttleLocations")
            .document(user.uid)
            .setData(locationDict, merge: true) { error in
                if let error = error {
                    print("❌ Error marking driver as active: \(error)")
                } else {
                    print("📍 Driver marked as active")
                }
            }
    }
    
    func markLocationInactive() {
        guard let user = Auth.auth().currentUser else { return }
        
        // Remove location data completely for privacy
        db.collection("shuttleLocations")
            .document(user.uid)
            .delete { error in
                if let error = error {
                    print("❌ Error removing location data: \(error)")
                } else {
                    print("🔒 Location data removed for privacy")
                }
            }
    }
    
    // MARK: - Session Management
    
    func startDailySession() {
        // Check if current user is authorized to start shuttle session
        // Only gmotion@gmail.com can start shuttle sessions
        guard let user = Auth.auth().currentUser else {
            ToastManager.shared.show("❌ User not authenticated", type: .error)
            return
        }
        
        let userEmail = user.email?.lowercased() ?? ""
        if userEmail != "gmotion@gmail.com" {
            ToastManager.shared.show("❌ Only authorized users can start shuttle sessions", type: .error)
            HapticManager.shared.error()
            print("❌ Unauthorized user tried to start shuttle: \(userEmail)")
            return
        }
        
        let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Driver"
        
        let session = ShuttleSession(
            date: Date(),
            driverName: driverName,
            driverUID: user.uid,
            entries: [],
            totalCustomers: 0,
            isActive: true,
            startTime: Date()
        )
        
        let ref = db.collection("shuttleSessions").document()
        var updatedSession = session
        updatedSession.id = ref.documentID
        
        try? ref.setData(from: session) { error in
            if let error = error {
                print("❌ Error creating shuttle session: \(error)")
                ToastManager.shared.show("❌ Error starting session: \(error.localizedDescription)", type: .error)
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.currentSession = updatedSession
            }
            
            // CRITICAL FIX: Automatically start location tracking when session starts
            DispatchQueue.main.async {
                self.startLocationTracking()
            }
            
            // Mark as active driver in shuttleLocations
            self.markLocationActive()
            
            // Wait a moment for Firebase to update, then start listening
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.listenToActiveDrivers()
            }
            
            // Update presence to online
            UserPresenceManager.shared.setOnline()
            
            self.listenToTodayEntries()
            
            // Send notification
            NotificationManager.shared.sendShuttleStartNotification(driverName: driverName)
            
            // Post notification for UI update
            NotificationCenter.default.post(name: NSNotification.Name("ShuttleSessionUpdated"), object: nil)
            
            print("✅ Shuttle session started: \(ref.documentID)")
        }
    }
    
    func endDailySession() async throws {
        guard var session = currentSession else { return }
        
        session.isActive = false
        session.endTime = Date()
        
        try db.collection("shuttleSessions")
            .document(session.id ?? "")
            .setData(from: session)
        
        // Mark location as inactive
        markLocationInactive()
        
        // Update presence to offline
        UserPresenceManager.shared.setOffline()
        
        stopLocationTracking()
        
        // Send notification with total customers
        let driverName = session.driverName
        let totalCustomers = session.totalCustomers
        NotificationManager.shared.sendShuttleEndNotification(driverName: driverName, totalCustomers: totalCustomers)
        
        await MainActor.run {
            self.currentSession = nil
        }
        
        print("✅ Shuttle session ended")
    }
    
    // MARK: - Customer Entry
    
    func addCustomerEntry(customerCount: Int, entryType: ShuttleEntryType) async throws {
        guard let user = Auth.auth().currentUser,
              let session = currentSession else {
            throw NSError(domain: "ShuttleManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
        }
        
        let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Driver"
        
        let entry = ShuttleEntry(
            customerCount: customerCount,
            entryType: entryType,
            timestamp: Date(),
            driverName: driverName,
            driverUID: user.uid,
            location: currentLocation.map { GeoPointData(coordinate: $0.coordinate) },
            sessionId: session.id ?? ""
        )
        
        // CRITICAL FIX: Use batch write for atomicity
        let batch = db.batch()
        
        // 1. Add entry to shuttleEntries collection
        let entryRef = db.collection("shuttleEntries").document()
        try batch.setData(from: entry, forDocument: entryRef)
        
        // 2. Update session with new entry and increment total customers
        let sessionRef = db.collection("shuttleSessions").document(session.id ?? "")
        
        // Convert entry to Firestore format
        let entryData: [String: Any] = [
            "customerCount": entry.customerCount,
            "entryType": entry.entryType.rawValue,
            "timestamp": Timestamp(date: entry.timestamp),
            "driverName": entry.driverName,
            "driverUID": entry.driverUID,
            "sessionId": entry.sessionId,
            "location": entry.location.map { [
                "latitude": $0.latitude,
                "longitude": $0.longitude
            ] } as Any
        ]
        
        batch.updateData([
            "entries": FieldValue.arrayUnion([entryData]),
            "totalCustomers": FieldValue.increment(Int64(customerCount))
        ], forDocument: sessionRef)
        
        // Commit the batch transaction
        try await batch.commit()
        
        // Update current session locally
        DispatchQueue.main.async {
            var updatedEntries = self.currentSession?.entries ?? []
            updatedEntries.append(entry)
            self.currentSession?.entries = updatedEntries
            self.currentSession?.totalCustomers += customerCount
        }
        
        // Send notification
        NotificationManager.shared.sendShuttleCustomerNotification(driverName: driverName, customerCount: customerCount)
        
        // Log activity
        logActivity(entry: entry)
        
        print("✅ Customer entry added atomically: \(customerCount) customers")
    }
    
    // MARK: - Listeners
    
    func listenToTodayEntries() {
        guard let session = currentSession else { return }
        
        // Use entries from current session directly
        todayEntries = session.entries.sorted { $0.timestamp > $1.timestamp }
        
        // WORKAROUND: Use only session entries to avoid Firebase index requirement
        print("✅ Today entries loaded: \(todayEntries.count)")
    }
    
    func listenToActiveDrivers() {
        // Only show authorized driver's location to all users
        locationsListener = db.collection("shuttleLocations")
            .whereField("isActive", isEqualTo: true)
            .whereField("driverEmail", isEqualTo: "gmotion@gmail.com")
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("❌ Error listening to locations: \(error)")
                    return
                }
                
                let allLocations = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: ShuttleLocation.self)
                } ?? []
                
                // Show ONLY authorized driver's location to all users
                DispatchQueue.main.async {
                    self?.activeDriverLocations = allLocations
                    print("✅ Active drivers updated: \(allLocations.count)")
                    for location in allLocations {
                        print("  - \(location.driverName)")
                    }
                }
            }
    }
    
    func stopListening() {
        entriesListener?.remove()
        locationsListener?.remove()
    }
    
    // MARK: - Activity Logging
    
    private func logActivity(entry: ShuttleEntry) {
        let activity = Activity(
            tip: .shuttlePickup,
            aciklama: "Shuttle pickup: \(entry.customerCount) customers",
            tarih: entry.timestamp,
            aracPlaka: nil,
            kullaniciAdi: entry.driverName
        )
        
        try? db.collection("activities").addDocument(from: activity) { error in
            if let error = error {
                print("❌ Error logging activity: \(error)")
            }
        }
    }
    
    // MARK: - Report Generation
    
    func generateDailyReport(for session: ShuttleSession) async throws -> DailyShuttleReport {
        // Fetch all entries for this session
        let snapshot = try await db.collection("shuttleEntries")
            .whereField("sessionId", isEqualTo: session.id ?? "")
            .order(by: "timestamp")
            .getDocuments()
        
        let entries = snapshot.documents.compactMap { doc in
            try? doc.data(as: ShuttleEntry.self)
        }
        
        let report = DailyShuttleReport(
            date: session.date,
            driverName: session.driverName,
            totalCustomers: session.totalCustomers,
            totalTrips: entries.count,
            entries: entries,
            startTime: session.startTime,
            endTime: session.endTime ?? Date()
        )
        
        return report
    }
    
    // MARK: - ETA Calculation
    
    private func calculateETAToDestination(from currentLocation: CLLocation) {
        let distance = currentLocation.distance(from: mainDestination)
        distanceToDestination = distance
        
        // Calculate if heading towards destination
        if let lastDistance = lastDistanceToDestination {
            isHeadingToDestination = distance < lastDistance
        }
        lastDistanceToDestination = distance
        
        // Calculate ETA based on average speed (40 km/h for shuttle)
        let averageSpeedKmh = 40.0
        let averageSpeedMs = averageSpeedKmh * 1000 / 3600 // m/s
        etaToDestination = distance / averageSpeedMs
        
        // Check for 5-minute notification
        if isHeadingToDestination && !has5MinuteNotificationBeenSent {
            if let eta = etaToDestination, eta <= 300 && eta > 240 { // Between 4-5 minutes
                send5MinuteNotification()
                has5MinuteNotificationBeenSent = true
            }
        }
        
        // Reset notification flag if moved away
        if !isHeadingToDestination && has5MinuteNotificationBeenSent {
            if let eta = etaToDestination, eta > 600 { // More than 10 minutes
                has5MinuteNotificationBeenSent = false
            }
        }
    }
    
    private func send5MinuteNotification() {
        guard let user = Auth.auth().currentUser,
              let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first else { return }
        
        NotificationManager.shared.sendShuttleETANotification(
            driverName: driverName,
            minutesRemaining: 5
        )
        
        print("📢 5-minute ETA notification sent")
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopListening()
        stopLocationTracking()
    }
}

// MARK: - CLLocationManagerDelegate

extension ShuttleManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
            
            // Calculate ETA and distance to main destination
            self.calculateETAToDestination(from: location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            print("✅ Location permission granted")
            DispatchQueue.main.async {
                if self.isTrackingLocation {
                    self.locationManager.startUpdatingLocation()
                }
            }
        case .denied, .restricted:
            print("❌ Location permission denied")
            DispatchQueue.main.async {
                self.isTrackingLocation = false
            }
        case .notDetermined:
            print("⏳ Location permission not determined")
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
}

