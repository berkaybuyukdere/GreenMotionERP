//
//  FleetImportSheetView.swift
//  AracHasarKayit
//
//  CSV / XLSX fleet list import (Plate, Make, Model, Category).
//

import SwiftUI
import UniformTypeIdentifiers

struct FleetImportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: AracViewModel

    @State private var fileImporterPresented = false
    @State private var parseIssues: [String] = []
    @State private var previewRows: [FleetVehicleImportRow] = []
    @State private var skippedExisting: [FleetVehicleImportRow] = []
    @State private var willImportCount = 0
    @State private var isImporting = false
    @State private var lastFileLabel = ""
    @State private var previewConfirmed = false
    @State private var askFinalImportConfirmation = false
    @State private var bulkGarageBranchKey: String = ""

    private var franchiseIdForImport: String {
        (viewModel.authManager?.userProfile?.resolvedFranchiseIdForDataAccess()
            ?? FirebaseService.shared.currentFranchiseId)
            .uppercased()
    }

    private var previewGroupsComputed: [(category: String, items: [FleetVehicleImportRow])] {
        FleetListImportParser.groupByCategory(previewRows)
    }

    private var isTurkeyImportContext: Bool {
        FranchiseCapabilityMatrix.isTurkeyFranchiseContext(
            serviceFranchiseId: franchiseIdForImport,
            userProfile: viewModel.authManager?.userProfile
        )
    }

    /// Türkiye: `franchises` koleksiyonundaki `TR_*` dokümanları; yoksa mevcut franchise dokümanındaki `garageBranches`.
    private var turkeyGarageBranchPickerOptions: [FranchiseGarageBranch] {
        let fromRegistry = viewModel.turkeyFranchiseLocationBranches
        if !fromRegistry.isEmpty { return fromRegistry }
        return viewModel.franchiseGarageBranches
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        fileImporterPresented = true
                    } label: {
                        Label("Choose CSV or XLSX…".localized, systemImage: "doc.badge.arrow.up")
                    }
                    .disabled(isImporting)
                } footer: {
                    Text("Uses columns Plate, Make, Model, Category; optional VIN and branch. Other columns are ignored.".localized)
                }

                if !lastFileLabel.isEmpty {
                    Section("Last file".localized) {
                        Text(lastFileLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !parseIssues.isEmpty {
                    Section("Parse warnings".localized) {
                        ForEach(parseIssues, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                        }
                    }
                }

                if willImportCount > 0 && isTurkeyImportContext {
                    Section {
                        if turkeyGarageBranchPickerOptions.isEmpty {
                            Text("No TR franchise locations found under the franchises collection. Imported vehicles will use your login session branch.".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Default garage branch".localized, selection: $bulkGarageBranchKey) {
                                ForEach(turkeyGarageBranchPickerOptions) { b in
                                    Text(b.displayName).tag(b.storageKey)
                                }
                            }
                            .onAppear {
                                guard bulkGarageBranchKey.isEmpty else { return }
                                let session = TurkiyeGarajSubeleri.sessionBranchStorageKey()
                                let list = turkeyGarageBranchPickerOptions
                                if let m = list.first(where: { TurkiyeGarajSubeleri.equivalentGarageBranchKeys($0.storageKey, session) }) {
                                    bulkGarageBranchKey = m.storageKey
                                } else if let first = list.first {
                                    bulkGarageBranchKey = first.storageKey
                                }
                            }
                        }
                    } header: {
                        Text("Garage branch".localized)
                    } footer: {
                        Text("Rows set to “Bulk default” use this branch. Pick a specific branch per row if needed.".localized)
                            .font(.caption)
                    }
                }

                if willImportCount > 0 {
                    Section {
                        Toggle("I checked plate / make / model / category preview and it is correct.".localized, isOn: $previewConfirmed)
                            .font(.subheadline)
                            .disabled(isImporting)
                    } header: {
                        Text("Validation before save".localized)
                    }

                    Section {
                        ForEach(previewGroupsComputed, id: \.category) { group in
                            DisclosureGroup {
                                ForEach(group.items) { row in
                                    fleetPreviewRowView(row)
                                }
                            } label: {
                                Text("\(group.category) (\(group.items.count))")
                            }
                        }
                    } header: {
                        Text("Preview — new vehicles (\(willImportCount))".localized)
                    }
                }

                if !skippedExisting.isEmpty {
                    Section("Already in fleet — skipped (\(skippedExisting.count))".localized) {
                        ForEach(skippedExisting.prefix(40)) { row in
                            Text("\(row.plateStored) · \(row.marka) \(row.model)")
                                .font(.caption)
                        }
                        if skippedExisting.count > 40 {
                            Text("… and \(skippedExisting.count - 40) more".localized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import fleet".localized)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.reloadFranchiseGarageMetadataFromFirestore()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import".localized) {
                        askFinalImportConfirmation = true
                    }
                    .disabled(willImportCount == 0 || isImporting || !previewConfirmed)
                }
            }
            .fileImporter(
                isPresented: $fileImporterPresented,
                allowedContentTypes: [
                    .commaSeparatedText,
                    .plainText,
                    UTType(filenameExtension: "csv") ?? .plainText,
                    UTType(filenameExtension: "xlsx") ?? .data,
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    handlePickedFile(url: url)
                case .failure(let err):
                    parseIssues = [err.localizedDescription]
                    previewRows = []
                    skippedExisting = []
                    willImportCount = 0
                    previewConfirmed = false
                }
            }
            .alert("Confirm fleet import?".localized, isPresented: $askFinalImportConfirmation) {
                Button("Cancel".localized, role: .cancel) {}
                Button("Import".localized, role: .destructive) {
                    Task { await runImport() }
                }
            } message: {
                Text(String(format: "You are about to import %d vehicle(s). The fields saved are Plate, Make, Model, Category only.".localized, willImportCount))
            }
        }
    }

    private func handlePickedFile(url: URL) {
        parseIssues = []
        lastFileLabel = url.lastPathComponent
        previewConfirmed = false

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()
        let fid = franchiseIdForImport

        do {
            let parsed: ([FleetVehicleImportRow], [String])
            if ext == "xlsx" {
                parsed = try FleetListImportParser.parseXLSX(fileURL: url, franchiseId: fid)
            } else {
                let data = try Data(contentsOf: url)
                parsed = try FleetListImportParser.parseCSV(data: data, franchiseId: fid)
            }

            var issues = parsed.1
            let deduped = FleetListImportParser.dedupeByPlate(franchiseId: fid, rows: parsed.0)
            if deduped.count < parsed.0.count {
                let n = parsed.0.count - deduped.count
                issues.append("Removed \(n) duplicate plate row(s) in file.".localized)
            }

            let existingPlates = viewModel.araclar.map(\.plaka)
            let filtered = FleetListImportParser.filterAgainstExistingFleet(
                franchiseId: fid,
                rows: deduped,
                existingPlates: existingPlates
            )

            parseIssues = issues
            skippedExisting = filtered.skippedExisting
            let will = filtered.willImport
            willImportCount = will.count
            previewRows = will
            if isTurkeyImportContext, bulkGarageBranchKey.isEmpty {
                let session = TurkiyeGarajSubeleri.sessionBranchStorageKey()
                let list = turkeyGarageBranchPickerOptions
                if let m = list.first(where: { TurkiyeGarajSubeleri.equivalentGarageBranchKeys($0.storageKey, session) }) {
                    bulkGarageBranchKey = m.storageKey
                } else if let first = list.first {
                    bulkGarageBranchKey = first.storageKey
                }
            }
        } catch {
            parseIssues = [error.localizedDescription]
            previewRows = []
            skippedExisting = []
            willImportCount = 0
            previewConfirmed = false
        }
    }

    @ViewBuilder
    private func fleetPreviewRowView(_ row: FleetVehicleImportRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.plateStored)
                .font(.subheadline.weight(.semibold))
            Text("\(row.marka) \(row.model)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let v = row.vin, !v.isEmpty {
                Text("VIN: \(v)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isTurkeyImportContext, let idx = previewRows.firstIndex(where: { $0.id == row.id }) {
                if turkeyGarageBranchPickerOptions.isEmpty {
                    Text("Uses login session branch (no TR franchise list).".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Garage branch".localized, selection: Binding(
                        get: { previewRows[idx].garageBranchStorageKey },
                        set: { previewRows[idx].garageBranchStorageKey = $0 }
                    )) {
                        Text("Bulk default".localized).tag(nil as String?)
                        ForEach(turkeyGarageBranchPickerOptions) { b in
                            Text(b.displayName).tag(Optional.some(b.storageKey))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func runImport() async {
        guard !previewRows.isEmpty else { return }
        isImporting = true
        let fb = bulkGarageBranchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = (isTurkeyImportContext && !fb.isEmpty) ? fb : nil
        let result = await viewModel.importFleetVehiclesQuietly(rows: previewRows, turkeyGarageBranchFallback: fallback)
        isImporting = false
        if result.imported > 0 {
            ToastManager.shared.show(String(format: "Imported %d vehicles".localized, result.imported), type: .success)
        }
        if result.skippedDuplicate > 0 {
            ToastManager.shared.show(String(format: "Skipped %d duplicate plate(s) already in fleet".localized, result.skippedDuplicate), type: .info)
        }
        if result.failed > 0 {
            ToastManager.shared.show(String(format: "%d could not be saved".localized, result.failed), type: .warning)
        }
        dismiss()
    }
}
