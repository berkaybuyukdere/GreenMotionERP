import SwiftUI
import UIKit

private enum TurkeyCheckoutTermsTextBundle {
    static func load(preferredEnglish: Bool) -> String {
        let name = preferredEnglish ? "rental_terms_en" : "rental_terms_tr"
        if let url = Bundle.main.url(forResource: name, withExtension: "txt"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Resources/RentalTerms"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        return preferredEnglish
            ? "Terms text is missing from the app bundle. Please reinstall or contact support."
            : "Kosul metni uygulama paketinde yok. Lutfen yeniden yukleyin veya destege basvurun."
    }
}

struct TurkeyCheckoutComplianceWizardView: View {
    @Binding var isPresented: Bool
    let draftExit: ExitIslemi
    let arac: Arac
    let vehiclePhotos: [UIImage]
    let damagePhotos: [UIImage]
    let franchiseDisplayName: String
    /// Çıkışta yalnızca araç (exit) formu imzalanır; genel koşullar iade sırasında tamamlanır.
    var includeGeneralRentalTerms: Bool = true
    var existingVehicleSignature: UIImage? = nil
    let commercialTitle: String
    let branchDisplayName: String
    let customerNationalId: String
    let staffSignerNameFallback: String?
    var existingSignedTermsPdfData: Data? = nil
    var initialTermsPreferredEnglish: Bool? = nil
    var onTermsAccepted: (_ languageCode: String, _ signedTermsDocument: Data) -> Void
    var onFinished: (_ customerSignature: UIImage?) -> Void

    private enum Step: Int {
        case terms = 0
        case pdfReview = 1
        case pdfSign = 2
    }

    @State private var step: Step = .terms
    @State private var useEnglish = false
    @State private var termsBody: String = TurkeyCheckoutTermsTextBundle.load(preferredEnglish: false)
    @State private var didAcceptRead = false
    @State private var termsReadingComplete = false
    @State private var termsSignSlotIndex = 0
    @State private var termsSlotStrokes: [[CGPoint]] = []
    @State private var termsSlotCanvasSize: CGSize = CGSize(width: 320, height: 200)
    @State private var collectedTermSignatures: [UIImage] = []
    @State private var marketingAllowCall = false
    @State private var marketingAllowEmail = false
    @State private var marketingAllowSms = false

    @State private var pdfData: Data?
    @State private var pdfPrepFailed = false
    @State private var isPreparingPdf = false
    @State private var pdfSigningSessionId = UUID()
    @State private var pdfSignStrokes: [[CGPoint]] = []
    @State private var pdfSignCanvasSize: CGSize = CGSize(width: 320, height: 160)
    @State private var showingSavedTermsPreview = false
    @State private var showingSavedVehiclePreview = false
    @State private var termsRedoRequested = false
    @State private var vehicleRedoRequested = false

    private var signatureSlots: Int {
        TurkeyRentalTermsPlaceholders.signaturePlaceholderCount(in: termsBody)
    }

