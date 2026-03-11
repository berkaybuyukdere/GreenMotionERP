import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

struct AdminPanelView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var healthItems: [AdminHealthItem] = []
    @State private var selectedHealthItem: AdminHealthItem?
    @State private var users: [AdminUserLiveRow] = []
    @State private var isRefreshing = false
    @State private var isLoadingUsers = false
    @State private var lastRefreshAt: Date?
    
    private let autoRefreshTimer = Timer.publish(every: 25, on: .main, in: .common).autoconnect()
    
    private var isAdmin: Bool {
        authManager.userProfile?.isSuperAdmin == true
    }
    
    private var currentFranchiseId: String {
        let fromService = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !fromService.isEmpty {
            return fromService
        }
        let fromProfile = (authManager.userProfile?.franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return fromProfile.isEmpty ? "CH" : fromProfile
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
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    liveHealthSection
                    authSessionSection
                    usersSection
                }
                .padding()
            }
            .navigationTitle("Admin Panel".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized) { dismiss() }
                }
            }
            .sheet(item: $selectedHealthItem) { item in
                HealthDetailSheet(item: item)
            }
            .task {
                await refreshAllLiveData(silent: false)
            }
            .onReceive(autoRefreshTimer) { _ in
                Task { await refreshAllLiveData(silent: true) }
            }
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
    
    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Franchise Users (Live)".localized)
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
                                .fill(user.isOnline ? Color.green : Color.red)
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
                            Text(user.lastSeenText)
                                .font(.caption2)
                                .foregroundColor(user.isOnline ? .green : .secondary)
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
        NavigationView {
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
                Button("Close".localized) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Admin Panel".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var lastRefreshText: String {
        guard let lastRefreshAt else {
            return "Waiting for first live refresh".localized
        }
        return "Last refresh: \(lastRefreshAt.formatted(date: .omitted, time: .standard))"
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
        async let users = loadUsersWithPresence()
        
        self.healthItems = (try? await checks) ?? []
        self.users = (try? await users) ?? []
        self.lastRefreshAt = Date()
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
        
        // Franchise users visibility
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
        
        // Presence feed
        do {
            let presenceQuery = db.collection("userPresence")
                .whereField("franchiseId", isEqualTo: currentFranchiseId)
            let snapshot = try await fetchSnapshot(presenceQuery)
            items.append(AdminHealthItem(
                id: "presence",
                title: "Presence Feed".localized,
                icon: "dot.radiowaves.left.and.right",
                status: snapshot.documents.isEmpty ? .warning : .healthy,
                message: "\(snapshot.documents.count) active presence documents",
                detail: "Source: userPresence (franchise scoped)"
            ))
        } catch {
            items.append(AdminHealthItem(
                id: "presence",
                title: "Presence Feed".localized,
                icon: "dot.radiowaves.left.and.right",
                status: .error,
                message: error.localizedDescription,
                detail: "Cannot read userPresence collection."
            ))
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
    
    private func loadUsersWithPresence() async throws -> [AdminUserLiveRow] {
        let db = Firestore.firestore()
        let usersQuery = db.collection("users")
            .whereField("franchiseId", isEqualTo: currentFranchiseId)
        let usersSnapshot = try await fetchSnapshot(usersQuery)
        let presenceQuery = db.collection("userPresence")
            .whereField("franchiseId", isEqualTo: currentFranchiseId)
        let presenceSnapshot = try? await fetchSnapshot(presenceQuery)
        
        var presenceByUid: [String: (status: String, lastSeen: Date?)] = [:]
        var presenceByEmail: [String: (status: String, lastSeen: Date?)] = [:]
        
        for doc in presenceSnapshot?.documents ?? [] {
            let data = doc.data()
            let status = (data["status"] as? String ?? "Offline")
            let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue()
            presenceByUid[doc.documentID] = (status, lastSeen)
            let email = ((data["email"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !email.isEmpty {
                presenceByEmail[email] = (status, lastSeen)
            }
        }
        
        var rows: [AdminUserLiveRow] = []
        let now = Date()
        
        for doc in usersSnapshot.documents {
            let data = doc.data()
            let email = (data["email"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstName = data["firstName"] as? String ?? ""
            let lastName = data["lastName"] as? String ?? ""
            let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = fullName.isEmpty ? (email.isEmpty ? doc.documentID : email) : fullName
            let role = (data["role"] as? String ?? "user").lowercased()
            let isActive = data["isActive"] as? Bool ?? true
            let franchiseId = (data["franchiseId"] as? String ?? currentFranchiseId).uppercased()
            
            let byUid = presenceByUid[doc.documentID]
            let byEmail = presenceByEmail[email.lowercased()]
            let presence = byUid ?? byEmail
            let lastSeen = presence?.lastSeen
            let status = presence?.status ?? "Offline"
            let isOnline = status.caseInsensitiveCompare("Online") == .orderedSame &&
                (lastSeen.map { now.timeIntervalSince($0) <= 300 } ?? false)
            
            rows.append(AdminUserLiveRow(
                id: doc.documentID,
                displayName: displayName,
                email: email.isEmpty ? "-" : email,
                role: role,
                franchiseId: franchiseId,
                isActive: isActive,
                isOnline: isOnline,
                lastSeen: lastSeen
            ))
        }
        
        return rows.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline && !rhs.isOnline }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
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
    let isOnline: Bool
    let lastSeen: Date?
    
    var lastSeenText: String {
        guard let lastSeen else { return "No presence data".localized }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let text = formatter.localizedString(for: lastSeen, relativeTo: Date())
        return isOnline ? "Online now".localized : "Last seen \(text)"
    }
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
