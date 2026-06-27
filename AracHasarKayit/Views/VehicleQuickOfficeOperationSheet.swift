import SwiftUI

/// Palantir quick fuel / washing entry from vehicle detail — replaces legacy Form sheet.
struct VehicleQuickOfficeOperationSheet: View {
    enum Kind {
        case fuel
        case washing

        var title: String {
            switch self {
            case .fuel: return "office_quick.fuel".localized
            case .washing: return "office_quick.washing".localized
            }
        }

        var icon: String {
            switch self {
            case .fuel: return "fuelpump.fill"
            case .washing: return "sparkles"
            }
        }

        var tint: Color {
            switch self {
            case .fuel: return PalantirTheme.warning
            case .washing: return PalantirTheme.accent
            }
        }
    }

    @EnvironmentObject private var viewModel: AracViewModel
    @Environment(\.dismiss) private var dismiss

    let kind: Kind
    let arac: Arac

    @State private var amount = ""
    @State private var notes = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isSaving = false
    @State private var showCompletion = false
    @State private var completionSucceeded = false

    private var isValid: Bool {
        let normalized = amount.replacingOccurrences(of: ",", with: ".")
        let value = Double(normalized) ?? -1
        return value >= 0
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WheelSysPalantirFormMetrics.scrollSpacing) {
                    header
                    amountCard
                    photosCard
                    notesCard
                    saveButton
                }
                .padding(.horizontal, WheelSysPalantirFormMetrics.scrollHPadding)
                .padding(.vertical, WheelSysPalantirFormMetrics.scrollVPadding)
            }
            .background(PalantirTheme.background)
            .blur(radius: showCompletion ? 6 : 0)
            .allowsHitTesting(!showCompletion)

            if showCompletion {
                PalantirOpsCompletionOverlay(
                    title: "palantir.completion.saving".localized,
                    steps: [
                        PalantirOpsCompletionStep(icon: "photo.fill", label: "palantir.completion.upload_photos".localized),
                        PalantirOpsCompletionStep(icon: kind.icon, label: kind.title),
                    ],
                    activeStepIndex: completionSucceeded ? 1 : 0,
                    progress: completionSucceeded ? 1 : 0.45,
                    succeeded: completionSucceeded,
                    successTitle: "Done".localized
                )
                .transition(.opacity)
            }
        }
        .wheelSysCHOpsChrome()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel".localized) { dismiss() }
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
            if kind == .washing, let last = viewModel.lastWashingPriceForCurrentFranchise() {
                amount = String(format: "%.2f", last)
            }
        }
    }

    private var header: some View {
        WheelSysPalantirOpsHeader(
            title: arac.plakaFormatli,
            subtitle: kind.title,
            badge: [arac.marka, arac.model].filter { !$0.isEmpty }.joined(separator: " ")
        )
    }

    private var amountCard: some View {
        WheelSysPalantirSectionCard(title: "Amount (\(AppCurrency.code))".localized, icon: "creditcard.fill") {
            WheelSysPalantirTextInput(
                label: "Amount".localized,
                text: $amount,
                placeholder: "0.00",
                keyboard: .decimalPad
            )
        }
    }

    private var photosCard: some View {
        WheelSysPalantirSectionCard(title: "Photos".localized, icon: "camera.fill") {
            HStack(spacing: 10) {
                WheelSysPalantirSecondaryButton(title: "Gallery".localized, icon: "photo.on.rectangle") {
                    showImagePicker = true
                }
                WheelSysPalantirSecondaryButton(title: "Camera".localized, icon: "camera") {
                    showCamera = true
                }
            }
            if !selectedImages.isEmpty {
                Text("\(selectedImages.count) " + "photos".localized)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
        }
    }

    private var notesCard: some View {
        WheelSysPalantirSectionCard(title: "Notes".localized, icon: "note.text") {
            WheelSysPalantirTextInput(
                label: "Notes (optional)".localized,
                text: $notes,
                placeholder: ""
            )
        }
    }

    private var saveButton: some View {
        WheelSysPalantirPrimaryButton(
            title: "Save".localized,
            icon: "checkmark",
            isLoading: isSaving,
            disabled: !isValid || isSaving
        ) {
            save()
        }
    }

    private func save() {
        guard isValid, !isSaving else { return }
        HapticManager.shared.medium()
        isSaving = true
        showCompletion = true
        completionSucceeded = false

        uploadPhotos { urls in
            let normalized = amount.replacingOccurrences(of: ",", with: ".")
            let value = Double(normalized) ?? 0
            let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

            switch kind {
            case .fuel:
                var operation = OfficeOperation(
                    type: .fuelReceipt,
                    date: Date(),
                    amount: value,
                    photos: urls,
                    vehiclePlate: arac.plakaFormatli,
                    notes: cleanNotes
                )
                viewModel.officeOperationEkle(operation)
                finishSuccess()
            case .washing:
                viewModel.addWashingRecord(
                    aracId: arac.id,
                    price: value,
                    photoURLs: urls,
                    notes: cleanNotes
                ) { ok in
                    if ok {
                        finishSuccess()
                    } else {
                        showCompletion = false
                        isSaving = false
                    }
                }
            }
        }
    }

    private func uploadPhotos(completion: @escaping ([String]) -> Void) {
        guard !selectedImages.isEmpty else {
            completion([])
            return
        }
        var urls: [String] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for image in selectedImages {
            group.enter()
            let path = "franchises/\(FirebaseService.shared.currentFranchiseId)/office_operations/\(UUID().uuidString).jpg"
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
            completion(urls)
        }
    }

    private func finishSuccess() {
        HapticManager.shared.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            completionSucceeded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            dismiss()
        }
    }
}

// Expose form metrics for this file (private in WheelSysPalantirFormComponents)
private enum WheelSysPalantirFormMetrics {
    static let scrollSpacing: CGFloat = 15
    static let scrollHPadding: CGFloat = 13
    static let scrollVPadding: CGFloat = 11
}
