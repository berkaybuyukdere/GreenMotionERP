import SwiftUI

/// Top-of-form vehicle strip (plate + model) using the shared glass surface.
struct GlassVehicleInfoCard: View {
    let plate: String
    let subtitle: String
    var statusLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "car.side.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plate)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                    if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let statusLine, !statusLine.isEmpty {
                Text(statusLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChromeSurface(cornerRadius: 14)
    }
}

/// Horizontal capture actions with a shared glass bar (damage / camera flows).
struct GlassDamageActionBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassChromeSurface(cornerRadius: 14)
    }
}
