import SwiftUI
import FirebaseFirestore

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
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
            
        case .weekly:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, end)
            
        case .monthly:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)
            
        case .custom:
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
            return (start, end)
        }
    }
    
    private func fetchSessions(from startDate: Date, to endDate: Date) async throws -> [ShuttleSession] {
        let snapshot = try await Firestore.firestore()
            .collection("shuttleSessions")
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
            
            var yPosition: CGFloat = 50
            
            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.systemCyan
            ]
            "Shuttle Report".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            // Date Range
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let subtitleFont = UIFont.systemFont(ofSize: 14)
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: subtitleFont,
                .foregroundColor: UIColor.gray
            ]
            let dateRangeText = "\(dateFormatter.string(from: dateRange.start)) - \(dateFormatter.string(from: dateRange.end))"
            dateRangeText.draw(at: CGPoint(x: 50, y: yPosition), withAttributes: subtitleAttributes)
            yPosition += 30
            
            // Summary
            let totalSessions = sessions.count
            let totalCustomers = sessions.reduce(0) { $0 + $1.totalCustomers }
            let totalTrips = sessions.reduce(0) { $0 + $1.entries.count }
            
            let summaryFont = UIFont.systemFont(ofSize: 12)
            let summaryAttributes: [NSAttributedString.Key: Any] = [
                .font: summaryFont,
                .foregroundColor: UIColor.darkGray
            ]
            
            "Total Sessions: \(totalSessions)".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: summaryAttributes)
            "Total Customers: \(totalCustomers)".draw(at: CGPoint(x: 200, y: yPosition), withAttributes: summaryAttributes)
            "Total Trips: \(totalTrips)".draw(at: CGPoint(x: 350, y: yPosition), withAttributes: summaryAttributes)
            yPosition += 30
            
            // Draw line
            context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
            context.cgContext.setLineWidth(1)
            context.cgContext.move(to: CGPoint(x: 50, y: yPosition))
            context.cgContext.addLine(to: CGPoint(x: 545, y: yPosition))
            context.cgContext.strokePath()
            yPosition += 20
            
            // Table Header
            let headerFont = UIFont.boldSystemFont(ofSize: 12)
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: UIColor.white
            ]
            
            // Header background
            context.cgContext.setFillColor(UIColor.systemCyan.cgColor)
            context.cgContext.fill(CGRect(x: 50, y: yPosition, width: 495, height: 25))
            
            "Date".draw(at: CGPoint(x: 60, y: yPosition + 5), withAttributes: headerAttributes)
            "Driver".draw(at: CGPoint(x: 180, y: yPosition + 5), withAttributes: headerAttributes)
            "Customers".draw(at: CGPoint(x: 320, y: yPosition + 5), withAttributes: headerAttributes)
            "Trips".draw(at: CGPoint(x: 420, y: yPosition + 5), withAttributes: headerAttributes)
            "Duration".draw(at: CGPoint(x: 480, y: yPosition + 5), withAttributes: headerAttributes)
            yPosition += 30
            
            // Table Rows
            let rowFont = UIFont.systemFont(ofSize: 10)
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: rowFont,
                .foregroundColor: UIColor.darkGray
            ]
            
            for session in sessions {
                // Check if new page is needed
                if yPosition > 750 {
                    context.beginPage()
                    yPosition = 50
                }
                
                let sessionDate = dateFormatter.string(from: session.startTime)
                sessionDate.draw(at: CGPoint(x: 60, y: yPosition), withAttributes: rowAttributes)
                session.driverName.draw(at: CGPoint(x: 180, y: yPosition), withAttributes: rowAttributes)
                "\(session.totalCustomers)".draw(at: CGPoint(x: 340, y: yPosition), withAttributes: rowAttributes)
                "\(session.entries.count)".draw(at: CGPoint(x: 430, y: yPosition), withAttributes: rowAttributes)
                session.duration.draw(at: CGPoint(x: 480, y: yPosition), withAttributes: rowAttributes)
                
                yPosition += 20
            }
            
            // Footer
            yPosition += 30
            let footerFont = UIFont.italicSystemFont(ofSize: 10)
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: UIColor.gray
            ]
            "Generated on \(dateFormatter.string(from: Date()))".draw(at: CGPoint(x: 50, y: yPosition), withAttributes: footerAttributes)
        }
        
        // Save PDF
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfPath = documentsPath.appendingPathComponent("ShuttleReport_\(reportType.rawValue)_\(Date().timeIntervalSince1970).pdf")
        
        do {
            try data.write(to: pdfPath)
            print("✅ PDF saved: \(pdfPath)")
            
            // Save to Shuttle Reports collection
            saveReportMetadata(url: pdfPath, sessions: sessions, dateRange: dateRange)
            
            return pdfPath
        } catch {
            print("❌ Error saving PDF: \(error)")
            return nil
        }
    }
    
    private func saveReportMetadata(url: URL, sessions: [ShuttleSession], dateRange: (start: Date, end: Date)) {
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
        
        Firestore.firestore()
            .collection("shuttleReports")
            .addDocument(data: report) { error in
                if let error = error {
                    print("❌ Error saving report metadata: \(error)")
                } else {
                    print("✅ Report metadata saved")
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

