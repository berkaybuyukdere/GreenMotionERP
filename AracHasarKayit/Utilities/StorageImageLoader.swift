import UIKit
import FirebaseStorage
import Kingfisher

final class StorageImageLoader {
    static let shared = StorageImageLoader()
    private let previewMaxDownloadBytes = 6 * 1024 * 1024
    /// PDFs (notably the kiosk-signed General Rental Terms) can exceed 6 MB once
    /// signatures are embedded — give them a more generous ceiling.
    private let pdfMaxDownloadBytes = 20 * 1024 * 1024
    private let maxFallbackCandidates = 4

    private init() {}

    private func maxDownloadBytes(forPath path: String) -> Int {
        let lower = path.lowercased()
        if lower.hasSuffix(".pdf") || lower.contains(".pdf?") || lower.contains("/kiosk-rental-terms/") {
            return pdfMaxDownloadBytes
        }
        return previewMaxDownloadBytes
    }
    
    func loadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        let urlCandidates = candidateDownloadURLs(from: urlString)
        if !urlCandidates.isEmpty {
            loadFromURLCandidates(urlCandidates, index: 0, original: urlString, completion: completion)
        } else {
            loadFromStorageFallback(urlString: urlString, completion: completion)
        }
    }
    
    private func loadFromURLCandidates(_ urls: [URL], index: Int, original: String, completion: @escaping (UIImage?) -> Void) {
        guard index < urls.count else {
            loadFromStorageFallback(urlString: original, completion: completion)
            return
        }
        
        let url = urls[index]
        KingfisherManager.shared.retrieveImage(with: url) { result in
            switch result {
            case .success(let value):
                DispatchQueue.main.async {
                    completion(value.image.normalizedImageOrientationForViewer())
                }
            case .failure:
                self.loadFromURLCandidates(urls, index: index + 1, original: original, completion: completion)
            }
        }
    }
    
    private func loadFromStorageFallback(urlString: String, completion: @escaping (UIImage?) -> Void) {
        let candidates = Array(candidateStoragePaths(from: urlString).prefix(maxFallbackCandidates))
        guard !candidates.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        loadFromPathCandidates(candidates, index: 0, completion: completion)
    }
    
    private func loadFromPathCandidates(_ paths: [String], index: Int, completion: @escaping (UIImage?) -> Void) {
        guard index < paths.count else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        let path = paths[index]
        Storage.storage().reference(withPath: path).getData(maxSize: Int64(previewMaxDownloadBytes)) { data, error in
            if let data, let image = UIImage(data: data) {
                DispatchQueue.main.async { completion(image.normalizedImageOrientationForViewer()) }
            } else {
                if let error {
                    print("⚠️ Storage fallback failed for path: \(path) - \(error.localizedDescription)")
                }
                self.loadFromPathCandidates(paths, index: index + 1, completion: completion)
            }
        }
    }

    // MARK: - Raw data (PDF / arbitrary)

    /// Downloads bytes from a Firebase HTTPS URL or `gs://` / raw storage path (used for stored rental-terms PDFs).
    func loadData(from urlString: String, completion: @escaping (Data?) -> Void) {
        let urlCandidates = candidateDownloadURLs(from: urlString)
        if !urlCandidates.isEmpty {
            loadDataFromURLCandidates(urlCandidates, index: 0, original: urlString, completion: completion)
        } else {
            let paths = Array(candidateStoragePaths(from: urlString).prefix(maxFallbackCandidates))
            loadDataFromPathCandidates(paths, index: 0, completion: completion)
        }
    }

    private func loadDataFromURLCandidates(_ urls: [URL], index: Int, original: String, completion: @escaping (Data?) -> Void) {
        guard index < urls.count else {
            let paths = Array(candidateStoragePaths(from: original).prefix(maxFallbackCandidates))
            loadDataFromPathCandidates(paths, index: 0, completion: completion)
            return
        }
        let url = urls[index]
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data, !data.isEmpty {
                DispatchQueue.main.async { completion(data) }
            } else {
                self.loadDataFromURLCandidates(urls, index: index + 1, original: original, completion: completion)
            }
        }.resume()
    }

    private func loadDataFromPathCandidates(_ paths: [String], index: Int, completion: @escaping (Data?) -> Void) {
        guard index < paths.count else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let path = paths[index]
        let limit = maxDownloadBytes(forPath: path)
        Storage.storage().reference(withPath: path).getData(maxSize: Int64(limit)) { data, error in
            if let data, !data.isEmpty {
                DispatchQueue.main.async { completion(data) }
            } else {
                if let error {
                    print("⚠️ Storage data load failed for path: \(path) - \(error.localizedDescription)")
                }
                self.loadDataFromPathCandidates(paths, index: index + 1, completion: completion)
            }
        }
    }

    // MARK: - gs:// helpers (private kiosk GRT)

    /// Downloads bytes directly from a `gs://bucket/path` URI using the Storage SDK
    /// (bypasses the public-URL candidate chain — required for private kiosk GRT PDFs).
    func loadStorageGSData(gsUri: String, completion: @escaping (Data?) -> Void) {
        let trimmed = gsUri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("gs://") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let limit = maxDownloadBytes(forPath: trimmed)
        let ref = Storage.storage().reference(forURL: trimmed)
        ref.getData(maxSize: Int64(limit)) { data, error in
            if let data, !data.isEmpty {
                DispatchQueue.main.async { completion(data) }
            } else {
                if let error {
                    print("⚠️ gs:// data load failed: \(trimmed) - \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    private func candidateDownloadURLs(from urlString: String) -> [URL] {
        guard let originalComponents = URLComponents(string: urlString) else { return [] }
        
        var urls: [URL] = []
        if let originalURL = URL(string: urlString) {
            urls.append(originalURL)
        }
        
        guard let extractedPath = extractStoragePath(from: urlString) else {
            return uniqueURLs(urls)
        }
        
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        let transformed = transformedPaths(for: extractedPath, franchiseId: franchiseId)
        
        // Rebuild Firebase download URLs with transformed object paths while preserving query items.
        if originalComponents.host?.contains("firebasestorage.googleapis.com") == true,
           let markerRange = originalComponents.path.range(of: "/o/") {
            let prefix = String(originalComponents.path[..<markerRange.upperBound])
            for path in transformed {
                var components = originalComponents
                let encoded = encodeStorageObjectPath(path)
                components.path = prefix + encoded
                if let rebuilt = components.url {
                    urls.append(rebuilt)
                }
            }
        }
        
        return uniqueURLs(urls)
    }
    
    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
    
    private func encodeStorageObjectPath(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
    
    private func candidateStoragePaths(from urlString: String) -> [String] {
        let franchiseId = FirebaseService.shared.currentFranchiseId.uppercased()
        var paths: [String] = []
        
        if let extractedPath = extractStoragePath(from: urlString) {
            paths.append(contentsOf: transformedPaths(for: extractedPath, franchiseId: franchiseId))
        }
        
        // If caller passed a raw storage path instead of a URL.
        if !urlString.contains("://") {
            paths.append(contentsOf: transformedPaths(for: urlString, franchiseId: franchiseId))
        }
        
        // Preserve order, remove duplicates.
        var seen = Set<String>()
        return paths.compactMap { raw in
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }
    
    private func extractStoragePath(from urlString: String) -> String? {
        guard let components = URLComponents(string: urlString) else { return nil }
        
        // Firebase download URL pattern (query variant): ...?o=<encoded_path>
        if let encodedPath = components.queryItems?.first(where: { $0.name == "o" })?.value {
            return encodedPath.removingPercentEncoding
        }
        
        // Firebase download URL pattern (path variant): .../o/<encoded_path>?alt=media...
        let marker = "/o/"
        if let markerRange = components.path.range(of: marker) {
            let encodedStart = markerRange.upperBound
            let encodedPath = String(components.path[encodedStart...])
            if !encodedPath.isEmpty, let decoded = encodedPath.removingPercentEncoding {
                return decoded
            }
        }
        
        // gs://bucket/path format
        if urlString.hasPrefix("gs://") {
            let noScheme = String(urlString.dropFirst("gs://".count))
            if let firstSlash = noScheme.firstIndex(of: "/") {
                let objectPathStart = noScheme.index(after: firstSlash)
                if objectPathStart < noScheme.endIndex {
                    return String(noScheme[objectPathStart...])
                }
            }
        }
        
        return nil
    }
    
    private func transformedPaths(for originalPath: String, franchiseId: String) -> [String] {
        let normalized = originalPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        
        var candidates: [String] = []
        let legacyPrefixes = [
            "hasar_fotograflari/",
            "iade_fotograflari/",
            "exit_fotograflari/",
            "office_operations/",
            "traffic_accident_contracts/",
            "police_reports/",
            "office_Return/",
            "return_pdfs/",
            "banking_transactions/",
            "traffic_fines/",
            "semesInvoices/",
            "protocolTemplates/"
        ]
        
        if normalized.hasPrefix("franchises/") {
            candidates.append(normalized)
            let parts = normalized.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count > 2 {
                let embeddedId = String(parts[1])
                let upperEmbedded = embeddedId.uppercased()
                if embeddedId != upperEmbedded {
                    var updated = parts
                    updated[1] = Substring(upperEmbedded)
                    candidates.append(updated.joined(separator: "/"))
                }
                let normFranchise = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !normFranchise.isEmpty && upperEmbedded != normFranchise {
                    var swapped = parts
                    swapped[1] = Substring(normFranchise)
                    candidates.append(swapped.joined(separator: "/"))
                }
            }
            
            // Legacy fallback from scoped path to top-level folders.
            if parts.count > 3 {
                let withoutScope = parts.dropFirst(2).joined(separator: "/")
                candidates.append(withoutScope)
            }
        } else if legacyPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            // Prefer scoped path first, keep legacy as fallback.
            candidates.append("franchises/\(franchiseId)/\(normalized)")
            candidates.append(normalized)
        } else {
            candidates.append(normalized)
        }
        
        return candidates
    }
}

// MARK: - EXIF / UIImage orientation

extension UIImage {
    /// Renders with `.up` so `size` matches pixels used by `ZoomPhotoPage` / `UIScrollView` zoom math (fixes wrong crop on camera photos).
    func normalizedImageOrientationForViewer() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
