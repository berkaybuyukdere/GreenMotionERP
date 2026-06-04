import SwiftUI

/// Prominent plate + reservation code row; optional navigation after operation is saved.
struct OperationIdentityLinkRow: View {
    let plate: String
    let reservationCode: String?
    let reservationLabel: String
    let vehicle: Arac
    var exit: ExitIslemi?
    var iade: IadeIslemi?
    var plateInteractive: Bool = false
    var codeInteractive: Bool = false

    @EnvironmentObject private var viewModel: AracViewModel

    private var trimmedCode: String? {
        let raw = reservationCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    var body: some View {
        HStack(spacing: 10) {
            plateControl
            if let code = trimmedCode {
                codeControl(code: code)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var plateControl: some View {
        let chip = identityChip(
            icon: "car.fill",
            title: "Plate".localized,
            value: plate,
            tint: .blue,
            interactive: plateInteractive
        )
        if plateInteractive {
            NavigationLink(destination: AracDetayView(arac: vehicle).environmentObject(viewModel)) {
                chip
            }
            .buttonStyle(.plain)
        } else {
            chip
        }
    }

    @ViewBuilder
    private func codeControl(code: String) -> some View {
        let chip = identityChip(
            icon: "number.circle.fill",
            title: reservationLabel,
            value: code,
            tint: .purple,
            interactive: codeInteractive
        )
        if codeInteractive, let exit {
            NavigationLink(destination: ExitDetayView(exit: exit).environmentObject(viewModel)) {
                chip
            }
            .buttonStyle(.plain)
        } else if codeInteractive, let iade {
            NavigationLink(destination: IadeDetayView(iade: iade).environmentObject(viewModel)) {
                chip
            }
            .buttonStyle(.plain)
        } else {
            chip
        }
    }

    private func identityChip(icon: String, title: String, value: String, tint: Color, interactive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if interactive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
