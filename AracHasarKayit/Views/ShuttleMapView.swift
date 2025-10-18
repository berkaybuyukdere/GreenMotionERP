import SwiftUI
import MapKit
import FirebaseAuth

/// Real-time shuttle location tracking map
struct ShuttleMapView: View {
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417), // Zürich, Switzerland
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var selectedDriver: ShuttleLocation?
    @State private var trackingMode: MapUserTrackingMode = .follow
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map
                Map(coordinateRegion: $region,
                    showsUserLocation: true,
                    userTrackingMode: $trackingMode,
                    annotationItems: shuttleManager.activeDriverLocations) { location in
                    MapAnnotation(coordinate: location.location.coordinate) {
                        ShuttleMarker(location: location, isSelected: selectedDriver?.id == location.id)
                            .onTapGesture {
                                selectedDriver = location
                                withAnimation {
                                    region.center = location.location.coordinate
                                }
                            }
                    }
                }
                .mapStyle(.standard)
                .ignoresSafeArea()
                
                // Driver info overlay
                if let selected = selectedDriver {
                    VStack {
                        Spacer()
                        DriverInfoCard(location: selected) {
                            selectedDriver = nil
                        }
                        .padding()
                        .transition(.move(edge: .bottom))
                    }
                }
                
                // Top controls
                VStack {
                    HStack {
                        // Session status indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(shuttleManager.currentSession != nil ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(shuttleManager.currentSession != nil ? "Active" : "Inactive")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial)
                        .cornerRadius(20)
                        .shadow(radius: 4)
                        .padding(.leading)
                        
                        Spacer()
                        
                        // Active drivers count
                        VStack(spacing: 4) {
                            Image(systemName: "bus.fill")
                                .font(.headline)
                            Text("\(shuttleManager.activeDriverLocations.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Drivers")
                                .font(.caption2)
                        }
                        .padding(12)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        
                        // Focus on me button
                        Button {
                            focusOnMyLocation()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .padding(12)
                                .background(.regularMaterial)
                                .cornerRadius(12)
                                .shadow(radius: 4)
                        }
                        .padding(.trailing)
                    }
                    .padding(.top)
                    
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // Customer Available Button (only for active session)
                        if shuttleManager.currentSession != nil {
                            CustomerAvailableButton()
                                .padding(.horizontal)
                        }
                        
                        // ETA Card (only if session is active and ETA is available)
                        if shuttleManager.currentSession != nil,
                           let eta = shuttleManager.etaToDestination,
                           let distance = shuttleManager.distanceToDestination {
                            ETACard(
                                eta: eta,
                                distance: distance,
                                isHeading: shuttleManager.isHeadingToDestination
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Shuttle Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                shuttleManager.listenToActiveDrivers()
                
                // Start location tracking for current user
                if shuttleManager.currentSession != nil {
                    shuttleManager.startLocationTracking()
                }
                
                // Focus on active driver's location (current user if session is active)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if shuttleManager.currentSession != nil, let myLocation = shuttleManager.currentLocation {
                        // If user has active session, focus on their location
                        focusOnMyLocation()
                    } else if !shuttleManager.activeDriverLocations.isEmpty {
                        // Otherwise, center on all active drivers
                        centerOnActiveDrivers()
                    }
                }
            }
            .onDisappear {
                shuttleManager.stopListening()
            }
        }
    }
    
    private func centerOnActiveDrivers() {
        guard !shuttleManager.activeDriverLocations.isEmpty else { return }
        
        let coordinates = shuttleManager.activeDriverLocations.map { $0.location.coordinate }
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
        )
        
        region = MKCoordinateRegion(center: center, span: span)
    }
    
    private func focusOnMyLocation() {
        if let myLocation = shuttleManager.currentLocation {
            withAnimation {
                region.center = myLocation.coordinate
                region.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            }
        }
    }
}

// MARK: - Shuttle Marker (Custom annotation)

struct ShuttleMarker: View {
    let location: ShuttleLocation
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Driver avatar
            ZStack {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: isSelected ? 50 : 40, height: isSelected ? 50 : 40)
                
