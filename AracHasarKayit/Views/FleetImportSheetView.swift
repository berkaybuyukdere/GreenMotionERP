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
    @State private var previewGroups: [(category: String, items: [FleetVehicleImportRow])] = []
    @State private var skippedExisting: [FleetVehicleImportRow] = []
    @State private var willImportCount = 0
    @State private var isImporting = false
    @State private var lastFileLabel = ""
    @State private var previewConfirmed = false
    @State private var askFinalImportConfirmation = false

    private var franchiseIdForImport: String {
        (viewModel.authManager?.userProfile?.resolvedFranchiseIdForDataAccess()
            ?? FirebaseService.shared.currentFranchiseId)
            .uppercased()
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
                    Text("Uses columns Plate, Make, Model, and Category only. Other columns are ignored.".localized)
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

                if willImportCount > 0 {
                    Section {
                        Toggle("I checked plate / make / model / category preview and it is correct.".localized, isOn: $previewConfirmed)
                            .font(.subheadline)
                            .disabled(isImporting)
                    } header: {
                        Text("Validation before save".localized)
                    }

                    Section {
                        ForEach(previewGroups, id: \.category) { group in
                            DisclosureGroup {
                                ForEach(group.items) { row in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.plateStored)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(row.marka) \(row.model)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
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
                    previewGroups = []
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
            previewGroups = FleetListImportParser.groupByCategory(will)
        } catch {
            parseIssues = [error.localizedDescription]
            previewGroups = []
            skippedExisting = []
            willImportCount = 0
            previewConfirmed = false
        }
    }

    @MainActor
    private func runImport() async {
        let flat = previewGroups.flatMap(\.items)
        guard !flat.isEmpty else { return }
        isImporting = true
        let result = await viewModel.importFleetVehiclesQuietly(rows: flat)
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
