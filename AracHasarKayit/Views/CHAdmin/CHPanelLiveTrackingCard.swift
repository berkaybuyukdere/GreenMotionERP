import SwiftUI

/// Palantir-style live operations feed for CH admin panel.
struct CHPanelLiveTrackingCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var feed = LiveActivityFeedService.shared

    @State private var searchText = ""
    @State private var currentPage = 0
    @State private var showPresenceRoster = false

    private let pageSize = 6
    private let feedVisibleRows: CGFloat = 6

    private var feedRowHeight: CGFloat {
        horizontalSizeClass == .compact ? 52 : 44
    }

    private var filteredEvents: [LiveActivityEvent] {
        feed.filteredEvents(matching: searchText)
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(filteredEvents.count) / Double(pageSize))))
    }

    private var safePage: Int {
        min(max(0, currentPage), max(0, pageCount - 1))
    }

    private var pageEvents: [LiveActivityEvent] {
        let start = safePage * pageSize
        guard start < filteredEvents.count else { return [] }
        return Array(filteredEvents[start..<min(start + pageSize, filteredEvents.count)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            presenceStrip
            searchField
            feedList
            paginationBar
        }
        .palantirCard()
        .frame(maxHeight: .infinity)
        .onChange(of: searchText) { _, _ in
            currentPage = 0
        }
        .onChange(of: feed.events.count) { _, _ in
            if safePage != currentPage {
                currentPage = safePage
            }
        }
        .sheet(isPresented: $showPresenceRoster) {
            FranchisePresenceRosterSheet(
                users: feed.presenceRoster,
                onDismiss: { showPresenceRoster = false }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(PalantirTheme.success.opacity(0.15))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(feed.isListening ? PalantirTheme.success : PalantirTheme.textMuted)
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE TRACKING")
                    .font(PalantirTheme.labelFont(12))
                    .foregroundStyle(PalantirTheme.success)
                    .tracking(1.4)
                    .lineLimit(1)
                Text("live_tracking.subtitle".localized)
                    .font(PalantirTheme.bodyFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                metricPill(value: "\(feed.eventsLast15Minutes)", label: "15m")
                if feed.isListening {
                    Text("LIVE")
                        .font(PalantirTheme.dataFont(9))
                        .foregroundStyle(PalantirTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().strokeBorder(PalantirTheme.accent.opacity(0.5)))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func metricPill(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(PalantirTheme.dataFont(12))
                .foregroundStyle(PalantirTheme.textPrimary)
            Text(label)
                .font(PalantirTheme.labelFont(8))
                .foregroundStyle(PalantirTheme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(PalantirTheme.surfaceHigh)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PalantirTheme.border))
        )
    }

    private var presenceStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showPresenceRoster = true
            } label: {
                HStack {
                    Text("live_tracking.presence_title".localized.uppercased())
                        .font(PalantirTheme.labelFont(9))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Text("\(feed.presenceRoster.count)")
                        .font(PalantirTheme.dataFont(10))
                        .foregroundStyle(PalantirTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(PalantirTheme.accent)
                }
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(feed.presenceRoster) { user in
                        PresenceUserChip(user: user)
                    }
                    if feed.presenceRoster.isEmpty {
                        Text("live_tracking.presence_empty".localized)
                            .font(PalantirTheme.bodyFont(11))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
            }
            .frame(height: 36)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(PalantirTheme.surfaceHigh)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PalantirTheme.accent.opacity(0.35)))
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PalantirTheme.textMuted)
            TextField("live_tracking.search_placeholder".localized, text: $searchText)
                .font(PalantirTheme.bodyFont(12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(PalantirTheme.surfaceHigh)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(PalantirTheme.border))
        )
    }

    private var feedList: some View {
        ZStack(alignment: .top) {
            if let err = feed.lastError {
                Text(err)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.critical)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if filteredEvents.isEmpty {
                Text(searchText.isEmpty ? "live_tracking.empty".localized : "live_tracking.empty_search".localized)
                    .font(PalantirTheme.bodyFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pageEvents.enumerated()), id: \.element.id) { index, event in
                        LiveActivityFeedRow(
                            event: event,
                            compactWidth: horizontalSizeClass == .compact
                        )
                        if index < pageEvents.count - 1 {
                            Divider().padding(.leading, 40).overlay(PalantirTheme.border)
                        }
                    }
                }
            }
        }
        .frame(minHeight: feedRowHeight, maxHeight: feedRowHeight * feedVisibleRows)
    }

    private var paginationBar: some View {
        HStack {
            Button {
                currentPage = max(0, safePage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(safePage == 0 || filteredEvents.count <= pageSize)

            Text(
                filteredEvents.count > pageSize
                    ? String(format: "live_tracking.page".localized, safePage + 1, pageCount)
                    : String(format: "live_tracking.total".localized, filteredEvents.count)
            )
            .font(PalantirTheme.dataFont(10))
            .foregroundStyle(PalantirTheme.textMuted)

            Button {
                currentPage = min(pageCount - 1, safePage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(safePage >= pageCount - 1 || filteredEvents.count <= pageSize)

            Spacer()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(PalantirTheme.accent)
        .buttonStyle(.plain)
        .frame(height: 28)
    }
}

private struct PresenceUserChip: View {
    let user: FranchiseUserPresence

    private var accent: Color {
        switch user.status.accentToken {
        case "success": return PalantirTheme.success
        case "accent": return PalantirTheme.accent
        default: return PalantirTheme.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: user.status.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(user.userName)
                    .font(PalantirTheme.dataFont(10))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(1)
                Text(user.status.label)
                    .font(PalantirTheme.labelFont(8))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(PalantirTheme.surface)
                .overlay(Capsule().strokeBorder(accent.opacity(0.45)))
        )
    }
}

private struct FranchisePresenceRosterSheet: View {
    let users: [FranchiseUserPresence]
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(users) { user in
                HStack(spacing: 10) {
                    Image(systemName: user.status.icon)
                        .foregroundStyle(statusColor(user.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.userName)
                            .font(PalantirTheme.heroFont(14))
                        Text(user.status.label)
                            .font(PalantirTheme.labelFont(10))
                            .foregroundStyle(statusColor(user.status))
                    }
                    Spacer()
                    Text(user.relativeUpdate)
                        .font(PalantirTheme.dataFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                }
                .listRowBackground(PalantirTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(PalantirTheme.background)
            .navigationTitle("live_tracking.presence_roster_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func statusColor(_ status: FranchisePresenceStatus) -> Color {
        switch status.accentToken {
        case "success": return PalantirTheme.success
        case "accent": return PalantirTheme.accent
        default: return PalantirTheme.textMuted
        }
    }
}

private struct LiveActivityFeedRow: View {
    let event: LiveActivityEvent
    var compactWidth: Bool = false

    private var accent: Color {
        switch event.kind.accentToken {
        case "success": return PalantirTheme.success
        case "warning": return PalantirTheme.warning
        case "critical": return PalantirTheme.critical
        case "accent": return PalantirTheme.accent
        default: return PalantirTheme.textMuted
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.kind.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.userName)
                        .font(PalantirTheme.heroFont(12))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .lineLimit(compactWidth ? 2 : 1)
                    Spacer(minLength: 2)
                    Text(event.relativeTime)
                        .font(PalantirTheme.dataFont(9))
                        .foregroundStyle(PalantirTheme.accent)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(event.localizedTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .lineLimit(compactWidth ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                if let plate = event.plate, !plate.isEmpty {
                    Text(plate)
                        .font(PalantirTheme.dataFont(9))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .lineLimit(1)
                } else if !event.subtitle.isEmpty, event.subtitle != event.title {
                    Text(event.localizedSubtitle)
                        .font(PalantirTheme.bodyFont(10))
                        .foregroundStyle(PalantirTheme.textMuted)
                        .lineLimit(compactWidth ? 2 : 1)
                }
            }
        }
        .frame(minHeight: 44, alignment: .top)
    }
}
