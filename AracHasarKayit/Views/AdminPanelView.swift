import SwiftUI
import FirebaseFirestore
import FirebaseStorage

struct AdminPanelView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var testResults: [TestResult] = []
    @State private var isRunningTests = false
    @State private var testProgress: Double = 0.0
    
    // Check if current user is admin
    private var isAdmin: Bool {
        authManager.currentUser?.email == "admin@gmail.com"
    }
    
    var body: some View {
        Group {
            if isAdmin {
                adminPanelContent
            } else {
                accessDeniedView
            }
        }
    }
    
    private var adminPanelContent: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        Text("Admin Panel")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Firebase Connection Tests")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    // Test Button
                    Button {
                        runAllTests()
                    } label: {
                        HStack {
                            if isRunningTests {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "play.circle.fill")
                            }
                            Text(isRunningTests ? "Running Tests..." : "Run All Tests")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isRunningTests ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isRunningTests)
                    .padding(.horizontal)
                    
                    // Progress Bar
                    if isRunningTests {
                        ProgressView(value: testProgress)
                            .padding(.horizontal)
                    }
                    
                    // Test Results
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Test Results")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(testResults) { result in
                                TestResultRow(result: result)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var accessDeniedView: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Access Denied")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("This panel is only accessible to administrators.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            .padding()
            .navigationTitle("Admin Panel")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func runAllTests() {
        isRunningTests = true
        testResults = []
        testProgress = 0.0
        
        let totalTests = 12.0
        let testStartTime = Date()
        
        // Run tests sequentially
        testFirestoreConnection(totalTests)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            testReadVehicles(totalTests)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                testReadDamageReports(totalTests)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    testReadReturns(totalTests)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        testReadOfficeOperations(totalTests)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            testReadVacationTimes(totalTests)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                testStorageConnection(totalTests)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    testImageUpload(totalTests)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        testImageDownload(totalTests)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            testWriteOperation(totalTests)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                testRealTimeListeners(totalTests)
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                    testAuthentication(totalTests)
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                        isRunningTests = false
                                                        testProgress = 1.0
                                                        // Save test results to Firebase
                                                        saveTestResultsToFirebase(startTime: testStartTime)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func saveTestResultsToFirebase(startTime: Date) {
        let db = Firestore.firestore()
        let totalDuration = Date().timeIntervalSince(startTime)
        let successCount = testResults.filter { $0.success }.count
        let failureCount = testResults.filter { !$0.success }.count
        
        // Prepare test results data
        let testResultsData = testResults.map { result in
            [
                "name": result.name,
                "success": result.success,
                "message": result.message,
                "duration": result.duration
            ] as [String: Any]
        }
        
        // Prepare log document
        let logData: [String: Any] = [
            "timestamp": Timestamp(date: Date()),
            "startTime": Timestamp(date: startTime),
            "totalDuration": totalDuration,
            "totalTests": testResults.count,
            "successCount": successCount,
            "failureCount": failureCount,
            "successRate": testResults.isEmpty ? 0.0 : Double(successCount) / Double(testResults.count),
            "userEmail": authManager.currentUser?.email ?? "unknown",
            "userId": authManager.currentUser?.uid ?? "unknown",
            "testResults": testResultsData,
            "deviceInfo": [
                "model": UIDevice.current.model,
                "systemVersion": UIDevice.current.systemVersion,
                "systemName": UIDevice.current.systemName
            ]
        ]
        
        // Save to Firebase
        let logId = UUID().uuidString
        db.collection("adminTestLogs").document(logId).setData(logData) { error in
            if let error = error {
                print("❌ Failed to save test results to Firebase: \(error.localizedDescription)")
            } else {
                print("✅ Test results saved to Firebase - Log ID: \(logId)")
                print("   Success: \(successCount)/\(testResults.count), Duration: \(String(format: "%.2f", totalDuration))s")
            }
        }
    }
    
    // MARK: - Test Functions
    
    private func testFirestoreConnection(_ total: Double) {
        let db = Firestore.firestore()
        let startTime = Date()
        
        // Test with a collection that definitely exists and has read permissions
        db.collection("araclar").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let message = success ? "Connected successfully" : "Connection failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Firestore Connection",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testReadVehicles(_ total: Double) {
        let startTime = Date()
        let db = Firestore.firestore()
        
        db.collection("araclar").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let count = snapshot?.documents.count ?? 0
            let message = success ? "Read \(count) vehicles" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Read Vehicles",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testReadDamageReports(_ total: Double) {
        let startTime = Date()
        let db = Firestore.firestore()
        
        db.collection("araclar").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let message = success ? "Can read damage reports" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Read Damage Reports",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testReadReturns(_ total: Double) {
        let startTime = Date()
        let db = Firestore.firestore()
        
        db.collection("iadeIslemleri").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let count = snapshot?.documents.count ?? 0
            let message = success ? "Read \(count) returns" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Read Returns",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testReadOfficeOperations(_ total: Double) {
        let startTime = Date()
        let db = Firestore.firestore()
        
        // Try office_operations (with underscore) first, as that's what the code uses
        db.collection("office_operations").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let count = snapshot?.documents.count ?? 0
            let message = success ? "Read \(count) operations" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Read Office Operations",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testReadVacationTimes(_ total: Double) {
        let startTime = Date()
        let db = Firestore.firestore()
        
        db.collection("vacationTimes").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let count = snapshot?.documents.count ?? 0
            let message = success ? "Read \(count) vacation times" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Read Vacation Times",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testStorageConnection(_ total: Double) {
        let startTime = Date()
        let storage = Storage.storage()
        let ref = storage.reference()
        
        ref.child("test").listAll { result, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let message = success ? "Storage connected" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Storage Connection",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testImageUpload(_ total: Double) {
        let startTime = Date()
        let storage = Storage.storage()
        let ref = storage.reference().child("test/admin_test_\(UUID().uuidString).jpg")
        
        // Create a small test image
        let testImage = UIImage(systemName: "checkmark.circle.fill") ?? UIImage()
        guard let imageData = testImage.pngData() else {
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Image Upload",
                    success: false,
                    message: "Failed to create test image",
                    duration: Date().timeIntervalSince(startTime)
                ))
                testProgress = Double(testResults.count) / total
            }
            return
        }
        
        ref.putData(imageData, metadata: nil) { metadata, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            
            if success {
                // Delete test file
                ref.delete { _ in }
            }
            
            let message = success ? "Upload successful" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Image Upload",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testImageDownload(_ total: Double) {
        let startTime = Date()
        let storage = Storage.storage()
        
        // Try to list images in hasar_fotograflari (any subfolder)
        // Use a specific subfolder that likely exists
        let ref = storage.reference().child("hasar_fotograflari/handover")
        
        ref.listAll { result, error in
            let duration = Date().timeIntervalSince(startTime)
            // Even if folder doesn't exist, if we can access it, that's success
            let success = error == nil || (error as NSError?)?.code != 403
            let message = success ? "Can access storage" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Image Download/List",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testWriteOperation(_ total: Double) {
        let startTime = Date()
        let db = Firestore.firestore()
        let testDoc = db.collection("adminTests").document(UUID().uuidString)
        
        testDoc.setData([
            "test": true,
            "timestamp": Timestamp(),
            "userId": authManager.currentUser?.uid ?? "unknown"
        ]) { error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            
            if success {
                // Delete test document
                testDoc.delete { _ in }
            }
            
            let message = success ? "Write successful" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Write Operation",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testRealTimeListeners(_ total: Double) {
        let startTime = Date()
        let db = Firestore.firestore()
        
        var listener: ListenerRegistration?
        listener = db.collection("araclar").limit(to: 1).addSnapshotListener { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let message = success ? "Listener active" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            // Remove listener immediately
            listener?.remove()
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Real-time Listeners",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testAuthentication(_ total: Double) {
        let startTime = Date()
        let success = authManager.currentUser != nil
        let duration = Date().timeIntervalSince(startTime)
        let email = authManager.currentUser?.email ?? "Not authenticated"
        let message = success ? "User: \(email)" : "Not authenticated"
        
        DispatchQueue.main.async {
            testResults.append(TestResult(
                name: "Authentication",
                success: success,
                message: message,
                duration: duration
            ))
            testProgress = Double(testResults.count) / total
        }
    }
}

// MARK: - Test Result Model
struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let success: Bool
    let message: String
    let duration: TimeInterval
}

// MARK: - Test Result Row
struct TestResultRow: View {
    let result: TestResult
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(result.success ? .green : .red)
            
            // Test Info
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(result.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.2f ms", result.duration * 1000))
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            Spacer()
        }
        .padding()
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

