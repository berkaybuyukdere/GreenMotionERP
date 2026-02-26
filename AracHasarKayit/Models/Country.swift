//
//  Country.swift
//  AracHasarKayit
//
//  Multi-Franchise Country Model - 26 European Countries
//

import Foundation

/// Represents a country with its plate validation pattern
struct Country: Identifiable, Codable, Equatable, Hashable {
    let id: String           // "de", "tr", "ch"
    let name: String         // "Germany"
    let flag: String         // "🇩🇪"
    let countryCode: String  // "DE"
    let platePattern: String // Regex pattern for plate validation
    let currency: String     // "EUR"
    let timezone: String     // "Europe/Berlin"
    let language: String     // "de"
    
    /// Validates a license plate against this country's pattern
    func validatePlate(_ plate: String) -> Bool {
        let trimmed = plate
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
        guard let regex = try? NSRegularExpression(pattern: platePattern) else { return false }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }
}

/// All supported European countries
struct CountryManager {
    
    /// All 26 European countries
    static let allCountries: [Country] = [
        Country(
            id: "at", name: "Austria", flag: "🇦🇹", countryCode: "AT",
            platePattern: "^[A-Z]{1,2}[0-9]{1,6}[A-Z]?$",
            currency: "EUR", timezone: "Europe/Vienna", language: "de"
        ),
        Country(
            id: "be", name: "Belgium", flag: "🇧🇪", countryCode: "BE",
            platePattern: "^[0-9][A-Z]{3}[0-9]{3}$",
            currency: "EUR", timezone: "Europe/Brussels", language: "nl"
        ),
        Country(
            id: "bg", name: "Bulgaria", flag: "🇧🇬", countryCode: "BG",
            platePattern: "^[A-Z]{1,2}[0-9]{4}[A-Z]{2}$",
            currency: "BGN", timezone: "Europe/Sofia", language: "bg"
        ),
        Country(
            id: "hr", name: "Croatia", flag: "🇭🇷", countryCode: "HR",
            platePattern: "^[A-Z]{2}[0-9]{3,4}[A-Z]{2}$",
            currency: "EUR", timezone: "Europe/Zagreb", language: "hr"
        ),
        Country(
            id: "cz", name: "Czech Republic", flag: "🇨🇿", countryCode: "CZ",
            platePattern: "^[0-9][A-Z][0-9][0-9]{4}$",
            currency: "CZK", timezone: "Europe/Prague", language: "cs"
        ),
        Country(
            id: "dk", name: "Denmark", flag: "🇩🇰", countryCode: "DK",
            platePattern: "^[A-Z]{2}[0-9]{5}$",
            currency: "DKK", timezone: "Europe/Copenhagen", language: "da"
        ),
        Country(
            id: "fi", name: "Finland", flag: "🇫🇮", countryCode: "FI",
            platePattern: "^[A-Z]{3}[0-9]{3}$",
            currency: "EUR", timezone: "Europe/Helsinki", language: "fi"
        ),
        Country(
            id: "fr", name: "France", flag: "🇫🇷", countryCode: "FR",
            platePattern: "^[A-Z]{2}[0-9]{3}[A-Z]{2}$",
            currency: "EUR", timezone: "Europe/Paris", language: "fr"
        ),
        Country(
            id: "de", name: "Germany", flag: "🇩🇪", countryCode: "DE",
            platePattern: "^[A-ZÄÖÜ]{1,3}[A-Z]{0,2}[0-9]{1,4}[EH]?$",
            currency: "EUR", timezone: "Europe/Berlin", language: "de"
        ),
        Country(
            id: "gr", name: "Greece", flag: "🇬🇷", countryCode: "GR",
            platePattern: "^[A-Z]{3}[0-9]{4}$",
            currency: "EUR", timezone: "Europe/Athens", language: "el"
        ),
        Country(
            id: "hu", name: "Hungary", flag: "🇭🇺", countryCode: "HU",
            platePattern: "^[A-Z]{3}[0-9]{3}$",
            currency: "HUF", timezone: "Europe/Budapest", language: "hu"
        ),
        Country(
            id: "ie", name: "Ireland", flag: "🇮🇪", countryCode: "IE",
            platePattern: "^[0-9]{2,3}[A-Z]{1,2}[0-9]{1,6}$",
            currency: "EUR", timezone: "Europe/Dublin", language: "en"
        ),
        Country(
            id: "it", name: "Italy", flag: "🇮🇹", countryCode: "IT",
            platePattern: "^[A-Z]{2}[0-9]{3}[A-Z]{2}$",
            currency: "EUR", timezone: "Europe/Rome", language: "it"
        ),
        Country(
            id: "lu", name: "Luxembourg", flag: "🇱🇺", countryCode: "LU",
            platePattern: "^[A-Z]{2}[0-9]{4}$",
            currency: "EUR", timezone: "Europe/Luxembourg", language: "fr"
        ),
        Country(
            id: "nl", name: "Netherlands", flag: "🇳🇱", countryCode: "NL",
            platePattern: "^[A-Z0-9]{2}[A-Z0-9]{2}[A-Z0-9]{2}$",
            currency: "EUR", timezone: "Europe/Amsterdam", language: "nl"
        ),
        Country(
            id: "no", name: "Norway", flag: "🇳🇴", countryCode: "NO",
            platePattern: "^[A-Z]{2}[0-9]{5}$",
            currency: "NOK", timezone: "Europe/Oslo", language: "no"
        ),
        Country(
            id: "pl", name: "Poland", flag: "🇵🇱", countryCode: "PL",
            platePattern: "^[A-Z]{2,3}[A-Z0-9]{4,5}$",
            currency: "PLN", timezone: "Europe/Warsaw", language: "pl"
        ),
        Country(
            id: "pt", name: "Portugal", flag: "🇵🇹", countryCode: "PT",
            platePattern: "^[A-Z]{2}[0-9]{2}[A-Z]{2}$",
            currency: "EUR", timezone: "Europe/Lisbon", language: "pt"
        ),
        Country(
            id: "ro", name: "Romania", flag: "🇷🇴", countryCode: "RO",
            platePattern: "^[A-Z]{1,2}[0-9]{2,3}[A-Z]{3}$",
            currency: "RON", timezone: "Europe/Bucharest", language: "ro"
        ),
        Country(
            id: "sk", name: "Slovakia", flag: "🇸🇰", countryCode: "SK",
            platePattern: "^[A-Z]{2}[0-9]{3}[A-Z]{2}$",
            currency: "EUR", timezone: "Europe/Bratislava", language: "sk"
        ),
        Country(
            id: "si", name: "Slovenia", flag: "🇸🇮", countryCode: "SI",
            platePattern: "^[A-Z]{2}[0-9]{2,3}[A-Z]{2}$",
            currency: "EUR", timezone: "Europe/Ljubljana", language: "sl"
        ),
        Country(
            id: "es", name: "Spain", flag: "🇪🇸", countryCode: "ES",
            platePattern: "^[0-9]{4}[A-Z]{3}$",
            currency: "EUR", timezone: "Europe/Madrid", language: "es"
        ),
        Country(
            id: "se", name: "Sweden", flag: "🇸🇪", countryCode: "SE",
            platePattern: "^[A-Z]{3}[0-9]{3}$",
            currency: "SEK", timezone: "Europe/Stockholm", language: "sv"
        ),
        Country(
            id: "ch", name: "Switzerland", flag: "🇨🇭", countryCode: "CH",
            platePattern: "^[A-Z]{1,2}[0-9]{1,6}$",
            currency: "CHF", timezone: "Europe/Zurich", language: "de"
        ),
        Country(
            id: "tr", name: "Turkey", flag: "🇹🇷", countryCode: "TR",
            platePattern: "^[0-9]{2}[A-Z]{1,3}[0-9]{2,4}$",
            currency: "TRY", timezone: "Europe/Istanbul", language: "tr"
        ),
        Country(
            id: "uk", name: "United Kingdom", flag: "🇬🇧", countryCode: "UK",
            platePattern: "^[A-Z]{2}[0-9]{2}[A-Z]{3}$",
            currency: "GBP", timezone: "Europe/London", language: "en"
        )
    ]
    
