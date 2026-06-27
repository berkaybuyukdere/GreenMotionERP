import SwiftUI

struct VehicleFleetOpsFilterBar: View {
    @Binding var selected: VehicleFleetOpsFilter
    var counts: [VehicleFleetOpsFilter: Int] = [:]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VehicleFleetOpsFilter.allCases) { filter in
                filterChip(filter)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            PalantirTheme.surface
                .ignoresSafeArea(edges: .horizontal)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PalantirTheme.border)
                .frame(height: 1)
        }
    }

    private func filterChip(_ filter: VehicleFleetOpsFilter) -> some View {
        let isSelected = selected == filter
        let accent = filter.selectedAccentColor
        let count = counts[filter]
        return Button {
            guard selected != filter else { return }
            HapticManager.shared.selection()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selected = filter
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: filter.iconName)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12, height: 12)
                    Text(filter.titleKey.localized)
                        .font(PalantirTheme.labelFont(10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let count {
                    Text("\(count)")
                        .font(PalantirTheme.dataFont(9))
                        .monospacedDigit()
                        .frame(minWidth: 22)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                isSelected ? accent.opacity(0.22) : PalantirTheme.surfaceHigh
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(isSelected ? accent : PalantirTheme.textMuted)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isSelected {
                        accent.opacity(0.12)
                    } else {
                        PalantirTheme.surface
                    }
                }
            )
            .overlay(
                Rectangle()
                    .strokeBorder(isSelected ? accent.opacity(0.55) : PalantirTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension VehicleFleetOpsFilter {
    var selectedAccentColor: Color {
        switch self {
        case .all: return PalantirTheme.accent
        case .ntr: return Color.orange
        case .available: return PalantirTheme.success
        case .rental: return Color(red: 0.427, green: 0.365, blue: 0.988)
        case .parking: return Color.pink
        }
    }
}
