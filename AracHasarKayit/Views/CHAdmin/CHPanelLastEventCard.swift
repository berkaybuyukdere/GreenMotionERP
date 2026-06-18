import SwiftUI

/// Latest operational event (fixed height companion to audit column).
struct CHPanelLastEventCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let event: LiveActivityEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("live_tracking.last_event_title".localized.uppercased())
                .font(PalantirTheme.labelFont(11))
                .foregroundStyle(PalantirTheme.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let event {
                lastEventBody(event)
            } else {
                Text("live_tracking.last_event_empty".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .palantirCard()
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func lastEventBody(_ event: LiveActivityEvent) -> some View {
        let accent = accentColor(for: event.kind.accentToken)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: event.kind.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.userName)
                        .font(PalantirTheme.heroFont(14))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .lineLimit(2)
                    if !event.userRole.isEmpty {
                        Text(event.userRole.uppercased())
                            .font(PalantirTheme.dataFont(8))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Text(event.relativeTime)
                    .font(PalantirTheme.dataFont(10))
                    .foregroundStyle(PalantirTheme.accent)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(event.localizedTitle)
                .font(PalantirTheme.heroFont(15))
                .foregroundStyle(PalantirTheme.textPrimary)
                .lineLimit(horizontalSizeClass == .compact ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !event.subtitle.isEmpty {
                Text(event.localizedSubtitle)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if let plate = event.plate, !plate.isEmpty {
                    Label(plate, systemImage: "car.fill")
                        .font(PalantirTheme.dataFont(10))
                        .foregroundStyle(PalantirTheme.textPrimary)
                }
                Text(event.exactTime)
                    .font(PalantirTheme.dataFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func accentColor(for token: String) -> Color {
        switch token {
        case "success": return PalantirTheme.success
        case "warning": return PalantirTheme.warning
        case "critical": return PalantirTheme.critical
        case "accent": return PalantirTheme.accent
        default: return PalantirTheme.textMuted
        }
    }
}
