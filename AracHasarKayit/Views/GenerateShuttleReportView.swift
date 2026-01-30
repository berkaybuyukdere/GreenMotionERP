import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import UIKit

/// Generate Shuttle Report with date filtering
struct GenerateShuttleReportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var reportType: ReportType = .daily
    @State private var selectedDate = Date()
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isGenerating = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    
    // Demo user email (backward compatibility)
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
    
    enum ReportType: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        case custom = "Custom Range"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Report Type") {
                    Picker("Type", selection: $reportType) {
                        ForEach(ReportType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Date Selection") {
                    switch reportType {
                    case .daily:
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    case .weekly:
                        DatePicker("Week Starting", selection: $selectedDate, displayedComponents: .date)
                    case .monthly:
                        DatePicker("Month", selection: $selectedDate, displayedComponents: .date)
                    case .custom:
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }
                
                Section {
                    Button {
                        generateReport()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isGenerating ? "Generating..." : "Generate PDF Report")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isGenerating)
                }
            }
            .navigationTitle("Generate Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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
    
    private func generateReport() {
        isGenerating = true
        
        Task {
            do {
                // Calculate date range based on report type
                let dateRange = getDateRange()
                
                // Fetch sessions in date range
                let sessions = try await fetchSessions(from: dateRange.start, to: dateRange.end)
                
                // Generate PDF
                let url = generatePDF(sessions: sessions, dateRange: dateRange)
                
                await MainActor.run {
                    isGenerating = false
                    
                    if let url = url {
                        shareURL = url
                        showShareSheet = true
                    }
                }
            } catch {
                print("❌ Error generating report: \(error)")
                await MainActor.run {
                    isGenerating = false
                }
            }
        }
    }
    
    private func getDateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        
        switch reportType {
        case .daily:
            let start = calendar.startOfDay(for: selectedDate)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return (start, calendar.startOfDay(for: Date()))
            }
            return (start, end)
            
        case .weekly:
            guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                return (calendar.startOfDay(for: selectedDate), calendar.startOfDay(for: Date()))
            }
            return (start, end)
            
        case .monthly:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return (calendar.startOfDay(for: selectedDate), calendar.startOfDay(for: Date()))
            }
            return (start, end)
            
        case .custom:
            let start = calendar.startOfDay(for: startDate)
            let endDateStart = calendar.startOfDay(for: endDate)
            guard let end = calendar.date(byAdding: .day, value: 1, to: endDateStart) else {
                return (start, calendar.startOfDay(for: Date()))
            }
            return (start, end)
        }
    }
    
    private func fetchSessions(from startDate: Date, to endDate: Date) async throws -> [ShuttleSession] {
        let snapshot = try await getCollectionReference("shuttleSessions")
            .whereField("startTime", isGreaterThanOrEqualTo: Timestamp(date: startDate))
            .whereField("startTime", isLessThan: Timestamp(date: endDate))
            .order(by: "startTime", descending: false)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: ShuttleSession.self)
        }
    }
    
    private func generatePDF(sessions: [ShuttleSession], dateRange: (start: Date, end: Date)) -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "Green Motion Shuttle",
            kCGPDFContextAuthor: "Admin",
            kCGPDFContextTitle: "Shuttle Report - \(reportType.rawValue)"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            let ctx = context.cgContext
            
            // MARK: - SWISS DESIGN HEADER (Minimal, no colors)
            var yPosition: CGFloat = 60
            
            // Company Name - Bold Helvetica
            let companyName = "GREEN MOTION AG"
            let companyFont = SwissPDFHelper.helveticaBold(size: 18)
            companyName.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: companyFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 25
            
            // Subtitle - Thin Helvetica
            let subtitle = "ZÜRICH • SWITZERLAND"
            let subtitleFont = SwissPDFHelper.helveticaThin(size: 9)
            subtitle.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: subtitleFont, .foregroundColor: SwissPDFHelper.mediumGray])
            yPosition += 40
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // Title
            let titleFont = SwissPDFHelper.helveticaBold(size: 24)
            "Shuttle Report".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: titleFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 35
            
            // Date Range
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let subtitleTextFont = SwissPDFHelper.helvetica(size: 10)
            let dateRangeText = "\(dateFormatter.string(from: dateRange.start)) - \(dateFormatter.string(from: dateRange.end))"
            dateRangeText.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: subtitleTextFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 25
            
            // Summary
            let totalSessions = sessions.count
            let totalCustomers = sessions.reduce(0) { $0 + $1.totalCustomers }
            let totalTrips = sessions.reduce(0) { $0 + $1.entries.count }
            
            let summaryFont = SwissPDFHelper.helvetica(size: 10)
            let summaryLabelFont = SwissPDFHelper.helveticaBold(size: 10)
            
            "Total Sessions:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryLabelFont, .foregroundColor: SwissPDFHelper.black])
            "\(totalSessions)".draw(at: CGPoint(x: 180, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            
            "Total Customers:".draw(at: CGPoint(x: 250, y: yPosition), withAttributes: [.font: summaryLabelFont, .foregroundColor: SwissPDFHelper.black])
            "\(totalCustomers)".draw(at: CGPoint(x: 380, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 20
            
            "Total Trips:".draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: summaryLabelFont, .foregroundColor: SwissPDFHelper.black])
            "\(totalTrips)".draw(at: CGPoint(x: 180, y: yPosition), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            yPosition += 30
            
            // Horizontal line separator
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition), to: CGPoint(x: pageRect.width - 60, y: yPosition), width: 0.5)
            yPosition += 30
            
            // Table Header - Bold, underlined
            let headerFont = SwissPDFHelper.helveticaBold(size: 9)
            let headerY = yPosition
            "DATE".draw(at: CGPoint(x: 60, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "DRIVER".draw(at: CGPoint(x: 180, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "CUSTOMERS".draw(at: CGPoint(x: 320, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "TRIPS".draw(at: CGPoint(x: 420, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            "DURATION".draw(at: CGPoint(x: 480, y: headerY), withAttributes: [.font: headerFont, .foregroundColor: SwissPDFHelper.black])
            
            // Underline header
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: headerY + 12), to: CGPoint(x: pageRect.width - 60, y: headerY + 12), width: 0.5)
            yPosition += 20
            
            // Table Rows
            let rowFont = SwissPDFHelper.helvetica(size: 9)
            
            for (index, session) in sessions.enumerated() {
                // Check if new page is needed
                if yPosition > 750 {
                    context.beginPage()
                    yPosition = 60
                }
                
                let sessionDate = dateFormatter.string(from: session.startTime)
                sessionDate.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                session.driverName.draw(at: CGPoint(x: 180, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                "\(session.totalCustomers)".draw(at: CGPoint(x: 340, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                "\(session.entries.count)".draw(at: CGPoint(x: 430, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                session.duration.draw(at: CGPoint(x: 480, y: yPosition), withAttributes: [.font: rowFont, .foregroundColor: SwissPDFHelper.black])
                
                // Thin separator line
                if index < sessions.count - 1 {
                    SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: yPosition + 12), to: CGPoint(x: pageRect.width - 60, y: yPosition + 12), width: 0.25)
                }
                
                yPosition += 18
            }
            
            // Footer
            let footerY = pageRect.height - 30
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 20), to: CGPoint(x: pageRect.width - 60, y: footerY - 20), width: 0.25)
            
            let footerFont = SwissPDFHelper.helveticaThin(size: 7)
            let footerText = "Green Motion AG • Zürich, Switzerland"
            footerText.draw(at: CGPoint(x: 60, y: footerY), withAttributes: [.font: footerFont, .foregroundColor: SwissPDFHelper.lightGray])
            "1".draw(at: CGPoint(x: pageRect.width - 80, y: footerY), withAttributes: [.font: footerFont, .foregroundColor: SwissPDFHelper.lightGray])
        }
        
        // Save PDF to temporary directory for sharing
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("ShuttleReport_\(reportType.rawValue)_\(Date().timeIntervalSince1970).pdf")
        
        do {
            try data.write(to: tempPath)
            print("✅ PDF saved: \(tempPath)")
            
            // Save to Shuttle Reports collection (use documents directory for metadata)
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let metadataPath = documentsPath.appendingPathComponent("ShuttleReport_\(reportType.rawValue)_\(Date().timeIntervalSince1970).pdf")
        
            // Also save a copy to documents for metadata
            try? data.write(to: metadataPath)
            saveReportMetadata(url: metadataPath, sessions: sessions, dateRange: dateRange)
            
            return tempPath
        } catch {
            print("❌ Error saving PDF: \(error)")
            return nil
        }
    }
    
    private func saveReportMetadata(url: URL, sessions: [ShuttleSession], dateRange: (start: Date, end: Date)) {
        Task {
            do {
        let report: [String: Any] = [
            "type": reportType.rawValue,
            "startDate": Timestamp(date: dateRange.start),
            "endDate": Timestamp(date: dateRange.end),
            "totalSessions": sessions.count,
            "totalCustomers": sessions.reduce(0) { $0 + $1.totalCustomers },
            "totalTrips": sessions.reduce(0) { $0 + $1.entries.count },
            "generatedAt": Timestamp(date: Date()),
            "pdfPath": url.path
        ]
        
                try await Firestore.firestore()
            .collection("shuttleReports")
                    .addDocument(data: report)
                
                    print("✅ Report metadata saved")
            } catch {
                print("❌ Error saving report metadata: \(error.localizedDescription)")
                // Non-blocking error - report generation succeeded, metadata save failed
                ErrorManager.shared.showError(error, context: "Save Report Metadata")
                }
            }
    }
}

// MARK: - Preview

struct GenerateShuttleReportView_Previews: PreviewProvider {
    static var previews: some View {
        GenerateShuttleReportView()
    }
}

