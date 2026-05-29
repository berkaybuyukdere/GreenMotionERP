import SwiftUI

// MARK: - Palantir-style Jarvis launcher (no auto LLM on panel open)

struct CHPanelJarvisLauncherCard: View {
    let jarvisEnabled: Bool
    let onOpenJarvis: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PalantirTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("JARVIS")
                        .font(PalantirTheme.labelFont(12))
                        .foregroundStyle(PalantirTheme.accent)
                        .tracking(1.2)
                    Text("jarvis.launcher.subtitle".localized)
                        .font(PalantirTheme.bodyFont(12))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer()
            }
            Text("jarvis.launcher.body".localized)
                .font(PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpenJarvis) {
                HStack {
                    Text("jarvis.launcher.open".localized)
                        .font(PalantirTheme.heroFont(14))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(PalantirTheme.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PalantirTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .disabled(!jarvisEnabled)
            .opacity(jarvisEnabled ? 1 : 0.45)
        }
        .palantirCard()
    }
}

// MARK: - Stripe-style audit row

struct CHPanelAuditStripeRow: View {
    let row: CHPanelAuditRow

    private var initials: String {
        let parts = row.userName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(row.userName.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        let hash = row.userName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hues: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .mint]
        return hues[abs(hash) % hues.count]
    }

    private var actionStyle: (icon: String, color: Color, label: String) {
        switch row.action.uppercased() {
        case "CREATED": return ("plus.circle.fill", .green, "Created")
        case "UPDATED": return ("pencil.circle.fill", .blue, "Updated")
        case "DELETED": return ("trash.circle.fill", .red, "Deleted")
        case "ACCESSED": return ("eye.circle.fill", .gray, "Accessed")
        default: return ("doc.circle.fill", .secondary, row.action)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [avatarColor.opacity(0.85), avatarColor.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Text(initials)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.userName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(row.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: actionStyle.icon)
                        .font(.caption)
                        .foregroundStyle(actionStyle.color)
                    Text(actionStyle.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(actionStyle.color)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(row.tableName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(row.recordId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Interactive chart detail sheet

struct CHPanelBucketDetailSheet: View {
    let bucket: CHPanelTimeBucket
    let period: CHPanelPeriod
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("ch_panel.bucket_period".localized) {
                    LabeledContent("Period", value: bucket.label)
                }
                Section("ch_panel.kpi_damages".localized) {
                    LabeledContent("Count", value: "\(bucket.damageCount)")
                    LabeledContent("Photos", value: "\(bucket.damagePhotos)")
                }
                Section("ch_panel.kpi_revenue".localized) {
                    LabeledContent("Total", value: AppCurrency.amountWithCode(bucket.officeRevenue))
                    LabeledContent("Transactions", value: "\(bucket.officeTransactionCount)")
                }
            }
            .navigationTitle("ch_panel.bucket_detail".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close".localized) { dismiss() }
                }
            }
        }
    }
}