    /// Get country by ID
    static func country(byId id: String) -> Country? {
        return allCountries.first { $0.id == id.lowercased() }
    }
    
    /// Get country by country code
    static func country(byCode code: String) -> Country? {
        return allCountries.first { $0.countryCode == code.uppercased() }
    }
    
    /// Default country (Switzerland)
    static var defaultCountry: Country {
        return country(byId: "ch") ?? allCountries[23]
    }
    
    /// Validate a plate for a specific country
    static func validatePlate(_ plate: String, forCountry countryId: String) -> Bool {
        guard let country = country(byId: countryId) else { return false }
        return country.validatePlate(plate)
    }
    
    /// Returns display examples used in scanner/manual-entry hints.
    static func plateExamples(for countryId: String) -> [String] {
        switch countryId.lowercased() {
        case "de":
            return ["HH EU19", "B AB1234", "M X987"]
        case "tr":
            return ["34 ABC 123", "06 AB 1234", "35 A 9999"]
        case "ch":
            return ["ZH 123456", "ZG 98765", "BS 555"]
        case "fr":
            return ["AB 123 CD", "EF 456 GH", "IJ 789 KL"]
        case "it":
            return ["AB 123 CD", "EF 456 GH", "IJ 789 KL"]
        default:
            return ["AB1234", "XYZ987", "A1B2C3"]
        }
    }
    
