import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - Hub card (Office Operations grid)

struct TrafficAccidentContractsOfficeCard: View {
    let selectedMonth: Date
    let contracts: [TrafficAccidentContract]
    var canViewFinancials: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }

    private var monthContracts: [TrafficAccidentContract] {
        let r = monthRange
        return contracts.filter { $0.createdAt >= r.start && $0.createdAt <= r.end }
    }

    private var count: Int { monthContracts.count }

    private var unpaidSum: Double { TrafficAccidentContract.totalOutstanding(monthContracts) }

    private var paidSum: Double { TrafficAccidentContract.totalPaidCollected(monthContracts) }

    /// Same 4-bucket idea as `BigOfficeOperationCard` — contract **counts** per slice of the month.
    private var sparklineData: [Double] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: selectedMonth)
        guard let monthStart = calendar.date(from: comps),
              let daysInMonth = calendar.range(of: .day, in: .month, for: selectedMonth)?.count else { return [] }
        let buckets = 4
        let bucketSize = max(1, daysInMonth / buckets)
        return (0..<buckets).map { bucket in
            let bucketStart = calendar.date(byAdding: .day, value: bucket * bucketSize, to: monthStart)!
            let bucketEnd = calendar.date(byAdding: .day, value: min((bucket + 1) * bucketSize, daysInMonth), to: monthStart)!
            return Double(monthContracts.filter { $0.createdAt >= bucketStart && $0.createdAt < bucketEnd }.count)
        }
    }

    private var sparklineColor: Color {
        let data = sparklineData
        guard data.count >= 2 else { return .orange }
        let mid = data.count / 2
        let first = data.prefix(mid).reduce(0, +)
        let second = data.suffix(data.count - mid).reduce(0, +)
        return second >= first ? .green : .red
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
    }

    var body: some View {
        let sData = sparklineData
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "car.side.rear.and.collision.and.car.side.front")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                Spacer()
                if canViewFinancials {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
            }

            if sData.count > 1 {
                SparklineChart(data: sData, color: sparklineColor)
                    .frame(height: 30)
            }

            if canViewFinancials {
                Text(AppCurrency.format(unpaidSum))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.secondary)
            }

            Text("Traffic accident contracts".localized)
                .font(canViewFinancials ? .caption : .subheadline.weight(.semibold))
                .foregroundColor(canViewFinancials ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            if canViewFinancials {
                (Text("\(count) \("entries".localized) · \("Paid".localized) ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                + Text(AppCurrency.format(paidSum))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("\(count) \("entries".localized)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - List + edit

struct TrafficAccidentContractsListView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let selectedMonth: Date

    private var canViewFinancials: Bool {
        let role = authManager.userProfile?.role
        return role == .manager || role == .admin || role == .superadmin || role == .globaladmin
    }

    @State private var searchQuery = ""
    @State private var paidFilter: PaidFilter = .all
    @State private var editing: TrafficAccidentContract?
    @State private var showCreate = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var contractPhotoGallerySession: PhotoGalleryFullScreenSession?
    @State private var contractPendingDelete: TrafficAccidentContract?

    private enum PaidFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case paid = "Paid"
        var title: String { rawValue.localized }
    }

    private var monthDisplayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: selectedMonth)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59), to: monthStart) ?? Date()
        return (monthStart, monthEnd)
    }

    private var baseFiltered: [TrafficAccidentContract] {
        let range = dateRange
        return viewModel.trafficAccidentContracts.filter { c in
            c.createdAt >= range.start && c.createdAt <= range.end
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private var filtered: [TrafficAccidentContract] {
        baseFiltered.filter { c in
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let qDigits = TrafficAccidentContract.resDigits(from: q)
            let matchesSearch: Bool = {
                if q.isEmpty { return true }
                if c.displayResCode.localizedCaseInsensitiveContains(q) { return true }
                if !qDigits.isEmpty, c.displayResCode.contains(qDigits) { return true }
                return false
            }()
            let matchesPaid: Bool = {
                switch paidFilter {
                case .all: return true
                case .pending: return !c.isFullyPaid
                case .paid: return c.isFullyPaid
                }
            }()
            return matchesSearch && matchesPaid
        }
    }

    private var pendingCount: Int { baseFiltered.filter { !$0.isFullyPaid }.count }
    private var paidCount: Int { baseFiltered.filter(\.isFullyPaid).count }
    private var unpaidSum: Double { TrafficAccidentContract.totalOutstanding(baseFiltered) }
    private var paidSum: Double { TrafficAccidentContract.totalPaidCollected(baseFiltered) }

    var body: some View {
        List {
            analyticsSection

            Section {
                Picker("Payment filter".localized, selection: $paidFilter) {
                    ForEach(PaidFilter.allCases, id: \.self) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search RES (digits)".localized, text: $searchQuery)
                        .keyboardType(.numbersAndPunctuation)
                }
            }

            Section("\("Contracts".localized) (\(filtered.count))") {
                if filtered.isEmpty {
                    Text("No contracts this month".localized)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { contract in
                        TrafficAccidentContractRow(
                            contract: contract,
                            onTogglePaid: { togglePaid(contract) },
                            onOpenEditor: { editing = contract },
                            onPreviewPhotos: {
                                guard !contract.photos.isEmpty else { return }
                                contractPhotoGallerySession = PhotoGalleryFullScreenSession(urlStrings: contract.photos, startIndex: 0)
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                contractPendingDelete = contract
                            } label: {
                                Label("Delete".localized, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Traffic accident contracts".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Back".localized)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        exportPDF()
                    } label: {
                        Label("Generate PDF Report".localized, systemImage: "doc.fill")
                    }
                    .disabled(filtered.isEmpty || isExporting)

                    Button {
                        exportCSV()
                    } label: {
                        Label("Generate Excel Report".localized, systemImage: "tablecells.fill")
                    }
                    .disabled(filtered.isEmpty || isExporting)
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $editing) { c in
            NavigationStack {
                TrafficAccidentContractEditorView(mode: .edit(c))
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                TrafficAccidentContractEditorView(mode: .create)
                    .environmentObject(viewModel)
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .fullScreenCover(item: $contractPhotoGallerySession) { session in
            Group {
                if let urls = session.urlStrings {
                    NativePhotoGalleryView(urlStrings: urls, initialIndex: session.startIndex)
                } else if let imgs = session.images {
                    NativePhotoGalleryView(images: imgs, initialIndex: session.startIndex)
                }
            }
        }
        .alert("Delete this contract?".localized, isPresented: Binding(
            get: { contractPendingDelete != nil },
            set: { if !$0 { contractPendingDelete = nil } }
        )) {
            Button("Cancel".localized, role: .cancel) { contractPendingDelete = nil }
            Button("Delete".localized, role: .destructive) {
                if let c = contractPendingDelete {
                    viewModel.trafficAccidentContractSil(c)
                    contractPendingDelete = nil
                }
            }
        } message: {
            Text(contractPendingDelete?.displayResCode ?? "")
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var analyticsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(monthDisplayText, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TrafficContractStatPill(title: "Pending".localized, value: "\(pendingCount)", color: .orange)
                    TrafficContractStatPill(title: "Paid".localized, value: "\(paidCount)", color: .green)
                }

                if canViewFinancials {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total unpaid".localized).font(.caption).foregroundStyle(.secondary)
                            Text(AppCurrency.format(unpaidSum)).font(.headline.weight(.bold)).foregroundStyle(.orange)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Total paid".localized).font(.caption).foregroundStyle(.secondary)
                            Text(AppCurrency.format(paidSum)).font(.headline.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func togglePaid(_ contract: TrafficAccidentContract) {
        var u = contract
        if u.isFullyPaid {
            u.paidAmount = nil
        } else {
            u.paidAmount = u.amount
        }
        viewModel.trafficAccidentContractGuncelle(u)
        HapticManager.shared.medium()
    }

    private func exportPDF() {
        isExporting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let data = TrafficAccidentContractExporter.pdfData(
                contracts: filtered,
                franchiseName: viewModel.franchiseName,
                monthLabel: monthDisplayText
            )
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fd = DateFormatter()
            fd.locale = Locale(identifier: "en_US_POSIX")
            fd.dateFormat = "yyyy-MM-dd"
            let tag = filtered.map(\.createdAt).max().map { fd.string(from: $0) } ?? "nodate"
            let url = documentsPath.appendingPathComponent("TrafficAccidentContracts_\(tag).pdf")
            do {
                try data.write(to: url)
                shareURL = url
                showShareSheet = true
            } catch {
                ErrorManager.shared.showError(error, context: "PDF Generation")
            }
            isExporting = false
        }
    }

    private func exportCSV() {
        isExporting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let raw = viewModel.franchiseName.trimmingCharacters(in: .whitespacesAndNewlines)
            let isGM = raw.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let brand = (raw.isEmpty || isGM) ? PDFExportBranding.genericCompanyTitle : raw.uppercased()
            var csv = ""
            csv += "\(brand) — TRAFFIC ACCIDENT CONTRACTS\n"
            csv += "\(UserDefaults.standard.selectedCountry.name)\n"
            csv += "Month:,\(monthDisplayText)\n\n"
            csv += "SUMMARY\n"
            csv += "Pending count:,\(pendingCount)\n"
            csv += "Paid count:,\(paidCount)\n"
            if canViewFinancials {
                csv += "Total unpaid:,\(AppCurrency.amountWithCode(unpaidSum))\n"
                csv += "Total paid:,\(AppCurrency.amountWithCode(paidSum))\n"
            }
            csv += "\n"
            csv += "DETAIL\n"
            csv += "Created,RES,Amount (\(AppCurrency.code)),Paid amount,Status,Photos,Recorded by\n"
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            for c in filtered.sorted(by: { $0.createdAt > $1.createdAt }) {
                let paidStr = c.paidAmount.map { String(format: "%.2f", $0) } ?? ""
                let status = c.isFullyPaid ? "Paid" : "Pending"
                let by = escapeCsv(c.createdByName ?? "")
                csv += "\(df.string(from: c.createdAt)),\(escapeCsv(c.displayResCode)),\(String(format: "%.2f", c.amount)),\(paidStr),\(status),\(c.photos.count),\(by)\n"
            }
            csv += "\n\(PDFExportBranding.csvGeneratedByLine)\n"

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = documentsPath.appendingPathComponent("TrafficAccidentContracts_\(Date().timeIntervalSince1970).csv")
            var bomData = Data([0xEF, 0xBB, 0xBF])
            bomData.append(csv.data(using: .utf8) ?? Data())
            do {
                try bomData.write(to: url)
                shareURL = url
                showShareSheet = true
            } catch {
                ErrorManager.shared.showError(error, context: "CSV Generation")
            }
            isExporting = false
        }
    }

    private func escapeCsv(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " ")
    }
}

private struct TrafficContractStatPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12))
        .cornerRadius(12)
    }
}

private struct TrafficAccidentContractRow: View {
    let contract: TrafficAccidentContract
    let onTogglePaid: () -> Void
    let onOpenEditor: () -> Void
    let onPreviewPhotos: () -> Void

    private var paidSoFar: Double { min(contract.amount, contract.paidAmount ?? 0) }

    private var statusIconName: String {
        if contract.isFullyPaid { return "checkmark.circle.fill" }
        if contract.hasPartialPayment { return "circle.lefthalf.filled" }
        return "circle.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePaid) {
                Image(systemName: statusIconName)
                    .font(.title3)
                    .foregroundStyle(contract.isFullyPaid ? Color.green : Color.orange)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contract.displayResCode)
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text(AppCurrency.format(contract.amount))
                        .font(.subheadline.weight(.bold))
                }
                if paidSoFar > 0.009 {
                    (Text(AppCurrency.format(paidSoFar))
                        .foregroundStyle(.green)
                    + Text(" / ")
                        .foregroundStyle(.secondary)
                    + Text(AppCurrency.format(contract.amount))
                        .foregroundStyle(contract.isFullyPaid ? Color.green : Color.orange))
                    .font(.caption.weight(.semibold))
                }
                if let raw = contract.createdByName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, !raw.contains("@") {
                    Text("\("Recorded by".localized) \(raw)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let uid = contract.createdBy, !uid.isEmpty {
                    Text("\("Recorded by".localized) \(String(uid.prefix(8)))…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    Label(contract.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !contract.photos.isEmpty {
                        Button(action: onPreviewPhotos) {
                            Label("\(contract.photos.count)", systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View photos".localized)
                    }
                    Text(contract.isFullyPaid ? "Paid".localized : "Pending".localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(contract.isFullyPaid ? Color.green : Color.orange)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenEditor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Editor

struct TrafficAccidentContractEditorView: View {
    enum Mode {
        case create
        case edit(TrafficAccidentContract)
    }

    private enum SaveOverlayPhase: Hashable {
        case uploading
        case completed
    }

    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    /// Digits only; stored as `RES-…` on save.
    @State private var resDigitsInput = ""
    @State private var amountText = ""
    /// Optional partial payment (e.g. 400 of 1000); empty = none yet (pending).
    @State private var paidAmountText = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var uploadedPhotoURLs: [String] = []
    @State private var isUploading = false
    @State private var photoGallerySession: PhotoGalleryFullScreenSession?
    @State private var showSaveOverlay = false
    @State private var saveOverlayPhase: SaveOverlayPhase = .uploading
    @State private var saveUploadProgress: Double = 0

    private var existing: TrafficAccidentContract? {
        if case .edit(let c) = mode { return c }
        return nil
    }

    var body: some View {
        ZStack {
            editorForm
                .blur(radius: showSaveOverlay ? 8 : 0)
                .allowsHitTesting(!showSaveOverlay)

            if showSaveOverlay {
                contractSaveOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var editorForm: some View {
        Form {
            Section("Contract".localized) {
                HStack(spacing: 10) {
                    Image(systemName: "number.square.fill")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 22)
                    HStack {
                        Text("RES-")
                            .foregroundStyle(.secondary)
                            .font(.body.weight(.medium))
                        TextField("digits only".localized, text: $resDigitsInput)
                            .keyboardType(.numberPad)
                            .onChange(of: resDigitsInput) { _, newVal in
                                let d = newVal.filter(\.isNumber)
                                if d != newVal { resDigitsInput = d }
                            }
                    }
                }
                Text("Stored as RES-#####".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "banknote")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 22)
                    TextField("Amount".localized, text: $amountText)
                        .keyboardType(.decimalPad)
                    Text(AppCurrency.code).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "creditcard")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 22)
                    TextField("Paid amount (optional)".localized, text: $paidAmountText)
                        .keyboardType(.decimalPad)
                    Text(AppCurrency.code).foregroundStyle(.secondary)
                }
                Text("Leave empty until the customer pays; enter a partial amount for orange pending.".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Photos".localized) {
                if !uploadedPhotoURLs.isEmpty || !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(uploadedPhotoURLs.enumerated()), id: \.offset) { index, url in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        photoGallerySession = PhotoGalleryFullScreenSession(urlStrings: uploadedPhotoURLs, startIndex: index)
                                    } label: {
                                        AsyncImageView(urlString: url) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                    .buttonStyle(.plain)
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
                            ForEach(selectedImages.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        photoGallerySession = PhotoGalleryFullScreenSession(images: selectedImages, startIndex: index)
                                    } label: {
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
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
                        }
                    }
                }
                Text("At least one photo is required.".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    showImagePicker = true
                } label: {
                    Label("Choose from Gallery".localized, systemImage: "photo.on.rectangle")
                }
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo".localized, systemImage: "camera")
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Text(modeTitle)
                        .frame(maxWidth: .infinity)
                }
                .disabled(isUploading || showSaveOverlay || !isValid)
            }
        }
        .navigationTitle(modeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .interactiveDismissDisabled(isUploading || showSaveOverlay)
        .onAppear {
            if let e = existing {
                resDigitsInput = TrafficAccidentContract.resDigits(from: e.resCode)
                amountText = String(format: "%.2f", e.amount)
                if let p = e.paidAmount {
                    paidAmountText = String(format: "%.2f", p)
                } else {
                    paidAmountText = ""
                }
                uploadedPhotoURLs = e.photos
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let img = capturedImage {
                selectedImages.append(img)
                capturedImage = nil
            }
        }) {
            OfficeCameraView(capturedImage: $capturedImage)
        }
        .fullScreenCover(item: $photoGallerySession) { session in
            Group {
                if let urls = session.urlStrings {
                    NativePhotoGalleryView(urlStrings: urls, initialIndex: session.startIndex)
                } else if let imgs = session.images {
                    NativePhotoGalleryView(images: imgs, initialIndex: session.startIndex)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: showSaveOverlay) { _, isVisible in
            if isVisible { dismissKeyboard() }
        }
    }

    private var contractSaveOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if saveOverlayPhase == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Contract saved".localized)
                        .font(.headline)
                } else {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 7)
                            .frame(width: 72, height: 72)
                        Circle()
                            .trim(from: 0, to: max(0.05, min(saveUploadProgress, 1)))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 72, height: 72)
                            .animation(.linear(duration: 0.2), value: saveUploadProgress)
                        Text("\(Int((max(0.05, min(saveUploadProgress, 1)) * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    Text("Saving contract...".localized)
                        .font(.headline)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .background(Color.black.opacity(0.75))
            .foregroundColor(.white)
            .cornerRadius(18)
            .shadow(radius: 12)
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resolvedRecorderNameForSave() -> String? {
        if let n = authManager.userProfile?.nameOrUsernameForAudit { return n }
        if let d = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !d.isEmpty, !d.contains("@") {
            return d
        }
        return nil
    }

    private var modeTitle: String {
        existing == nil ? "Add contract".localized : "Edit contract".localized
    }

    private var isValid: Bool {
        let digits = TrafficAccidentContract.resDigits(from: resDigitsInput)
        guard !digits.isEmpty, let a = Double(amountText.replacingOccurrences(of: ",", with: ".")), a > 0 else { return false }
        let photoCount = selectedImages.count + uploadedPhotoURLs.count
        return photoCount > 0
    }

    /// Parsed optional paid amount; `nil` if blank or zero (treated as nothing paid yet).
    private static func parsePaidAmount(_ text: String, maxAmount: Double) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 0.009 else { return nil }
        return min(max(0, v), max(0, maxAmount))
    }

    private func save() {
        let canonical = TrafficAccidentContract.canonicalRES(from: resDigitsInput)
        guard !canonical.isEmpty, let amt = Double(amountText.replacingOccurrences(of: ",", with: ".")), amt > 0 else { return }
        guard !isUploading else { return }

        isUploading = true
        saveOverlayPhase = .uploading
        saveUploadProgress = 0.05
        withAnimation(.easeInOut(duration: 0.2)) {
            showSaveOverlay = true
        }

        let existing = uploadedPhotoURLs
        let newImages = selectedImages
        let totalNew = newImages.count

        if totalNew == 0 {
            saveUploadProgress = 1
            saveOverlayPhase = .completed
            HapticManager.shared.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                finalizeContractSave(urls: existing, canonical: canonical, amt: amt)
            }
            return
        }

        var urls = existing
        var idx = 0

        func uploadStep() {
            guard idx < totalNew else {
                saveUploadProgress = 1
                saveOverlayPhase = .completed
                HapticManager.shared.success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    finalizeContractSave(urls: urls, canonical: canonical, amt: amt)
                }
                return
            }
            let img = newImages[idx]
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/traffic_accident_contracts/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(img, path: path) { url, _ in
                DispatchQueue.main.async {
                    if let url {
                        urls.append(url)
                    }
                    idx += 1
                    saveUploadProgress = min(0.98, 0.05 + Double(idx) / Double(totalNew) * 0.93)
                    uploadStep()
                }
            }
        }
        uploadStep()
    }

    private func finalizeContractSave(urls: [String], canonical: String, amt: Double) {
        guard !urls.isEmpty else {
            isUploading = false
            showSaveOverlay = false
            ToastManager.shared.show("Add at least one contract photo.".localized, type: .warning)
            return
        }
        let uid = Auth.auth().currentUser?.uid
        let parsedPaid = Self.parsePaidAmount(paidAmountText, maxAmount: amt)
        let recorder = resolvedRecorderNameForSave()

        switch mode {
        case .create:
            var c = TrafficAccidentContract(
                photos: urls,
                amount: amt,
                resCode: canonical,
                paidAmount: parsedPaid,
                createdAt: Date(),
                franchiseId: FirebaseService.shared.currentFranchiseId,
                createdBy: uid,
                createdByName: recorder
            )
            c.documentId = c.id.uuidString
            viewModel.trafficAccidentContractEkle(c)
        case .edit(let old):
            var c = old
            c.resCode = canonical
            c.amount = amt
            c.photos = urls
            c.paidAmount = parsedPaid
            viewModel.trafficAccidentContractGuncelle(c)
        }
        isUploading = false
        showSaveOverlay = false
        dismiss()
    }
}

private enum TrafficAccidentContractExporter {
    static func pdfData(contracts: [TrafficAccidentContract], franchiseName: String, monthLabel: String) -> Data {
        let pdfMetadata = [
            kCGPDFContextTitle: "Traffic Accident Contracts",
            kCGPDFContextAuthor: PDFExportBranding.pdfMetadataAuthor,
            kCGPDFContextCreator: PDFExportBranding.pdfMetadataAuthor
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetadata as [String: Any]
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let rawName = franchiseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGM = rawName.range(of: "green motion", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        let companyName = (rawName.isEmpty || isGM) ? PDFExportBranding.genericCompanyTitle : rawName.uppercased()

        let pendingN = contracts.filter { !$0.isFullyPaid }.count
        let paidN = contracts.filter(\.isFullyPaid).count
        let unpaidSum = TrafficAccidentContract.totalOutstanding(contracts)
        let paidSum = TrafficAccidentContract.totalPaidCollected(contracts)

        return renderer.pdfData { context in
            context.beginPage()
            let ctx = context.cgContext
            var y: CGFloat = 60

            companyName.draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 18), .foregroundColor: SwissPDFHelper.black])
            y += 22
            UserDefaults.standard.selectedCountry.name.uppercased().draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaThin(size: 9), .foregroundColor: SwissPDFHelper.mediumGray])
            y += 36
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 26

            "Traffic Accident Contracts".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 22), .foregroundColor: SwissPDFHelper.black])
            y += 30
            "Month:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 10), .foregroundColor: SwissPDFHelper.black])
            monthLabel.draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helvetica(size: 10), .foregroundColor: SwissPDFHelper.black])
            y += 28

            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 22

            "SUMMARY".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 22
            let summaryFont = SwissPDFHelper.helvetica(size: 10)
            "Pending count:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(pendingN)".draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 18
            "Paid count:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            "\(paidN)".draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 18
            "Total unpaid:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            AppCurrency.amountWithCode(unpaidSum).draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: UIColor.systemOrange])
            y += 18
            "Total paid:".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: summaryFont, .foregroundColor: SwissPDFHelper.black])
            AppCurrency.amountWithCode(paidSum).draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: UIColor.systemGreen])
            y += 28

            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y), to: CGPoint(x: pageRect.width - 60, y: y), width: 0.5)
            y += 22

            "DETAIL".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: SwissPDFHelper.helveticaBold(size: 12), .foregroundColor: SwissPDFHelper.black])
            y += 22

            let headerFont = SwissPDFHelper.helveticaBold(size: 9)
            let rowFont = SwissPDFHelper.helvetica(size: 9)
            let df = DateFormatter()
            df.dateFormat = "dd/MM/yy HH:mm"

            "DATE".draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: headerFont])
            "RES".draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: headerFont])
            "AMOUNT".draw(at: CGPoint(x: 360, y: y), withAttributes: [.font: headerFont])
            "STATUS".draw(at: CGPoint(x: 460, y: y), withAttributes: [.font: headerFont])
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y + 12), to: CGPoint(x: pageRect.width - 60, y: y + 12), width: 0.5)
            y += 22

            let sorted = contracts.sorted { $0.createdAt > $1.createdAt }
            for (index, c) in sorted.prefix(40).enumerated() {
                if y > 740 {
                    context.beginPage()
                    y = 60
                }
                df.string(from: c.createdAt).draw(at: CGPoint(x: 60, y: y), withAttributes: [.font: rowFont])
                c.displayResCode.draw(at: CGPoint(x: 200, y: y), withAttributes: [.font: rowFont])
                AppCurrency.amountWithCode(c.amount).draw(at: CGPoint(x: 360, y: y), withAttributes: [.font: rowFont])
                (c.isFullyPaid ? "Paid" : "Pending").draw(at: CGPoint(x: 460, y: y), withAttributes: [.font: rowFont])
                if index < sorted.prefix(40).count - 1 {
                    SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: y + 12), to: CGPoint(x: pageRect.width - 60, y: y + 12), width: 0.25)
                }
                y += 18
            }

            let footerY = pageRect.height - 28
            SwissPDFHelper.drawHorizontalLine(context: ctx, from: CGPoint(x: 60, y: footerY - 16), to: CGPoint(x: pageRect.width - 60, y: footerY - 16), width: 0.25)
            let footer = "\(PDFExportBranding.copyrightLine) • \(UserDefaults.standard.selectedCountry.name)"
            footer.draw(at: CGPoint(x: 60, y: footerY), withAttributes: [.font: SwissPDFHelper.helveticaThin(size: 7), .foregroundColor: SwissPDFHelper.lightGray])
        }
    }
}
