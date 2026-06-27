import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var aramaMetni = ""
    @State private var seciliActivity: Activity?
    @State private var detayGoster = false
    @State private var selectedArac: Arac?
    @State private var navigateToVehicleDetail = false
    @State private var selectedOfficeOperation: OfficeOperation?
    @State private var navigateToOfficeOperation = false

    private var isCHActivityContext: Bool {
        FranchiseCapabilityMatrix.wheelSysModuleEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        )
    }

    var filtreliActivities: [Activity] {
        let allActivities = viewModel.activities
        guard !aramaMetni.isEmpty else { return allActivities }
        let searchText = aramaMetni.lowercased()
        return allActivities.filter { activity in
            activity.aciklama.lowercased().contains(searchText) ||
            (activity.aracPlaka?.lowercased().contains(searchText) ?? false) ||
            (activity.kullaniciAdi?.lowercased().contains(searchText) ?? false) ||
            (activity.kullaniciEmail?.lowercased().contains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Aktivite Geçmişi".localized)
                .sheet(isPresented: $detayGoster) {
                    if let activity = seciliActivity {
                        ActivityDetayView(activity: activity)
                    }
                }
                .background(
                    NavigationLink(
                        destination: selectedArac.map { AracDetayView(arac: $0) },
                        isActive: $navigateToVehicleDetail,
                        label: { EmptyView() }
                    )
                )
                .background(
                    NavigationLink(
                        destination: selectedOfficeOperation.map { operation in
                            OfficeOperationDetailViewWrapper(operation: operation)
                                .environmentObject(viewModel)
                        },
                        isActive: $navigateToOfficeOperation,
                        label: { EmptyView() }
                    )
                )
        }
        .modifier(ConditionalWheelSysCHChrome(enabled: isCHActivityContext))
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.activities.isEmpty {
            emptyStateView
        } else {
            activitiesListView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.5))

            Text("Henüz Aktivite Yok".localized)
                .font(.title2)
                .fontWeight(.bold)

            Text("Araç ve hasar kayıtlarınız burada görünecek".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var activitiesListView: some View {
        List {
            ForEach(gruplananActivities.keys.sorted(by: >), id: \.self) { tarih in
                Section(tarihBasligi(tarih)) {
                    ForEach(gruplananActivities[tarih] ?? []) { activity in
                        ModernActivityRow(activity: activity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateToActivityDetail(activity)
                            }
                    }
                }
            }
        }
        .fleetListPalantirChrome(enabled: isCHActivityContext)
        .searchable(text: $aramaMetni, prompt: "Search activity...".localized)
    }

    private func navigateToActivityDetail(_ activity: Activity) {
        if activity.tip == .officeOperation, let operationId = activity.officeOperationId {
            if let operation = viewModel.officeOperations.first(where: { $0.id == operationId }) {
                selectedOfficeOperation = operation
                navigateToOfficeOperation = true
                return
            }
        }

        if let plate = activity.aracPlaka {
            if let arac = viewModel.araclar.first(where: { $0.plaka == plate || $0.plakaFormatli == plate }) {
                selectedArac = arac
                navigateToVehicleDetail = true
                return
            }
        }

        seciliActivity = activity
        detayGoster = true
    }

    var gruplananActivities: [String: [Activity]] {
        Dictionary(grouping: filtreliActivities) { activity in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: activity.tarih)
        }
    }

    func tarihBasligi(_ tarihStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let tarih = formatter.date(from: tarihStr) else { return tarihStr }

        let calendar = Calendar.current
        if calendar.isDateInToday(tarih) {
            return "Today".localized
        } else if calendar.isDateInYesterday(tarih) {
            return "Yesterday".localized
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
            formatter.locale = Locale.current
            return formatter.string(from: tarih)
        }
    }
}

// MARK: - Activity Detail View

struct ActivityDetayView: View {
    let activity: Activity
    @Environment(\.dismiss) var dismiss
    @Environment(\.palantirModeEnabled) private var palantirMode

    var body: some View {
        NavigationView {
            Group {
                if palantirMode {
                    palantirDetailContent
                } else {
                    legacyDetailContent
                }
            }
            .navigationTitle("Aktivite Detayı".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close".localized) { dismiss() }
                }
            }
        }
        .modifier(ConditionalWheelSysCHChrome(enabled: palantirMode))
    }

    // MARK: - Palantir branch

    private var palantirDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                // Event header card
                WheelSysPalantirSectionCard(title: "Activity".localized, icon: activity.tip.icon) {
                    HStack(spacing: 12) {
                        PalantirOpsIconTile(
                            systemName: activity.tip.icon,
                            tint: activity.tip.color,
                            size: 44
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.tip.englishDisplayName)
                                .font(PalantirTheme.labelFont(13))
                                .foregroundStyle(PalantirTheme.textPrimary)
                            Text(activity.tarih.formatted(date: .long, time: .shortened))
                                .font(PalantirTheme.dataFont(11))
                                .foregroundStyle(PalantirTheme.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }

                // Details data rows card
                WheelSysPalantirSectionCard(title: "Details".localized, icon: "info.circle") {
                    if let plaka = activity.aracPlaka {
                        WheelSysPalantirDataRow(label: "Vehicle".localized, value: plaka)
                    }
                    palantirUserRow
                }

                // Description card
                WheelSysPalantirSectionCard(title: "Description".localized, icon: "text.quote") {
                    Text(activity.localizedDescription)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Detailed info (optional)
                if let detay = activity.detayliAciklama, !detay.isEmpty {
                    WheelSysPalantirSectionCard(title: "Detailed Information".localized, icon: "doc.text") {
                        Text(detay)
                            .font(PalantirTheme.bodyFont(13))
                            .foregroundStyle(PalantirTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 13)
        }
        .background(PalantirTheme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var palantirUserRow: some View {
        if let name = activity.kullaniciAdi, !name.isEmpty {
            WheelSysPalantirDataRow(label: "User".localized, value: name, monospace: false)
        } else if let email = activity.kullaniciEmail, !email.isEmpty {
            WheelSysPalantirDataRow(label: "User".localized, value: email, monospace: false)
        }
    }

    // MARK: - Legacy (non-CH) branch

    private var legacyDetailContent: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: activity.tip.icon)
                        .font(.system(size: 50))
                        .foregroundColor(activity.tip.color)

                    Text(activity.tip.rawValue)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(activity.tarih.formatted(date: .long, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if let plaka = activity.aracPlaka {
                Section("Vehicle".localized) {
                    HStack {
                        Image(systemName: "number.square.fill")
                            .foregroundColor(.blue)
                        Text(plaka)
                            .font(.headline)
                    }
                }
            }

            Section("Description".localized) {
                Text(activity.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let kullaniciAdi = activity.kullaniciAdi, !kullaniciAdi.isEmpty {
                Section("User".localized) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text(kullaniciAdi)
                            .font(.body)
                    }
                }
            } else if let kullaniciEmail = activity.kullaniciEmail, !kullaniciEmail.isEmpty {
                Section("User".localized) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        Text(kullaniciEmail)
                            .font(.body)
                    }
                }
            }

            if let detay = activity.detayliAciklama, !detay.isEmpty {
                Section("Detailed Information".localized) {
                    Text(detay)
                        .font(.body)
                }
            }
        }
    }
}