                Image(systemName: "bus.fill")
                    .font(.system(size: isSelected ? 24 : 18))
                    .foregroundColor(.white)
                
                // Status ring
                Circle()
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: isSelected ? 56 : 46, height: isSelected ? 56 : 46)
            }
            .shadow(radius: 4)
            
            // Pointer
            Image(systemName: "arrowtriangle.down.fill")
                .font(.caption)
                .foregroundColor(.cyan)
                .offset(y: -4)
        }
        .animation(.spring(), value: isSelected)
    }
}

// MARK: - Driver Info Card

struct DriverInfoCard: View {
    let location: ShuttleLocation
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.driverName)
                        .font(.headline)
                    
                    Text("Last updated: \(location.formattedTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Location details
            HStack(spacing: 20) {
                if let speed = location.speed, speed > 0 {
                    VStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .foregroundColor(.cyan)
                        Text("\(Int(speed)) km/h")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                if let heading = location.heading {
                    VStack(spacing: 4) {
                        Image(systemName: "location.north.fill")
                            .foregroundColor(.cyan)
                            .rotationEffect(.degrees(heading))
                        Text("\(Int(heading))Â°")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
                
                Button {
                    openInMaps()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                        Text("Navigate")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.cyan)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 8)
    }
    
    private func openInMaps() {
        let coordinate = location.location.coordinate
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = "\(location.driverName) (Shuttle)"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

// MARK: - Customer Available Button

struct CustomerAvailableButton: View {
    @StateObject private var shuttleManager = ShuttleManager.shared
    @State private var isCooldown = false
    @State private var cooldownRemaining = 0
    
    var body: some View {
        Button {
            sendCustomerAvailableNotification()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("Müşteri Var")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                if isCooldown {
                    Text("(\(cooldownRemaining)s)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.yellow, Color.orange]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .yellow.opacity(0.4), radius: 8, x: 0, y: 4)
            )
        }
        .disabled(isCooldown)
        .opacity(isCooldown ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isCooldown)
    }
    
    private func sendCustomerAvailableNotification() {
        guard let user = Auth.auth().currentUser,
              let driverName = user.displayName ?? user.email?.components(separatedBy: "@").first else { return }
        
        // Send notification
        NotificationManager.shared.sendShuttleCustomerAvailableNotification(driverName: driverName)
        
        // Start cooldown
        startCooldown()
        
        // Haptic feedback
        HapticManager.shared.success()
        
        print("📢 Customer available notification sent by \(driverName)")
    }
    
    private func startCooldown() {
        isCooldown = true
        cooldownRemaining = 5
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            cooldownRemaining -= 1
            
            if cooldownRemaining <= 0 {
                isCooldown = false
                timer.invalidate()
            }
        }
    }
}

// MARK: - ETA Card

struct ETACard: View {
    let eta: TimeInterval
    let distance: CLLocationDistance
    let isHeading: Bool
    
    var formattedETA: String {
        let minutes = Int(eta / 60)
        if minutes < 1 {
            return "< 1 min"
        }
        return "\(minutes) min"
    }
    
    var formattedDistance: String {
        let km = distance / 1000
        if km < 1 {
            return String(format: "%.0f m", distance)
        }
        return String(format: "%.1f km", km)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon with animation
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.cyan, Color.blue]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 56, height: 56)
                    .shadow(color: .cyan.opacity(0.4), radius: 8, x: 0, y: 4)
                
                Image(systemName: isHeading ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("To Hofwisenstrasse 36")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Heading indicator
                    if isHeading {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption)
                            Text("En Route")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)
                    }
                }
                
                HStack(spacing: 20) {
                    // Distance
                    Label(formattedDistance, systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.cyan)
                    
                    // ETA
                    Label(formattedETA, systemImage: "clock.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.cyan.opacity(0.5), Color.blue.opacity(0.5)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Preview

struct ShuttleMapView_Previews: PreviewProvider {
    static var previews: some View {
        ShuttleMapView()
    }
}
