import SwiftUI

// MARK: - CH WheelSys chrome (always Palantir — independent of Settings toggle)

/// Forces Palantir ops styling on CH WheelSys flows (checkout, return, journal).
struct WheelSysCHOpsChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.palantirModeEnabled, true)
            .background(PalantirTheme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .toolbarBackground(PalantirTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(PalantirTheme.accent)
    }
}

extension View {
    func wheelSysCHOpsChrome() -> some View {
        modifier(WheelSysCHOpsChrome())
    }
}

/// Applies Palantir chrome only when CH WheelSys ops are active.
struct ConditionalWheelSysCHChrome: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.wheelSysCHOpsChrome()
        } else {
            content
        }
    }
}

// MARK: - Shared components (WHEELSYS-REPORT journal / rental fields)

struct WheelSysPalantirOpsHeader: View {
    let title: String
    var subtitle: String?
    var badge: String?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(11))
                    .foregroundStyle(PalantirTheme.accent)
                    .tracking(0.55)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(PalantirTheme.bodyFont(13))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
            Spacer(minLength: 0)
            if let badge, !badge.isEmpty {
                PalantirOpsBadge(text: badge, tone: .accent)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct WheelSysPalantirMetricTile: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = PalantirTheme.accent
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label.uppercased())
                            .font(PalantirTheme.labelFont(8))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .lineLimit(1)
                        Text(value.isEmpty ? "—" : value)
                            .font(PalantirTheme.dataFont(12))
                            .foregroundStyle(PalantirTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(label.uppercased())
                            .font(PalantirTheme.labelFont(9))
                            .foregroundStyle(PalantirTheme.textMuted)
                            .lineLimit(1)
                    }
                    Text(value.isEmpty ? "—" : value)
                        .font(PalantirTheme.dataFont(13))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .padding(11)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.background.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(PalantirTheme.border, lineWidth: 1)
        )
    }
}

