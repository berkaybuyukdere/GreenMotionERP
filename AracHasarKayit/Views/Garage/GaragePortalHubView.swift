import SwiftUI

struct GaragePortalHubView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var viewModel: AracViewModel

    @State private var showDamageReports = false
    @State private var showCalculations = false

    private var isCHGarage: Bool {
        FranchiseCapabilityMatrix.garageSemesPortalEnabled(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile,
            fallbackCountryCode: authManager.userProfile?.countryCode ?? "CH"
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PalantirTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        portalGrid
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("garage_portal.nav_title".localized)
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showDamageReports) {
                GarageScopedDamageReportsView()
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
            .navigationDestination(isPresented: $showCalculations) {
                SemesInvoicesView()
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("garage_portal.subtitle".localized)
                .font(PalantirTheme.bodyFont(14))
                .foregroundStyle(PalantirTheme.textMuted)
            if let name = authManager.userProfile?.displayName, !name.isEmpty {
                Text(name)
                    .font(PalantirTheme.heroFont(18))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .palantirCard()
    }

    private var portalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            portalCard(
                title: "Damage Reports".localized,
                subtitle: "garage_portal.damage.subtitle".localized,
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                action: { showDamageReports = true }
            )
            if isCHGarage {
                portalCard(
                    title: "announcements.calculations".localized,
                    subtitle: "garage_portal.calculations.subtitle".localized,
                    icon: "doc.text.fill",
                    tint: PalantirTheme.accent,
                    action: { showCalculations = true }
                )
            }
        }
    }

    private func portalCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticManager.shared.medium()
            action()
        }) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
            .padding(16)
            .background(PalantirTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GarageScopedDamageReportsView: View {
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchQuery = ""
    @State private var dateFilterPreset: ReportDateFilterPreset = .all
    @State private var filterMonth = reportMonthStart(Date())
    @State private var showMonthPicker = false

    private var garageVehicleIds: Set<UUID> {
        guard let gid = authManager.userProfile?.linkedGarageId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !gid.isEmpty else { return [] }
        let gLower = gid.lowercased()
        return Set(viewModel.garageServiceJobs.filter { $0.targetGarageId.lowercased() == gLower }.map(\.vehicleId))
    }

    private var scopedDamages: [(arac: Arac, hasar: HasarKaydi)] {
        var rows: [(Arac, HasarKaydi)] = []
        for arac in viewModel.araclar where garageVehicleIds.contains(arac.id) {
            for hasar in arac.hasarKayitlari {
                let matchesSearch = searchQuery.isEmpty
                    || arac.plaka.localizedCaseInsensitiveContains(searchQuery)
                    || hasar.resKodu.localizedCaseInsensitiveContains(searchQuery)
                let matchesDate = reportDateMatchesFilter(
                    hasar.tarih,
                    preset: dateFilterPreset,
                    filterMonth: filterMonth
                )
                if matchesSearch && matchesDate { rows.append((arac, hasar)) }
            }
        }
        return rows.sorted { $0.1.tarih > $1.1.tarih }
    }

    private var stats: (total: Int, completed: Int, inProgress: Int) {
        let damages = scopedDamages.map(\.1)
        return (
            damages.count,
            damages.filter { $0.durum == .done }.count,
            damages.filter { $0.durum == .inProgress }.count
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !scopedDamages.isEmpty { metricsSection }
                searchFilterSection

                if scopedDamages.isEmpty {
                    ContentUnavailableView(
                        "No records found".localized,
                        systemImage: "exclamationmark.triangle",
                        description: Text("Try another month or search term.".localized)
                    )
                    .padding(.top, 32)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(scopedDamages, id: \.1.id) { pair in
                            NavigationLink {
                                HasarDetayView(hasar: pair.1, aracId: pair.0.id, aracPlaka: pair.0.plakaFormatli)
                            } label: {
                                garageDamageRow(arac: pair.0, hasar: pair.1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(PalantirTheme.background)
        .navigationTitle("Damage Reports".localized)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showMonthPicker) {
            ReportMonthPickerSheet(filterMonth: $filterMonth)
        }
    }

    private var metricsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            PalantirMetricTile(title: "Total".localized, value: "\(stats.total)", icon: "number", tint: .orange)
            PalantirMetricTile(title: "Completed".localized, value: "\(stats.completed)", icon: "checkmark.seal.fill", tint: PalantirTheme.success)
            PalantirMetricTile(title: "In Progress".localized, value: "\(stats.inProgress)", icon: "clock.fill", tint: PalantirTheme.warning)
        }
    }

    private var searchFilterSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PalantirTheme.textMuted)
                TextField("Search by plate or RES code".localized, text: $searchQuery)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(PalantirTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(PalantirTheme.border, lineWidth: 1))

            ReportDateFilterControls(
                preset: $dateFilterPreset,
                filterMonth: $filterMonth,
                showMonthPicker: $showMonthPicker
            )
        }
    }

    private func garageDamageRow(arac: Arac, hasar: HasarKaydi) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(hasar.resKodu)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(arac.plakaFormatli)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                Text(hasar.tarih.formatted(date: .abbreviated, time: .shortened))
                    .font(PalantirTheme.dataFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .padding(14)
        .background(PalantirTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PalantirTheme.border, lineWidth: 1))
    }
}
