import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

struct AdminPanelView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var healthItems: [AdminHealthItem] = []
    @State private var selectedHealthItem: AdminHealthItem?
    @State private var users: [AdminUserLiveRow] = []
    @State private var isRefreshing = false
    @State private var isLoadingUsers = false
    @State private var lastRefreshAt: Date?
    @State private var auditActivities: [Activity] = []
    @State private var isLoadingAudit = false
    @State private var isAuditExpanded = false
    @State private var showClearActivitiesConfirmation = false
    @State private var isClearingActivities = false
    
    private let autoRefreshTimer = Timer.publish(every: 25, on: .main, in: .common).autoconnect()
    
    private var isAdmin: Bool {
        authManager.userProfile?.canAccessFranchiseAdminPanel == true
    }

    /// `users` list + directory UI require Firestore rules reserved for platform operators.
    private var showElevatedUserDirectory: Bool {
        authManager.userProfile?.isElevatedAdmin == true
    }

    private var currentFranchiseId: String {
        let fromService = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !fromService.isEmpty {
            return fromService
        }
        let fromProfile = (authManager.userProfile?.resolvedFranchiseIdForDataAccess() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return fromProfile  // No franchise resolved — UI will show warning when empty
    }
    
    var body: some View {
        Group {
            if isAdmin {
                adminContent
            } else {
                accessDeniedView
            }
        }
    }
    
    private var adminContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                if currentFranchiseId.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Franchise ID could not be resolved. Health checks and user lookups may be incomplete.".localized)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                headerCard
                liveHealthSection
                authSessionSection
                if showElevatedUserDirectory {
                    usersSection
                }
                auditLogSection
            }
            .padding()
        }
        .navigationTitle("Admin Panel".localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedHealthItem) { item in
            HealthDetailSheet(item: item)
        }
        .task {
            await refreshAllLiveData(silent: false)
        }
        .onReceive(autoRefreshTimer) { _ in
            Task { await refreshAllLiveData(silent: true) }
        }
        .confirmationDialog(
            "Clear all activities?".localized,
            isPresented: $showClearActivitiesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All".localized, role: .destructive) {
                performClearActivities()
            }
            Button("Cancel".localized, role: .cancel) {}
        } message: {
            Text("This permanently removes every activity entry for the current franchise for all users.".localized)
        }
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live System Monitor".localized)
                        .font(.headline)
                    Text("Franchise: \(currentFranchiseId)")
                        .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    Task { await refreshAllLiveData(silent: false) }
                } label: {
                    HStack(spacing: 6) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh".localized)
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRefreshing)
            }
            
            Text(lastRefreshText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private var liveHealthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Health Checks".localized)
                .font(.headline)
            
            if healthItems.isEmpty {
                Text("Loading live checks...".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(healthItems) { item in
                    Button {
                        selectedHealthItem = item
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(item.tintColor.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                Image(systemName: item.icon)
                                    .foregroundColor(item.tintColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text(item.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(item.tintColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var authSessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Auth Session".localized)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("UID: \(authManager.currentUser?.uid ?? "-")")
                    .font(.caption)
                Text("Email: \(authManager.currentUser?.email ?? "-")")
                    .font(.caption)
                Text("Display Name: \(authManager.currentUser?.displayName ?? "-")")
                    .font(.caption)
                Text("Role: \(authManager.userProfile?.role.rawValue ?? "-")")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var auditLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Operations audit log".localized)
                    .font(.headline)
                Spacer()
                if isLoadingAudit {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("\(auditActivities.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text("Check Out, Return, Check In, and Damage events with user attribution (latest load).".localized)
                .font(.caption2)
                .foregroundColor(.secondary)

            if isAdmin {
                Text("Clearing removes all recent activity records for this franchise from the server for every user. This cannot be undone. Confirm below if you still want to clear.".localized)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showClearActivitiesConfirmation = true
                } label: {
                    HStack {
                        if isClearingActivities {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Clear recent activities".localized)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isClearingActivities || isLoadingAudit)
            }
            
            if !auditActivities.isEmpty {
                detailedAuditSummaryCard
            }
            
            if auditActivities.isEmpty && !isLoadingAudit {
                Text("No audit entries loaded".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                let showingRows = isAuditExpanded ? min(100, auditActivities.count) : min(10, auditActivities.count)
                ForEach(Array(auditActivities.prefix(showingRows))) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: row.tip.icon)
                                .foregroundColor(row.tip.color)
                            Text(row.tip.englishDisplayName)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(row.tarih.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(row.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.primary)
                        if let actor = resolvedAuditActorDisplay(for: row), !actor.isEmpty {
                            Text(actor)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if auditActivities.count > 10 {
                    Button {
                        withAnimation(.easeInOut) {
                            isAuditExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(isAuditExpanded ? "Collapse".localized : "Load More".localized)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(isAuditExpanded ? .teal : .primary)
                            Image(systemName: isAuditExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(isAuditExpanded ? .teal : .secondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
    }
    
    private var detailedAuditSummaryCard: some View {
        let topTypes = Dictionary(grouping: auditActivities, by: { $0.tip.englishDisplayName })
            .mapValues(\.count)
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(4)
        
        let topActors = auditActivities
            .compactMap { resolvedAuditActorDisplay(for: $0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { partial, name in
                partial[name, default: 0] += 1
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(4)
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Detailed Audit Report".localized)
                .font(.subheadline.weight(.semibold))
            Text("Top event types and top operators in the latest loaded audit set.".localized)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if !topTypes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Events".localized)
                        .font(.caption.weight(.semibold))
                    ForEach(Array(topTypes), id: \.key) { entry in
                        HStack {
                            Text(entry.key)
                                .font(.caption2)
                            Spacer()
                            Text("\(entry.value)")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
            }
            
            if !topActors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Operators".localized)
                        .font(.caption.weight(.semibold))
                    ForEach(Array(topActors), id: \.key) { entry in
                        HStack {
                            Text(entry.key)
                                .font(.caption2)
                            Spacer()
                            Text("\(entry.value)")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - (Work time audit moved into Working Hours)

    private func resolvedAuditActorDisplay(for activity: Activity) -> String? {
        let name = activity.kullaniciAdi?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        
        let email = activity.kullaniciEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !email.isEmpty else { return nil }
        
        if let matchedUser = users.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
            return matchedUser.displayName
        }
        
        return email.components(separatedBy: "@").first ?? email
    }
    
    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Franchise Users".localized)
                    .font(.headline)
                Spacer()
                if isLoadingUsers {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("\(users.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            if users.isEmpty && !isLoadingUsers {
                Text("No users found for this franchise".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(users) { user in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(user.isActive ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text(user.displayName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(user.role.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(user.email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("UID: \(user.id)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Franchise: \(user.franchiseId)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(user.isActive ? "Active".localized : "Inactive".localized)
                                .font(.caption2)
                                .foregroundColor(user.isActive ? .green : .secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private var accessDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54))
                .foregroundColor(.red)
            Text("Access Denied".localized)
                .font(.title3.weight(.bold))
            Text("This panel is only accessible to administrators.".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Admin Panel".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var lastRefreshText: String {
        guard let lastRefreshAt else {
            return "Waiting for first live refresh".localized
        }
        return "Last refresh: \(lastRefreshAt.formatted(date: .omitted, time: .standard))"
    }

    private func performClearActivities() {
        guard !isClearingActivities else { return }
        isClearingActivities = true
        viewModel.clearAllFranchiseActivities { error in
            isClearingActivities = false
            if let error {
                ErrorManager.shared.showError(error, context: "Clear activities")
            } else {
                ErrorManager.shared.showSuccess("All activities cleared for this franchise.".localized)
                auditActivities = []
                isLoadingAudit = true
                viewModel.loadAuditActivities(limit: 350) { list in
                    auditActivities = list
                    isLoadingAudit = false
                }
            }
        }
    }
    
    @MainActor
    private func refreshAllLiveData(silent: Bool) async {
        if isRefreshing { return }
        isRefreshing = true
        if !silent { isLoadingUsers = true }
        defer {
            isRefreshing = false
            isLoadingUsers = false
        }
        
        async let checks = loadLiveHealthChecks()
        if showElevatedUserDirectory {
            async let users = loadFranchiseUsers()
            self.users = (try? await users) ?? []
        } else {
            self.users = []
        }
        self.healthItems = (try? await checks) ?? []
        self.lastRefreshAt = Date()
        
        isLoadingAudit = true
        viewModel.loadAuditActivities(limit: 350) { list in
            auditActivities = list
            isLoadingAudit = false
        }

        // Work time audit trail moved into Working Hours UI.
    }
    
    private func loadLiveHealthChecks() async throws -> [AdminHealthItem] {
        let db = Firestore.firestore()
        let storage = Storage.storage()
        var items: [AdminHealthItem] = []
        
        // Auth session
        if let user = authManager.currentUser {
            items.append(AdminHealthItem(
                id: "auth",
                title: "Authentication".localized,
                icon: "person.badge.key.fill",
                status: .healthy,
                message: "Logged in as \(user.email ?? user.uid)",
                detail: "User ID: \(user.uid)"
            ))
            } else {
            items.append(AdminHealthItem(
                id: "auth",
                title: "Authentication".localized,
                icon: "person.badge.key.fill",
                status: .error,
                message: "No authenticated user".localized,
                detail: "Session is missing."
            ))
        }
        
        // Firestore connectivity
        do {
            let snapshot = try await fetchSnapshot(
                FirebaseService.shared.getFilteredQuery("araclar").limit(to: 1)
            )
            items.append(AdminHealthItem(
                id: "firestore",
                title: "Firestore Connectivity".localized,
                icon: "externaldrive.fill.badge.checkmark",
                status: .healthy,
                message: "Reachable (\(snapshot.documents.count) sample records)",
                detail: "Collection: araclar"
            ))
        } catch {
            items.append(AdminHealthItem(
                id: "firestore",
                title: "Firestore Connectivity".localized,
                icon: "externaldrive.fill.badge.checkmark",
                status: .error,
                message: error.localizedDescription,
                detail: "Collection read failed for araclar."
            ))
        }
        
        // Franchise users visibility (Firestore `users` list is restricted to platform operators)
        if authManager.userProfile?.isElevatedAdmin == true {
            do {
                let usersQuery = db.collection("users")
                    .whereField("franchiseId", isEqualTo: currentFranchiseId)
                let snapshot = try await fetchSnapshot(usersQuery)
                items.append(AdminHealthItem(
                    id: "users",
                    title: "Franchise Users".localized,
                    icon: "person.3.fill",
                    status: snapshot.documents.isEmpty ? .warning : .healthy,
                    message: "\(snapshot.documents.count) users in \(currentFranchiseId)",
                    detail: "Source: users collection"
                ))
            } catch {
                items.append(AdminHealthItem(
                    id: "users",
                    title: "Franchise Users".localized,
                    icon: "person.3.fill",
                    status: .error,
                    message: error.localizedDescription,
                    detail: "Cannot read users collection."
                ))
            }
        }
        
        // Office operations feed
        do {
            let snapshot = try await fetchSnapshot(
                FirebaseService.shared.getFilteredQuery("office_operations").limit(to: 5)
            )
            items.append(AdminHealthItem(
                id: "office_ops",
                title: "Office Operations Feed".localized,
                icon: "building.2.crop.circle.fill",
                status: .healthy,
                message: "\(snapshot.documents.count) latest records fetched",
                detail: "Collection: office_operations"
            ))
        } catch {
            items.append(AdminHealthItem(
                id: "office_ops",
                title: "Office Operations Feed".localized,
                icon: "building.2.crop.circle.fill",
                status: .error,
                message: error.localizedDescription,
                detail: "Cannot read office_operations."
            ))
        }
        
        // Additional sales people feed
        do {
            let snapshot = try await fetchSnapshot(
                FirebaseService.shared.getFilteredQuery("additional_sales_people").limit(to: 20)
            )
            items.append(AdminHealthItem(
                id: "sales_people",
                title: "Additional Sales People".localized,
                icon: "person.crop.circle.badge.plus",
                status: snapshot.documents.isEmpty ? .warning : .healthy,
                message: "\(snapshot.documents.count) person records",
                detail: "Collection: additional_sales_people"
            ))
        } catch {
            items.append(AdminHealthItem(
                id: "sales_people",
                title: "Additional Sales People".localized,
                icon: "person.crop.circle.badge.plus",
                status: .error,
                message: error.localizedDescription,
                detail: "Cannot read additional_sales_people."
            ))
        }
        
        // Scoped storage access
        do {
            _ = try await listStorage(path: "franchises/\(currentFranchiseId)/test", storage: storage)
            items.append(AdminHealthItem(
                id: "storage_scoped",
                title: "Scoped Storage Access".localized,
                icon: "externaldrive.badge.checkmark",
                status: .healthy,
                message: "franchises/\(currentFranchiseId)/test reachable",
                detail: "Storage listing succeeded."
            ))
        } catch {
            items.append(AdminHealthItem(
                id: "storage_scoped",
                title: "Scoped Storage Access".localized,
                icon: "externaldrive.badge.checkmark",
                status: .error,
                message: error.localizedDescription,
                detail: "Storage path check failed."
            ))
        }
        
        // Return pdf storage path
        do {
            let result = try await listStorage(path: "franchises/\(currentFranchiseId)/return_pdfs", storage: storage)
            items.append(AdminHealthItem(
                id: "return_pdfs",
                title: "Return PDF Storage".localized,
                icon: "doc.richtext.fill",
                status: .healthy,
                message: "\(result.items.count) files, \(result.prefixes.count) folders",
                detail: "Path: franchises/\(currentFranchiseId)/return_pdfs"
            ))
        } catch {
            items.append(AdminHealthItem(
                id: "return_pdfs",
                title: "Return PDF Storage".localized,
                icon: "doc.richtext.fill",
                status: .error,
                message: error.localizedDescription,
                detail: "Cannot list return_pdfs path."
            ))
        }
        
        return items
    }
    
    private func loadFranchiseUsers() async throws -> [AdminUserLiveRow] {
        let db = Firestore.firestore()
        let usersQuery = db.collection("users")
            .whereField("franchiseId", isEqualTo: currentFranchiseId)
        let usersSnapshot = try await fetchSnapshot(usersQuery)
        
        var rows: [AdminUserLiveRow] = []
        
        for doc in usersSnapshot.documents {
            let data = doc.data()
            let email = (data["email"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstName = data["firstName"] as? String ?? ""
            let lastName = data["lastName"] as? String ?? ""
            let username = (data["username"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let nick = (data["nickname"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstTrim = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String = {
                if !username.isEmpty { return username }
                if !firstTrim.isEmpty { return firstTrim }
                if !nick.isEmpty { return nick }
                if !fullName.isEmpty { return fullName }
                return email.isEmpty ? doc.documentID : email
            }()
            let role = (data["role"] as? String ?? "user").lowercased()
            let isActive = data["isActive"] as? Bool ?? true
            let franchiseId = (data["franchiseId"] as? String ?? currentFranchiseId).uppercased()
            
            rows.append(AdminUserLiveRow(
                id: doc.documentID,
                displayName: displayName,
                email: email.isEmpty ? "-" : email,
                role: role,
                franchiseId: franchiseId,
                isActive: isActive
            ))
        }
        
        return rows.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
    
    private func fetchSnapshot(_ query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AdminPanel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Empty query snapshot"]
                    ))
                }
            }
        }
    }
    
    private func fetchSnapshot(_ collection: CollectionReference) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            collection.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AdminPanel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Empty collection snapshot"]
                    ))
                }
            }
        }
    }
    
    private func listStorage(path: String, storage: Storage) async throws -> StorageListResult {
        try await withCheckedThrowingContinuation { continuation in
            storage.reference().child(path).listAll { result, error in
                if let error {
                    continuation.resume(throwing: error)
                        return
                    }
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "AdminPanel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Empty storage list result"]
                    ))
                }
            }
        }
    }
}

private struct AdminHealthItem: Identifiable {
    enum Status {
        case healthy
        case warning
        case error
    }
    
    let id: String
    let title: String
    let icon: String
    let status: Status
    let message: String
    let detail: String
    
    var tintColor: Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

private struct AdminUserLiveRow: Identifiable {
    let id: String
    let displayName: String
    let email: String
    let role: String
    let franchiseId: String
    let isActive: Bool
}

private struct HealthDetailSheet: View {
    let item: AdminHealthItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.title2)
                        .foregroundColor(item.tintColor)
                    Text(item.title)
                        .font(.headline)
                }
                Text(item.message)
                    .font(.subheadline)
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
            .navigationTitle("Check Detail".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { dismiss() }
                }
            }
        }
    }
}
