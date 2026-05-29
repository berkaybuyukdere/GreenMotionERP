import SwiftUI
import MapKit

struct ShuttleMapView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var locationService = ShuttleLocationSharingService.shared

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var sharingToggle = false
    @State private var showPrivacySheet = false
    @State private var lastTapNotifyAt: Date?

    private var isShuttleDriver: Bool {
        authManager.userProfile?.role == .shuttle
    }

    private var driverDisplayName: String {
        if let p = authManager.userProfile {
            let n = "\(p.firstName) \(p.lastName)".trimmingCharacters(in: .whitespaces)
            if !n.isEmpty { return n }
        }
        return authManager.userProfile?.email ?? "Shuttle"
    }

    private var requesterName: String {
        driverDisplayName
    }

    private var pins: [ShuttleDriverLocation] {
        guard let uid = authManager.userProfile?.uid else { return locationService.activeDrivers }
        return locationService.activeDrivers.filter { $0.driverUid != uid }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                mapLayer
                controlPanel
                JarvisLearningBeacon(screen: "ShuttleMap")
            }
            .background(PalantirTheme.background.ignoresSafeArea())
            .navigationTitle("shuttle_map.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPrivacySheet = true
                    } label: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                    .accessibilityLabel("shuttle_map.privacy_title".localized)
                }
            }
            .sheet(isPresented: $showPrivacySheet) {
                shuttlePrivacySheet
            }
            .onAppear {
                locationService.setMapTabVisible(true)
                sharingToggle = locationService.isSharingEnabled
                centerOnDrivers()
            }
            .onDisappear {
                sharingToggle = false
                locationService.setSharingEnabled(false, driverName: driverDisplayName, notifyOnEnable: false)
                locationService.setMapTabVisible(false)
            }
            .onChange(of: locationService.activeDrivers) { _, _ in
                centerOnDrivers()
            }
            .onChange(of: locationService.lastLocalFix) { _, _ in
                if isShuttleDriver, locationService.isSharingEnabled, let fix = locationService.lastLocalFix {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: fix.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                        ))
                    }
                }
            }
        }
    }

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            ForEach(pins) { driver in
                Annotation(driver.driverName, coordinate: driver.coordinate) {
                    Button {
                        handleDriverPinTap(driver)
                    } label: {
                        shuttlePin(for: driver)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isShuttleDriver, let fix = locationService.lastLocalFix, locationService.isSharingEnabled {
                Annotation("shuttle_map.you".localized, coordinate: fix.coordinate) {
                    Image(systemName: "bus.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(PalantirTheme.accent))
                }
            }
        }
        .mapStyle(colorScheme == .dark ? .standard(elevation: .realistic) : .standard)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func shuttlePin(for driver: ShuttleDriverLocation) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "bus.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .padding(8)
                .background(Circle().fill(driver.isLiveOnMap ? PalantirTheme.success : Color.gray.opacity(0.55)))
            if !driver.isLiveOnMap, let ended = driver.offlineSince {
                Text("shuttle_map.offline".localized)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(PalantirTheme.textMuted)
                Text(ended, style: .relative)
                    .font(.system(size: 7))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isShuttleDriver {
                Toggle("shuttle_map.share_location".localized, isOn: $sharingToggle)
                    .font(PalantirTheme.bodyFont(14))
                    .tint(PalantirTheme.success)
                    .onChange(of: sharingToggle) { _, on in
                        locationService.setSharingEnabled(on, driverName: driverDisplayName, notifyOnEnable: on)
                        if on {
                            LiveActivityTracker.shared.record(
                                .shuttleSharingOn,
                                title: "Shuttle live location ON",
                                subtitle: driverDisplayName,
                                userProfile: authManager.userProfile,
                                force: true
                            )
                        }
                    }
                Text("shuttle_map.share_hint".localized)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
                Text("shuttle_map.privacy_short".localized)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            } else {
                Text("shuttle_map.viewer_hint".localized)
                    .font(PalantirTheme.bodyFont(13))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Text("shuttle_map.tap_notify_hint".localized)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            }

            if pins.isEmpty && !(isShuttleDriver && locationService.isSharingEnabled) {
                Text("shuttle_map.no_active".localized)
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
            } else {
                ForEach(pins) { d in
                    HStack {
                        Circle()
                            .fill(d.isLiveOnMap ? PalantirTheme.success : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(d.driverName)
                            .font(PalantirTheme.heroFont(13))
                            .foregroundStyle(PalantirTheme.textPrimary)
                        Spacer()
                        if d.isLiveOnMap {
                            Text(d.updatedAt, style: .relative)
                                .font(PalantirTheme.dataFont(11))
                                .foregroundStyle(PalantirTheme.textMuted)
                        } else if let ended = d.offlineSince {
                            Text(String(format: "shuttle_map.offline_since".localized, ended.formatted(date: .abbreviated, time: .shortened)))
                                .font(PalantirTheme.dataFont(10))
                                .foregroundStyle(PalantirTheme.textMuted)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            if let err = locationService.publishError {
                Text(err)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.critical)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(PalantirTheme.surface.opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PalantirTheme.border))
        )
        .padding()
    }

    private var shuttlePrivacySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("shuttle_map.privacy_title".localized)
                        .font(PalantirTheme.heroFont(18))
                    Text("shuttle_map.privacy_body".localized)
                        .font(PalantirTheme.bodyFont(14))
                        .foregroundStyle(PalantirTheme.textPrimary)
                    Text("shuttle_map.privacy_offline".localized)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                .padding()
            }
            .background(PalantirTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close".localized) { showPrivacySheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func handleDriverPinTap(_ driver: ShuttleDriverLocation) {
        guard !isShuttleDriver else { return }
        guard driver.isLiveOnMap else { return }
        let now = Date()
        if let last = lastTapNotifyAt, now.timeIntervalSince(last) < 90 { return }
        lastTapNotifyAt = now
        locationService.notifyDriverCustomerWaiting(
            driverUid: driver.driverUid,
            driverName: driver.driverName,
            requestedBy: requesterName
        )
    }

    private func centerOnDrivers() {
        var coords = pins.map(\.coordinate)
        if isShuttleDriver, let fix = locationService.lastLocalFix, locationService.isSharingEnabled {
            coords.append(fix.coordinate)
        }
        guard !coords.isEmpty else {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417),
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            ))
            return
        }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.4 + 0.02),
            longitudeDelta: max(0.02, (lngs.max()! - lngs.min()!) * 1.4 + 0.02)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}
