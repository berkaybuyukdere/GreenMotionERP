import SwiftUI

/// Fuel in 0…8 steps (8 = full). Compact row + slider only.
private struct FuelEighthsGauge: View {
    @Binding var eighths: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fuel level (0–8)".localized)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(eighths)/8")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(eighths) },
                    set: { eighths = min(8, max(0, Int($0.rounded()))) }
                ),
                in: 0...8,
                step: 1
            )
            .tint(.blue)
        }
        .padding(.vertical, 2)
    }
}

private struct CheckInSyncOverlay: View {
    let statusMessage: String
    let failed: Bool
    let success: Bool
    let errorText: String?
    var onDismissError: () -> Void
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 18) {
                if failed {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.red)
                    Text("Sync failed".localized)
                        .font(.headline)
                    Text(errorText ?? "Unknown error".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Close".localized) {
                        onDismissError()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else if success {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(statusMessage)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let degrees = (t * 140).truncatingRemainder(dividingBy: 360)
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 4)
                                .frame(width: 76, height: 76)
                            Circle()
                                .trim(from: 0, to: 0.28)
                                .stroke(
                                    AngularGradient(
                                        colors: [.cyan, .blue, .purple, .cyan],
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                )
                                .frame(width: 76, height: 76)
                                .rotationEffect(.degrees(degrees))
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.white)
                        }
                    }
                    Text(statusMessage)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    Text("WheelSys integration".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(Color.black.opacity(0.82))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
    }
}

extension CheckInView {
    /// Single `RES-XXXXX` token for audit text (avoids `RES RES-…` when `resKodu` already includes `RES-`).
    fileprivate static func normalizedReservationLabel(for raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "—" }
        var u = t.uppercased()
        if u.hasPrefix("RES-") { return u }
        if u.hasPrefix("RES") {
            let after = u.dropFirst(3).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            if after.allSatisfy(\.isNumber), !after.isEmpty { return "RES-\(after)" }
        }
        let digits = t.filter(\.isNumber)
        if !digits.isEmpty { return "RES-\(digits)" }
        return t
    }
}

/// Operational check-in when the vehicle is back: km + fuel steps. Tied to the latest open checkout RES (`linkedExit`).
struct CheckInView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    
    let aracId: UUID
    let linkedExit: ExitIslemi
    
    @State private var kmText = ""
    @State private var fuelEighths = 8
    @State private var isSaving = false
    @State private var showSyncOverlay = false
    @State private var syncStatusMessage = ""
    @State private var syncFailed = false
    @State private var syncSucceeded = false
    @State private var syncErrorText: String?
    @State private var stepTask: Task<Void, Never>?
    
    private var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == aracId })
    }

    private var minimumRequiredKm: Int? {
        guard let checkoutKm = linkedExit.km else { return nil }
        return checkoutKm + 1
    }
    
    var body: some View {
        ZStack {
            Form {
                Section {
                    if let arac {
                        HStack {
                            Text("Vehicle".localized)
                            Spacer()
                            Text(arac.plakaFormatli)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("RES (checkout)".localized)
                        Spacer()
                        Text(linkedExit.resKodu.isEmpty ? "—" : linkedExit.resKodu)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    TextField("Current odometer (km)".localized, text: $kmText)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                        .onChange(of: kmText) { _, new in
                            let digits = new.filter(\.isNumber)
                            kmText = String(digits.prefix(6))
                        }
                    
                    FuelEighthsGauge(eighths: $fuelEighths)
                } header: {
                    Text("Vehicle check-in".localized)
                } footer: {
                    Text("Check-in is stored for this RES (checkout). Fuel is recorded in 0–8 steps (8 = full).".localized)
                        .font(.caption)
                }
                
                Section {
                    Button {
                        Task { await saveCheckIn() }
                    } label: {
                        if isSaving {
                            HStack {
                                ProgressView()
                                Text("Saving…".localized)
                            }
                        } else {
                            Text("Complete check-in".localized)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("Check In".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel".localized) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .blur(radius: showSyncOverlay ? 5 : 0)
            .allowsHitTesting(!showSyncOverlay)
            
            if showSyncOverlay {
                CheckInSyncOverlay(
                    statusMessage: syncStatusMessage,
                    failed: syncFailed,
                    success: syncSucceeded,
                    errorText: syncErrorText,
                    onDismissError: {
                        syncFailed = false
                        syncErrorText = nil
                        showSyncOverlay = false
                        isSaving = false
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSyncOverlay)
        .onAppear {
            if kmText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let minKm = minimumRequiredKm {
                kmText = String(minKm)
            }
        }
        .onDisappear {
            stepTask?.cancel()
            stepTask = nil
        }
    }
    
    @MainActor
    private func saveCheckIn() async {
        guard let arac else { return }
        let trimmed = kmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Validators.validateKM(trimmed), let km = Int(trimmed) else {
            ToastManager.shared.show("Please enter a valid kilometers (0-999,999)".localized, type: .warning)
            return
        }
        if let minKm = minimumRequiredKm, km < minKm {
            ToastManager.shared.show(
                String(format: "Mileage must be at least %d km (checkout + 1).".localized, minKm),
                type: .warning
            )
            return
        }
        
        let uid = authManager.currentUser?.uid ?? ""
        let snap = LastCheckInSnapshot(
            km: km,
            fuelEighths: fuelEighths,
            reservationNumber: linkedExit.resKodu,
            checkedInBy: uid,
            customerName: nil,
            linkedExitId: linkedExit.id
        )
        
        var updated = arac
        updated.checkInKayitlari.append(snap)
        
        isSaving = true
        showSyncOverlay = true
        syncFailed = false
        syncSucceeded = false
        syncErrorText = nil
        syncStatusMessage = "WheelSys: connecting…".localized
        
        let steps = [
            "WheelSys: connecting…".localized,
            "Sending check-in data…".localized,
            "Syncing reservation & vehicle record…".localized
        ]
        stepTask?.cancel()
        stepTask = Task { @MainActor in
            for s in steps.dropFirst() {
                try? await Task.sleep(for: .milliseconds(780))
                guard !Task.isCancelled else { return }
                syncStatusMessage = s
            }
        }
        
        let result: Result<Void, Error> = await withCheckedContinuation { cont in
            viewModel.aracGuncelleForCheckInSync(updated) { cont.resume(returning: $0) }
        }
        
        stepTask?.cancel()
        stepTask = nil
        
        switch result {
        case .success:
            syncStatusMessage = "✓ Check-in saved".localized
            syncSucceeded = true
            let resForAudit = Self.normalizedReservationLabel(for: linkedExit.resKodu)
            viewModel.activityEkle(
                .checkInKaydedildi,
                aciklama: "\(arac.plakaFormatli) - Check In \(resForAudit) · \(km) km · fuel \(snap.fuelEighths)/8",
                aracPlaka: arac.plakaFormatli
            )
            HapticManager.shared.success()
            try? await Task.sleep(for: .milliseconds(650))
            showSyncOverlay = false
            isSaving = false
            ToastManager.shared.show("✓ Check-in saved".localized, type: .success)
            dismiss()
        case .failure(let error):
            syncFailed = true
            syncErrorText = error.localizedDescription
            syncStatusMessage = ""
            HapticManager.shared.error()
            isSaving = false
        }
    }
}
