import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Shuttle Reports - Generated PDF reports list
struct ShuttleReportsView: View {
    @State private var reports: [ShuttleReport] = []
    @State private var isLoading = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @Environment(\.dismiss) var dismiss
    
    // Demo user email
    private let demoUserEmail = "demo@gmail.com"
    
    // Check if current user is demo user
    private var isDemoUser: Bool {
        guard let user = Auth.auth().currentUser else { return false }
        let email = user.email?.lowercased() ?? ""
        
        // Check email pattern: *_demo@* or demo_*@* or @demo.example.com
        if email.contains("_demo@") || email.hasPrefix("demo_") || email.hasSuffix("@demo.example.com") {
            return true
        }
        
        // Check old demo email (backward compatibility)
        if email == demoUserEmail {
            return true
        }
        
        return false
    }
    
    // Get collection reference - handles both production and demo (subcollection) collections
    private func getCollectionReference(_ baseName: String) -> CollectionReference {
        let db = Firestore.firestore()
        guard isDemoUser, let userId = Auth.auth().currentUser?.uid else {
            // Production: normal collection
            return db.collection(baseName)
        }
        
        // Old demo user (demo@gmail.com) uses demo_* prefix for backward compatibility
        if let email = Auth.auth().currentUser?.email?.lowercased(), email == demoUserEmail {
            return db.collection("demo_\(baseName)")
        }
        
        // New demo users: subcollection structure - demo_environments/{userId}/{baseName}
        return db.collection("demo_environments")
            .document(userId)
            .collection(baseName)
    }
    
    // Get collection name with demo prefix if needed (backward compatibility - use getCollectionReference instead)
    private func collectionName(_ baseName: String) -> String {
        // Old demo user (demo@gmail.com) uses demo_* prefix
        if let email = Auth.auth().currentUser?.email?.lowercased(), email == demoUserEmail {
            return "demo_\(baseName)"
        }
        // New demo users will use subcollection structure via getCollectionReference()
        return baseName
    }
    
    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if reports.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Reports Generated")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Generate reports from Shuttle İşlemleri")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(reports) { report in
                        ReportRow(report: report)
                            .onTapGesture {
                                shareReport(report)
                            }
                    }
                    .onDelete(perform: deleteReport)
                }
            }
            .navigationTitle("Shuttle Reports")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadReports()
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ActivityViewController(activityItems: [url])
                }
            }
        }
    }
    
    private func loadReports() {
        isLoading = true
        
        Task {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("shuttleReports")
                    .order(by: "generatedAt", descending: true)
                    .limit(to: 50)
                    .getDocuments()
                
                let loadedReports = snapshot.documents.compactMap { doc -> ShuttleReport? in
                    guard let data = doc.data() as? [String: Any],
                          let type = data["type"] as? String,
                          let startDate = (data["startDate"] as? Timestamp)?.dateValue(),
                          let endDate = (data["endDate"] as? Timestamp)?.dateValue(),
                          let totalSessions = data["totalSessions"] as? Int,
                          let totalCustomers = data["totalCustomers"] as? Int,
                          let totalTrips = data["totalTrips"] as? Int,
                          let generatedAt = (data["generatedAt"] as? Timestamp)?.dateValue(),
                          let pdfPath = data["pdfPath"] as? String else {
                        return nil
                    }
                    
                    return ShuttleReport(
                        id: doc.documentID,
                        type: type,
                        startDate: startDate,
                        endDate: endDate,
                        totalSessions: totalSessions,
                        totalCustomers: totalCustomers,
                        totalTrips: totalTrips,
                        generatedAt: generatedAt,
                        pdfPath: pdfPath
                    )
                }
                
                await MainActor.run {
                    reports = loadedReports
                    isLoading = false
                }
            } catch {
                print("❌ Error loading reports: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func shareReport(_ report: ShuttleReport) {
        let fileURL = URL(fileURLWithPath: report.pdfPath)
        
        if FileManager.default.fileExists(atPath: report.pdfPath) {
            shareURL = fileURL
            showShareSheet = true
        } else {
            print("❌ PDF file not found: \(report.pdfPath)")
        }
    }
    
    private func deleteReport(at offsets: IndexSet) {
        for index in offsets {
            let report = reports[index]
            
            // Delete from Firestore
            Firestore.firestore()
                .collection("shuttleReports")
                .document(report.id)
                .delete { error in
                    if let error = error {
                        print("❌ Error deleting report: \(error)")
                    }
                }
            
            // Delete PDF file
            try? FileManager.default.removeItem(atPath: report.pdfPath)
        }
        
        reports.remove(atOffsets: offsets)
    }
}

// MARK: - Report Row

struct ReportRow: View {
    let report: ShuttleReport
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundColor(.cyan)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(report.type)
                    .font(.headline)
                
                Text(report.formattedDateRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Label("\(report.totalSessions) sessions", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Label("\(report.totalCustomers) customers", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(.cyan)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shuttle Report Model

struct ShuttleReport: Identifiable {
    let id: String
    let type: String
    let startDate: Date
    let endDate: Date
    let totalSessions: Int
    let totalCustomers: Int
    let totalTrips: Int
    let generatedAt: Date
    let pdfPath: String
    
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }
}

// MARK: - Preview

struct ShuttleReportsView_Previews: PreviewProvider {
    static var previews: some View {
        ShuttleReportsView()
    }
}
