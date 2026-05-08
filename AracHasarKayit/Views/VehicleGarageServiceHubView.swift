import SwiftUI
import FirebaseAuth

/// List + create flow for `garageServiceJobs` (external garage send) for one vehicle.
struct VehicleGarageServiceHubView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) private var dismiss
    var arac: Arac

    @State private var showNewJob = false
    @State private var editingJob: GarageServiceJob?
    @State private var deletingJob: GarageServiceJob?
    @State private var searchText = ""
    @State private var exportURL: URL?

    private var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }

    private var jobs: [GarageServiceJob] {
        viewModel.garageServiceJobs(forVehicleId: guncelArac.id)
    }
    
    private var visibleJobs: [GarageServiceJob] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return jobs }
        return jobs.filter { $0.vehiclePlate.lowercased().contains(q) }
    }

    private var legacyBranchList: [FranchiseGarageBranch] {
        let fromRegistry = viewModel.turkeyFranchiseLocationBranches
        if !fromRegistry.isEmpty { return fromRegistry }
        return viewModel.franchiseGarageBranches
    }

    var body: some View {
        List {
            if visibleJobs.isEmpty {
                Section {
                    Text("garage_service.empty_history".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(visibleJobs) { job in
                        NavigationLink {
                            GarageServiceJobDetailReadOnlyView(job: job, branchLabel: targetLabel(for: job.targetGarageId))
                        } label: {
                            GarageServiceJobRow(job: job, branchLabel: targetLabel(for: job.targetGarageId))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deletingJob = job
                            } label: {
                                Label("Delete".localized, systemImage: "trash")
                            }
                            Button {
                                editingJob = job
                            } label: {
                                Label("Edit".localized, systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text(String(format: "garage_service.history_section".localized, visibleJobs.count))
                }
            }
        }
        .navigationTitle("garage_service.hub_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search by plate...".localized)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewJob = true
                } label: {
                    Label("garage_service.new_job".localized, systemImage: "plus.circle.fill")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Excel", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        exportURL = createExcelLikeCSV()
                    } label: {
                        Label("Excel", systemImage: "tablecells")
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showNewJob) {
            GarageServiceJobFormView(
                arac: guncelArac,
                onSaveSuccess: {
                    showNewJob = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        dismiss()
                    }
                }
            )
            .environmentObject(viewModel)
        }
        .sheet(item: $editingJob) { job in
            NavigationView {
                GarageServiceJobFormView(
                    arac: guncelArac,
                    editingJob: job,
                    onSaveSuccess: {
                        editingJob = nil
                    }
                )
                .environmentObject(viewModel)
            }
        }
        .alert(
            "Delete service job?".localized,
            isPresented: Binding(
                get: { deletingJob != nil },
                set: { if !$0 { deletingJob = nil } }
            ),
            presenting: deletingJob
        ) { job in
            Button("Delete".localized, role: .destructive) {
                viewModel.garageServiceJobSil(job)
            }
            Button("Cancel".localized, role: .cancel) {}
        } message: { _ in
            Text("This operation cannot be undone.".localized)
        }
        .onAppear {
            viewModel.reloadFranchiseGarageMetadataFromFirestore()
        }
        .onChange(of: visibleJobs.count) { _, _ in
            exportURL = nil
        }
    }

    /// Resolves **ServisFirma** name by UUID; falls back to legacy garage branch keys on older jobs.
    private func targetLabel(for stored: String) -> String {
        let key = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "—" }
        if let f = viewModel.servisFirmalari.first(where: { $0.id.uuidString.lowercased() == key.lowercased() }) {
            return f.ad
        }
        if let b = legacyBranchList.first(where: { $0.storageKey == key }) {
            return b.displayName
        }
        return key
    }
}

// MARK: - Row + detail

