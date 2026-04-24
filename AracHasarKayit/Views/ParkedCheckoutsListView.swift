import SwiftUI

/// Parked checkouts (`ExitStatus.parked`) — Dashboard kartı ve Vehicles sheet’i için.
struct ParkedCheckoutsListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var parkedSearchText = ""
    @State private var expandedParkedCategories: Set<String> = []

    private var isSwitzerlandContext: Bool {
        let serviceId = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if serviceId.hasPrefix("CH") { return true }
        if let profile = authManager.userProfile {
            let pid = profile.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if pid.hasPrefix("CH") { return true }
            let cc = profile.countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return cc == "CH"
        }
        return false
    }

    private var parkedExits: [ExitIslemi] {
        guard isSwitzerlandContext else { return [] }
        return viewModel.exitIslemleri
            .filter { $0.status == .parked }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var parkedExitsByCategory: [(category: String, exits: [ExitIslemi])] {
        let grouped = Dictionary(grouping: parkedExits) { parkedExit in
            let category = viewModel.araclar.first(where: { $0.id == parkedExit.aracId })?.kategori
            let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Uncategorized".localized : trimmed
        }
        return grouped
            .map { key, exits in
                (category: key, exits: exits.sorted(by: { $0.createdAt > $1.createdAt }))
            }
            .sorted { lhs, rhs in
                if lhs.category == rhs.category { return lhs.exits.count > rhs.exits.count }
                return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
            }
    }

    private var filteredParkedExitsByCategory: [(category: String, exits: [ExitIslemi])] {
        let q = parkedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return parkedExitsByCategory }
        return parkedExitsByCategory.compactMap { group in
            let filtered = group.exits.filter { exit in
                exit.aracPlaka.lowercased().contains(q) ||
                    group.category.lowercased().contains(q)
            }
            guard !filtered.isEmpty else { return nil }
            return (category: group.category, exits: filtered)
        }
    }

    var body: some View {
        Group {
            if !isSwitzerlandContext {
                ContentUnavailableView("Parked Vehicles".localized, systemImage: "car.circle")
            } else if parkedExits.isEmpty {
                ContentUnavailableView("Parked Vehicles".localized, systemImage: "car.circle")
            } else {
                List {
                    ForEach(filteredParkedExitsByCategory, id: \.category) { group in
                        let isExpanded = expandedParkedCategories.contains(group.category)
                        Section {
                            Button {
                                if isExpanded {
                                    expandedParkedCategories.remove(group.category)
                                } else {
                                    expandedParkedCategories.insert(group.category)
                                }
                            } label: {
                                HStack {
                                    Text("\(group.category) (\(group.exits.count))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if isExpanded {
                                ForEach(group.exits) { parkedExit in
                                    NavigationLink(destination: ExitDetayView(exit: parkedExit).environmentObject(viewModel)) {
                                        HStack(spacing: 10) {
                                            Circle()
                                                .fill(Color.purple.opacity(0.18))
                                                .frame(width: 28, height: 28)
                                                .overlay(
                                                    Image(systemName: "car.fill")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundColor(.purple)
                                                )
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(parkedExit.aracPlaka)
                                                    .font(.subheadline.weight(.semibold))
                                                Text(parkedExit.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text("Parked".localized)
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(.purple)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.purple.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Parked Vehicles".localized)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $parkedSearchText, prompt: "Search by plate or category".localized)
        .onAppear {
            expandedParkedCategories = Set(parkedExitsByCategory.map(\.category))
        }
    }
}
