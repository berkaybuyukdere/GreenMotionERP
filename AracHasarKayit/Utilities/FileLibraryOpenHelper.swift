import Foundation
import FirebaseStorage

enum FileLibraryOpenHelper {
    enum OpenError: LocalizedError {
        case missingLocation
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .missingLocation: return "files.open_failed".localized
            case .downloadFailed: return "files.open_failed".localized
            }
        }
    }

    /// Resolves a Firebase Storage download URL from stored metadata.
    static func resolveDownloadURL(for item: FileLibraryItem) async throws -> URL {
        let trimmed = item.downloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           !trimmed.isEmpty,
           url.scheme?.hasPrefix("http") == true {
            return url
        }

        let path = item.storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw OpenError.missingLocation }

        return try await Storage.storage().reference(withPath: path).downloadURL()
    }

    /// Downloads remote file bytes into a temp file for Quick Look / share.
    static func materializeLocalFile(from remoteURL: URL, preferredName: String) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              !data.isEmpty else {
            throw OpenError.downloadFailed
        }

        let safeName = preferredName.isEmpty ? "file" : preferredName
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName, isDirectory: false)
        try? FileManager.default.removeItem(at: destination)
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
