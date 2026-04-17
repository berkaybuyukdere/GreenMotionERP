import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Carries URLs with the gallery presentation so `fullScreenCover` never opens with a stale empty `urlPreviewURLs` array.
private struct CustomerInfoScanRemoteGallery: Identifiable {
    let id = UUID()
    let urls: [String]
    let startIndex: Int
}

/// Carries local images with start index for the same reason as `CustomerInfoScanRemoteGallery`.
private struct CustomerInfoScanLocalGallery: Identifiable {
    let id = UUID()
    let images: [UIImage]
    let startIndex: Int
}

struct CustomerInfoScanView: View {
    enum DocumentType: String, CaseIterable, Identifiable {
        case drivingLicense = "Driving License"
        case nationalId = "National ID"
        case passport = "Passport"
        var id: String { rawValue }
    }

    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDocumentType: DocumentType = .drivingLicense
    @State private var navCode: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var fullNameRaw: String = ""
    @State private var extractedText: String = ""
    @State private var photos: [UIImage] = []
    @State private var cameraPhotos: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @State private var records: [CustomerInfoScanRecord] = []
    @State private var selectedRecordId: String?
    @State private var isEditingRecord = false
    @State private var editingPhotoURLs: [String] = []
    @State private var listener: ListenerRegistration?
    @State private var showDeleteConfirm = false
    @State private var remoteGallery: CustomerInfoScanRemoteGallery?
    @State private var localGallery: CustomerInfoScanLocalGallery?

    private var allPhotos: [UIImage] { photos + cameraPhotos }
    private var selectedRecord: CustomerInfoScanRecord? {
        records.first(where: { $0.id == selectedRecordId })
    }

