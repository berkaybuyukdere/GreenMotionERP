import SwiftUI
import UIKit

struct WheelSysNTRActionSheet: View {
    let arac: Arac
    let fleetVehicle: WheelSysFleetVehicle?
    let onComplete: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var viewModel: AracViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    @ObservedObject private var fleetStore = WheelSysVehicleFleetStatusStore.shared
    @State private var selectedType: WheelSysNTRType = .repair
    @State private var mileageText = ""
    @State private var fuelEighths = 8
    @State private var working = false
    @State private var errorMessage: String?
    @State private var ntrPhotos: [UIImage] = []
    @State private var showCamera = false
    @State private var notesText = ""

    private var liveArac: Arac {
        viewModel.araclar.first(where: { $0.id == arac.id }) ?? arac
    }

    private var ntrContext: WheelSysNTRResolvedContext {
        WheelSysNTRService.resolveContext(arac: liveArac, fleetStore: fleetStore)
    }

    private var isCloseMode: Bool { ntrContext.isCloseMode }

    private var stationCode: String {
        fleetVehicle?.station ?? "ZRH"
    }

    private var appUserDisplayName: String? {
        let profile = authManager.userProfile
        let display = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }
        let email = profile?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? nil : email
    }

    private var sortedNtrHistory: [WheelSysNTRHistoryEntry] {
        liveArac.wheelsysNtrHistory.sorted { $0.timestamp > $1.timestamp }
    }

    private var openOutboundResNo: String? {
        let exit = viewModel.exitIslemleri(for: arac)
            .filter { !$0.isDeleted && $0.status == .completed }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        let res = exit?.resKodu.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return res.isEmpty ? nil : res
    }

    private var hasOpenOutboundCheckout: Bool {
        let exits = viewModel.exitIslemleri(for: arac)
            .filter { !$0.isDeleted && $0.status == .completed }
        let returns = viewModel.iadeIslemleri(for: arac)
            .filter { !$0.isDeleted && $0.status == .completed }
        guard let latestExit = exits.max(by: { $0.createdAt < $1.createdAt }) else { return false }
        guard let latestReturn = returns.max(by: { $0.createdAt < $1.createdAt }) else { return true }
        return latestExit.createdAt > latestReturn.createdAt
    }

    private var hasOpenReturn: Bool {
        viewModel.iadeIslemleri(for: arac).contains {
            !$0.isDeleted && $0.status != .completed
        }
    }

    private var createBlockReason: WheelSysNTRCreateBlockReason? {
        guard !isCloseMode else { return nil }
        return WheelSysNTRService.createBlockReason(
            arac: liveArac,
            fleetStore: fleetStore,
            hasOpenOutboundCheckout: hasOpenOutboundCheckout,
            openCheckoutResNo: openOutboundResNo,
            hasOpenReturn: hasOpenReturn
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let doc = liveArac.wheelsysNtrDocNo, !doc.isEmpty, isCloseMode {
                        WheelSysPalantirSectionCard(title: "wheelsys_ntr.doc_no".localized, icon: "doc.text") {
                            Text(doc)
                                .font(PalantirTheme.dataFont(14))
                                .foregroundStyle(PalantirTheme.textPrimary)
                        }
                        .padding(.horizontal, 13)
                    }

                    if isCloseMode {
                        WheelSysPalantirSectionCard(
                            title: "wheelsys_ntr.close_section".localized,
                            icon: "arrow.down.circle"
                        ) {
                            vehicleFieldsContent(includeEntityId: true)
                        }
                        .padding(.horizontal, 13)
                    } else {
                        WheelSysPalantirSectionCard(
                            title: "wheelsys_ntr.type_section".localized,
                            icon: "list.bullet.rectangle"
                        ) {
                            ntrTypePicker
                        }
                        .padding(.horizontal, 13)

                        WheelSysPalantirSectionCard(
                            title: "wheelsys_ntr.vehicle_section".localized,
                            icon: "car"
                        ) {
                            vehicleFieldsContent(includeEntityId: false)
                        }
                        .padding(.horizontal, 13)
                    }

                    notesSection

                    ntrPhotoSection

                    if !sortedNtrHistory.isEmpty {
                        ntrHistorySection
                    }

                    if let block = createBlockReason, !isCloseMode {
                        WheelSysPalantirStatusStrip(
                            icon: "exclamationmark.triangle.fill",
                            message: block.localizedMessage,
                            tint: PalantirTheme.warning
                        )
                        .padding(.horizontal, 13)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(PalantirTheme.bodyFont(12))
                            .foregroundStyle(PalantirTheme.critical)
                            .padding(.horizontal, 13)
                    }

                    WheelSysPalantirPrimaryButton(
                        title: isCloseMode
                            ? "wheelsys_ntr.close_action".localized
                            : "wheelsys_ntr.create_action".localized,
                        isLoading: working,
                        disabled: working || (createBlockReason != nil && !isCloseMode)
                    ) {
                        Task { await submit() }
                    }
                    .padding(.horizontal, 13)
                }
                .padding(.vertical, 11)
            }
            .background(PalantirTheme.background)
            .navigationTitle(
                isCloseMode ? "wheelsys_ntr.close_title".localized : "wheelsys_ntr.create_title".localized
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) {
                        HapticManager.shared.light()
                        onCancel()
                    }
                    .disabled(working)
                }
            }
            .overlay {
                if working {
                    PalantirOpsBlockingOverlay(title: "wheelsys_ntr.working".localized)
                }
            }
            .sheet(isPresented: $showCamera) {
                WheelSysNTRCameraPicker { image in
                    if let image {
                        ntrPhotos.append(image)
                        HapticManager.shared.scanSuccess()
                    }
                }
            }
            .task {
                await fleetStore.refreshIfNeeded()
                await WheelSysNTRService.syncActiveNTRFromFleetIfNeeded(arac: liveArac, fleetStore: fleetStore)
            }
            .onAppear { prefill() }
        }
        .wheelSysCHOpsChrome()
    }

    @ViewBuilder
    private func vehicleFieldsContent(includeEntityId: Bool) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if includeEntityId, let entityId = ntrContext.entityId {
                palantirLabeledRow("ID", value: String(entityId), icon: "number")
            }
            palantirLabeledRow("Plaka".localized, value: liveArac.plakaFormatli, icon: "car.fill")
            palantirLabeledRow("Group".localized, value: fleetVehicle?.group ?? liveArac.kategori, icon: "square.grid.2x2")
            palantirLabeledRow("Station".localized, value: stationCode, icon: "mappin.and.ellipse")

            VStack(alignment: .leading, spacing: 6) {
                Text("KM".localized.uppercased())
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
                TextField("KM".localized, text: $mileageText)
                    .keyboardType(.numberPad)
                    .font(PalantirTheme.dataFont(14))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 11)
                    .background(PalantirTheme.surfaceHigh)
                    .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
            }

            WheelSysPalantirFuelSlider(label: "Fuel".localized, eighths: $fuelEighths, tint: PalantirTheme.warning)
        }
    }

    private func palantirLabeledRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PalantirTheme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
                Text(value)
                    .font(PalantirTheme.dataFont(13))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
            Spacer(minLength: 0)
        }
    }

    private var ntrHistorySection: some View {
        WheelSysPalantirSectionCard(title: "wheelsys_ntr.history_title".localized, icon: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sortedNtrHistory.prefix(12)) { entry in
                    ntrHistoryRow(entry)
                    if entry.id != sortedNtrHistory.prefix(12).last?.id {
                        Rectangle().fill(PalantirTheme.border).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 13)
    }

    private func ntrHistoryRow(_ entry: WheelSysNTRHistoryEntry) -> some View {
        let actionLabel = entry.action == .opened
            ? "wheelsys_ntr.history_opened".localized
            : "wheelsys_ntr.history_closed".localized
        let who = [entry.wheelsysUserName, entry.appUserName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let doc = entry.docNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typeLabel: String? = {
            guard entry.action == .opened, let raw = entry.ntrType,
                  let type = WheelSysNTRType(rawValue: raw) else { return nil }
            return type.titleKey.localized
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: entry.action == .opened ? "wrench.and.screwdriver" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.action == .opened ? PalantirTheme.warning : PalantirTheme.success)
                Text(actionLabel)
                    .font(PalantirTheme.labelFont(10))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer(minLength: 0)
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            if !doc.isEmpty {
                Text(doc)
                    .font(PalantirTheme.dataFont(12))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
            if let typeLabel {
                Text(typeLabel)
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            if !who.isEmpty {
                Text(who)
                    .font(PalantirTheme.bodyFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            if let km = entry.km {
                Text(String(format: "wheelsys_ntr.history_km_fuel".localized, km, entry.fuelEighths ?? 0))
                    .font(PalantirTheme.labelFont(9))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Text(notes)
                    .font(PalantirTheme.bodyFont(11))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
        }
    }

    private var notesSection: some View {
        WheelSysPalantirSectionCard(title: "wheelsys_ntr.notes_section".localized, icon: "note.text") {
            TextField("wheelsys_ntr.notes_placeholder".localized, text: $notesText, axis: .vertical)
                .lineLimit(3...6)
                .font(PalantirTheme.bodyFont(13))
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .background(PalantirTheme.surfaceHigh)
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
        .padding(.horizontal, 13)
    }

    private var ntrPhotoSection: some View {
        WheelSysPalantirSectionCard(title: "Photos".localized, icon: "camera.fill") {
            VStack(alignment: .leading, spacing: 10) {
                if ntrPhotos.isEmpty {
                    Text("Optional photos for this NTR record.".localized)
                        .font(PalantirTheme.bodyFont(12))
                        .foregroundStyle(PalantirTheme.textMuted)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(ntrPhotos.enumerated()), id: \.offset) { index, photo in
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipped()
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            HapticManager.shared.light()
                                            ntrPhotos.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, PalantirTheme.critical)
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                            }
                        }
                    }
                }
                Button {
                    HapticManager.shared.selection()
                    showCamera = true
                } label: {
                    Label("Add photo".localized, systemImage: "camera.fill")
                        .font(PalantirTheme.labelFont(12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(PalantirTheme.accent)
                        .background(PalantirTheme.surfaceHigh)
                        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
        .padding(.horizontal, 13)
    }

    private var ntrTypePicker: some View {
        HStack(spacing: 6) {
            ForEach(WheelSysNTRType.allCases) { type in
                let isSelected = selectedType == type
                Button {
                    HapticManager.shared.selection()
                    selectedType = type
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: type.iconName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(type.titleKey.localized)
                            .font(PalantirTheme.labelFont(9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isSelected ? PalantirTheme.warning : PalantirTheme.textMuted)
                    .background(isSelected ? PalantirTheme.warning.opacity(0.12) : PalantirTheme.surfaceHigh)
                    .overlay(
                        Rectangle().stroke(
                            isSelected ? PalantirTheme.warning.opacity(0.55) : PalantirTheme.border,
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
    }

    private func prefill() {
        let km = fleetVehicle?.mileage ?? liveArac.wheelsysNtrStartKm ?? liveArac.lastCheckIn?.km ?? 0
        mileageText = WheelSysZurichDateTime.formatKmText(km)
        fuelEighths = liveArac.wheelsysNtrStartFuel ?? liveArac.lastCheckIn?.fuelEighths ?? 8
    }

    private var trimmedNotes: String? {
        let trimmed = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    private func submit() async {
        working = true
        errorMessage = nil
        defer { working = false }

        guard let payload = WheelSysNTRService.buildVehiclePayload(arac: liveArac, fleetVehicle: fleetVehicle) else {
            let message = "wheelsys_ntr.missing_vehicle_link".localized
            HapticManager.shared.error()
            ToastManager.shared.show(message, type: .error)
            errorMessage = message
            return
        }

        let km = WheelSysZurichDateTime.parseKmText(mileageText)
        let station = stationCode
        let context = WheelSysNTRService.resolveContext(arac: liveArac, fleetStore: fleetStore)

        if context.isCloseMode, let entityId = context.entityId {
            let request = WheelSysNTRCloseRequest(
                ntrEntityId: entityId,
                closeKm: km,
                closeFuelEighths: fuelEighths,
                closeDateTime: nil,
                station: station
            )
            let result = await WheelSysNTRService.closeNTR(
                arac: liveArac,
                request: request,
                appUserName: appUserDisplayName,
                localNotes: trimmedNotes
            )
            switch result {
            case .success:
                await uploadNtrPhotosIfNeeded()
                await fleetStore.refresh(force: true)
                HapticManager.shared.success()
                ToastManager.shared.show("wheelsys_ntr.close_success".localized, type: .success)
                WheelSysActivityReporter.record(
                    .ntrClose(plate: liveArac.plakaFormatli, docNo: liveArac.wheelsysNtrDocNo),
                    viewModel: viewModel,
                    userProfile: authManager.userProfile
                )
                onComplete()
            case .failure(let error):
                HapticManager.shared.error()
                ToastManager.shared.show(error.localizedDescription, type: .error)
                errorMessage = error.localizedDescription
            }
        } else {
            if let block = createBlockReason {
                errorMessage = block.localizedMessage
                HapticManager.shared.error()
                return
            }
            var vehicle = payload
            vehicle = WheelSysNTRVehiclePayload(
                plateNo: payload.plateNo,
                wheelsysVehicleId: payload.wheelsysVehicleId,
                carGroup: payload.carGroup,
                modelName: payload.modelName,
                modelId: payload.modelId,
                mileage: km > 0 ? km : payload.mileage,
                fuelEighths: fuelEighths
            )
            let request = WheelSysNTRService.defaultCreateRequest(
                vehicle: vehicle,
                type: selectedType,
                station: station
            )
            let result = await WheelSysNTRService.createNTR(
                arac: liveArac,
                request: request,
                appUserName: appUserDisplayName,
                localNotes: trimmedNotes
            )
            switch result {
            case .success(let created):
                await uploadNtrPhotosIfNeeded()
                let doc = created.docNo ?? "ID \(created.entityId)"
                HapticManager.shared.success()
                ToastManager.shared.show(
                    String(format: "wheelsys_ntr.create_success".localized, doc),
                    type: .success
                )
                WheelSysActivityReporter.record(
                    .ntrOpen(plate: liveArac.plakaFormatli, docNo: doc),
                    viewModel: viewModel,
                    userProfile: authManager.userProfile
                )
                onComplete()
            case .failure(let error):
                HapticManager.shared.error()
                ToastManager.shared.show(error.localizedDescription, type: .error)
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func uploadNtrPhotosIfNeeded() async {
        guard !ntrPhotos.isEmpty else { return }
        let fid = FirebaseService.shared.currentFranchiseId.uppercased()
        for photo in ntrPhotos {
            let path = "franchises/\(fid)/ntr-photos/\(liveArac.id.uuidString)/\(UUID().uuidString).jpg"
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                CachedImageManager.shared.uploadImage(photo, path: path) { _, _ in
                    continuation.resume()
                }
            }
        }
    }
}

private struct WheelSysNTRCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}