    private var termsSlotStrokePoints: Int {
        termsSlotStrokes.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .terms: termsStep
                case .pdfReview: pdfReviewStep
                case .pdfSign: pdfSignStep
                }
            }
            .navigationTitle(navigationTitleForStep)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { isPresented = false }
                }
                if step == .pdfReview, pdfData != nil, !isPreparingPdf, !pdfPrepFailed {
                    if showingSavedVehiclePreview {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("tr_compliance.redo_sign".localized) {
                                HapticManager.shared.light()
                                vehicleRedoRequested = true
                                showingSavedVehiclePreview = false
                                pdfSignStrokes.removeAll()
                                step = .pdfSign
                            }
                        }
                    } else {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("tr_checkout.wizard_next_to_sign".localized) {
                                HapticManager.shared.light()
                                pdfSignStrokes.removeAll()
                                step = .pdfSign
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                if step == .pdfSign {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button("tr_terms.clear_pad".localized) {
                                HapticManager.shared.light()
                                pdfSignStrokes.removeAll()
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("tr_checkout.wizard_sign_done_now".localized) {
                                HapticManager.shared.medium()
                                finishPdfSignIfPossible()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(pdfSignPointCount <= 4)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            if let initialTermsPreferredEnglish {
                useEnglish = initialTermsPreferredEnglish
            }
            termsBody = TurkeyCheckoutTermsTextBundle.load(preferredEnglish: useEnglish)
            if !includeGeneralRentalTerms {
                if let sig = existingVehicleSignature, !vehicleRedoRequested {
                    prepareSignedVehiclePreview(signature: sig)
                } else {
                    prepareVehiclePdfOnly()
                }
            }
        }
        .onChange(of: useEnglish) { _, v in
            termsBody = TurkeyCheckoutTermsTextBundle.load(preferredEnglish: v)
            resetTermsSignatureFlow()
        }
    }

    private func resetTermsSignatureFlow() {
        termsReadingComplete = false
        termsSignSlotIndex = 0
        termsSlotStrokes.removeAll()
        collectedTermSignatures.removeAll()
    }

    private var navigationTitleForStep: String {
        switch step {
        case .terms:
            if termsReadingComplete {
                return String(format: "tr_terms.signature_slot_nav".localized, termsSignSlotIndex + 1, max(signatureSlots, 1))
            }
            return "tr_terms.title".localized
        case .pdfReview: return "tr_checkout.wizard_pdf_review_nav".localized
        case .pdfSign: return "tr_checkout.wizard_sign_step_nav".localized
        }
    }

    private var prefilledHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("tr_terms.prefilled_header_title_checkout".localized)
                .font(.custom("Helvetica-Bold", size: 13))
            Group {
                labeled("tr_terms.field.plate".localized, arac.plakaFormatli)
                labeled("tr_terms.field.renter".localized, draftExit.customerFullName.isEmpty ? "—" : draftExit.customerFullName)
                labeled("tr_terms.field.email".localized, (draftExit.customerEmail ?? "").isEmpty ? "—" : (draftExit.customerEmail ?? ""))
                labeled("tr_terms.field.checkout_date".localized, formatted(date: draftExit.exitTarihi))
                if let p = draftExit.pickUpBranch, !p.isEmpty {
                    labeled("tr_terms.field.pickup_branch".localized, TurkiyeGarajSubeleri.displayTitle(forStoredKey: p))
                }
                if let d = draftExit.dropOffBranch, !d.isEmpty {
                    labeled("tr_terms.field.dropoff_branch".localized, TurkiyeGarajSubeleri.displayTitle(forStoredKey: d))
                }
                if let nav = draftExit.navKodu?.trimmingCharacters(in: .whitespacesAndNewlines), !nav.isEmpty {
                    labeled("tr_terms.field.nav_code".localized, nav)
                }
                if !commercialTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    labeled("tr_terms.field.commercial_title".localized, commercialTitle)
                }
                if !branchDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    labeled("tr_terms.field.branch_name".localized, branchDisplayName)
                }
                let nid = customerNationalId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !nid.isEmpty {
                    labeled("National ID".localized, nid)
                }
            }
            .font(.custom("Helvetica", size: 13))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.custom("Helvetica-Bold", size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func formatted(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: useEnglish ? "en_US_POSIX" : "tr_TR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private var termsFillContext: TurkeyRentalTermsFillContext {
        TurkeyRentalTermsFillContext(
            customerFirstName: draftExit.customerFirstName ?? "",
            customerLastName: draftExit.customerLastName ?? "",
            testDriverFirstName: draftExit.testDriverFirstName,
            testDriverLastName: draftExit.testDriverLastName,
            customerNationalId: customerNationalId,
            commercialTitle: commercialTitle,
            branchDisplayName: branchDisplayName,
            agreementDate: draftExit.exitTarihi,
            localeIdentifier: TurkeyRentalTermsFillContext.localeForTermsLanguageCode(useEnglish ? "en" : "tr"),
            callPermissionAllowed: marketingAllowCall,
            emailPermissionAllowed: marketingAllowEmail,
            smsPermissionAllowed: marketingAllowSms,
            useEnglishPermissionLabels: useEnglish
        )
    }

    private var filledTermsForMultiSlotPreview: String {
        TurkeyRentalTermsPlaceholders.applyForMultiSignaturePdf(to: termsBody, context: termsFillContext)
    }

    private var hasExistingSignedTermsPdf: Bool {
        guard let d = existingSignedTermsPdfData else { return false }
        return TurkeyRentalTermsPlaceholders.isPdfDocumentData(d)
    }

    private var termsStep: some View {
        Group {
            if !includeGeneralRentalTerms {
                ProgressView("tr_terms.preparing_pdf".localized)
            } else if !termsReadingComplete {
                termsReadingScroll
            } else {
                termsSignatureSlotPage
            }
        }
    }

    private func prepareVehiclePdfOnly() {
        isPreparingPdf = true
        pdfPrepFailed = false
        DispatchQueue.global(qos: .userInitiated).async {
            let vehiclePdf = ExitPDFGenerator.shared.makeTurkeyCheckoutPdfDataForSignatureOverlay(
                exit: draftExit,
                arac: arac,
                vehiclePhotos: vehiclePhotos,
                damagePhotos: damagePhotos,
                franchiseDisplayName: franchiseDisplayName,
                staffSignerNameFallback: staffSignerNameFallback
            )
            DispatchQueue.main.async {
                isPreparingPdf = false
                guard let vehiclePdf else {
                    pdfPrepFailed = true
                    return
                }
                pdfData = vehiclePdf
                pdfSigningSessionId = UUID()
                showingSavedVehiclePreview = false
                step = .pdfReview
            }
        }
    }

    private func prepareSignedVehiclePreview(signature: UIImage) {
        isPreparingPdf = true
        pdfPrepFailed = false
        DispatchQueue.global(qos: .userInitiated).async {
            let vehiclePdf = ExitPDFGenerator.shared.makeTurkeyCheckoutPdfDataWithCustomerSignature(
                exit: draftExit,
                arac: arac,
                vehiclePhotos: vehiclePhotos,
                damagePhotos: damagePhotos,
                franchiseDisplayName: franchiseDisplayName,
                staffSignerNameFallback: staffSignerNameFallback,
                customerSignature: signature
            )
            DispatchQueue.main.async {
                isPreparingPdf = false
                guard let vehiclePdf else {
                    pdfPrepFailed = true
                    prepareVehiclePdfOnly()
                    return
                }
                pdfData = vehiclePdf
                pdfSigningSessionId = UUID()
                showingSavedVehiclePreview = true
                step = .pdfReview
            }
        }
    }

    private var termsReadingScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("tr_terms.wizard_order_hint".localized)
                    .font(.custom("Helvetica", size: 14))
                    .foregroundStyle(.secondary)

                Text("tr_terms.legal_disclaimer_eidas".localized)
                    .font(.custom("Helvetica", size: 12))
                    .foregroundStyle(.secondary)

                Picker("", selection: $useEnglish) {
                    Text("Türkçe").tag(false)
                    Text("English").tag(true)
                }
                .pickerStyle(.segmented)

                prefilledHeader

                TurkeyRentalTermsFilledStackView(
                    rawTerms: termsBody,
                    context: termsFillContext,
                    termsStrokes: [],
                    termsCanvasSize: .init(width: 320, height: 160),
                    showsInlineSignaturePreview: false
                )

                Toggle("tr_terms.read_accept_toggle".localized, isOn: $didAcceptRead)
                    .font(.custom("Helvetica", size: 14))

                if didAcceptRead {
                    TurkeyMarketingConsentSection(
                        allowCall: $marketingAllowCall,
                        allowEmail: $marketingAllowEmail,
                        allowSms: $marketingAllowSms,
                        useEnglish: useEnglish
                    )
                }
            }
            .padding()
            .padding(.bottom, 72)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                HapticManager.shared.medium()
                termsReadingComplete = true
                termsSignSlotIndex = 0
                termsSlotStrokes.removeAll()
                collectedTermSignatures.removeAll()
            } label: {
                Text("tr_terms.continue_to_signatures".localized)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(didAcceptRead ? Color.accentColor : Color.gray.opacity(0.45))
            }
            .disabled(!didAcceptRead)
            .buttonStyle(.plain)
            .background(.bar)
        }
    }

    private var termsSignatureSlotPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            if signatureSlots > 0 {
                TurkeyTermsMultiSignatureScrollPreview(
                    filledWithSlotMarkers: filledTermsForMultiSlotPreview,
                    isTurkishLayout: !useEnglish,
                    activeSlotIndex: termsSignSlotIndex,
                    collectedSignatures: collectedTermSignatures,
                    totalSlots: signatureSlots,
                    hasExistingSavedPdf: hasExistingSignedTermsPdf
                )
                .padding(.horizontal)
            }

            Text("\(termsSignSlotIndex + 1)/\(max(signatureSlots, 1))")
                .font(.title2.bold().monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

            TurkeyMarketingConsentSection(
                allowCall: $marketingAllowCall,
                allowEmail: $marketingAllowEmail,
                allowSms: $marketingAllowSms,
                useEnglish: useEnglish
            )
            .padding(.horizontal)

            TurkeyTermsSignaturePad(strokes: $termsSlotStrokes) { termsSlotCanvasSize = $0 }
                .frame(height: 220)
                .padding(.horizontal)

            HStack {
                Button("tr_terms.clear_pad".localized) {
                    HapticManager.shared.light()
                    termsSlotStrokes.removeAll()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(nextButtonTitle) {
                    HapticManager.shared.light()
                    advanceTermsSignatureFlow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(termsSlotStrokePoints <= 4)
            }
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var nextButtonTitle: String {
        let last = termsSignSlotIndex >= max(signatureSlots - 1, 0)
        return last ? "tr_checkout.wizard_next_pdf".localized : "tr_terms.signature_next_slot".localized
    }

    private func advanceTermsSignatureFlow() {
        guard let png = TurkeyTermsSignaturePad.rasterizeSignaturePNG(strokes: termsSlotStrokes, canvasSize: termsSlotCanvasSize),
              let img = UIImage(data: png) else { return }
        collectedTermSignatures.append(img)
        termsSlotStrokes.removeAll()
        if termsSignSlotIndex >= max(signatureSlots - 1, 0) {
            finalizeAllTermsSignaturesAndOpenVehiclePdf()
        } else {
            termsSignSlotIndex += 1
        }
    }

    private func finalizeAllTermsSignaturesAndOpenVehiclePdf() {
        let lang = useEnglish ? "en" : "tr"
        let raw = termsBody
        let ctx = termsFillContext
        let slots = max(signatureSlots, 0)
        let imagesSnapshot = collectedTermSignatures
        isPreparingPdf = true
        pdfPrepFailed = false
        DispatchQueue.global(qos: .userInitiated).async {
            let docData: Data?
            let turkishPdfLayout = (lang != "en")
            if slots == 0 {
                let filled = TurkeyRentalTermsPlaceholders.apply(to: raw, context: ctx, embedSignatureMarker: false)
                docData = TurkeyRentalTermsPlaceholders.makePdfData(
                    filledWithMarkers: filled,
                    signatureImage: nil,
                    isTurkishLayout: turkishPdfLayout
                )
            } else {
                let filled = TurkeyRentalTermsPlaceholders.applyForMultiSignaturePdf(to: raw, context: ctx)
                docData = TurkeyRentalTermsPlaceholders.makePdfDataMulti(
                    filledWithSlotMarkers: filled,
                    signatureImages: imagesSnapshot,
                    isTurkishLayout: turkishPdfLayout
                )
            }
            guard let termsPdf = docData else {
                DispatchQueue.main.async {
                    isPreparingPdf = false
                    pdfPrepFailed = true
                }
                return
            }
            DispatchQueue.main.async {
                onTermsAccepted(lang, termsPdf)
            }
            let vehiclePdf = ExitPDFGenerator.shared.makeTurkeyCheckoutPdfDataForSignatureOverlay(
                exit: draftExit,
                arac: arac,
                vehiclePhotos: vehiclePhotos,
                damagePhotos: damagePhotos,
                franchiseDisplayName: franchiseDisplayName,
                staffSignerNameFallback: staffSignerNameFallback
            )
            DispatchQueue.main.async {
                isPreparingPdf = false
                guard let vehiclePdf else {
                    pdfPrepFailed = true
                    return
                }
                pdfData = vehiclePdf
                pdfSigningSessionId = UUID()
                step = .pdfReview
            }
        }
    }

    private var pdfReviewStep: some View {
        Group {
            if isPreparingPdf {
                ProgressView("tr_terms.preparing_pdf".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pdfPrepFailed || pdfData == nil {
                Text("tr_terms.pdf_failed".localized)
                    .foregroundStyle(.red)
                    .padding()
            } else if let data = pdfData {
                VStack(spacing: 0) {
                    Text("tr_checkout.wizard_pdf_review_hint".localized)
                        .font(.custom("Helvetica", size: 13))
                        .foregroundStyle(.secondary)
                        .padding(10)
                    TurkeyReadOnlyPdfRepresentable(pdfData: data)
                        .id(pdfSigningSessionId)
                        .edgesIgnoringSafeArea(.bottom)
                }
            }
        }
    }

    private var pdfSignStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tr_checkout.wizard_sign_step_hint".localized)
                .font(.custom("Helvetica", size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            TurkeyTermsSignaturePad(strokes: $pdfSignStrokes) { pdfSignCanvasSize = $0 }
                .frame(height: 200)
                .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var pdfSignPointCount: Int {
        pdfSignStrokes.reduce(0) { $0 + $1.count }
    }

    private func finishPdfSignIfPossible() {
        guard step == .pdfSign else { return }
        guard pdfSignPointCount > 4 else { return }
        guard let data = TurkeyTermsSignaturePad.rasterizeSignaturePNG(strokes: pdfSignStrokes, canvasSize: pdfSignCanvasSize),
              let img = UIImage(data: data) else { return }
        HapticManager.shared.success()
        onFinished(img)
        isPresented = false
    }
}
