import SwiftUI
import PhotosUI
import UIKit
import CoreImage

// MARK: - Image → document-style scan look

extension UIImage {
    /// High-contrast grayscale pipeline suitable for “scanned PDF” pages.
    func applyingDocumentScanLook() -> UIImage {
        guard let ciImage = CIImage(image: self) else { return self }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let extent = ciImage.extent
        let mono = ciImage.applyingFilter("CIPhotoEffectMono")
        let adjusted = mono.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.22,
            kCIInputBrightnessKey: 0.04,
            kCIInputSaturationKey: 0,
        ])
        let sharpened = adjusted.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.35])
        guard let cg = context.createCGImage(sharpened, from: extent) else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }
}

enum DocumentScanPDFBuilder {
    static func buildPDF(scannedImage: UIImage, title: String, ocrAppendix: String?) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 36
        let meta = [
            NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 14),
            NSAttributedString.Key.foregroundColor: UIColor.darkGray,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let titleText = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Document".localized
                : title.trimmingCharacters(in: .whitespacesAndNewlines)
            titleText.draw(at: CGPoint(x: margin, y: margin), withAttributes: meta)

            let maxW = pageRect.width - margin * 2
            let maxH = pageRect.height - margin * 2 - 40
            let img = scannedImage
            let scale = min(maxW / img.size.width, maxH / img.size.height)
            let drawSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let origin = CGPoint(x: margin + (maxW - drawSize.width) / 2, y: margin + 28)
            img.draw(in: CGRect(origin: origin, size: drawSize))

            if let ocr = ocrAppendix?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
                ctx.beginPage()
                "OCR".localized.draw(at: CGPoint(x: margin, y: margin), withAttributes: meta)
                let body = ocr as NSString
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph,
                ]
                let textRect = CGRect(x: margin, y: margin + 24, width: pageRect.width - margin * 2, height: pageRect.height - margin * 2 - 24)
                body.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            }
        }
        let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = (safe.isEmpty ? "scan" : safe) + "_\(Int(Date().timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Report hub: document scan → PDF, OCR, share

struct DocumentScanReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var documentTitle: String = ""
    @State private var sourceImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var ocrText: String = ""
    @State private var isRunningOCR = false
    @State private var showCamera = false
    @State private var cameraCapture: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showShare = false
    @State private var pdfURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Capture or choose a document photo. A scan-style PDF is generated; run OCR for invoices or calculation sheets.".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Document name".localized, text: $documentTitle)
                    .textFieldStyle(.roundedBorder)

                if let preview = processedImage ?? sourceImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(height: 200)
                        .overlay(
                            Text("No document yet".localized)
                                .foregroundColor(.secondary)
                        )
                }

                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo".localized, systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    PhotosPicker(selection: $photoPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Photo Gallery".localized, systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    runOCR()
                } label: {
                    if isRunningOCR {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Run OCR".localized, systemImage: "text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled((processedImage ?? sourceImage) == nil || isRunningOCR)

                if !ocrText.isEmpty {
                    Text("OCR result".localized)
                        .font(.headline)
                    Text(ocrText)
                        .font(.caption.monospaced())
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }

                Button {
                    prepareAndShare()
                } label: {
                    Label("Share or email PDF".localized, systemImage: "square.and.arrow.up.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled((processedImage ?? sourceImage) == nil)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Document Scan".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) { dismiss() }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(selectedImage: $cameraCapture)
        }
        .onChange(of: cameraCapture) { _, img in
            if let img {
                ingestImage(img)
                cameraCapture = nil
            }
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    await MainActor.run { ingestImage(ui) }
                }
                await MainActor.run { photoPickerItem = nil }
            }
        }
        .sheet(isPresented: $showShare) {
            if let pdfURL {
                ShareSheet(activityItems: [pdfURL])
            }
        }
    }

    private func ingestImage(_ image: UIImage) {
        sourceImage = image
        processedImage = image.applyingDocumentScanLook()
        ocrText = ""
        errorMessage = nil
    }

    private func runOCR() {
        guard let img = processedImage ?? sourceImage else { return }
        isRunningOCR = true
        MultilingualDocumentOCRService.shared.recognizeFullDocumentText(from: img) { text in
            DispatchQueue.main.async {
                isRunningOCR = false
                ocrText = text
            }
        }
    }

    private func prepareAndShare() {
        guard let img = processedImage ?? sourceImage else { return }
        let appendix = ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ocrText
        guard let url = DocumentScanPDFBuilder.buildPDF(
            scannedImage: img,
            title: documentTitle,
            ocrAppendix: appendix
        ) else {
            errorMessage = "Could not create PDF.".localized
            return
        }
        pdfURL = url
        errorMessage = nil
        showShare = true
    }
}
