import SwiftUI
import FirebaseAuth

/// Set NTR received / needs service + note for one vehicle.
struct VehicleServiceStatusSheet: View {
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var flagStore = VehicleServiceFlagStore.shared

    let arac: Arac

    @State private var kind: VehicleServiceFlagKind = .needsService
    @State private var note = ""
    @State private var isSaving = false

    private var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }

    private var existing: VehicleServiceFlag? {
        flagStore.flag(forVehicleId: guncelArac.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("vehicle_service_flag.status_section".localized) {
                    Picker("vehicle_service_flag.status".localized, selection: $kind) {
                        ForEach(VehicleServiceFlagKind.allCases) { option in
                            Label(option.localizedTitle, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Notes".localized) {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }

                if let existing {
                    Section {
                        LabeledContent("vehicle_service_flag.updated_by".localized) {
                            Text(existing.updatedByName)
                        }
                        LabeledContent("vehicle_service_flag.updated_at".localized) {
                            Text(existing.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            HStack {
                                ProgressView()
                                Text("Saving…".localized)
                            }
                        } else {
                            Text("Save".localized)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)

                    if existing != nil {
                        Button("vehicle_service_flag.clear".localized, role: .destructive) {
                            Task { await clearStatus() }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle("vehicle_service_flag.sheet_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
            }
            .onAppear {
                if let existing {
                    kind = existing.kind
                    note = existing.note
                }
            }
        }
    }

    private func save() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let name = authManager.userProfile?.displayName else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await flagStore.save(
                vehicleId: guncelArac.id,
                plate: guncelArac.plakaFormatli,
                kind: kind,
                note: note,
                userId: uid,
                userName: name
            )
            HapticManager.shared.light()
            dismiss()
        } catch {
            HapticManager.shared.error()
        }
    }

    private func clearStatus() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await flagStore.clear(vehicleId: guncelArac.id)
            HapticManager.shared.light()
            dismiss()
        } catch {
            HapticManager.shared.error()
        }
    }
}

struct VehicleServiceFlagBanner: View {
    let flag: VehicleServiceFlag
    var emphasize: Bool = false
    var onManage: (() -> Void)?

    var body: some View {
        Group {
            if let onManage {
                Button(action: onManage) { bannerContent }
                    .buttonStyle(.plain)
            } else {
                bannerContent
            }
        }
        .padding(.horizontal, 4)
    }

    private var bannerContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: flag.kind.icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(flag.kind.localizedTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(flag.plate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                if !flag.note.isEmpty {
                    Text(flag.note)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                Text(String(format: "vehicle_service_flag.updated_by_format".localized, flag.updatedByName))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 0)
            if onManage != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(flag.kind == .needsService ? Color.red : Color.orange)
        )
        .overlay {
            if emphasize {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
            }
        }
    }
}

struct VehicleServiceFlagsPinnedSection: View {
    @ObservedObject var flagStore: VehicleServiceFlagStore
    @EnvironmentObject private var viewModel: AracViewModel
    var onSelectVehicle: (Arac) -> Void

    var body: some View {
        let items = flagStore.activeFlags()
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                    Text("vehicle_service_flag.pinned_title".localized)
                        .font(.headline)
                    Spacer()
                    Text("\(items.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)

                ForEach(items) { flag in
                    if let arac = viewModel.vehicle(matchingServiceFlag: flag) {
                        Button {
                            onSelectVehicle(arac)
                        } label: {
                            VehicleServiceFlagBanner(flag: flag)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                    } else {
                        VehicleServiceFlagBanner(flag: flag)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}