struct WheelSysPalantirDataRow: View {
    let label: String
    let value: String
    var monospace: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(PalantirTheme.labelFont(9))
                .foregroundStyle(PalantirTheme.textMuted)
                .frame(width: 88, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(monospace ? PalantirTheme.dataFont(13) : PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WheelSysPalantirMetricsBar: View {
    let items: [(icon: String, label: String, value: String, tint: Color)]
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        WheelSysPalantirMetricTile(
                            icon: item.icon,
                            label: item.label,
                            value: item.value,
                            tint: item.tint,
                            compact: true
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        WheelSysPalantirMetricTile(
                            icon: item.icon,
                            label: item.label,
                            value: item.value,
                            tint: item.tint
                        )
                    }
                }
                .padding(13)
            }
        }
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

/// Large tappable circle chevrons for journal day navigation.
struct WheelSysJournalDateNavButton: View {
    let systemName: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            guard !disabled else { return }
            HapticManager.shared.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(PalantirTheme.accent)
                .frame(width: 48, height: 48)
                .background(PalantirTheme.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(PalantirTheme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// Journal-style day navigation bar (Daily View, Journal Ops).
struct WheelSysJournalDateToolbar: View {
    let formattedDay: String
    var isLoading: Bool = false
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            WheelSysJournalDateNavButton(
                systemName: "chevron.left.circle.fill",
                disabled: isLoading,
                action: onPrevious
            )

            VStack(spacing: 2) {
                Text(formattedDay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if isLoading {
                    ProgressView().scaleEffect(0.65)
                }
            }
            .frame(maxWidth: .infinity)

            WheelSysJournalDateNavButton(
                systemName: "chevron.right.circle.fill",
                disabled: isLoading,
                action: onNext
            )

            Button(action: onToday) {
                Text("ch_ops.today".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PalantirTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(PalantirTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PalantirTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(PalantirTheme.surfaceHigh)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }
}

/// Palantir journal row — left accent bar + fixed-width columns.
struct WheelSysPalantirJournalListRow: View {
    let accentColor: Color
    let backgroundColor: Color
    let resText: String
    let plateText: String
    let groupText: String
    let driverText: String
    let fuelText: String
    let timeText: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
            HStack(spacing: 8) {
                journalCell(resText, width: 60, bold: true)
                journalCell(plateText, width: 92, bold: true)
                journalCell(groupText, width: 36, bold: false)
                journalCell(driverText, width: 88, bold: false)
                journalCell(fuelText, width: 28, bold: false)
                journalCell(timeText, width: 40, bold: false)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .frame(minHeight: 38)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PalantirTheme.border).frame(height: 1)
        }
    }

    private func journalCell(_ text: String, width: CGFloat, bold: Bool) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(bold ? .caption.weight(.bold) : .caption)
            .foregroundStyle(PalantirTheme.textPrimary)
            .frame(width: width, alignment: .leading)
            .lineLimit(bold ? 1 : 2)
            .minimumScaleFactor(bold ? 0.75 : 1)
    }
}

/// Side-by-side ops panel (checkout vs return).
struct WheelSysPalantirOpsSidePanel<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PalantirTheme.background.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Metric with optional highlighted delta (km / fuel / days).
struct WheelSysPalantirDiffMetric: View {
    let label: String
    let value: String
    var diffText: String? = nil
    var highlightDiff: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(PalantirTheme.labelFont(8))
                .foregroundStyle(PalantirTheme.textMuted)
            Text(value.isEmpty ? "—" : value)
                .font(PalantirTheme.dataFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
            if let diffText, !diffText.isEmpty {
                Text(diffText)
                    .font(PalantirTheme.dataFont(12).weight(.bold))
                    .foregroundStyle(highlightDiff ? PalantirTheme.warning : PalantirTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WheelSysPalantirStatusStrip: View {
    let icon: String
    let message: String
    var tint: Color = PalantirTheme.accent
    var showsSpinner: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if showsSpinner {
                ProgressView().controlSize(.small).tint(tint)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(message)
                .font(PalantirTheme.labelFont(12))
                .foregroundStyle(PalantirTheme.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(tint.opacity(0.08))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(tint.opacity(0.35)),
            alignment: .bottom
        )
    }
}

// MARK: - Notes sidebar (return flow)

struct WheelSysPalantirNoteRow: View {
    let note: WheelSysEntityNote
    var onDelete: (() -> Void)? = nil
    var deleteDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: note.source == "vehicle" ? "car.fill" : "doc.text.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PalantirTheme.accent)
                if !note.createdBy.isEmpty {
                    Text(note.createdBy)
                        .font(PalantirTheme.labelFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                Spacer(minLength: 0)
                if !note.createdAt.isEmpty {
                    Text(note.createdAt)
                        .font(PalantirTheme.dataFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(deleteDisabled ? PalantirTheme.textMuted : PalantirTheme.critical)
                    .disabled(deleteDisabled)
                }
            }
            Text(note.text)
                .font(PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.background.opacity(0.55))
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct WheelSysPalantirNotesSidebar: View {
    let rentalNotes: [WheelSysEntityNote]
    let vehicleNotes: [WheelSysEntityNote]
    @Binding var newNoteText: String
    var isSaving: Bool = false
    var isDeleting: Bool = false
    var statusMessage: String? = nil
    var statusIsError: Bool = false
    var canAddNote: Bool = true
    var onSave: () -> Void
    var onDelete: ((WheelSysEntityNote) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    if rentalNotes.isEmpty && vehicleNotes.isEmpty {
                        WheelSysPalantirStatusStrip(
                            icon: "note.text",
                            message: "wheelsys.return.notes_empty".localized,
                            tint: PalantirTheme.textMuted
                        )
                    }
                    if !rentalNotes.isEmpty {
                        sectionHeader("wheelsys.return.rental_notes".localized, icon: "doc.text.fill")
                        ForEach(rentalNotes) { note in
                            WheelSysPalantirNoteRow(
                                note: note,
                                onDelete: onDelete.map { handler in { handler(note) } },
                                deleteDisabled: isDeleting || isSaving
                            )
                        }
                    }
                    if !vehicleNotes.isEmpty {
                        sectionHeader("wheelsys.return.vehicle_notes".localized, icon: "car.fill")
                        ForEach(vehicleNotes) { note in
                            WheelSysPalantirNoteRow(
                                note: note,
                                onDelete: onDelete.map { handler in { handler(note) } },
                                deleteDisabled: isDeleting || isSaving
                            )
                        }
                    }
                    if canAddNote {
                        WheelSysPalantirInsetDivider()
                            .padding(.vertical, 4)
                        WheelSysPalantirTextInput(
                            label: "wheelsys.return.note_placeholder".localized,
                            text: $newNoteText
                        )
                        WheelSysPalantirPrimaryButton(
                            title: "wheelsys.return.save_note".localized,
                            icon: "square.and.pencil",
                            isLoading: isSaving,
                            disabled: isSaving || isDeleting
                                || newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            onSave()
                        }
                    }
                    if let statusMessage, !statusMessage.isEmpty {
                        WheelSysPalantirStatusStrip(
                            icon: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
                            message: statusMessage,
                            tint: statusIsError ? PalantirTheme.critical : PalantirTheme.success
                        )
                    }
                }
                .padding(13)
            }
            .background(PalantirTheme.background)
            .navigationTitle("wheelsys.return.notes_header".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
        .wheelSysCHOpsChrome()
        .presentationDetents([.fraction(0.52), .large])
        .presentationDragIndicator(.visible)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PalantirTheme.accent)
            Text(title.uppercased())
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
        }
    }
}

// MARK: - Notes preview (2–3 rows + show all)

struct WheelSysPalantirNotesPreview: View {
    let notes: [WheelSysEntityNote]
    var onShowAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if notes.isEmpty {
                WheelSysPalantirStatusStrip(
                    icon: "note.text",
                    message: "wheelsys.return.notes_empty".localized,
                    tint: PalantirTheme.textMuted
                )
            } else {
                ForEach(notes) { note in
                    WheelSysPalantirNoteRow(note: note)
                }
                if let onShowAll {
                    WheelSysPalantirSecondaryButton(
                        title: "wheelsys.notes.show_all".localized,
                        icon: "list.bullet.rectangle"
                    ) {
                        onShowAll()
                    }
                }
            }
        }
    }
}

// MARK: - Ops action button (destructive press-fill animation)

struct PalantirOpsActionButton: View {
    let title: String
    let icon: String
    var style: Style = .accent
    var disabled: Bool = false
    var titleScale: TitleScale = .regular
    let action: () -> Void

    enum Style {
        case accent, warning, destructive
    }

    enum TitleScale {
        case regular, large

        var fontSize: CGFloat {
            switch self {
            case .regular: return 11
            case .large: return 13
            }
        }

        var iconFont: Font {
            switch self {
            case .regular: return .title3
            case .large: return .title2
            }
        }
    }

    @State private var armed = false

    private var destructiveIdle: Bool { style == .destructive && !armed }

    private var iconTint: Color {
        switch style {
        case .accent: return PalantirTheme.accent
        case .warning: return PalantirTheme.warning
        case .destructive: return PalantirTheme.critical
        }
    }

    private var fillTint: Color {
        switch style {
        case .accent: return PalantirTheme.accent
        case .warning: return PalantirTheme.warning
        case .destructive: return PalantirTheme.critical
        }
    }

    var body: some View {
        Button {
            guard !disabled else { return }
            HapticManager.shared.selection()
            HapticManager.shared.medium()
            withAnimation(.easeOut(duration: 0.14)) { armed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeOut(duration: 0.22)) { armed = false }
                action()
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(titleScale.iconFont)
                    .foregroundStyle(destructiveIdle ? iconTint : (armed ? PalantirTheme.onAccent : PalantirTheme.onAccent))
                Text(title)
                    .font(PalantirTheme.labelFont(titleScale.fontSize))
                    .foregroundStyle(destructiveIdle ? PalantirTheme.textPrimary : PalantirTheme.onAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, titleScale == .large ? 16 : 14)
            .background(
                disabled
                    ? PalantirTheme.border.opacity(0.35)
                    : (armed ? fillTint : (destructiveIdle ? PalantirTheme.surfaceHigh : fillTint))
            )
            .overlay(Rectangle().stroke(destructiveIdle && !armed ? PalantirTheme.border : fillTint.opacity(0.35), lineWidth: 1))
            .opacity(disabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Shared list / history row chrome

struct PalantirOpsIconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Rectangle()
                .fill(tint.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(tint)
        }
        .overlay(Rectangle().stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

struct PalantirOpsListRowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(PalantirTheme.background.opacity(0.55))
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct ConditionalPalantirRowSurface: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.modifier(PalantirOpsListRowSurface())
        } else {
            content
        }
    }
}

extension View {
    func palantirOpsListRowSurface() -> some View {
        modifier(PalantirOpsListRowSurface())
    }

    @ViewBuilder
    func fleetListPalantirChrome(enabled: Bool) -> some View {
        if enabled {
            self
                .scrollContentBackground(.hidden)
                .background(PalantirTheme.background)
        } else {
            self
        }
    }
}

// MARK: - Reports / CH office hub cards

struct PalantirCHHubStatCard: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    var tint: Color = PalantirTheme.accent
    var sparklineData: [Double] = []
    var sparklineColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            if sparklineData.count > 1 {
                SparklineChart(data: sparklineData, color: sparklineColor ?? tint)
                    .frame(height: 40)
            }
            Text(value)
                .font(PalantirTheme.heroFont(22))
                .foregroundStyle(PalantirTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(PalantirTheme.bodyFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(14)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct PalantirReportMetricTile: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = PalantirTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(PalantirTheme.heroFont(24))
                .foregroundStyle(PalantirTheme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: false))
            Text(title.uppercased())
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
                .lineLimit(2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct PalantirReportSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PalantirTheme.textMuted)
            TextField(placeholder, text: $text)
                .font(PalantirTheme.bodyFont(14))
                .textInputAutocapitalization(.characters)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct PalantirSquareToolbarIconButton: View {
    let systemName: String
    var accessibilityLabel: String? = nil

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PalantirTheme.onAccent)
            .frame(width: 32, height: 32)
            .background(PalantirTheme.accent)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

/// Full-screen dim overlay with Palantir-styled progress (assign / sync).
struct PalantirOpsBlockingOverlay: View {
    let title: String
    var microcopy: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(PalantirTheme.accent)
                    .scaleEffect(1.1)
                Text(title)
                    .font(PalantirTheme.labelFont(12))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let microcopy, !microcopy.isEmpty {
                    Text(microcopy)
                        .font(PalantirTheme.bodyFont(11))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: 300)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        }
    }
}
