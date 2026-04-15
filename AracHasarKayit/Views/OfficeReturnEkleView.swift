import SwiftUI

struct OfficeReturnEkleView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    
    var editingReturn: OfficeReturn? = nil
    
    @State private var amount = ""
    @State private var selectedReason: OfficeReturnReason = .vehicleReturn
    @State private var selectedDate: Date = Date()
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var existingPhotoURLs: [String] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var selectedPhotoForPreview: String?
    @State private var selectedImageForPreview: UIImage?
    @State private var showPhotoPreview = false
    @State private var uploadedPhotoURLs: [String] = []
    @State private var isUploading = false
    @State private var uploadErrors: [Error] = []
    @State private var showCompletionOverlay = false
    @State private var completionSucceeded = false
    @State private var pulseAnimation = false
    
    var isEditMode: Bool {
        editingReturn != nil
    }
    
    init(editingReturn: OfficeReturn? = nil) {
        self.editingReturn = editingReturn
        
        if let returnOp = editingReturn {
            _amount = State(initialValue: String(format: "%.2f", returnOp.amount))
            _selectedReason = State(initialValue: returnOp.reason)
            _selectedDate = State(initialValue: returnOp.date)
            _notes = State(initialValue: returnOp.notes)
            _existingPhotoURLs = State(initialValue: returnOp.photos)
        }
    }
    
    var body: some View {
        ZStack {
            Form {
                if isUploading {
                    Section {
                        UploadProgressView(
                            progress: Double(uploadedPhotoURLs.count) / Double(selectedImages.count + existingPhotoURLs.count),
                            currentItem: uploadedPhotoURLs.count,
                            totalItems: selectedImages.count + existingPhotoURLs.count,
                            message: "Uploading photos...".localized
                        )
                    }
                }
                
                if !uploadErrors.isEmpty {
                    Section {
                        ForEach(Array(uploadErrors.enumerated()), id: \.offset) { _, error in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                reasonSection
                amountSection
                dateSection
                photoSection
                notesSection
                saveSection
            }
            .blur(radius: showCompletionOverlay ? 8 : 0)
            .allowsHitTesting(!showCompletionOverlay)
            
            if showCompletionOverlay {
                completionOverlay
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .navigationTitle(isEditMode ? "Edit Return".localized : "Add Return".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
        .onChange(of: showCompletionOverlay) { isVisible in
            if isVisible {
                dismissKeyboard()
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let newImage = capturedImage {
                selectedImages.append(newImage)
                capturedImage = nil
            }
        }) {
            OfficeReturnCameraView(capturedImage: $capturedImage)
        }
        .sheet(item: Binding(
            get: { selectedPhotoForPreview.map { PhotoPreviewItem.url($0) } },
            set: { if $0 == nil { selectedPhotoForPreview = nil } }
        )) { item in
            if case .url(let url) = item {
                NativePhotoGalleryView(urlStrings: [url], initialIndex: 0)
            }
        }
        .sheet(item: Binding(
            get: { selectedImageForPreview.map { PhotoPreviewItem.image($0) } },
            set: { if $0 == nil { selectedImageForPreview = nil } }
        )) { item in
            if case .image(let image) = item {
                NativePhotoGalleryView(images: [image], initialIndex: 0)
            }
        }
    }
    
    private var reasonSection: some View {
        Section("Return Reason *") {
            Picker("Reason", selection: $selectedReason) {
                ForEach(OfficeReturnReason.allCases, id: \.self) { reason in
                    HStack {
                        Image(systemName: reason.icon)
                        Text(reason.rawValue)
                    }
                    .tag(reason)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var amountSection: some View {
        Section("Return Amount *") {
            HStack {
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                
                Text(AppCurrency.code)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var dateSection: some View {
        Section("Date".localized) {
            DatePicker("Return Date".localized, selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
        }
    }
    
    private var photoSection: some View {
        Section("Photos *".localized) {
            // Existing photos
            if !existingPhotoURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(existingPhotoURLs.indices, id: \.self) { index in
                            Button {
                                selectedPhotoForPreview = existingPhotoURLs[index]
                                showPhotoPreview = true
                            } label: {
                                AsyncImageView(urlString: existingPhotoURLs[index]) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            Button {
                                                existingPhotoURLs.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.6)))
                                            }
                                            .offset(x: 5, y: -5),
                                            alignment: .topTrailing
                                        )
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // New photos
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            Button {
                                selectedImageForPreview = selectedImages[index]
                                showPhotoPreview = true
                            } label: {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        Button {
                                            selectedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                        }
                                        .offset(x: 5, y: -5),
                                        alignment: .topTrailing
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // Add photo buttons
            HStack(spacing: 16) {
                Button {
                    showImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.fill")
                        Text("From Gallery".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
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
            }
            
            if existingPhotoURLs.isEmpty && selectedImages.isEmpty {
                Text("At least one photo is required".localized)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes (Optional)".localized) {
            TextEditor(text: $notes)
                .frame(height: 100)
        }
    }
    
    private var saveSection: some View {
        Section {
            Button {
                completionSucceeded = false
                pulseAnimation = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompletionOverlay = true
                }
                saveReturn()
            } label: {
                if isUploading {
                    HStack {
                        ProgressView()
                        Text("Uploading...".localized)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(isEditMode ? "Update Return".localized : "Save Return".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(isUploading || !isValid)
        }
    }
    
    private var completionOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if completionSucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(.green)
                    Text("Done".localized)
                        .font(.headline)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                    Text("Uploading...".localized)
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
    
    private var isValid: Bool {
        // Amount must be valid and > 0
        guard let amountValue = Double(amount), amountValue > 0 else { return false }
        
        // At least one photo required (existing or new)
        guard !existingPhotoURLs.isEmpty || !selectedImages.isEmpty else { return false }
        
        return true
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func saveReturn() {
        guard isValid else {
            withAnimation(.easeInOut(duration: 0.2)) { showCompletionOverlay = false }
            return
        }
        
        isUploading = true
        uploadErrors = []
        uploadedPhotoURLs = []
        
        // Keep existing photos
        uploadedPhotoURLs = existingPhotoURLs
        
        let group = DispatchGroup()
        let lock = NSLock()
        
        // Upload new photos
        for image in selectedImages {
            group.enter()
            let path = "office_Return/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(image, path: path) { url, error in
                DispatchQueue.main.async {
                    if let url = url {
                        lock.lock()
                        uploadedPhotoURLs.append(url)
                        lock.unlock()
                    } else if let error = error {
                        lock.lock()
                        uploadErrors.append(error)
                        lock.unlock()
                        print("❌ Photo upload error: \(error.localizedDescription)")
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            guard let amountValue = Double(self.amount), amountValue > 0 else {
                self.isUploading = false
                return
            }
            
            let finalReturn = OfficeReturn(
                amount: amountValue,
                reason: self.selectedReason,
                date: self.selectedDate,
                photos: self.uploadedPhotoURLs,
                notes: self.notes
            )
            
            if let editing = self.editingReturn {
                // Update existing return with same ID
                var updatedReturn = finalReturn
                updatedReturn.id = editing.id
                self.viewModel.officeReturnGuncelle(updatedReturn)
            } else {
                // Add new return
                self.viewModel.officeReturnEkle(finalReturn)
            }
            
            self.isUploading = false
            
            // Show error if some uploads failed
            if !self.uploadErrors.isEmpty {
                ErrorManager.shared.showError(message: "Some photos failed to upload. Return saved with available photos.".localized)
                self.completionSucceeded = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                    self.dismiss()
                }
            } else {
                self.completionSucceeded = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.2)) { self.showCompletionOverlay = false }
                    self.dismiss()
                }
            }
        }
    }
}

