import SwiftUI

/// Equal-width payment method chips; fixed size — selection changes fill color only.
struct FleetPaymentMethodPicker: View {
    @Binding var selection: FleetPaymentCategory
    var options: [FleetPaymentCategory] = [.debtCollection, .bankingTransaction, .officePayment]
    var buttonHeight: CGFloat = 52

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                chip(option)
            }
        }
    }

    private func chip(_ option: FleetPaymentCategory) -> some View {
        let isSelected = selection == option
        return Button {
            selection = option
            HapticManager.shared.selection()
        } label: {
            Text(option.localizedTitle)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.purple : Color(.tertiarySystemFill))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
