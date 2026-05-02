import SwiftUI

struct VehicleTrackCrossRow: Identifiable, Hashable {
    let id: String
    let plateDisplay: String
    let modelLine: String?
    let fromDisplay: String
    let toDisplay: String
    let kindLabel: String
    let departSummary: String?
}

/// Türkiye: şube bazlı filo özeti ve pick-up / drop-off ile çapraz şube hareketleri.
struct VehicleTrackReportView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    let selectedMonth: Date
    /// When set (e.g. Reports `fullScreenCover`), **Done** clears the presenter; plain `dismiss()` can fail with nested `NavigationView`.
    var onClose: (() -> Void)? = nil

    @State private var arrowPulse = false

    private var sessionKey: String { TurkiyeGarajSubeleri.sessionBranchStorageKey() }

    private var monthRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selectedMonth)
        let start = cal.date(from: comps) ?? selectedMonth
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    private var atMyBranch: [Arac] {
        viewModel.araclar
            .filter { !$0.isDeleted }
            .filter { Self.branchKeysMatch($0.garageBranchId, sessionKey) }
            .sorted { $0.plakaFormatli < $1.plakaFormatli }
    }

    private var otherBranchHere: [Arac] {
        viewModel.araclar
            .filter { !$0.isDeleted }
            .filter { !Self.branchKeysMatch($0.garageBranchId, sessionKey) }
            .sorted { $0.plakaFormatli < $1.plakaFormatli }
    }

    private var crossRows: [VehicleTrackCrossRow] {
        Self.buildCrossRows(
            viewModel: viewModel,
            sessionKey: sessionKey,
            range: monthRange
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session branch".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(TurkiyeGarajSubeleri.displayTitle(forStoredKey: sessionKey))
                        .font(.headline)
                }
                .padding(.vertical, 4)
            }

            Section {
                metricTile(title: "Vehicles at this branch".localized, value: "\(atMyBranch.count)", systemImage: "building.2.fill", tint: .blue)
                metricTile(title: "Other-branch home, on fleet list".localized, value: "\(otherBranchHere.count)", systemImage: "car.2.fill", tint: .orange)
                metricTile(title: "Cross-branch trips (month)".localized, value: "\(crossRows.count)", systemImage: "arrow.left.arrow.right", tint: .teal)
            } header: {
                Text("Summary".localized)
            }

            if !atMyBranch.isEmpty {
                Section("Garaged at this branch".localized) {
                    ForEach(atMyBranch) { arac in
                        vehicleRow(arac)
                    }
                }
            }

            if !otherBranchHere.isEmpty {
                Section("Registered to another branch".localized) {
                    ForEach(otherBranchHere) { arac in
                        vehicleRow(arac)
                    }
                }
            }

            if !crossRows.isEmpty {
                Section("Pick-up → drop-off (this month)".localized) {
                    ForEach(crossRows) { row in
                        crossBranchRowView(row)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Vehicle Track".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done".localized) {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                arrowPulse = true
            }
        }
    }

    private func metricTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func vehicleRow(_ arac: Arac) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(arac.plakaFormatli)
                    .font(.headline)
                Text("\(arac.marka) \(arac.model)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(TurkiyeGarajSubeleri.displayTitle(forStoredKey: arac.garageBranchId))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func crossBranchRowView(_ row: VehicleTrackCrossRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.plateDisplay)
                    .font(.headline)
                Spacer()
                Text(row.kindLabel)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            if let model = row.modelLine, !model.isEmpty {
                Text(model)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Text(row.fromDisplay)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                animatedArrow
                Text(row.toDisplay)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            if let depart = row.departSummary {
                Text(depart)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var animatedArrow: some View {
        Image(systemName: "arrow.right.circle.fill")
            .font(.title3)
            .foregroundStyle(.teal)
            .offset(x: arrowPulse ? 4 : -2)
            .accessibilityLabel("Direction".localized)
    }

    // MARK: - Badge + row builder

    static func dashboardBadgeCount(
        viewModel: AracViewModel,
        authManager: AuthenticationManager,
        range: (start: Date, end: Date)
    ) -> Int {
        guard FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: authManager.userProfile
        ) else { return 0 }
        let session = TurkiyeGarajSubeleri.sessionBranchStorageKey()
        let at = viewModel.araclar.filter { !$0.isDeleted && branchKeysMatch($0.garageBranchId, session) }.count
        let cross = buildCrossRows(viewModel: viewModel, sessionKey: session, range: range).count
        return at + cross
    }

    private static func buildCrossRows(
        viewModel: AracViewModel,
        sessionKey: String,
        range: (start: Date, end: Date)
    ) -> [VehicleTrackCrossRow] {
        var rows: [VehicleTrackCrossRow] = []
        let exits = viewModel.exitIslemleri.filter { !$0.isDeleted }
        let iades = viewModel.iadeIslemleri.filter { !$0.isDeleted }

        for ex in exits where ex.createdAt >= range.start && ex.createdAt < range.end {
            guard let pu = ex.pickUpBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty,
                  let du = ex.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !du.isEmpty,
                  !branchLabelsLooselyEqual(pu, du) else { continue }
            guard branchMentionsSession(pickup: pu, dropoff: du, sessionKey: sessionKey) else { continue }
            let model = viewModel.markaModelLine(forVehicleId: ex.aracId, fallbackPlate: ex.aracPlaka)
            rows.append(
                VehicleTrackCrossRow(
                    id: "ex-\(ex.id.uuidString)",
                    plateDisplay: ex.aracPlaka,
                    modelLine: model,
                    fromDisplay: pu,
                    toDisplay: du,
                    kindLabel: "Check-out".localized,
                    departSummary: departSummary(exitDate: ex.exitTarihi, plannedReturn: ex.plannedReturnAt)
                )
            )
        }

        for ia in iades where ia.iadeTarihi >= range.start && ia.iadeTarihi < range.end {
            guard let pu = ia.pickUpBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !pu.isEmpty,
                  let du = ia.dropOffBranch?.trimmingCharacters(in: .whitespacesAndNewlines), !du.isEmpty,
                  !branchLabelsLooselyEqual(pu, du) else { continue }
            guard branchMentionsSession(pickup: pu, dropoff: du, sessionKey: sessionKey) else { continue }
            let model = viewModel.markaModelLine(forVehicleId: ia.aracId, fallbackPlate: ia.aracPlaka)
            rows.append(
                VehicleTrackCrossRow(
                    id: "ia-\(ia.id.uuidString)",
                    plateDisplay: ia.aracPlaka,
                    modelLine: model,
                    fromDisplay: pu,
                    toDisplay: du,
                    kindLabel: "Return".localized,
                    departSummary: "\("Return date:".localized) \(Self.formatted(ia.iadeTarihi))"
                )
            )
        }

        return rows.sorted { $0.plateDisplay < $1.plateDisplay }
    }

    private static func departSummary(exitDate: Date, plannedReturn: Date?) -> String? {
        let d1 = "\("Depart:".localized) \(formatted(exitDate))"
        if let pr = plannedReturn {
            return d1 + " · " + "\("Planned return:".localized) \(formatted(pr))"
        }
        return d1
    }

    private static func formatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private static func branchKeysMatch(_ a: String?, _ b: String?) -> Bool {
        TurkiyeGarajSubeleri.equivalentGarageBranchKeys(a, b)
    }

    private static func branchLabelsLooselyEqual(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func branchMentionsSession(pickup: String, dropoff: String, sessionKey: String) -> Bool {
        let sessionTitle = TurkiyeGarajSubeleri.displayTitle(forStoredKey: sessionKey)
        let tokens = [sessionKey, sessionTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let pu = pickup.lowercased()
        let du = dropoff.lowercased()
        for t in tokens {
            if pu.contains(t) || du.contains(t) { return true }
        }
        return false
    }
}

extension AracViewModel {
    func markaModelLine(forVehicleId id: UUID, fallbackPlate: String) -> String? {
        if let a = araclar.first(where: { $0.id == id }) {
            let m = "\(a.marka) \(a.model)".trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? nil : m
        }
        return nil
    }
}