private struct GarageServiceJobRow: View {
    let job: GarageServiceJob
    let branchLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.serviceDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(job.status.localizedTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(job.status == .pending ? Color.orange.opacity(0.26) : Color.green.opacity(0.26))
                    .clipShape(Capsule())
            }
            Text(purposeLabel(job.purpose))
                .font(.subheadline)
            Text(branchLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let completedAt = job.completedAt {
                Text("Completed: \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }

    private func purposeLabel(_ raw: String) -> String {
        if let p = GarageServiceJobPurpose(rawValue: raw) {
            return p.localizedTitle
        }
        return raw.isEmpty ? "—" : raw
    }
}

private struct GarageServiceJobDetailReadOnlyView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let job: GarageServiceJob
    let branchLabel: String

    @State private var previewURL: String?
    @State private var showEdit = false

    var body: some View {
        List {
            Section("garage_service.section.summary".localized) {
                LabeledContent("garage_service.field.service_date".localized) {
                    Text(job.serviceDate.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("garage_service.field.status".localized) {
                    Text(job.status.localizedTitle)
                }
                LabeledContent("garage_service.field.target_garage".localized) {
                    Text(branchLabel)
                }
                LabeledContent("garage_service.field.purpose".localized) {
                    Text(purposeLabel(job.purpose))
                }
                LabeledContent("Sent at".localized) {
                    Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let completedAt = job.completedAt {
                    LabeledContent("Completed at".localized) {
                        Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            if !job.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Notes".localized) {
                    Text(job.notes)
                }
            }
            if let completionNotes = job.completionNotes, !completionNotes.isEmpty {
                Section("Completion note".localized) {
                    Text(completionNotes)
                }
            }
            if !job.photoURLs.isEmpty {
                Section("Before photos".localized) {
                    photoScroller(job.photoURLs)
                }
            }
            if !job.completionPhotoURLs.isEmpty {
                Section("After photos".localized) {
                    photoScroller(job.completionPhotoURLs)
                }
            }
        }
        .navigationTitle("garage_service.detail_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit".localized) {
                    showEdit = true
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationView {
                GarageServiceJobFormView(
                    arac: vehicleForJob(),
                    editingJob: job,
                    onSaveSuccess: {
                        showEdit = false
                    }
                )
                .environmentObject(viewModel)
            }
        }
        .sheet(item: Binding(
            get: { previewURL.map { PreviewURL(url: $0) } },
            set: { previewURL = $0?.url }
        )) { item in
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: URL(string: item.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    default:
                        ProgressView()
                    }
                }
            }
        }
    }

    private func purposeLabel(_ raw: String) -> String {
        if let p = GarageServiceJobPurpose(rawValue: raw) {
            return p.localizedTitle
        }
        return raw
    }

    private func photoScroller(_ urls: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(urls, id: \.self) { url in
                    Button {
                        previewURL = url
                    } label: {
                        AsyncImage(url: URL(string: url)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "photo").foregroundStyle(.secondary)
                            default:
                                ProgressView()
                            }
                        }
                        .frame(width: 110, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func vehicleForJob() -> Arac {
        viewModel.araclar.first(where: { $0.id == job.vehicleId }) ?? Arac(
            plaka: job.vehiclePlate,
            marka: "",
            model: "",
            kategori: "S"
        )
    }
}

private struct PreviewURL: Identifiable {
    let id = UUID()
    let url: String
}

extension VehicleGarageServiceHubView {
    private func createExcelLikeCSV() -> URL? {
        var lines: [String] = ["Plate,Purpose,Service Company,Status,Sent Date,Completed Date,Notes,Completion Notes"]
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .short
        for j in visibleJobs {
            let purpose = GarageServiceJobPurpose(rawValue: j.purpose)?.localizedTitle ?? j.purpose
            let completed = j.completedAt.map { dateFmt.string(from: $0) } ?? ""
            let sent = dateFmt.string(from: j.createdAt)
            let row = [
                j.vehiclePlate,
                purpose,
                targetLabel(for: j.targetGarageId),
                j.status.localizedTitle,
                sent,
                completed,
                j.notes.replacingOccurrences(of: ",", with: " "),
                (j.completionNotes ?? "").replacingOccurrences(of: ",", with: " "),
            ].joined(separator: ",")
            lines.append(row)
        }
        let text = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("service-hub-export-\(UUID().uuidString).csv")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Form

struct GarageServiceJobFormView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) private var dismiss

    var arac: Arac
    var editingJob: GarageServiceJob? = nil
    /// When set (hub flow), caller pops navigation and dismisses hub — avoids nested sheet + extra blank dismiss.
    var onSaveSuccess: (() -> Void)? = nil

    @State private var targetServiceCompanyId: String = ""
    @State private var purpose: GarageServiceJobPurpose = .repair
    @State private var notes = ""
    @State private var serviceDate = Date()
    @State private var pickupNotifyEmail = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @FocusState private var notesFieldFocused: Bool
    @State private var completionNotes = ""

    private var serviceCompanies: [ServisFirma] {
        viewModel.servisFirmalari
    }

    private var guncelArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }

    private var canSave: Bool {
        !targetServiceCompanyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var isEditMode: Bool { editingJob != nil }

    private var selectedCompanyLabel: String {
        let idStr = targetServiceCompanyId.trimmingCharacters(in: .whitespacesAndNewlines)
        if idStr.isEmpty { return "garage_service.pick_branch".localized }
        if let f = viewModel.servisFirmalari.first(where: { $0.id.uuidString.lowercased() == idStr.lowercased() }) {
            return f.ad
        }
        return idStr
    }

    var body: some View {
        Form {
            Section("garage_service.field.target_garage".localized) {
                if serviceCompanies.isEmpty {
                    Text("garage_service.no_branches_hint".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        ServisFirmalariView()
                            .environmentObject(viewModel)
                    } label: {
                        Label("garage_service.manage_service_companies".localized, systemImage: "building.2.fill")
                    }
                } else {
                    Menu {
                        ForEach(serviceCompanies) { firma in
                            Button {
                                notesFieldFocused = false
                                targetServiceCompanyId = firma.id.uuidString
                            } label: {
                                HStack {
                                    Text(firma.ad)
                                    if firma.id.uuidString.lowercased() == targetServiceCompanyId.lowercased() {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedCompanyLabel)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("garage_service.field.purpose".localized) {
                Menu {
                    ForEach(GarageServiceJobPurpose.allCases) { p in
                        Button {
                            notesFieldFocused = false
                            purpose = p
                        } label: {
                            HStack {
                                Text(p.localizedTitle)
                                if p == purpose {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(purpose.localizedTitle)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                DatePicker(
                    "garage_service.field.service_date".localized,
                    selection: $serviceDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Section {
                TextField("garage_service.field.pickup_notify_email".localized, text: $pickupNotifyEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("garage_service.field.pickup_notify_email_header".localized)
            } footer: {
                Text("garage_service.field.pickup_notify_email_footer".localized)
                    .font(.caption)
            }

            Section("Photos".localized) {
                if !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedImages.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Button {
                                        selectedImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red, .white)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
                Button {
                    showImagePicker = true
                } label: {
                    Label("Choose from Gallery".localized, systemImage: "photo.on.rectangle")
                }
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo".localized, systemImage: "camera.fill")
                }
            }

            Section("Notes".localized) {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                    .focused($notesFieldFocused)
            }
            
            if isEditMode {
                Section("Completion note".localized) {
                    TextEditor(text: $completionNotes)
                        .frame(minHeight: 70)
                }
            }

            Section {
                Button {
                    saveJob()
                } label: {
                    if isSaving {
                        HStack {
                            ProgressView()
                            Text("Uploading...".localized)
                        }
                    } else {
                        Text(isEditMode ? "Update".localized : "Save".localized)
                    }
                }
                .disabled(!canSave || isSaving || serviceCompanies.isEmpty)
            }
        }
        .navigationTitle(isEditMode ? "Edit Service".localized : "garage_service.new_job".localized)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel".localized) {
                    notesFieldFocused = false
                    dismiss()
                }
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
        .onAppear {
            if let editingJob {
                targetServiceCompanyId = editingJob.targetGarageId
                if let p = GarageServiceJobPurpose(rawValue: editingJob.purpose) { purpose = p }
                notes = editingJob.notes
                serviceDate = editingJob.serviceDate
                pickupNotifyEmail = editingJob.pickupNotifyEmail ?? ""
                completionNotes = editingJob.completionNotes ?? ""
            } else if targetServiceCompanyId.isEmpty, let first = serviceCompanies.first {
                targetServiceCompanyId = first.id.uuidString
            }
        }
    }

    private func saveJob() {
        guard canSave else { return }
        isSaving = true
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [String] = []

        for image in selectedImages {
            group.enter()
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/garage_service_jobs/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(image, path: path) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let now = Date()
            let em = pickupNotifyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetKey = targetServiceCompanyId.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetName = serviceCompanies.first(where: { $0.id.uuidString == targetKey })?.ad
            let job = GarageServiceJob(
                id: editingJob?.id ?? UUID(),
                documentId: editingJob?.documentId,
                vehicleId: guncelArac.id,
                vehiclePlate: guncelArac.plakaFormatli,
                targetGarageId: targetKey,
                targetGarageName: targetName,
                purpose: purpose.rawValue,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                photoURLs: editingJob != nil ? (editingJob?.photoURLs ?? []) + urls : urls,
                completionPhotoURLs: editingJob != nil ? (editingJob?.completionPhotoURLs ?? []) : [],
                serviceDate: serviceDate,
                status: editingJob?.status ?? .pending,
                createdAt: editingJob?.createdAt ?? now,
                createdBy: editingJob?.createdBy ?? Auth.auth().currentUser?.uid,
                completedAt: editingJob?.completedAt,
                completionNotes: completionNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : completionNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                franchiseId: FirebaseService.shared.currentFranchiseId.uppercased(),
                pickupNotifyEmail: em.isEmpty ? nil : em
            )
            viewModel.garageServiceJobKaydet(job) { err in
                isSaving = false
                if err == nil {
                    notesFieldFocused = false
                    if let onSaveSuccess {
                        onSaveSuccess()
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }
}
