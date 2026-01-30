import Foundation
import SwiftUI

/// Localization manager for multi-language support (EN, TR, DE)
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: Language = .english
    
    enum Language: String, CaseIterable {
        case english = "en"
        case turkish = "tr"
        case german = "de"
        
        var displayName: String {
            switch self {
            case .english: return "English"
            case .turkish: return "Türkçe"
            case .german: return "Deutsch"
            }
        }
        
        /// Flag emoji for Settings language picker
        var flagEmoji: String {
            switch self {
            case .english: return "🇬🇧"
            case .turkish: return "🇹🇷"
            case .german: return "🇩🇪"
            }
        }
    }
    
    /// Bundle for the currently selected language (used for in-app language switch)
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
              let langBundle = Bundle(path: path) else {
            return Bundle.main
        }
        return langBundle
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "AppLanguage"),
           let language = Language(rawValue: saved) {
            currentLanguage = language
        } else {
            currentLanguage = .english
        }
    }
    
    func setLanguage(_ language: Language) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
        print("✅ Language changed to: \(language.displayName)")
    }
    
    func string(for key: String) -> String {
        return NSLocalizedString(key, bundle: bundle, value: key, comment: "")
    }
}

// Common translations
extension String {
    var localized: String {
        LocalizationManager.shared.string(for: self)
    }
}
