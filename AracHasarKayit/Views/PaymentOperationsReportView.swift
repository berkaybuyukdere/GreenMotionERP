import SwiftUI
import FirebaseFirestore

/// Switzerland (CH): card scan + Luhn validation only (no payments).
struct PaymentOperationsReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var customerReference = ""
    @State private var plate = ""
    @State private var descriptionText = ""

    @State private var lastScanResult: CHScannedCardResult?
    @State private var showCardScan = false
    @State private var isSavingScan = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @State private var recentCardScans: [CardScanRecord] = []
    @State private var cardScansListener: ListenerRegistration?

    private var franchiseId: String {
        let sid = FirebaseService.shared.currentFranchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !sid.isEmpty { return sid }
        return authManager.userProfile?.franchiseId
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "CH"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                if let successMessage {
                    Text(successMessage)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                cardScanSection
                recentCardScansSection
            }
            .padding()
        }
        .navigationTitle("Card Verification".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back".localized)
                    }
                }
            }
        }
        .onAppear {
            StripeCHCardScanService.configureIfNeeded()
            subscribeRecentCardScans()
        }
        .onDisappear {
            cardScansListener?.remove()
            cardScansListener = nil
        }
        .fullScreenCover(isPresented: $showCardScan) {
            CardScanLauncherView { result in
                showCardScan = false
                handleCardScan(result)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Card scan & verification".localized, systemImage: "camera.viewfinder")
                .font(.headline)
            Text("ch_stripe.card_verify_intro".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Text(franchiseId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private var cardScanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            optionalField("Customer reference".localized, text: $customerReference,
                          placeholder: "RES / contract no.")
            optionalField("Plate".localized, text: $plate, placeholder: "ZH 123456")
            optionalField("Note".localized, text: $descriptionText,
                          placeholder: "ch_stripe.description_placeholder".localized)

            if let scan = lastScanResult {
                scanResultCard(scan)
            }

            Button {
                showCardScan = true
            } label: {
                HStack(spacing: 8) {
                    if isSavingScan {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "camera.viewfinder")
                    }
                    Text("Scan card with camera".localized)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSavingScan)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func scanResultCard(_ scan: CHScannedCardResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: scan.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(scan.isValid ? .green : .red)
            VStack(alignment: .leading, spacing: 3) {
                Text(scan.maskedDisplay)
                    .font(.headline.monospaced())
                Text(scan.brandName.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(scan.validationMessage)
                    .font(.subheadline)
                    .foregroundStyle(scan.isValid ? .green : .red)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(scan.isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }

    private var recentCardScansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent card scans".localized)
                .font(.subheadline.weight(.semibold))
            if recentCardScans.isEmpty {
                Text("ch_stripe.no_card_scans_yet".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentCardScans) { scan in
                    HStack(spacing: 10) {
                        Image(systemName: scan.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(scan.isValid ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scan.maskedDisplay)
                                .font(.subheadline.weight(.semibold).monospaced())
                            Text(scan.brand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !scan.customerReference.isEmpty {
                                Text(scan.customerReference)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let date = scan.createdAt {
                            Text(date, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    private func optionalField(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Card scan

    private func handleCardScan(_ result: Result<CHScannedCardResult, Error>) {
        switch result {
        case .success(let scan):
            lastScanResult = scan
            HapticManager.shared.light()
            Task {
                isSavingScan = true
                defer { isSavingScan = false }
                do {
                    try await StripeCHCardScanService.saveScanRecord(
                        franchiseId: franchiseId,
                        result: scan,
                        customerReference: customerReference,
                        plate: plate,
                        description: descriptionText
                    )
                    successMessage = scan.isValid
                        ? "ch_stripe.card_valid".localized
                        : "ch_stripe.card_invalid".localized
                    errorMessage = nil
                    scan.isValid
                        ? HapticManager.shared.success()
                        : HapticManager.shared.error()
                } catch {
                    errorMessage = error.localizedDescription
                    successMessage = nil
                }
            }
        case .failure(let error):
            if let scanError = error as? StripeCHCardScanServiceError,
               case .cancelled = scanError {
                return
            }
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    // MARK: - Firestore

    private func subscribeRecentCardScans() {
        cardScansListener?.remove()
        let ref = Firestore.firestore()
            .collection("franchises").document(franchiseId)
            .collection("cardScans")
            .order(by: "createdAt", descending: true)
            .limit(to: 25)
        cardScansListener = ref.addSnapshotListener { snap, _ in
            guard let docs = snap?.documents else { return }
            recentCardScans = docs.compactMap { CardScanRecord(document: $0) }
        }
    }
}

// MARK: - Card scan launcher (back button + start)

private struct CardScanLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    let onFinished: (Result<CHScannedCardResult, Error>) -> Void

    @State private var launchStripeScan = false
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "creditcard.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(AppTheme.primary)
                Text("ch_stripe.scan_launcher_hint".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if let scanError {
                    Text(scanError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
                Button {
                    scanError = nil
                    launchStripeScan = true
                } label: {
                    Text("Scan card with camera".localized)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppTheme.padding)
                .padding(.bottom, AppTheme.paddingLarge)
            }
            .navigationTitle("Card scan & verification".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back".localized)
                        }
                    }
                }
            }
            .background {
                if launchStripeScan {
                    CardScanUIKitBridge { result in
                        launchStripeScan = false
                        switch result {
                        case .success(let scan):
                            onFinished(.success(scan))
                        case .failure(let error):
                            if let scanError = error as? StripeCHCardScanServiceError,
                               case .cancelled = scanError {
                                return
                            }
                            scanError = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}

// MARK: - UIKit bridge (reliable re-present)

private struct CardScanUIKitBridge: UIViewControllerRepresentable {
    let onFinished: (Result<CHScannedCardResult, Error>) -> Void

    func makeUIViewController(context: Context) -> CardScanPresenterViewController {
        let vc = CardScanPresenterViewController()
        vc.onFinished = { result in
            onFinished(result)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: CardScanPresenterViewController, context: Context) {
        uiViewController.startScanIfNeeded()
    }
}

private final class CardScanPresenterViewController: UIViewController {
    var onFinished: ((Result<CHScannedCardResult, Error>) -> Void)?
    private var didStartScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    func startScanIfNeeded() {
        guard !didStartScan else { return }
        didStartScan = true
        StripeCHCardScanService.configureIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            StripeCHCardScanService.presentScan(from: self) { [weak self] result in
                self?.didStartScan = false
                self?.onFinished?(result)
            }
        }
    }
}

// MARK: - Models

private struct CardScanRecord: Identifiable {
    let id: String
    let last4: String
    let brand: String
    let isValid: Bool
    let customerReference: String
    let createdAt: Date?

    var maskedDisplay: String {
        StripeCHCardScanService.maskedDisplay(last4: last4)
    }

    init?(document: QueryDocumentSnapshot) {
        let d = document.data()
        id = document.documentID
        last4 = d["last4"] as? String ?? "????"
        brand = d["brand"] as? String ?? ""
        isValid = d["isValid"] as? Bool ?? false
        customerReference = d["customerReference"] as? String ?? ""
        if let ts = d["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = nil
        }
    }
}
