import SwiftUI
import Kingfisher

struct ExitDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let exit: ExitIslemi
    @State private var silmeOnayiGoster = false
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    @State private var photoGalleryItem: PhotoGallerySheetItem?
    @State private var showEditSheet = false
    @Environment(\.dismiss) var dismiss

    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == exit.aracId })
    }

    private var pdfFileName: String {
        let resStr  = exit.resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        let plate   = exit.aracPlaka.replacingOccurrences(of: " ", with: "")
        if resStr.isEmpty {
            return "CHECKOUT-\(plate)"
        } else {
            let safeRes = resStr.replacingOccurrences(of: " ", with: "")
            return "CHECKOUT-\(safeRes)-\(plate)"
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                vehicleInfoCard

                if !exit.notlar.isEmpty {
                    notesCard
                }
                if !exit.fotograflar.isEmpty {
                    photosSection
                }
                if exit.status == .completed {
                    pdfButton
                }

                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Check Out Details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.light()
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .medium))
                }
            }
        }
        .fullScreenCover(item: $photoGalleryItem) { item in
            NativePhotoGalleryView(urlStrings: exit.fotograflar, initialIndex: item.startIndex)
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL { ActivityViewController(activityItems: [url]) }
        }
        .sheet(isPresented: $showEditSheet) {
            if let arac = arac {
                SheetWrapper {
                    NavigationView {
                        ExitIslemView(arac: arac, existingExit: exit, onExitCompleted: { _ in })
                    }
                }
            }
        }
        .alert("Delete Check Out Record".localized, isPresented: $silmeOnayiGoster) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Delete".localized, role: .destructive) {
                viewModel.exitSil(exit)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this check out record?".localized)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(statusAccentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: statusIcon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(statusAccentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(exit.aracPlaka)
                    .font(.system(size: 17, weight: .bold))
                Text("Check Out".localized)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(statusLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(statusAccentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusAccentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    private var statusAccentColor: Color {
        switch exit.status {
        case .inProgress: return .orange
        case .parked:     return .purple
        case .completed:  return .blue
        }
    }

    private var statusIcon: String {
        switch exit.status {
        case .inProgress: return "clock.arrow.circlepath"
        case .parked:     return "car.fill"
        case .completed:  return "arrow.right.circle.fill"
        }
    }

    private var statusLabel: String {
        switch exit.status {
        case .inProgress: return "In Progress".localized
        case .parked:     return "Parked".localized
        case .completed:  return "Completed".localized
        }
    }

    // MARK: - Vehicle Info Card

    private var vehicleInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("VEHICLE INFORMATION".localized)
            VStack(spacing: 0) {
                infoRow(icon: "number.square.fill",    color: .blue,   label: "Plate".localized,        value: exit.aracPlaka)
                Divider().padding(.leading, 50)
                infoRow(icon: "calendar",              color: .orange, label: "Process Date".localized,  value: exit.exitTarihi.formatted(date: .long, time: .shortened))
                if let km = exit.km {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "gauge.medium",      color: .green,  label: "KM".localized,            value: "\(km) km")
                }
                if !exit.resKodu.isEmpty {
                    Divider().padding(.leading, 50)
                    infoRow(icon: "number.circle.fill", color: .purple, label: "RES Code".localized,     value: exit.resKodu)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("NOTES".localized)
            Text(exit.notlar)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
        }
    }

    // MARK: - Photos Section (Apple Photos-style 3-column grid)

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(String(format: "PHOTOS (%d)".localized, exit.fotograflar.count))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3),
                spacing: 3
            ) {
                ForEach(Array(exit.fotograflar.enumerated()), id: \.offset) { index, url in
                    DetailPhotoGridCell(
                        urlString:  url,
                        label:      String(format: "Photo %d", index + 1),
                        labelColor: .blue
                    ) {
                        photoGalleryItem = PhotoGallerySheetItem(startIndex: index)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - PDF Button (blue)

    private var pdfButton: some View {
        Button {
            HapticManager.shared.medium()
            generatePDF()
        } label: {
            HStack(spacing: 10) {
                if pdfOlusturuluyor {
                    ProgressView().tint(.white).scaleEffect(0.9)
                    Text("Generating PDF...".localized).font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "doc.text.fill").font(.system(size: 16, weight: .semibold))
                    Text("Generate PDF".localized).font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding(.vertical, 15)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(pdfOlusturuluyor)
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button(role: .destructive) {
            HapticManager.shared.medium()
            silmeOnayiGoster = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill").font(.system(size: 14, weight: .semibold))
                Text("Delete Check Out Record".localized).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.red)
            .padding(.vertical, 15)
            .background(Color.red.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
            .padding(.leading, 2)
            .padding(.bottom, 7)
    }

    @ViewBuilder
    private func infoRow(icon: String, color: Color = .secondary, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color(.tertiaryLabel))
                .frame(width: 20)
            Text(label).font(.system(size: 15)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: - Logic (unchanged)

    func generatePDF() {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        ExitPDFGenerator.shared.generateExitPDF(exit: exit, arac: arac) { url in
            DispatchQueue.main.async {
                self.pdfOlusturuluyor = false
                if let url = url { self.shareRenamedPDF(url: url, name: self.pdfFileName) }
            }
        }
    }

    private func shareRenamedPDF(url: URL, name: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safeName).appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: url, to: dest)
        pdfURL = dest
        pdfPaylas = true
    }
}

// MARK: - ExitFotoButton (preserved for backward compatibility)

struct ExitFotoButton: View {
    let urlString: String
    let index: Int
    let onTap: () -> Void
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let image = image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 120, height: 120).cornerRadius(12).clipped()
                } else if isLoading {
                    ZStack { Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 120, height: 120).cornerRadius(12); ProgressView() }
                } else {
                    ZStack { Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 120, height: 120).cornerRadius(12); Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray) }
                }
                Text(String(format: "Foto %d".localized, index + 1)).font(.caption2).fontWeight(.bold).foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear { StorageImageLoader.shared.loadImage(from: urlString) { self.image = $0; self.isLoading = false } }
    }
}
