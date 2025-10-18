import Foundation
import SwiftUI

/// Localization manager for multi-language support
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: Language = .english
    
    enum Language: String, CaseIterable {
        case english = "en"
        case turkish = "tr"
        case german = "de"
        case french = "fr"
        
        var displayName: String {
            switch self {
            case .english: return "English"
            case .turkish: return "Türkçe"
            case .german: return "Deutsch"
            case .french: return "Français"
            }
        }
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "AppLanguage"),
           let language = Language(rawValue: saved) {
            currentLanguage = language
        }
    }
    
    func setLanguage(_ language: Language) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
        print("✅ Language changed to: \(language.displayName)")
    }
    
    func string(for key: String) -> String {
        // In a real app, this would load from Localizable.strings
        return NSLocalizedString(key, comment: "")
    }
}

// Common translations
extension String {
    var localized: String {
        LocalizationManager.shared.string(for: self)
    }
}

