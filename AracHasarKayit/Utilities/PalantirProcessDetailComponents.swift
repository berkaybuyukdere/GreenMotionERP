import SwiftUI

// MARK: - CH process detail (Hasar / Iade / Exit read-only screens)

enum PalantirProcessDetailSupport {
    static func isEnabled(userProfile: UserProfile?) -> Bool {
        FranchiseCapabilityMatrix.wheelSysFleetOpsEnabledForSession(
            serviceFranchiseId: FirebaseService.shared.currentFranchiseId,
            userProfile: userProfile
        )
    }
}

struct PalantirProcessDetailHero: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = PalantirTheme.accent
    let badge: String
    var badgeTone: PalantirOpsBadge.Tone = .accent

    var body: some View {
        HStack(spacing: 12) {
            PalantirOpsIconTile(systemName: icon, tint: tint, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PalantirTheme.dataFont(17))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            Spacer(minLength: 0)
            PalantirOpsBadge(text: badge, tone: badgeTone)
        }
        .padding(13)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct PalantirProcessDetailInfoSection: View {
    let title: String
    var icon: String = "info.circle"
    let rows: [(label: String, value: String)]

    var body: some View {
        WheelSysPalantirSectionCard(title: title, icon: icon) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { WheelSysPalantirInsetDivider() }
                    WheelSysPalantirDataRow(label: row.label, value: row.value)
                        .padding(.vertical, 8)
                }
            }
        }
    }
}

extension View {
    func palantirProcessDetailChrome(enabled: Bool) -> some View {
        modifier(ConditionalWheelSysCHChrome(enabled: enabled))
    }

    @ViewBuilder
    func processDetailScreenBackground(_ palantir: Bool) -> some View {
        if palantir {
            background(PalantirTheme.background.ignoresSafeArea())
        } else {
            background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }
}
