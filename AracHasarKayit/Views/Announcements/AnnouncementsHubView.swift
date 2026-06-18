import SwiftUI
import FirebaseAuth

struct AnnouncementsHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @ObservedObject private var store = AnnouncementStore.shared
    @ObservedObject private var serviceFlagStore = VehicleServiceFlagStore.shared
    var initialSegment: Int = 0
    @State private var segment = 0
    @State private var showComposer = false
    @State private var selectedAnnouncement: FranchiseAnnouncement?
    @State private var selectedServiceVehicle: Arac?
    @State private var scrollOffset: CGFloat = 0
    @State private var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large
    @State private var showChatMedia = false
    @State private var showChatSearch = false
    @State private var showChatMembers = false
    @State private var showChatAI = false
    @State private var chatSearchQuery = ""

    private var canPublish: Bool { authManager.userProfile?.canPublishAnnouncements == true }
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    private var dailyReportItems: [FranchiseAnnouncement] {
        store.publishedAnnouncements().filter(\.isDailyReport)
    }

    private var generalAnnouncementItems: [FranchiseAnnouncement] {
        store.publishedAnnouncements().filter { !$0.isDailyReport }
    }

    private var hasFeedContent: Bool {
        !dailyReportItems.isEmpty
            || !generalAnnouncementItems.isEmpty
            || !serviceFlagStore.activeFlags().isEmpty
    }

    init(initialSegment: Int = 0) {
        self.initialSegment = initialSegment
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        NavigationStack {
            Group {
                if segment == 0 {
                    announcementFeed
                } else {
                    TeamChatTabView(store: store, searchQuery: chatSearchQuery)
                        .environmentObject(viewModel)
                        .environmentObject(authManager)
                }
            }
            .background(MessagesTheme.chatBackground(for: colorScheme))
            .navigationTitle(segment == 0 ? "Announcements".localized : "announcements.tab.chat".localized)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(titleDisplayMode == .inline ? .visible : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    segmentPicker
                }
                if canPublish, segment == 0 {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showComposer = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(MessagesTheme.iosBlue)
                        }
                    }
                }
                if segment == 1 {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { showChatSearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        Button { showChatMedia = true } label: {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                        Button { showChatMembers = true } label: {
                            Image(systemName: "person.2.fill")
                        }
                        if GroqInsightsService.shared.hasAPIKey {
                            Button { showChatAI = true } label: {
                                Image(systemName: "sparkles")
                            }
                        }
                    }
                }
            }
            .onAppear {
                store.startListening()
                serviceFlagStore.startListening()
                titleDisplayMode = .large
                segment = initialSegment
                Task {
                    guard let profile = authManager.userProfile,
                          let uid = Auth.auth().currentUser?.uid else { return }
                    await store.touchLastOnline(userId: uid, userName: profile.displayName)
                }
            }
            .onDisappear {
                store.stopListening()
                serviceFlagStore.stopListening()
            }
            .onChange(of: segment) { _, _ in
                scrollOffset = 0
                titleDisplayMode = .large
            }
            .sheet(isPresented: $showComposer) {
                AnnouncementComposerView(store: store)
                    .environmentObject(authManager)
            }
            .navigationDestination(item: $selectedAnnouncement) { item in
                AnnouncementDetailView(store: store, announcement: item)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
            .navigationDestination(item: $selectedServiceVehicle) { arac in
                AracDetayView(arac: arac)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showChatMedia) {
                TeamChatMediaGalleryView(store: store)
            }
            .sheet(isPresented: $showChatSearch) {
                TeamChatSearchSheet(store: store, query: $chatSearchQuery)
            }
            .sheet(isPresented: $showChatMembers) {
                TeamChatMembersSheet(store: store)
            }
            .sheet(isPresented: $showChatAI) {
                TeamChatAISheet()
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
    }

    private var segmentPicker: some View {
        Picker("", selection: $segment) {
            Text("announcements.tab.feed".localized).tag(0)
            Text("announcements.tab.chat".localized).tag(1)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }

    private var announcementFeed: some View {
        Group {
            if store.isLoading && !hasFeedContent {
                ProgressView("announcements.loading".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasFeedContent {
                ContentUnavailableView(
                    "announcements.empty.title".localized,
                    systemImage: "megaphone.fill",
                    description: Text("announcements.empty.subtitle".localized)
                )
            } else {
                List {
                    if !serviceFlagStore.activeFlags().isEmpty {
                        Section {
                            ForEach(serviceFlagStore.activeFlags()) { flag in
                                Button {
                                    if let arac = viewModel.vehicle(matchingServiceFlag: flag) {
                                        selectedServiceVehicle = arac
                                    }
                                } label: {
                                    VehicleServiceFlagBanner(flag: flag)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .listRowBackground(Color.clear)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.orange)
                                Text("vehicle_service_flag.pinned_title".localized)
                            }
                        }
                    }

                    if !dailyReportItems.isEmpty {
                        Section {
                            ForEach(dailyReportItems) { item in
                                announcementRow(item, isDailyReport: true)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticManager.shared.light()
                                        selectedAnnouncement = item
                                    }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "chart.bar.doc.horizontal.fill")
                                    .foregroundStyle(.blue)
                                Text("announcements.daily_reports".localized)
                            }
                        }
                    }

                    ForEach(generalAnnouncementItems) { item in
                        announcementRow(item, isDailyReport: false)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.shared.light()
                                selectedAnnouncement = item
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if canPublish {
                                    Button {
                                        Task {
                                            try? await store.setPinned(
                                                announcementId: item.id,
                                                pinned: !item.pinned
                                            )
                                        }
                                    } label: {
                                        Label(
                                            item.pinned ? "announcements.unpin".localized : "announcements.pin".localized,
                                            systemImage: item.pinned ? "pin.slash" : "pin.fill"
                                        )
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("announcementsFeedScroll")).minY
                        )
                    }
                )
                .coordinateSpace(name: "announcementsFeedScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    let collapsed = value < -24
                    if collapsed && titleDisplayMode != .inline {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            titleDisplayMode = .inline
                        }
                    } else if !collapsed && titleDisplayMode != .large {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            titleDisplayMode = .large
                        }
                    }
                }
            }
        }
    }

    private func announcementRow(_ item: FranchiseAnnouncement, isDailyReport: Bool = false) -> some View {
        let read = store.isRead(announcementId: item.id, userId: uid)
        return HStack(alignment: .top, spacing: 14) {
            AnnouncementIconPalette.badge(
                icon: isDailyReport ? "chart.bar.doc.horizontal.fill" : item.icon,
                colorKey: isDailyReport ? "blue" : item.iconColorKey,
                size: 48,
                dimmed: read
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    Text(item.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PalantirTheme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    if !read {
                        Circle()
                            .fill(MessagesTheme.iosBlue)
                            .frame(width: 10, height: 10)
                            .accessibilityLabel("announcements.unread_badge".localized)
                    }
                }

                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(PalantirTheme.textMuted)
                    .lineLimit(isDailyReport ? 6 : 2)

                HStack(spacing: 6) {
                    Text(item.createdByName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MessagesTheme.iosBlue)
                    Text("·")
                        .foregroundStyle(PalantirTheme.textMuted)
                    Text(item.publishedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                        .font(.caption)
                        .foregroundStyle(PalantirTheme.textMuted)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDailyReport
                        ? Color.blue.opacity(0.35)
                        : (item.pinned ? Color.orange.opacity(0.35) : MessagesTheme.iosGray4.opacity(0.6)),
                    lineWidth: isDailyReport || item.pinned ? 1.5 : 1
                )
        )
        .opacity(read ? 0.92 : 1)
    }
}

extension FranchiseAnnouncement: Hashable {
    static func == (lhs: FranchiseAnnouncement, rhs: FranchiseAnnouncement) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
