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
        if id.lowercased() == "tr" {
            return TurkishPlateFormats.isValidCompact(trimmed)
        }
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
            platePattern: "^[A-ZÄÖÜ]{1,3}[A-Z]{1,2}[0-9]{1,4}[EH]?$",
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
            platePattern: TurkishPlateFormats.compactRegexDocumentation,
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
            return ["34 FC 6302", "06 AH 408", "35 AAC 771", "41 BK 9910"]
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
            return ["B", "M", "HH", "K", "F", "S", "D", "H", "HB", "N", "DU", "BO", "DO",
                    "E", "KA", "MA", "FR", "UL", "RT", "TÜ", "KN", "RA", "LB", "FN", "AA",
                    "WOB", "BS", "GS", "PE", "HI", "WF", "OL", "OS", "LG", "HH", "HB"]
        case "tr":
            // City codes + common letter groups (helps Vision; include RAV — Y/V fix is post-processed).
            return [
                "34", "06", "35", "07", "16", "41", "01", "10", "33", "42", "32", "38", "44", "50", "55",
                "RAV", "FC", "TT", "AB", "CD", "EF", "GH", "JK", "LM", "NP", "RS", "TU", "VZ",
            ]
        default:
            return []
        }
    }
    
    /// Filters OCR strings that are unlikely to be plates (company names, model lines, etc.).
    static func ocrTextLooksLikePlate(_ raw: String, countryId: String) -> Bool {
        let cleaned = normalizeRawOCRText(raw)
        guard cleaned.count >= 4, cleaned.count <= 14 else { return false }
        let alphaCount = cleaned.filter(\.isLetter).count
        let digitCount = cleaned.filter(\.isNumber).count
        guard digitCount >= 1, alphaCount >= 1 else { return false }

        let tokens = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if tokens.count > 2 { return false }

        let joined = tokens.joined()
        if joined.count > 10, !validatePlate(joined, forCountry: countryId) {
            return false
        }

        let lower = cleaned.lowercased()
        let blocked = ["green", "motion", "rent", "rental", "car", "gmbh", "ag", "ltd", "bmw", "mercedes", "audi", "volkswagen", "vw", "toyota", "ford", "hyundai", "kia", "skoda", "seat"]
        if blocked.contains(where: { lower.contains($0) }) { return false }

        if validatePlate(joined, forCountry: countryId) { return true }
        return tokens.contains { validatePlate($0, forCountry: countryId) }
    }

    /// Finds best plate candidate from OCR texts and formats it for display.
    static func bestDetectedPlate(from texts: [String], countryId: String) -> String? {
        let cid = countryId.lowercased()
        if cid == "de" {
            return bestGermanPlate(from: texts)
        }
        if cid == "tr" {
            return TurkishPlateFormats.bestPlate(from: texts)
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
    
    // ── Primary German plate parser: database-validated token matching ─────────
    //
    // German plates have two round stickers (TÜV + Hauptuntersuchung seal) placed
    // physically between the city code (Unterscheidungszeichen) and the identifier
    // (letters+digits). The OCR camera often mistakes these circular seals for the
    // letter "O" or digit "0", corrupting the plate string. This parser uses the
    // complete GermanPlateDatabase to determine where the city code ends and the
    // identifier begins — so sticker characters that land between area and ID are
    // skipped safely, and sticker characters that land inside a spaced-out city
    // code (e.g. "W O B" for "WOB") are merged correctly.
    //
    // Three passes:
    //  1. Token-based   — split on spaces; try 1-3 consecutive tokens as area code.
    //  2. Compact split — strip all spaces; try leading 1-3 chars as area code.
    //  3. Insertion fix — try inserting "O" into the area candidate to repair an
    //                     area character lost to sticker overlap.
    //  4. Regex fallback — old regex-only approach for plates not yet in the DB.
    
    private static func bestGermanPlate(from texts: [String]) -> String? {
        // ── Step 0: Build an expanded candidate pool ──────────────────────────
        // For each raw OCR string we add its OCR-corrected compact variant and a
        // spaced version with the area code already separated from the identifier.
        // This guarantees that even if the internal correction inside
        // parseGermanPlateWithDatabase is unreachable for a particular input shape
        // (e.g. the first token is longer than 3 chars), the corrected form is
        // still tried as an explicit standalone input.
        var pool: [String] = texts
        for raw in texts {
            let compact = raw
                .uppercased()
                .replacingOccurrences(of: "[^A-Z0-9ÄÖÜ]", with: "", options: .regularExpression)
            guard compact.count >= 3 else { continue }

            // Apply area-code correction (e.g. WBSZK295 → WOBZK295)
            let corrected = GermanPlateDatabase.correctOCRCompactPrefix(compact)
            if corrected != compact && !pool.contains(corrected) {
                pool.append(corrected)
            }

            // Also build a version with the area code separated by a space, so the
            // token-based Pass 1 inside parseGermanPlateWithDatabase can split it.
            let source = corrected.isEmpty ? compact : corrected
            for areaLen in 1...min(3, source.count - 1) {
                let areaCand = String(source.prefix(areaLen))
                // Only add if the prefix is a known valid German district code
                guard areaCand.allSatisfy(\.isLetter),
                      GermanPlateDatabase.isValid(areaCand) else { continue }
                let spaced = areaCand + " " + String(source.dropFirst(areaLen))
                if !pool.contains(spaced) { pool.append(spaced) }
                break  // first valid area length wins
            }
        }

        // ── Pass 1–3: database-validated (original texts + pre-corrected variants)
        for raw in pool {
            if let result = parseGermanPlateWithDatabase(raw) {
                return result
            }
        }

        // ── Pass 4: exhaustive single confusable flip in area-code window ──────
        // Handles cases where the correction map doesn't cover the exact misread
        // but a single character swap yields a valid district code.
        let confusablePairs: [(Character, Character)] = [
            ("S", "O"), ("O", "S"),
            ("0", "O"), ("O", "0"),
            ("5", "S"), ("S", "5"),
            ("8", "B"), ("B", "8"),
        ]
        for raw in pool {
            let compact = raw
                .uppercased()
                .replacingOccurrences(of: "[^A-Z0-9ÄÖÜ]", with: "", options: .regularExpression)
            guard compact.count >= 4 else { continue }
            var chars = Array(compact)
            for pos in 0..<min(3, chars.count) {
                let original = chars[pos]
                for (from, to) in confusablePairs where original == from {
                    chars[pos] = to
                    let variant = String(chars)
                    for areaLen in 1...min(3, chars.count - 1) {
                        let area = String(variant.prefix(areaLen))
                        guard GermanPlateDatabase.isValid(area) else { continue }
                        let rest = String(variant.dropFirst(areaLen))
                        if let plate = extractGermanID(from: rest, area: area) {
                            return plate
                        }
                    }
                    chars[pos] = original
                }
            }
        }

        // ── Pass 5: regex-only fallback (unknown district codes not yet in DB) ─
        // NOTE: only reached when the database-validated passes all return nil.
        // We still validate the parsed plate via the database so that a misread
        // area code like "WBS" is rejected and never returned to the caller.
        for raw in texts {
            let candidates = germanCandidatesFallback(from: raw)
            for candidate in candidates {
                if let parsed = parseGermanPlate(candidate),
                   validatePlate(parsed, forCountry: "de") {
                    // Extra guard: if the area code exists in the database but differs
                    // from what was parsed, skip — the earlier passes would have caught
                    // the correct area code.
                    let parts = parsed.split(separator: " ")
                    if let areaStr = parts.first {
                        let area = String(areaStr)
                        // If the area is NOT in the DB it might still be a genuine
                        // new/reintroduced code — allow it. But if the area IS
                        // definitively a misread of another code (in the misread map),
                        // skip this result entirely.
                        if GermanPlateDatabase.isKnownMisread(area) { continue }
                    }
                    return parsed
                }
            }
        }
        return nil
    }

    /// Database-validated parser. Finds the city code by looking it up in
    /// GermanPlateDatabase, then extracts the identifier from what remains.
    private static func parseGermanPlateWithDatabase(_ raw: String) -> String? {
        let normalized = raw
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9ÄÖÜ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var tokens = normalized.components(separatedBy: " ").filter { !$0.isEmpty }
        if let first = tokens.first,
           first.count <= 3,
           first.allSatisfy({ $0.isLetter }) {
            let fixedFirst = GermanPlateDatabase.correctOCRAreaToken(first)
            if fixedFirst != first {
                tokens[0] = fixedFirst
            }
        }
        var compact = tokens.joined()
        compact = GermanPlateDatabase.correctOCRCompactPrefix(compact)

        // Circular-sticker character set: Vision frequently misreads the round
        // HU/TÜV stickers as one of these characters.
        let stickerChars: Set<Character> = ["O", "0", "Q", "C", "G"]

        // ── Pass 1: Token-based area matching ──────────────────────────────────
        // Handles: "WOB ZK 295", "W O B ZK 295", "WOB O ZK 295"
        if tokens.count >= 2 {
            for areaTokenCount in 1...min(3, tokens.count - 1) {
                let area = tokens[0..<areaTokenCount].joined()
                guard GermanPlateDatabase.isValid(area) else { continue }
                // Remaining tokens — filter lone sticker-like single-char tokens.
                let idTokens = Array(tokens[areaTokenCount...])
                    .filter { t in
                        guard t.count == 1, let ch = t.first else { return true }
                        return !stickerChars.contains(ch)
                    }
                guard !idTokens.isEmpty else { continue }
                if let plate = extractGermanID(from: idTokens.joined(), area: area) {
                    return plate
                }
            }
        }

        // ── Pass 2: Compact-string split ────────────────────────────────────────
        // Handles: "WOBZK295" (merged), "WOBOZK295" / "WOBOOZK295" (1-2 sticker chars).
        // Iterates areaLen from 1 → 3 so that the shortest valid area code that
        // successfully strips a sticker char wins first.
        if compact.count >= 3 {
            for areaLen in 1...min(3, compact.count - 2) {
                let area = String(compact.prefix(areaLen))
                guard GermanPlateDatabase.isValid(area) else { continue }
                let rest = String(compact.dropFirst(areaLen))

                // Direct match (no sticker in the way)
                if let plate = extractGermanID(from: rest, area: area) {
                    return plate
                }

                // Try removing 1 sticker-like character at any position between letters
                let restChars = Array(rest)
                for i in restChars.indices {
                    let ch = restChars[i]
                    guard stickerChars.contains(ch) else { continue }
                    let prevLetter = i == 0 || restChars[i - 1].isLetter
                    let nextLetter = i < restChars.count - 1 && restChars[i + 1].isLetter
                    guard prevLetter && nextLetter else { continue }
                    var cleaned1 = restChars
                    cleaned1.remove(at: i)
                    if let plate = extractGermanID(from: String(cleaned1), area: area) {
                        return plate
                    }
                    // Try also removing the NEXT character if it also looks like a sticker
                    // (two-sticker scenario: plate has TWO circular stickers, OCR reads both)
                    if i + 1 < restChars.count, stickerChars.contains(restChars[i + 1]) {
                        var cleaned2 = restChars
                        cleaned2.remove(at: i + 1)
                        cleaned2.remove(at: i)
                        if let plate = extractGermanID(from: String(cleaned2), area: area) {
                            return plate
                        }
                    }
                }
            }
        }

        // ── Pass 3: Insertion-correction ───────────────────────────────────────
        // OCR may drop one character from the area code because the sticker
        // visually overlaps it (e.g. OCR reads "WB" when the plate is "WOB").
        // We try inserting "O" at every position of the candidate area token(s)
        // to recover the full valid area code.
        if tokens.count >= 2 {
            for areaTokenCount in 1...min(3, tokens.count - 1) {
                let baseArea = tokens[0..<areaTokenCount].joined()
                for insertPos in 0...baseArea.count {
                    guard baseArea.count + 1 <= 3 else { continue } // max 3-char area code
                    let idx = baseArea.index(baseArea.startIndex, offsetBy: insertPos)
                    let expandedArea = String(baseArea[..<idx]) + "O" + String(baseArea[idx...])
                    guard GermanPlateDatabase.isValid(expandedArea) else { continue }
                    let idTokens = Array(tokens[areaTokenCount...])
                        .filter { $0 != "O" && $0 != "0" }
                    guard !idTokens.isEmpty else { continue }
                    if let plate = extractGermanID(from: idTokens.joined(), area: expandedArea) {
                        return plate
                    }
                }
            }
        }

        return nil
    }

    /// Extracts the identifier part (1-2 letters + 1-4 digits + optional E/H)
    /// from a string that has already had the area code removed.
    private static func extractGermanID(from idString: String, area: String) -> String? {
        let pattern = "^([A-Z]{1,2})([0-9OISBZQG]{1,4})([EH]?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: idString.utf16.count)
        guard let match = regex.firstMatch(in: idString, range: range),
              let lettersRange = Range(match.range(at: 1), in: idString),
              let digitsRange  = Range(match.range(at: 2), in: idString),
              let suffixRange  = Range(match.range(at: 3), in: idString) else { return nil }

        let letters = String(idString[lettersRange])
        let suffix  = String(idString[suffixRange])
        var digits  = String(String(idString[digitsRange]).map { ch -> Character in
            switch ch {
            case "O", "Q": return "0"
            case "I":       return "1"
            case "S":       return "5"
            case "B":       return "8"
            case "Z":       return "2"
            case "G":       return "6"
            default:        return ch
            }
        })

        // German registration numbers never start with 0; strip leading zeros.
        while digits.count > 1 && digits.first == "0" {
            digits = String(digits.dropFirst())
        }
        guard digits.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil else { return nil }

        return "\(area) \(letters)\(digits)\(suffix)"
    }

    // ── Regex-only fallback (used when area code is not yet in the database) ──

    private static func parseGermanPlate(_ raw: String) -> String? {
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
              let areaRange    = Range(match.range(at: 1), in: normalized),
              let lettersRange = Range(match.range(at: 2), in: normalized),
              let digitsRange  = Range(match.range(at: 3), in: normalized),
              let suffixRange  = Range(match.range(at: 4), in: normalized) else { return nil }

        let area    = String(normalized[areaRange])
        let letters = String(normalized[lettersRange])
        let suffix  = String(normalized[suffixRange])
        var digits  = String(String(normalized[digitsRange]).map { ch -> Character in
            switch ch {
            case "O", "Q": return "0"
            case "I":       return "1"
            case "S":       return "5"
            case "B":       return "8"
            case "Z":       return "2"
            case "G":       return "6"
            default:        return ch
            }
        })

        while digits.count > 1 && digits.first == "0" {
            digits = String(digits.dropFirst())
        }
        guard digits.range(of: "^[0-9]{1,4}$", options: .regularExpression) != nil else { return nil }
        return "\(area) \(letters)\(digits)\(suffix)"
    }

    /// Generates candidate strings for the regex-only fallback.
    /// NOTE: Does NOT remove standalone O/0 tokens (Case A was removed to prevent
    /// area codes like "WOB" from being corrupted to "WB"). Only Case B (sticker
    /// merges into a compact run of letters) is retained.
    private static func germanCandidatesFallback(from raw: String) -> [String] {
        let normalized = raw
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9ÄÖÜ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let compact = normalized.replacingOccurrences(of: " ", with: "")
        var out: [String] = [normalized]
        if !compact.isEmpty {
            out.append(compact)
            let fixedCompact = GermanPlateDatabase.correctOCRCompactPrefix(compact)
            if fixedCompact != compact {
                out.append(fixedCompact)
            }
        }

        // Remove an "O"/"0" that sits between two letter characters in the
        // compact string — this handles a sticker fused into the plate text.
        let chars = Array(compact)
        for i in chars.indices {
            let ch = chars[i]
            guard ch == "O" || ch == "0" else { continue }
            let prevIsLetter = i > 0 && chars[i - 1].isLetter
            let nextIsLetter = i < chars.count - 1 && chars[i + 1].isLetter
            if prevIsLetter && nextIsLetter {
                var variant = chars; variant.remove(at: i)
                out.append(String(variant))
            }
        }

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
        /// `users.franchiseId` value chosen at login (e.g. CH, TR_SABIHAGOKCEN).
        static let loginSelectedFranchiseId = "loginSelectedFranchiseId"
    }
    
    /// Whether the user has explicitly chosen a country (login or post-login sync).
    var hasPersistedCountrySelection: Bool {
        let raw = string(forKey: Keys.selectedCountryId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !raw.isEmpty
    }

    /// Get the currently selected country ID (empty until the user picks one at login).
    var selectedCountryId: String {
        get { string(forKey: Keys.selectedCountryId) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                removeObject(forKey: Keys.selectedCountryId)
            } else {
                set(trimmed, forKey: Keys.selectedCountryId)
            }
        }
    }
    
    /// Franchise picked on login (multi-franchise countries). Used with country validation on session restore.
    var loginSelectedFranchiseId: String? {
        get {
            let s = string(forKey: Keys.loginSelectedFranchiseId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return s.isEmpty ? nil : s
        }
        set {
            if let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                set(v, forKey: Keys.loginSelectedFranchiseId)
            } else {
                removeObject(forKey: Keys.loginSelectedFranchiseId)
            }
        }
    }

    private func loginFranchiseKey(for countryCode: String) -> String {
        "loginSelectedFranchiseId_\(countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())"
    }

    /// Last franchise chosen for a specific country (prevents CH branch showing when TR is selected).
    func loginSelectedFranchiseId(for countryCode: String) -> String? {
        let key = loginFranchiseKey(for: countryCode)
        let s = string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    func setLoginSelectedFranchiseId(_ franchiseId: String?, for countryCode: String) {
        let key = loginFranchiseKey(for: countryCode)
        if let v = franchiseId?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            set(v.uppercased(), forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
    
    /// Get the currently selected country (only when the user has explicitly chosen one at login).
    var selectedCountry: Country {
        guard hasPersistedCountrySelection else {
            return CountryManager.defaultCountry
        }
        let raw = string(forKey: Keys.selectedCountryId)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CountryManager.country(byId: raw) ?? CountryManager.defaultCountry
    }

    /// Branch picked at login for the active session (`loginSelectedFranchiseId_DE`, etc.).
    func sessionLoginFranchiseId(preferredCountryCode: String? = nil) -> String? {
        func scoped(for cc: String) -> String? {
            let scoped = loginSelectedFranchiseId(for: cc)?.uppercased() ?? ""
            return scoped.isEmpty ? nil : scoped
        }
        if let cc = preferredCountryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !cc.isEmpty {
            if let s = scoped(for: cc) { return s }
        }
        if hasPersistedCountrySelection {
            let cc = selectedCountry.countryCode.uppercased()
            if let s = scoped(for: cc) { return s }
        }
        if let global = loginSelectedFranchiseId, !global.isEmpty {
            let g = global.uppercased()
            if let cc = preferredCountryCode?.uppercased(), !cc.isEmpty,
               LoginFranchiseCountryGuard.franchiseBelongsToCountry(
                   franchiseId: g,
                   documentCountryCode: nil,
                   selectedCountryCode: cc
               ) {
                return g
            }
            if hasPersistedCountrySelection,
               LoginFranchiseCountryGuard.franchiseBelongsToCountry(
                   franchiseId: g,
                   documentCountryCode: nil,
                   selectedCountryCode: selectedCountry.countryCode
               ) {
                return g
            }
        }
        return nil
    }
}

// MARK: - Session country (login picker + profile; never CH-by-default for DE users)

enum SessionCountryResolver {
    /// Resolves UI/country context: `countryCode` wins over legacy `franchiseId` (e.g. DE vs CH).
    static func activeCountry(userProfile: UserProfile?) -> Country {
        if let profile = userProfile {
            if profile.isCrossFranchisePlatformOperator {
                return UserDefaults.standard.selectedCountry
            }
            if let byCode = CountryManager.country(byCode: profile.countryCode) {
                return byCode
            }
            let fid = profile.franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if fid.count == 2, let byRoot = CountryManager.country(byCode: fid) {
                return byRoot
            }
            if let byId = CountryManager.country(byId: fid.lowercased()) {
                return byId
            }
        }
        return UserDefaults.standard.selectedCountry
    }
}