    var body: some View {
        Form {
            inputSection
            photoSection
            saveSection
            recordsSection
            selectedRecordSection
        }
        .navigationTitle("Customer Info Scan".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $photos)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: handleCameraDismiss) {
            CameraView(capturedImage: $capturedImage)
        }
        .onAppear { startListening() }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .confirmationDialog("Delete".localized, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete".localized, role: .destructive) {
                deleteSelectedRecord()
            }
            Button("Cancel".localized, role: .cancel) {}
        }
        .fullScreenCover(item: $remoteGallery) { item in
            NativePhotoGalleryView(urlStrings: item.urls, initialIndex: item.startIndex)
        }
        .fullScreenCover(item: $localGallery) { item in
            NativePhotoGalleryView(images: item.images, initialIndex: item.startIndex)
        }
    }

    private var inputSection: some View {
        Section("Customer Info Scan".localized) {
            Picker("Document Type".localized, selection: $selectedDocumentType) {
                ForEach(DocumentType.allCases) { type in
                    Text(type.rawValue.localized).tag(type)
                }
            }
            TextField("NAV Code".localized, text: $navCode)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)
            TextField("First Name".localized, text: $firstName)
            TextField("Last Name".localized, text: $lastName)
            if !fullNameRaw.isEmpty {
                Text("\("OCR Name".localized): \(fullNameRaw)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var photoSection: some View {
        Section("Document Photos".localized) {
            Button {
                showCamera = true
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Take Photo".localized)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showImagePicker = true
            } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Choose from Gallery".localized)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if allPhotos.isEmpty {
                Text("No photo selected".localized)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(allPhotos.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 78)
                                .clipped()
                                .cornerRadius(8)
                                .onTapGesture {
                                    localGallery = CustomerInfoScanLocalGallery(images: allPhotos, startIndex: index)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                saveRecord()
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text(isEditingRecord ? "Update".localized : "Save Customer Scan".localized)
                }
            }
            .disabled(isSaving || allPhotos.isEmpty || navCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var recordsSection: some View {
        Section("Customer Scan Records".localized) {
            if records.isEmpty {
                Text("No customer scan data yet.".localized)
                    .foregroundColor(.secondary)
            } else {
                ForEach(records) { record in
                    Button {
                        selectedRecordId = record.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.navCode.isEmpty ? "-" : record.navCode)
                                    .font(.subheadline.weight(.semibold))
                                Text([record.firstName, record.lastName].filter { !$0.isEmpty }.joined(separator: " "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedRecordSection: some View {
        if let selectedRecord {
            Section("Selected Record".localized) {
                Text("Type".localized + ": \(selectedRecord.documentType)")
                Text("NAV Code".localized + ": \(selectedRecord.navCode)")
                Text("Name".localized + ": " + [selectedRecord.firstName, selectedRecord.lastName].filter { !$0.isEmpty }.joined(separator: " "))

                if !selectedRecord.photoURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(selectedRecord.photoURLs.enumerated()), id: \.offset) { index, url in
                                Button {
                                    remoteGallery = CustomerInfoScanRemoteGallery(
                                        urls: selectedRecord.photoURLs,
                                        startIndex: index
                                    )
                                } label: {
                                    AsyncImage(url: URL(string: url)) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            Color.secondary.opacity(0.2)
                                        }
                                    }
                                    .frame(width: 110, height: 78)
                                    .clipped()
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack {
                    Button("Edit".localized) {
                        beginEditing(selectedRecord)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Delete".localized, role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func handleCameraDismiss() {
        guard let capturedImage else { return }
        cameraPhotos.append(capturedImage)
        self.capturedImage = nil
    }

    private func saveRecord() {
        isSaving = true
        uploadNewPhotos { uploadedURLs, error in
            if let error {
                isSaving = false
                ErrorManager.shared.showError(error, context: "Customer Info Scan Upload")
                return
            }

            let mergedPhotoURLs = editingPhotoURLs + uploadedURLs
            let cleanNav = navCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let record = CustomerInfoScanRecord(
                id: isEditingRecord ? (selectedRecordId ?? UUID().uuidString) : UUID().uuidString,
                franchiseId: FirebaseService.shared.currentFranchiseId,
                documentType: selectedDocumentType.rawValue,
                navCode: cleanNav,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                fullNameRaw: fullNameRaw,
                photoURLs: mergedPhotoURLs,
                extractedText: extractedText,
                createdBy: authManager.userProfile?.email ?? Auth.auth().currentUser?.uid ?? "unknown",
                createdAt: selectedRecord?.createdAt ?? Date()
            )

            FirebaseService.shared.saveCustomerInfoScan(record) { error in
                isSaving = false
                if let error {
                    ErrorManager.shared.showError(error, context: "Customer Info Scan Save")
                } else {
                    ToastManager.shared.show(
                        isEditingRecord ? "Update".localized : "Customer info scan saved".localized,
                        type: .success
                    )
                    clearForm()
                }
            }
        }
    }

    private func uploadNewPhotos(completion: @escaping ([String], Error?) -> Void) {
        guard !allPhotos.isEmpty else {
            completion([], nil)
            return
        }
        let group = DispatchGroup()
        var uploadedURLs: [String] = []
        var firstError: Error?
        for image in allPhotos {
            group.enter()
            let path = "customer_info_scans/\(UUID().uuidString).jpg"
            FirebaseService.shared.uploadImage(image, path: path) { url, error in
                if let url { uploadedURLs.append(url) }
                if firstError == nil, let error { firstError = error }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(uploadedURLs, firstError)
        }
    }

    private func startListening() {
        listener?.remove()
        listener = FirebaseService.shared.observeCustomerInfoScans { rows in
            DispatchQueue.main.async {
                records = rows
                if selectedRecordId == nil {
                    selectedRecordId = rows.first?.id
                }
            }
        }
    }

    private func beginEditing(_ record: CustomerInfoScanRecord) {
        isEditingRecord = true
        selectedRecordId = record.id
        selectedDocumentType = DocumentType(rawValue: record.documentType) ?? .drivingLicense
        navCode = record.navCode
        firstName = record.firstName
        lastName = record.lastName
        fullNameRaw = record.fullNameRaw
        extractedText = record.extractedText
        editingPhotoURLs = record.photoURLs
        photos = []
        cameraPhotos = []
    }

    private func deleteSelectedRecord() {
        guard let selectedRecordId else { return }
        FirebaseService.shared.deleteCustomerInfoScan(selectedRecordId) { error in
            if let error {
                ErrorManager.shared.showError(error, context: "Customer Info Scan Delete")
            } else {
                ToastManager.shared.show("Delete".localized, type: .success)
                self.selectedRecordId = nil
                clearForm()
            }
        }
    }

    private func clearForm() {
        isEditingRecord = false
        selectedDocumentType = .drivingLicense
        navCode = ""
        firstName = ""
        lastName = ""
        fullNameRaw = ""
        extractedText = ""
        photos = []
        cameraPhotos = []
        editingPhotoURLs = []
    }
}

