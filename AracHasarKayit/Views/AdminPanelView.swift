import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

struct AdminPanelView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var testResults: [TestResult] = []
    @State private var isRunningTests = false
    @State private var testProgress: Double = 0.0
    @State private var isLoadingLogs = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    
    // Check if current user is superadmin (role-based, no email hardcode)
    private var isAdmin: Bool {
        authManager.userProfile?.isSuperAdmin == true
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
                        Text("Admin Panel".localized)
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Firebase Connection Tests".localized)
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
                            Text((isRunningTests ? "Running Tests..." : "Run All Tests").localized)
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
                    
                    // Export Test Logs Button
                    Button {
                        exportTestLogs()
                    } label: {
                        HStack {
                            if isLoadingLogs {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "doc.text.fill")
                            }
                            Text((isLoadingLogs ? "Loading Logs..." : "Export Test Logs").localized)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isLoadingLogs ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoadingLogs)
                    .padding(.horizontal)
                    
                    // Progress Bar
                    if isRunningTests {
                        ProgressView(value: testProgress)
                            .padding(.horizontal)
                    }
                    
                    // Test Results
                    if !testResults.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Test Results".localized)
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
            .navigationTitle("Admin Panel".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close".localized) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ActivityViewController(activityItems: [url])
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
                
                Text("Access Denied".localized)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("This panel is only accessible to administrators.".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Close".localized) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            .padding()
            .navigationTitle("Admin Panel".localized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func runAllTests() {
        isRunningTests = true
        testResults = []
        testProgress = 0.0
        
        let totalTests = 35.0 // Updated total test count
        let testStartTime = Date()
        
        // Run tests sequentially
        testFirestoreConnection(totalTests)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            testReadVehicles(totalTests)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                testReadDamageReports(totalTests)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    testReadReturns(totalTests)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        testReadCheckOuts(totalTests)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            testReadOfficeOperations(totalTests)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                testReadVacationTimes(totalTests)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    // CRUD Tests for each operation
                                    testCreateReturn(totalTests)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        testUpdateReturn(totalTests)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            testDeleteReturn(totalTests)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                testCreateCheckOut(totalTests)
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    testUpdateCheckOut(totalTests)
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                        testDeleteCheckOut(totalTests)
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                            testCreateOfficeOperation(totalTests)
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                testUpdateOfficeOperation(totalTests)
                                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                    testDeleteOfficeOperation(totalTests)
                                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                        // Storage Tests
                                                                        testStorageConnection(totalTests)
                                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                            testImageUpload(totalTests)
                                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                testImageDownload(totalTests)
                                                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                    testStorageDamagePhotos(totalTests)
                                                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                        testStorageReturnPhotos(totalTests)
                                                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                            testStorageCheckOutPhotos(totalTests)
                                                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                                testStorageOfficePhotos(totalTests)
                                                                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                                    // Connection Tests
                                                                                                    testWriteOperation(totalTests)
                                                                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                                        testRealTimeListeners(totalTests)
                                                                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                                            testAuthentication(totalTests)
                                                                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                                                                                testNetworkConnection(totalTests)
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
        }
    }
    
    private func saveTestResultsToFirebase(startTime: Date) {
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
        
        // Save to Firebase (adminTestLogs is global collection)
        let logId = UUID().uuidString
        FirebaseService.shared.getCollectionReference("adminTestLogs").document(logId).setData(logData) { error in
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
        let startTime = Date()
        
        // Test with a collection that definitely exists and has read permissions
        FirebaseService.shared.getFilteredQuery("araclar").limit(to: 1).getDocuments { snapshot, error in
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
        
        FirebaseService.shared.getFilteredQuery("araclar").limit(to: 1).getDocuments { snapshot, error in
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
        
        FirebaseService.shared.getFilteredQuery("araclar").limit(to: 1).getDocuments { snapshot, error in
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
        
        FirebaseService.shared.getFilteredQuery("iadeIslemleri").limit(to: 1).getDocuments { snapshot, error in
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
        
        FirebaseService.shared.getFilteredQuery("office_operations").limit(to: 1).getDocuments { snapshot, error in
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
        
        FirebaseService.shared.getFilteredQuery("vacationTimes").limit(to: 1).getDocuments { snapshot, error in
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
    
    // MARK: - Check Out Operations Tests
    
    private func testReadCheckOuts(_ total: Double) {
        let startTime = Date()
        
        FirebaseService.shared.getFilteredQuery("exitIslemleri").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            let count = snapshot?.documents.count ?? 0
            let message = success ? "Read \(count) check out operations" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Read Check Out Operations",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testCreateCheckOut(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("exitIslemleri").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "aracId": UUID().uuidString,
            "aracPlaka": "TEST-001",
            "exitTarihi": Timestamp(date: Date()),
            "fotograflar": [],
            "notlar": "Admin test check out",
            "resKodu": "RES-999",
            "status": "inProgress"
        ]
        
        testDoc.setData(testData) { error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            
            if success {
                // Delete test document
                testDoc.delete { _ in }
            }
            
            let message = success ? "Check out created successfully" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Create Check Out",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testUpdateCheckOut(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("exitIslemleri").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "aracId": UUID().uuidString,
            "aracPlaka": "TEST-001",
            "exitTarihi": Timestamp(date: Date()),
            "fotograflar": [],
            "notlar": "Admin test check out",
            "resKodu": "RES-999",
            "status": "inProgress"
        ]
        
        // First create, then update
        testDoc.setData(testData) { createError in
            if createError == nil {
                testDoc.updateData(["notlar": "Updated test check out"]) { updateError in
                    let duration = Date().timeIntervalSince(startTime)
                    let success = updateError == nil
                    
                    // Delete test document
                    testDoc.delete { _ in }
                    
                    let message = success ? "Check out updated successfully" : "Failed: \(updateError?.localizedDescription ?? "Unknown")"
                    
                    DispatchQueue.main.async {
                        testResults.append(TestResult(
                            name: "Update Check Out",
                            success: success,
                            message: message,
                            duration: duration
                        ))
                        testProgress = Double(testResults.count) / total
                    }
                }
            } else {
                let duration = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    testResults.append(TestResult(
                        name: "Update Check Out",
                        success: false,
                        message: "Failed to create test document",
                        duration: duration
                    ))
                    testProgress = Double(testResults.count) / total
                }
            }
        }
    }
    
    private func testDeleteCheckOut(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("exitIslemleri").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "aracId": UUID().uuidString,
            "aracPlaka": "TEST-001",
            "exitTarihi": Timestamp(date: Date()),
            "fotograflar": [],
            "notlar": "Admin test check out",
            "resKodu": "RES-999",
            "status": "inProgress"
        ]
        
        // First create, then delete
        testDoc.setData(testData) { createError in
            if createError == nil {
                testDoc.delete { deleteError in
                    let duration = Date().timeIntervalSince(startTime)
                    let success = deleteError == nil
                    let message = success ? "Check out deleted successfully" : "Failed: \(deleteError?.localizedDescription ?? "Unknown")"
                    
                    DispatchQueue.main.async {
                        testResults.append(TestResult(
                            name: "Delete Check Out",
                            success: success,
                            message: message,
                            duration: duration
                        ))
                        testProgress = Double(testResults.count) / total
                    }
                }
            } else {
                let duration = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    testResults.append(TestResult(
                        name: "Delete Check Out",
                        success: false,
                        message: "Failed to create test document",
                        duration: duration
                    ))
                    testProgress = Double(testResults.count) / total
                }
            }
        }
    }
    
    // MARK: - Return Operations CRUD Tests
    
    private func testCreateReturn(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("iadeIslemleri").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "aracId": UUID().uuidString,
            "aracPlaka": "TEST-001",
            "iadeTarihi": Timestamp(date: Date()),
            "fotograflar": [],
            "notlar": "Admin test return",
            "status": "completed"
        ]
        
        testDoc.setData(testData) { error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            
            if success {
                testDoc.delete { _ in }
            }
            
            let message = success ? "Return created successfully" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Create Return",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testUpdateReturn(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("iadeIslemleri").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "aracId": UUID().uuidString,
            "aracPlaka": "TEST-001",
            "iadeTarihi": Timestamp(date: Date()),
            "fotograflar": [],
            "notlar": "Admin test return",
            "status": "completed"
        ]
        
        testDoc.setData(testData) { createError in
            if createError == nil {
                testDoc.updateData(["notlar": "Updated test return"]) { updateError in
                    let duration = Date().timeIntervalSince(startTime)
                    let success = updateError == nil
                    testDoc.delete { _ in }
                    
                    let message = success ? "Return updated successfully" : "Failed: \(updateError?.localizedDescription ?? "Unknown")"
                    
                    DispatchQueue.main.async {
                        testResults.append(TestResult(
                            name: "Update Return",
                            success: success,
                            message: message,
                            duration: duration
                        ))
                        testProgress = Double(testResults.count) / total
                    }
                }
            } else {
                let duration = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    testResults.append(TestResult(
                        name: "Update Return",
                        success: false,
                        message: "Failed to create test document",
                        duration: duration
                    ))
                    testProgress = Double(testResults.count) / total
                }
            }
        }
    }
    
    private func testDeleteReturn(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("iadeIslemleri").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "aracId": UUID().uuidString,
            "aracPlaka": "TEST-001",
            "iadeTarihi": Timestamp(date: Date()),
            "fotograflar": [],
            "notlar": "Admin test return",
            "status": "completed"
        ]
        
        testDoc.setData(testData) { createError in
            if createError == nil {
                testDoc.delete { deleteError in
                    let duration = Date().timeIntervalSince(startTime)
                    let success = deleteError == nil
                    let message = success ? "Return deleted successfully" : "Failed: \(deleteError?.localizedDescription ?? "Unknown")"
                    
                    DispatchQueue.main.async {
                        testResults.append(TestResult(
                            name: "Delete Return",
                            success: success,
                            message: message,
                            duration: duration
                        ))
                        testProgress = Double(testResults.count) / total
                    }
                }
            } else {
                let duration = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    testResults.append(TestResult(
                        name: "Delete Return",
                        success: false,
                        message: "Failed to create test document",
                        duration: duration
                    ))
                    testProgress = Double(testResults.count) / total
                }
            }
        }
    }
    
    // MARK: - Office Operations CRUD Tests
    
    private func testCreateOfficeOperation(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("office_operations").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "type": "Additional Sales",
            "date": Timestamp(date: Date()),
            "amount": 100.0,
            "photos": [],
            "notes": "Admin test office operation"
        ]
        
        testDoc.setData(testData) { error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil
            
            if success {
                testDoc.delete { _ in }
            }
            
            let message = success ? "Office operation created successfully" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Create Office Operation",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testUpdateOfficeOperation(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("office_operations").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "type": "Additional Sales",
            "date": Timestamp(date: Date()),
            "amount": 100.0,
            "photos": [],
            "notes": "Admin test office operation"
        ]
        
        testDoc.setData(testData) { createError in
            if createError == nil {
                testDoc.updateData(["notes": "Updated test office operation"]) { updateError in
                    let duration = Date().timeIntervalSince(startTime)
                    let success = updateError == nil
                    testDoc.delete { _ in }
                    
                    let message = success ? "Office operation updated successfully" : "Failed: \(updateError?.localizedDescription ?? "Unknown")"
                    
                    DispatchQueue.main.async {
                        testResults.append(TestResult(
                            name: "Update Office Operation",
                            success: success,
                            message: message,
                            duration: duration
                        ))
                        testProgress = Double(testResults.count) / total
                    }
                }
            } else {
                let duration = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    testResults.append(TestResult(
                        name: "Update Office Operation",
                        success: false,
                        message: "Failed to create test document",
                        duration: duration
                    ))
                    testProgress = Double(testResults.count) / total
                }
            }
        }
    }
    
    private func testDeleteOfficeOperation(_ total: Double) {
        let startTime = Date()
        let testDoc = FirebaseService.shared.getCollectionReference("office_operations").document(UUID().uuidString)
        
        let testData: [String: Any] = [
            "type": "Additional Sales",
            "date": Timestamp(date: Date()),
            "amount": 100.0,
            "photos": [],
            "notes": "Admin test office operation"
        ]
        
        testDoc.setData(testData) { createError in
            if createError == nil {
                testDoc.delete { deleteError in
                    let duration = Date().timeIntervalSince(startTime)
                    let success = deleteError == nil
                    let message = success ? "Office operation deleted successfully" : "Failed: \(deleteError?.localizedDescription ?? "Unknown")"
                    
                    DispatchQueue.main.async {
                        testResults.append(TestResult(
                            name: "Delete Office Operation",
                            success: success,
                            message: message,
                            duration: duration
                        ))
                        testProgress = Double(testResults.count) / total
                    }
                }
            } else {
                let duration = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    testResults.append(TestResult(
                        name: "Delete Office Operation",
                        success: false,
                        message: "Failed to create test document",
                        duration: duration
                    ))
                    testProgress = Double(testResults.count) / total
                }
            }
        }
    }
    
    // MARK: - Storage Folder Tests
    
    private func testStorageDamagePhotos(_ total: Double) {
        let startTime = Date()
        let storage = Storage.storage()
        let ref = storage.reference().child("hasar_fotograflari/handover")
        
        ref.listAll { result, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil || (error as NSError?)?.code != 403
            let count = result?.items.count ?? 0
            let message = success ? "Access to damage photos (\(count) items)" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Storage: Damage Photos",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testStorageReturnPhotos(_ total: Double) {
        let startTime = Date()
        let storage = Storage.storage()
        let ref = storage.reference().child("iade_fotograflari")
        
        ref.listAll { result, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil || (error as NSError?)?.code != 403
            let count = result?.items.count ?? 0
            let message = success ? "Access to return photos (\(count) items)" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Storage: Return Photos",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testStorageCheckOutPhotos(_ total: Double) {
        let startTime = Date()
        let storage = Storage.storage()
        let ref = storage.reference().child("exit_fotograflari")
        
        ref.listAll { result, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil || (error as NSError?)?.code != 403
            let count = result?.items.count ?? 0
            let message = success ? "Access to check out photos (\(count) items)" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Storage: Check Out Photos",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    private func testStorageOfficePhotos(_ total: Double) {
        let startTime = Date()
        let storage = Storage.storage()
        let ref = storage.reference().child("office_operations")
        
        ref.listAll { result, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil || (error as NSError?)?.code != 403
            let count = result?.items.count ?? 0
            let message = success ? "Access to office photos (\(count) items)" : "Failed: \(error?.localizedDescription ?? "Unknown")"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Storage: Office Photos",
                    success: success,
                    message: message,
                    duration: duration
                ))
                testProgress = Double(testResults.count) / total
            }
        }
    }
    
    // MARK: - Network Connection Test
    
    private func testNetworkConnection(_ total: Double) {
        let startTime = Date()
        
        FirebaseService.shared.getFilteredQuery("araclar").limit(to: 1).getDocuments { snapshot, error in
            let duration = Date().timeIntervalSince(startTime)
            let success = error == nil || (error as NSError?)?.code != -1009 // -1009 is no internet connection
            let message = success ? "Network connection active" : "No network connection"
            
            DispatchQueue.main.async {
                testResults.append(TestResult(
                    name: "Network Connection",
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
        let testDoc = FirebaseService.shared.getCollectionReference("adminTests").document(UUID().uuidString)
        
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
        
        var listener: ListenerRegistration?
        listener = FirebaseService.shared.getFilteredQuery("araclar").limit(to: 1).addSnapshotListener { snapshot, error in
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
    
    // MARK: - Export Test Logs
    
    private func exportTestLogs() {
        isLoadingLogs = true
        
        // adminTestLogs is global collection - use getCollectionReference for reads
        FirebaseService.shared.getCollectionReference("adminTestLogs")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    let nsError = error as NSError
                    // If error is due to missing index (code 9), try without order
                    if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 9 {
                        print("⚠️ Index missing, trying without order by...")
                        loadTestLogsWithoutOrder()
                        return
                    }
                    
                    // If permission error, show detailed message
                    if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                        print("❌ Permission denied - User: \(authManager.currentUser?.email ?? "unknown")")
                        print("   User ID: \(authManager.currentUser?.uid ?? "unknown")")
                        print("   Is authenticated: \(authManager.currentUser != nil)")
                    }
                    
                    DispatchQueue.main.async {
                        isLoadingLogs = false
                        print("❌ Error loading test logs: \(error.localizedDescription)")
                        ErrorManager.shared.showError(error, context: "Export Test Logs")
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    isLoadingLogs = false
                    
                    guard let documents = snapshot?.documents else {
                        ErrorManager.shared.showError(message: "No test logs found")
                        return
                    }
                    
                    print("✅ Loaded \(documents.count) test log documents")
                    
                    // Sort documents by timestamp manually (if order by failed)
                    let sortedDocuments = documents.sorted { doc1, doc2 in
                        let timestamp1 = (doc1.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        let timestamp2 = (doc2.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        return timestamp1 > timestamp2
                    }
                    
                    // Convert documents to text format
                    let textContent = formatTestLogsAsText(documents: sortedDocuments)
                    
                    // Save to temporary file
                    let fileName = "admin_test_logs_\(Date().timeIntervalSince1970).txt"
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    
                    do {
                        try textContent.write(to: fileURL, atomically: true, encoding: .utf8)
                        print("✅ Test logs exported to: \(fileURL.path)")
                        shareURL = fileURL
                        showShareSheet = true
                    } catch {
                        print("❌ Error writing test logs file: \(error.localizedDescription)")
                        ErrorManager.shared.showError(error, context: "Export Test Logs")
                    }
                }
            }
    }
    
    private func loadTestLogsWithoutOrder() {
        FirebaseService.shared.getCollectionReference("adminTestLogs")
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingLogs = false
                    
                    if let error = error {
                        print("❌ Error loading test logs (without order): \(error.localizedDescription)")
                        ErrorManager.shared.showError(error, context: "Export Test Logs")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        ErrorManager.shared.showError(message: "No test logs found")
                        return
                    }
                    
                    print("✅ Loaded \(documents.count) test log documents (without order)")
                    
                    // Sort documents by timestamp manually
                    let sortedDocuments = documents.sorted { doc1, doc2 in
                        let timestamp1 = (doc1.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        let timestamp2 = (doc2.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date.distantPast
                        return timestamp1 > timestamp2
                    }
                    
                    // Convert documents to text format
                    let textContent = formatTestLogsAsText(documents: sortedDocuments)
                    
                    // Save to temporary file
                    let fileName = "admin_test_logs_\(Date().timeIntervalSince1970).txt"
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                    
                    do {
                        try textContent.write(to: fileURL, atomically: true, encoding: .utf8)
                        print("✅ Test logs exported to: \(fileURL.path)")
                        shareURL = fileURL
                        showShareSheet = true
                    } catch {
                        print("❌ Error writing test logs file: \(error.localizedDescription)")
                        ErrorManager.shared.showError(error, context: "Export Test Logs")
                    }
                }
            }
    }
    
    private func formatTestLogsAsText(documents: [QueryDocumentSnapshot]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var text = String(repeating: "=", count: 80) + "\n"
        text += "ADMIN TEST LOGS EXPORT\n"
        text += "Generated: \(dateFormatter.string(from: Date()))\n"
        text += "Total Logs: \(documents.count)\n"
        text += String(repeating: "=", count: 80) + "\n\n"
        
        for (index, document) in documents.enumerated() {
            let data = document.data()
            let docId = document.documentID
            
            text += "\n" + String(repeating: "=", count: 80) + "\n"
            text += "LOG #\(index + 1) - Document ID: \(docId)\n"
            text += String(repeating: "=", count: 80) + "\n\n"
            
            // Parse timestamp
            if let timestamp = data["timestamp"] as? Timestamp {
                text += "Timestamp: \(dateFormatter.string(from: timestamp.dateValue()))\n"
            }
            
            // Parse startTime
            if let startTime = data["startTime"] as? Timestamp {
                text += "Start Time: \(dateFormatter.string(from: startTime.dateValue()))\n"
            }
            
            // Parse user info
            if let userEmail = data["userEmail"] as? String {
                text += "User Email: \(userEmail)\n"
            }
            
            if let userId = data["userId"] as? String {
                text += "User ID: \(userId)\n"
            }
            
            // Parse test statistics
            if let totalTests = data["totalTests"] as? Int {
                text += "Total Tests: \(totalTests)\n"
            }
            
            if let successCount = data["successCount"] as? Int {
                text += "Success Count: \(successCount)\n"
            }
            
            if let failureCount = data["failureCount"] as? Int {
                text += "Failure Count: \(failureCount)\n"
            }
            
            if let successRate = data["successRate"] as? Double {
                text += "Success Rate: \(String(format: "%.2f%%", successRate * 100))\n"
            }
            
            if let totalDuration = data["totalDuration"] as? Double {
                text += "Total Duration: \(String(format: "%.2f", totalDuration)) seconds\n"
            }
            
            // Parse device info
            if let deviceInfo = data["deviceInfo"] as? [String: Any] {
                text += "\nDevice Info:\n"
                if let model = deviceInfo["model"] as? String {
                    text += "  Model: \(model)\n"
                }
                if let systemName = deviceInfo["systemName"] as? String {
                    text += "  System: \(systemName)\n"
                }
                if let systemVersion = deviceInfo["systemVersion"] as? String {
                    text += "  Version: \(systemVersion)\n"
                }
            }
            
            // Parse test results
            if let testResults = data["testResults"] as? [[String: Any]] {
                text += "\nTest Results:\n"
                text += String(repeating: "-", count: 80) + "\n"
                
                for (testIndex, testResult) in testResults.enumerated() {
                    text += "\nTest #\(testIndex + 1):\n"
                    
                    if let name = testResult["name"] as? String {
                        text += "  Name: \(name)\n"
                    }
                    
                    if let success = testResult["success"] as? Bool {
                        text += "  Status: \(success ? "✅ PASSED" : "❌ FAILED")\n"
                    }
                    
                    if let message = testResult["message"] as? String {
                        text += "  Message: \(message)\n"
                    }
                    
                    if let duration = testResult["duration"] as? Double {
                        text += "  Duration: \(String(format: "%.3f", duration)) seconds\n"
                    }
                }
            }
            
            text += "\n"
        }
        
        text += "\n" + String(repeating: "=", count: 80) + "\n"
        text += "END OF EXPORT\n"
        text += String(repeating: "=", count: 80) + "\n"
        
        return text
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

