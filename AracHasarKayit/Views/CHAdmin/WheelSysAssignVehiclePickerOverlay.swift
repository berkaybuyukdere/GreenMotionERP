import SwiftUI

/// Centered compact vehicle picker — search by plate or model; same-category matches rank first.
struct WheelSysAssignVehiclePickerOverlay: View {
    let title: String
    let categoryCode: String
    let vehicles: [WheelSysAssignableVehicle]
    var isLoading: Bool = false
    var onSelect: (WheelSysAssignableVehicle) -> Void
    var onDismiss: () -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @FocusState private var searchFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?

    private var rankedVehicles: [WheelSysAssignableVehicle] {
        let categoryNorm = WheelSysCategoryNormalizer.normalize(categoryCode)
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var list = vehicles
        if !query.isEmpty {
            list = vehicles.filter { vehicle in
                let plate = vehicle.plateNo.lowercased()
                let model = vehicle.modelName.lowercased()
                let group = vehicle.carGroup.lowercased()
                return plate.contains(query) || model.contains(query) || group.contains(query)
            }
        }

        return list.sorted { lhs, rhs in
            let lCat = lhs.matchesCategory(categoryNorm)
            let rCat = rhs.matchesCategory(categoryNorm)
            if lCat != rCat { return lCat }
            if lhs.readyToGo != rhs.readyToGo { return lhs.readyToGo }
            return lhs.plateNo.localizedCaseInsensitiveCompare(rhs.plateNo) == .orderedAscending
        }
    }

    private var sameCategoryCount: Int {
        let categoryNorm = WheelSysCategoryNormalizer.normalize(categoryCode)
        guard !categoryNorm.isEmpty else { return 0 }
        return rankedVehicles.filter { $0.matchesCategory(categoryNorm) }.count
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                pickerHeader
                searchField
                if !categoryCode.isEmpty {
                    categoryHintBar
                }
                vehicleList
            }
            .frame(maxWidth: 380)
            .frame(maxHeight: min(UIScreen.main.bounds.height * 0.72, 520))
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            .padding(.horizontal, 20)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                searchFocused = true
            }
        }
    }

    private var pickerHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .tracking(0.5)
                Text("wheelsys_assign.picker_subtitle".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .frame(width: 30, height: 30)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(PalantirTheme.surfaceHigh)
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundStyle(PalantirTheme.accent),
            alignment: .top
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PalantirTheme.textMuted)
            TextField("wheelsys_assign.picker_search".localized, text: $searchText)
                .font(PalantirTheme.dataFont(14))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .onChange(of: searchText) { _, newValue in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard !Task.isCancelled else { return }
                        debouncedSearchText = newValue
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PalantirTheme.background)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var categoryHintBar: some View {
        HStack(spacing: 6) {
            PalantirOpsBadge(text: categoryCode, tone: .accent)
            Text(String(
                format: "wheelsys_assign.picker_category_hint".localized,
                sameCategoryCount,
                rankedVehicles.count
            ))
            .font(PalantirTheme.labelFont(10))
            .foregroundStyle(PalantirTheme.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var vehicleList: some View {
        if isLoading && vehicles.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("wheelsys_assign.loading_page".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else if rankedVehicles.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "car.slash")
                    .font(.title2)
                    .foregroundStyle(PalantirTheme.textMuted)
                Text(searchText.isEmpty
                     ? "wheelsys_assign.empty".localized
                     : "wheelsys_assign.picker_no_match".localized)
                    .font(.caption)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rankedVehicles) { vehicle in
                        vehicleRow(vehicle)
                        Rectangle()
                            .fill(PalantirTheme.border)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private func vehicleRow(_ vehicle: WheelSysAssignableVehicle) -> some View {
        let categoryNorm = WheelSysCategoryNormalizer.normalize(categoryCode)
        let matches = !categoryNorm.isEmpty && vehicle.matchesCategory(categoryNorm)

        return Button {
            HapticManager.shared.selection()
            HapticManager.shared.medium()
            onSelect(vehicle)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vehicle.plateNo)
                            .font(PalantirTheme.heroFont(14).monospaced())
                            .foregroundStyle(PalantirTheme.textPrimary)
                        if matches {
                            Text(categoryCode)
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(PalantirTheme.accent.opacity(0.15))
                                .foregroundStyle(PalantirTheme.accent)
                        }
                        if vehicle.readyToGo {
                            Text("wheelsys_assign.ready_to_go".localized)
                                .font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(PalantirTheme.success.opacity(0.14))
                                .foregroundStyle(PalantirTheme.success)
                        }
                    }
                    HStack(spacing: 8) {
                        if !vehicle.modelName.isEmpty {
                            Text(vehicle.modelName)
                                .font(PalantirTheme.bodyFont(11))
                                .foregroundStyle(PalantirTheme.textMuted)
                                .lineLimit(1)
                        }
                        Text("\(vehicle.mileage) km · \(vehicle.fuel)/8")
                            .font(PalantirTheme.dataFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(matches ? PalantirTheme.accent.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
