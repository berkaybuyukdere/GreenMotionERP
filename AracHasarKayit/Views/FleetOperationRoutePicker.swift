import SwiftUI

/// Equal-width route chips for Operations intake (Traffic / Inkasso / Banking).
struct FleetOperationRoutePicker: View {
    @Binding var selection: FleetOperationRoute?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FleetOperationRoute.allCases) { route in
                routeChip(route)
            }
        }
    }

    private func routeChip(_ route: FleetOperationRoute) -> some View {
        let isSelected = selection == route
        return Button {
            selection = route
            HapticManager.shared.selection()
        } label: {
            Text(route.localizedTitle)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? routeFill(route) : Color(.tertiarySystemFill))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func routeFill(_ route: FleetOperationRoute) -> Color {
        switch route {
        case .trafficAccident: return .orange
        case .inkasso: return .red
        case .bankingTransaction: return .indigo
        }
    }
}