    /// OCR helper words per country to improve recognition.
    static func ocrHints(for countryId: String) -> [String] {
        switch countryId.lowercased() {
        case "ch":
            return ["ZH", "BE", "LU", "UR", "SZ", "OW", "NW", "GL", "ZG", "FR", "SO", "BS", "BL", "SH", "AR", "AI", "SG", "GR", "AG", "TG", "TI", "VD", "VS", "NE", "GE", "JU"]
        case "de":
            return ["B", "M", "HH", "K", "F", "S", "D", "HB", "N", "DU"]
        case "tr":
            return ["34", "06", "35", "07", "16", "41", "01", "10", "33", "42"]
        default:
            return []
        }
    }
    
    /// Finds best plate candidate from OCR texts and formats it for display.
    static func bestDetectedPlate(from texts: [String], countryId: String) -> String? {
        let cid = countryId.lowercased()
        if cid == "de" {
            return bestGermanPlate(from: texts)
        }
        return bestGenericPlate(from: texts, countryId: cid)
    }
    
    private static func bestGenericPlate(from texts: [String], countryId: String) -> String? {
        for raw in texts {
            let cleaned = normalizeRawOCRText(raw)
            guard !cleaned.isEmpty else { continue }
            
            if validatePlate(cleaned, forCountry: countryId) {
                return cleaned
            }
            
            for variation in generateCommonOCRVariations(cleaned) {
                if validatePlate(variation, forCountry: countryId) {
                    return variation
                }
            }
        }
        return nil
    }
    
    private static func bestGermanPlate(from texts: [String]) -> String? {
        for raw in texts {
            let candidates = germanCandidates(from: raw)
            for candidate in candidates {
                if let parsed = parseGermanPlate(candidate), validatePlate(parsed, forCountry: "de") {
                    return parsed
                }
            }
        }
        return nil
    }
    
    private static func parseGermanPlate(_ raw: String) -> String? {
        // Examples: "HH EU19", "B AB1234", "M X987"
        let pattern = "^([A-ZÄÖÜ]{1,3})\\s*([A-Z]{1,2})\\s*([0-9OISBZQG]{1,4})([EH]?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let normalized = raw
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9ÄÖÜ\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let searchRange = NSRange(location: 0, length: normalized.utf16.count)
        guard let match = regex.firstMatch(in: normalized, range: searchRange),
              match.numberOfRanges >= 5,
              let areaRange = Range(match.range(at: 1), in: normalized),
              let lettersRange = Range(match.range(at: 2), in: normalized),
              let digitsRange = Range(match.range(at: 3), in: normalized),
              let suffixRange = Range(match.range(at: 4), in: normalized) else {
            return nil
        }
        
        let area = String(normalized[areaRange])
        let letters = String(normalized[lettersRange])
        let suffix = String(normalized[suffixRange])
        let fixedDigits = String(normalized[digitsRange]).map { ch -> Character in
            switch ch {
            case "O", "Q": return "0"
            case "I": return "1"
            case "S": return "5"
            case "B": return "8"
            case "Z": return "2"
            case "G": return "6"
            default: return ch
            }
        }
        let digits = String(fixedDigits)
        guard digits.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil else { return nil }
        
        // Keep user-requested display style: "HH EU19"
        return "\(area) \(letters)\(digits)\(suffix)"
    }
    
    private static func germanCandidates(from raw: String) -> [String] {
        let normalized = raw
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9ÄÖÜ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !normalized.isEmpty else { return [] }
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        
        var out: [String] = [normalized]
        if !compact.isEmpty { out.append(compact) }
        
        // Avoid duplicate tries while preserving order.
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
    
    private static func normalizeRawOCRText(_ raw: String) -> String {
        raw
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "[^A-Z0-9ÄÖÜ]", with: "", options: .regularExpression)
    }
    
    private static func generateCommonOCRVariations(_ text: String) -> [String] {
        var variations: [String] = [text]
        let replacements: [(String, String)] = [
            ("O", "0"), ("0", "O"),
            ("I", "1"), ("1", "I"),
            ("S", "5"), ("5", "S"),
            ("Z", "2"), ("2", "Z"),
            ("B", "8"), ("8", "B")
        ]
        
        for (from, to) in replacements where text.contains(from) {
            variations.append(text.replacingOccurrences(of: from, with: to))
        }
        
        var seen = Set<String>()
        return variations.filter { seen.insert($0).inserted }
    }
}

// MARK: - UserDefaults Extension for Selected Country

extension UserDefaults {
    private enum Keys {
        static let selectedCountryId = "selectedCountryId"
    }
    
    /// Get the currently selected country ID
    var selectedCountryId: String {
        get { string(forKey: Keys.selectedCountryId) ?? "ch" }
        set { set(newValue, forKey: Keys.selectedCountryId) }
    }
    
    /// Get the currently selected country
    var selectedCountry: Country {
        return CountryManager.country(byId: selectedCountryId) ?? CountryManager.defaultCountry
    }
}
