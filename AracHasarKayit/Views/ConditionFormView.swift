import SwiftUI
import UIKit

struct ConditionFormView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @StateObject private var formViewModel: ConditionFormViewModel

    @State private var isGeneratingPDF = false
    @State private var pdfURL: URL?
    @State private var showShareSheet = false
    @State private var isSavingDamage = false
    @State private var showRecordsExpanded = true
    @State private var expandedRecordIds: Set<UUID> = []
    @State private var markerScale: CGFloat = 1.0
    @State private var markerDeleteTarget: HasarKaydi?
    @State private var showMarkerDeleteAlert = false

    init(arac: Arac) {
        _formViewModel = StateObject(wrappedValue: ConditionFormViewModel(arac: arac))
    }

    private var liveVehicle: Arac {
        viewModel.araclar.first(where: { $0.id == formViewModel.arac.id }) ?? formViewModel.arac
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                canvasSection
                damageEditorSection
                previousRecordsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Condition Form".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { exportPDF() } label: {
                    if isGeneratingPDF {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isGeneratingPDF)
            }
        }
        .onAppear {
            formViewModel.sync(with: liveVehicle.hasarKayitlari)
        }
        .onReceive(viewModel.$araclar) { _ in
            formViewModel.sync(with: liveVehicle.hasarKayitlari)
        }
        .sheet(isPresented: $showShareSheet) {
            if let pdfURL {
                ActivityViewController(activityItems: [pdfURL])
            }
        }
        .alert("Delete marker?", isPresented: $showMarkerDeleteAlert, presenting: markerDeleteTarget) { damage in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.hasarConditionMappingSil(aracId: liveVehicle.id, hasarId: damage.id) { ok in
                    if ok {
                        formViewModel.unmapDamageLocally(damage.id)
                        ToastManager.shared.show("Marker mapping removed", type: .success)
                    } else {
                        ToastManager.shared.show("Marker mapping remove failed", type: .error)
                    }
                }
            }
        } message: { damage in
            Text("Marker #\(damage.markerNumber ?? 0) will be removed from damage map only. Damage record will stay.")
        }
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        VehicleConditionCanvasView(
            conditionDamages: formViewModel.conditionDamages,
            selectedRegionId: formViewModel.selectedRegionId,
            draftRefX:        formViewModel.draftRefX,
            draftRefY:        formViewModel.draftRefY,
            showDraftMarker:  formViewModel.draftViewBlockId != nil,
            nextMarkerNumber: formViewModel.nextMarkerNumber,
            markerScale:      markerScale,
            onTap:        { refPt in formViewModel.handleCanvasTap(refX: refPt.x, refY: refPt.y) },
            onMarkerTap:  { dmg in
                markerDeleteTarget = dmg
                showMarkerDeleteAlert = true
            },
            onDraftDrag:  { refPt in formViewModel.handleDraftDrag(refX: refPt.x, refY: refPt.y) }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 4)
    }

    // MARK: - Damage Editor

    private var damageEditorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("Damage Editor")
                    .font(.headline)
                Spacer()
                if formViewModel.selectedDamageId != nil {
                    Button("New Marker") {
                        formViewModel.clearSelection()
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
            }

            // Active region badge
            if let regionId = formViewModel.selectedRegionId,
               let region   = VehicleRegionDef.region(id: regionId) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.orange)
                    Text(region.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    if let blockName = VehicleViewBlock.block(id: region.viewBlockId)?.displayName {
                        Text("· \(blockName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Tap the diagram to select a region")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Region picker (full list via menu)
            HStack {
                Text("Region").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Menu {
                    ForEach(VehicleRegionDef.allRegions) { r in
                        Button(r.displayName) { formViewModel.selectRegionCenter(r.id) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formViewModel.selectedRegionId.flatMap { VehicleRegionDef.region(id: $0)?.displayName } ?? "Select Area")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundColor(.orange)
                }
            }

            HStack {
                Text("Marker Scale")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Slider(value: $markerScale, in: 0.10...1.8, step: 0.05)
                Text(String(format: "%.2fx", markerScale))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            // Damage Type
            HStack {
                Text("Type").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Menu {
                    ForEach(ConditionFormViewModel.damageTypes, id: \.self) { t in
                        Button(t) { formViewModel.damageType = t }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formViewModel.damageType).font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundColor(.orange)
                }
            }

            // Severity
            HStack {
                Text("Severity").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Menu {
                    ForEach(ConditionFormViewModel.severityLevels, id: \.self) { s in
                        Button(s) { formViewModel.damageSeverity = s }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(formViewModel.damageSeverity).font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundColor(.orange)
                }
            }

            TextField("Reservation Code", text: $formViewModel.reservationCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("Kilometers", text: $formViewModel.kmValue)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            TextField("Notes", text: $formViewModel.notes, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            // Save button
            HStack {
                Spacer()
                Button {
                    isSavingDamage = true
                    formViewModel.registerRecord(using: viewModel) { success in
                        isSavingDamage = false
                        guard success else {
                            ToastManager.shared.show("Select an existing previous record and map area first", type: .warning)
                            return
                        }
                        ToastManager.shared.show("✓ Record mapped on condition form", type: .success)
                        formViewModel.sync(with: liveVehicle.hasarKayitlari)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSavingDamage {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Register Record")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isSavingDamage)
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Previous Damage Records

    private var previousRecordsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Text("Previous Damage Records")
                    .font(.headline)
                Text("(\(liveVehicle.hasarKayitlari.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                selectAllButton
                collapseButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showRecordsExpanded {
                VStack(spacing: 8) {
                    if liveVehicle.hasarKayitlari.isEmpty {
                        Text("No damage records")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(sortedRecords) { record in
                            recordRow(record)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }

        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var sortedRecords: [HasarKaydi] {
        liveVehicle.hasarKayitlari.sorted(by: { $0.tarih > $1.tarih })
    }

    @ViewBuilder
    private var selectAllButton: some View {
        let all = sortedRecords
        let allChecked = !all.isEmpty && all.allSatisfy { formViewModel.isChecked($0.id) }
        Button(allChecked ? "Deselect All" : "Select All") {
            withAnimation(.easeInOut(duration: 0.15)) {
                if allChecked {
                    formViewModel.deselectAllRecords()
                } else {
                    formViewModel.selectAllRecords(sortedRecords)
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.orange)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showRecordsExpanded.toggle()
            }
        } label: {
            Image(systemName: showRecordsExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Individual Record Row

    private func conditionRecordRowFill(isRegistered: Bool, pendingPlacement: Bool, isChecked: Bool) -> Color {
        if isRegistered { return Color.orange.opacity(0.12) }
        if pendingPlacement { return Color.orange.opacity(0.06) }
        if isChecked { return Color.green.opacity(0.07) }
        return Color(.secondarySystemGroupedBackground)
    }

    private func conditionRecordRowStroke(isRegistered: Bool, pendingPlacement: Bool, isChecked: Bool) -> Color {
        if isRegistered { return Color.orange.opacity(0.45) }
        if pendingPlacement { return Color.orange.opacity(0.28) }
        if isChecked { return Color.green.opacity(0.30) }
        return Color.clear
    }

    @ViewBuilder
    private func recordRow(_ record: HasarKaydi) -> some View {
        let isChecked  = formViewModel.isChecked(record.id)
        let isActive   = formViewModel.selectedDamageId == record.id
        let isExpanded = expandedRecordIds.contains(record.id)
        let isRegistered = record.isConditionForm == true
            && record.conditionViewBlockId != nil
            && record.conditionPointX != nil
            && record.conditionPointY != nil
        let pendingConditionPlacement = record.isConditionForm == true && !isRegistered
        let isLockedOther = formViewModel.selectionLockedToRecordId != nil && formViewModel.selectionLockedToRecordId != record.id

        HStack(alignment: .top, spacing: 10) {

            // Left checkbox — toggles inclusion, does NOT collapse/expand
            Button {
                if isRegistered { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    formViewModel.toggleCheck(record.id)
                    if formViewModel.isChecked(record.id) {
                        formViewModel.selectDamage(record)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(isChecked ? Color.green : Color(.systemGray3), lineWidth: 1.8)
                        .frame(width: 26, height: 26)
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
            .disabled(isLockedOther || isRegistered)

            // Right content — tapping toggles expand; also activates for canvas placement if checked
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    // Row tap is only expand/collapse (always allowed), not selection.
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expandedRecordIds.contains(record.id) {
                            expandedRecordIds.remove(record.id)
                        } else {
                            expandedRecordIds.insert(record.id)
                        }
                    }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                if isActive {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 6, height: 6)
                                }
                                Text(record.resKodu)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(isChecked ? .green : .primary)
                                if pendingConditionPlacement {
                                    Text("Place on diagram".localized)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                                }
                                if let regionId  = record.conditionRegionId,
                                   let regionDef = VehicleRegionDef.region(id: regionId) {
                                    Text("· \(regionDef.displayName)")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            Text("\(liveVehicle.plakaFormatli)  ·  \(record.km) km  ·  \(record.tarih.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                // Expanded details
                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        if !record.notlar.isEmpty {
                            Text(record.notlar)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !record.fotograflar.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(record.fotograflar.enumerated()), id: \.offset) { _, url in
                                        AsyncImageView(urlString: url) { img in
                                            img.resizable()
                                                .scaledToFill()
                                                .frame(width: 70, height: 70)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(conditionRecordRowFill(
                    isRegistered: isRegistered,
                    pendingPlacement: pendingConditionPlacement,
                    isChecked: isChecked
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            conditionRecordRowStroke(
                                isRegistered: isRegistered,
                                pendingPlacement: pendingConditionPlacement,
                                isChecked: isChecked
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - PDF Export

    private func exportPDF() {
        isGeneratingPDF = true
        // Condition-form markers + all checked records (deduplicated by id)
        var combined = formViewModel.conditionDamages
        for record in liveVehicle.hasarKayitlari where formViewModel.isChecked(record.id) {
            if !combined.contains(where: { $0.id == record.id }) {
                combined.append(record)
            }
        }
        let sigToken = UUID().uuidString
        let fid = FirebaseService.shared.currentFranchiseId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pdfOptions = ConditionFormPDFOptions(signatureQRToken: sigToken, franchiseIdForQR: fid)
        ConditionFormPDFGenerator.shared.generateConditionFormPDF(arac: liveVehicle, damages: combined, options: pdfOptions) { url in
            isGeneratingPDF = false
            guard let url else {
                ToastManager.shared.show("PDF export failed", type: .error)
                return
            }
            pdfURL = url
            showShareSheet = true
        }
    }
}
