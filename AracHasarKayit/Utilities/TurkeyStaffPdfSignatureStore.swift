import UIKit

/// Saved staff signature + display name for Turkey return / checkout PDFs (Teslim Alan).
enum TurkeyStaffPdfSignatureStore {
    private static let imageKey = "trStaffReturnPdfSignaturePNG_v1"
    private static let nameKey = "trStaffReturnPdfSignatureDisplayName_v1"

    private static var defaults: UserDefaults { UserDefaults.standard }

    static func loadSignatureImage() -> UIImage? {
        guard let data = defaults.data(forKey: imageKey), let img = UIImage(data: data) else { return nil }
        return img
    }

    static func saveSignatureImage(_ image: UIImage?) {
        if let image, let data = image.pngData() {
            defaults.set(data, forKey: imageKey)
        } else {
            defaults.removeObject(forKey: imageKey)
        }
    }

    static func loadDisplayName(fallbackProfileFullName: String?) -> String? {
        let stored = (defaults.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        let fb = (fallbackProfileFullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return fb.isEmpty ? nil : fb
    }

    static func saveDisplayName(_ name: String?) {
        let t = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty {
            defaults.removeObject(forKey: nameKey)
        } else {
            defaults.set(t, forKey: nameKey)
        }
    }
}
