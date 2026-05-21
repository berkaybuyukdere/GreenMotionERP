import SwiftUI
import FirebaseAuth

// MARK: - Hub card

struct PoliceReportsOfficeCard: View {
    let selectedMonth: Date
    let reports: [PoliceReport]
    @Environment(\.colorScheme) private var colorScheme

    private var monthRange: (start: Date, end: Date) {
        CHFleetHubCardSparkline.monthRange(for: selectedMonth)
    }

    private var monthReports: [PoliceReport] {
        let r = monthRange
        return reports.filter { $0.reportDate >= r.start && $0.reportDate <= r.end }
    }

    private var count: Int { monthReports.count }
    private var pendingCount: Int { monthReports.filter { !$0.isProcessed }.count }

    private var sparklineData: [Double] {
        let pairs = monthReports.map { (date: $0.reportDate, amount: 1.0) }
        return CHFleetHubCardSparkline.amountBuckets(month: selectedMonth, datedAmounts: pairs)
    }

    private var sparklineColor: Color {
        CHFleetHubCardSparkline.trendColor(for: sparklineData)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }

    var body: some View {
        let sData = sparklineData
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            if sData.count > 1 {
                SparklineChart(data: sData, color: sparklineColor)
                    .frame(height: 30)
            } else {
                Color.clear.frame(height: 30)
            }
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            Text("Police Reports".localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            if pendingCount > 0 {
                Text("\(pendingCount) \("pending".localized)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("\(count) \("entries".localized)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.systemGray4), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - List

struct PoliceReportsListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let selectedMonth: Date

    @State private var listMonth: Date
    @State private var showMonthPicker = false
    @State private var searchQuery = ""
    @State private var showAdd = false
    @State private var editing: PoliceReport?
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @State private var pendingDelete: PoliceReport?

    init(selectedMonth: Date) {
        self.selectedMonth = selectedMonth
        _listMonth = State(initialValue: selectedMonth)
    }

    private var dateRange: (start: Date, end: Date) {
        CHFleetHubCardSparkline.monthRange(for: listMonth)
    }

    private var baseFiltered: [PoliceReport] {
        let r = dateRange
        return viewModel.policeReports
            .filter { $0.reportDate >= r.start && $0.reportDate <= r.end }
            .sorted { $0.reportDate > $1.reportDate }
    }

    private var filtered: [PoliceReport] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return baseFiltered }
        return baseFiltered.filter { TrafficAccidentContract.matchesRESSearch(query: q, resField: $0.resCode, notes: $0.notes) }
    }

    private var pendingCount: Int { baseFiltered.filter { !$0.isProcessed }.count }

    private var monthDisplayText: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: listMonth)
    }

    var body: some View {
        List {
            Section {
                Button { showMonthPicker = true } label: {
                    Label(monthDisplayText, systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    Text("Total".localized)
                    Text("\(baseFiltered.count)").fontWeight(.bold)
                    Spacer()
                    Text("Pending".localized)
                        .foregroundStyle(.secondary)
                    Text("\(pendingCount)")
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            }

            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search RES or RES-12345".localized, text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("\("Police Reports".localized) (\(filtered.count))") {
                if filtered.isEmpty {
                    Text("No police reports this month".localized).foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { report in
                        HStack(alignment: .center, spacing: 8) {
                            Button {
                                editing = report
                            } label: {
                                PoliceReportRow(report: report) {
                                    guard !report.photos.isEmpty else { return }
                                    photoGallerySession = PhotoGalleryFullScreenSession(urlStrings: report.photos, startIndex: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                viewModel.togglePoliceReportProcessed(report)
                            } label: {
                                Image(systemName: report.isProcessed ? "checkmark.shield.fill" : "shield.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(report.isProcessed ? Color.green : Color.orange)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        (report.isProcessed ? Color.green : Color.orange).opacity(0.18)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                report.isProcessed
                                    ? "Mark as pending".localized
                                    : "Mark as processed".localized
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = report
                            } label: {
                                Label("Delete".localized, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Police Reports".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add police report".localized)
            }
        }
        .onChange(of: selectedMonth) { _, m in listMonth = m }
        .sheet(isPresented: $showMonthPicker) { monthPickerSheet }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                PoliceReportEditorSheet(mode: .create)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(item: $editing) { report in
            NavigationStack {
                PoliceReportEditorSheet(mode: .edit(report))
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .fullScreenCover(item: $photoGallerySession) { session in
            if let urls = session.urlStrings {
                NativePhotoGalleryView(urlStrings: urls, initialIndex: session.startIndex)
            }
        }
        .alert("Delete this report?".localized, isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel".localized, role: .cancel) { pendingDelete = nil }
            Button("Delete".localized, role: .destructive) {
                if let r = pendingDelete { viewModel.policeReportSil(r) }
                pendingDelete = nil
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var monthPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Select Month".localized, selection: $listMonth, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Spacer()
            }
            .padding()
            .navigationTitle("Select Month".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done".localized) { showMonthPicker = false }
                }
            }
        }
    }
}

private struct PoliceReportRow: View {
    let report: PoliceReport
    var onPreviewPhotos: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(report.displayResCode)
                    .font(.headline.weight(.semibold))
                if !report.notes.isEmpty {
                    Text(report.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let name = report.createdByName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, !name.contains("@") {
                    Text("\("Recorded by".localized) \(name)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    Label(report.reportDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !report.photos.isEmpty {
                        Button(action: onPreviewPhotos) {
                            Label("\(report.photos.count)", systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Editor

struct PoliceReportEditorSheet: View {
    enum Mode: Hashable {
        case create
        case edit(PoliceReport)
    }

    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var resDigits = ""
    @State private var reportDate = Date()
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var uploadedPhotoURLs: [String] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @State private var showSaveOverlay = false

    private var existing: PoliceReport? {
        if case .edit(let r) = mode { return r }
        return nil
    }

    private var canSave: Bool {
        !TrafficAccidentContract.resDigits(from: resDigits).isEmpty
            && (selectedImages.count + uploadedPhotoURLs.count) > 0
            && !isSaving
    }

    var body: some View {
        ZStack {
            Form {
                Section("Report".localized) {
                    HStack(spacing: 10) {
                        Image(systemName: "number.square.fill").foregroundStyle(.blue).frame(width: 22)
                        Text("RES-").foregroundStyle(.secondary)
                        TextField("digits only".localized, text: $resDigits)
                            .keyboardType(.numberPad)
                            .onChange(of: resDigits) { _, v in
                                let d = v.filter(\.isNumber)
                                if d != v { resDigits = d }
                            }
                    }
                    DatePicker("Report date".localized, selection: $reportDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Notes (optional)".localized, text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Photos".localized) {
                    photoSection
                    Text("Add at least one document photo.".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Save".localized) {
                        Task { await saveTapped() }
                    }
                    .disabled(!canSave)
                }
            }
            .blur(radius: showSaveOverlay ? 6 : 0)
            .allowsHitTesting(!showSaveOverlay)

            if showSaveOverlay {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Saving...".localized).font(.headline)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .navigationTitle(modeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .onAppear {
            if let e = existing {
                resDigits = TrafficAccidentContract.resDigits(from: e.resCode)
                reportDate = e.reportDate
                notes = e.notes
                uploadedPhotoURLs = e.photos
            }
        }
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $showImagePicker) { ImagePicker(selectedImages: $selectedImages) }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let img = capturedImage {
                selectedImages.append(img)
                capturedImage = nil
            }
        }) {
            OfficeCameraView(capturedImage: $capturedImage)
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "Add police report".localized
        case .edit: return "Edit police report".localized
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        if !uploadedPhotoURLs.isEmpty || !selectedImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(uploadedPhotoURLs.enumerated()), id: \.offset) { i, _ in
                        photoThumbRemote(index: i)
                    }
                    ForEach(selectedImages.indices, id: \.self) { i in
                        photoThumbLocal(index: i)
                    }
                }
            }
        }
        Button { showImagePicker = true } label: {
            Label("Choose from Gallery".localized, systemImage: "photo.on.rectangle")
        }
        Button { showCamera = true } label: {
            Label("Take Photo".localized, systemImage: "camera")
        }
    }

    private func photoThumbRemote(index: Int) -> some View {
        let url = uploadedPhotoURLs[index]
        return ZStack(alignment: .topTrailing) {
            AsyncImageView(urlString: url) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button {
                uploadedPhotoURLs.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .background(Color.white.clipShape(Circle()))
            }
            .padding(4)
        }
    }

    private func photoThumbLocal(index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: selectedImages[index])
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
                selectedImages.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .background(Color.white.clipShape(Circle()))
            }
            .padding(4)
        }
    }

    @MainActor
    private func saveTapped() async {
        let canon = TrafficAccidentContract.canonicalRES(from: resDigits)
        guard !canon.isEmpty else { return }

        isSaving = true
        showSaveOverlay = true

        var urls = uploadedPhotoURLs
        for img in selectedImages {
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/police_reports/\(UUID().uuidString).jpg"
            if let url = try? await ImageUploadActor.shared.upload(image: img, path: path) {
                urls.append(url)
            }
        }

        guard !urls.isEmpty else {
            isSaving = false
            showSaveOverlay = false
            ToastManager.shared.show("Add at least one document photo.".localized, type: .warning)
            return
        }

        let uid = Auth.auth().currentUser?.uid
        let recorder = authManager.userProfile?.nameOrUsernameForAudit
            ?? Auth.auth().currentUser?.displayName

        switch mode {
        case .create:
            var report = PoliceReport(
                photos: urls,
                resCode: canon,
                reportDate: reportDate,
                createdAt: Date(),
                franchiseId: FirebaseService.shared.currentFranchiseId,
                createdBy: uid,
                createdByName: recorder,
                isProcessed: false,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            report.documentId = report.id.uuidString
            viewModel.policeReportEkle(report)
        case .edit(var report):
            report.resCode = canon
            report.reportDate = reportDate
            report.photos = urls
            report.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.policeReportGuncelle(report)
        }

        HapticManager.shared.success()
        try? await Task.sleep(nanoseconds: 500_000_000)
        isSaving = false
        showSaveOverlay = false
        dismiss()
    }
}
