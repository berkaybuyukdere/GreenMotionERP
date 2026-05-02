//
//  FleetListImportParser.swift
//  AracHasarKayit
//
//  Düsseldorf-style fleet list: Plate, Make, Model, Category (other columns ignored).
//

import Foundation
import ZIPFoundation

struct FleetVehicleImportRow: Identifiable, Equatable {
    var id: String { "\(sourceRow)|\(plateStored)|\(marka)|\(model)|\(vin ?? "")" }
    let sourceRow: Int
    let plateStored: String
    let marka: String
    let model: String
    let kategori: String
    var vin: String?
    /// Turkey garage branch storage key; `nil` means use bulk default from import UI at save time.
    var garageBranchStorageKey: String?
}

enum FleetListImportParserError: LocalizedError {
    case cannotOpenArchive
    case missingSheet
    case invalidEncoding
    case missingHeaders
    case emptyFile
    case emptyPlate

    var errorDescription: String? {
        switch self {
        case .cannotOpenArchive: return "Could not open spreadsheet archive."
        case .missingSheet: return "Could not find xl/worksheets/sheet1.xml in the workbook."
        case .invalidEncoding: return "Could not decode XML as UTF-8."
        case .missingHeaders: return "Missing required columns: Plate, Make, Model, Category."
        case .emptyFile: return "File is empty."
        case .emptyPlate: return "Plate value is empty."
        }
    }
}

enum FleetListImportParser {

    // MARK: - Public

    static func parseCSV(data: Data, franchiseId: String) throws -> (rows: [FleetVehicleImportRow], issues: [String]) {
        guard let text = String(data: data, encoding: .utf8) else { throw FleetListImportParserError.invalidEncoding }
        let matrix = parseCSVTextToMatrix(text)
        return matrixToFleetRows(matrix, franchiseId: franchiseId)
    }

    static func parseXLSX(fileURL: URL, franchiseId: String) throws -> (rows: [FleetVehicleImportRow], issues: [String]) {
        guard let archive = Archive(url: fileURL, accessMode: .read) else {
            throw FleetListImportParserError.cannotOpenArchive
        }
        guard let sheetEntry = archive.first(where: { $0.path == "xl/worksheets/sheet1.xml" }) else {
            throw FleetListImportParserError.missingSheet
        }
        var sheetData = Data()
        _ = try archive.extract(sheetEntry, consumer: { chunk in sheetData.append(chunk) })
        guard let sheetXml = String(data: sheetData, encoding: .utf8) else {
            throw FleetListImportParserError.invalidEncoding
        }

        var shared: [String] = []
        if let ssEntry = archive.first(where: { $0.path == "xl/sharedStrings.xml" }) {
            var ssData = Data()
            _ = try archive.extract(ssEntry, consumer: { chunk in ssData.append(chunk) })
            if let ssXml = String(data: ssData, encoding: .utf8) {
                shared = parseSharedStrings(xml: ssXml)
            }
        }

        let matrix = buildMatrixFromSheetXML(sheetXml, sharedStrings: shared)
        return matrixToFleetRows(matrix, franchiseId: franchiseId)
    }

    static func groupByCategory(_ rows: [FleetVehicleImportRow]) -> [(category: String, items: [FleetVehicleImportRow])] {
        let grouped = Dictionary(grouping: rows, by: { $0.kategori })
        return grouped.keys.sorted().map { key in
            (category: key, items: grouped[key] ?? [])
        }
    }

    static func dedupeByPlate(franchiseId: String, rows: [FleetVehicleImportRow]) -> [FleetVehicleImportRow] {
        var seen = Set<String>()
        var out: [FleetVehicleImportRow] = []
        for r in rows {
            let k = plateDedupeKey(franchiseId: franchiseId, storedPlate: r.plateStored)
            guard !k.isEmpty, !seen.contains(k) else { continue }
            seen.insert(k)
            out.append(r)
        }
        return out
    }

    static func filterAgainstExistingFleet(
        franchiseId: String,
        rows: [FleetVehicleImportRow],
        existingPlates: [String]
    ) -> (willImport: [FleetVehicleImportRow], skippedExisting: [FleetVehicleImportRow]) {
        let existingKeys = Set(existingPlates.map { plateDedupeKey(franchiseId: franchiseId, storedPlate: $0) })
        var will: [FleetVehicleImportRow] = []
        var skip: [FleetVehicleImportRow] = []
        for r in rows {
            let k = plateDedupeKey(franchiseId: franchiseId, storedPlate: r.plateStored)
            if existingKeys.contains(k) {
                skip.append(r)
            } else {
                will.append(r)
            }
        }
        return (will, skip)
    }

    // MARK: - Plate / category

    static func plateDedupeKey(franchiseId: String, storedPlate: String) -> String {
        let fid = franchiseId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if fid.hasPrefix("TR") {
            return TurkishPlateFormats.normalizeCompact(storedPlate)
        }
        if fid.hasPrefix("DE") {
            return storedPlate
                .uppercased()
                .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
        }
        return storedPlate.replacingOccurrences(of: " ", with: "").uppercased()
    }

    static func storedPlate(franchiseId: String, rawPlate: String) throws -> String {
        let fid = franchiseId.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = rawPlate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FleetListImportParserError.emptyPlate }
        if fid.hasPrefix("TR") {
            let compact = TurkishPlateFormats.normalizeCompact(trimmed)
            guard TurkishPlateFormats.isValidCompact(compact) else {
                throw NSError(domain: "FleetListImport", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid Turkish plate: \(trimmed)",
                ])
            }
            return compact
        }
        if fid.hasPrefix("DE") {
            return normalizeGermanStoredPlate(trimmed)
        }
        return trimmed.replacingOccurrences(of: " ", with: "").uppercased()
    }

    private static func normalizeGermanStoredPlate(_ raw: String) -> String {
        let up = raw.uppercased()
        let cleaned = up
            .replacingOccurrences(of: "[^A-Z0-9\\s-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        if cleaned.contains("-") {
            let parts = cleaned.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            let city = (parts.first ?? "").replacingOccurrences(of: "[^A-Z]", with: "", options: .regularExpression)
            let rest = parts.dropFirst().joined(separator: "")
                .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
            if let m = rest.range(of: "^([A-Z]{1,2})([0-9][A-Z0-9]*)$", options: .regularExpression) {
                let token = String(rest[m])
                let letters = token.replacingOccurrences(of: "([A-Z]{1,2}).*$", with: "$1", options: .regularExpression)
                let digits = token.replacingOccurrences(of: "^[A-Z]{1,2}([0-9][A-Z0-9]*)$", with: "$1", options: .regularExpression)
                if !city.isEmpty, !letters.isEmpty, !digits.isEmpty {
                    return "\(city)-\(letters) \(digits)"
                }
            }
            return cleaned
        }

        let compact = cleaned.replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
        if let r = compact.range(of: "[0-9]"), r.lowerBound != compact.startIndex {
            let letters = String(compact[..<r.lowerBound])
            let digits = String(compact[r.lowerBound...])
            if !letters.isEmpty, !digits.isEmpty {
                return "\(letters) \(digits)"
            }
        }
        return compact
    }

    // MARK: - CSV

    private static func parseCSVTextToMatrix(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cur = ""
        var inQuotes = false
        let s = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        for ch in s {
            if inQuotes {
                if ch == "\"" {
                    inQuotes = false
                } else {
                    cur.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                row.append(cur)
                cur = ""
            } else if ch == "\n" {
                row.append(cur)
                cur = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
            } else if ch == "\r" {
                continue
            } else {
                cur.append(ch)
            }
        }
        row.append(cur)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            rows.append(row)
        }
        return rows
    }

    // MARK: - XLSX / sheet XML

    private static func parseSharedStrings(xml: String) -> [String] {
        var out: [String] = []
        let pattern = "<si[\\s\\S]*?</si>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return out }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        regex.enumerateMatches(in: xml, options: [], range: range) { result, _, _ in
            guard let r = result?.range, let swiftRange = Range(r, in: xml) else { return }
            let block = String(xml[swiftRange])
            if let t = firstMatch(block, pattern: "<t[^>]*>([^<]*)</t>") {
                out.append(decodeXmlEntities(t))
            } else {
                var pieces: [String] = []
                let tp = try? NSRegularExpression(pattern: "<t[^>]*>([^<]*)</t>", options: [])
                let br = NSRange(block.startIndex..<block.endIndex, in: block)
                tp?.enumerateMatches(in: block, options: [], range: br) { m, _, _ in
                    guard let mr = m?.range(at: 1), let sr = Range(mr, in: block) else { return }
                    pieces.append(decodeXmlEntities(String(block[sr])))
                }
                out.append(pieces.joined())
            }
        }
        return out
    }

    private static func buildMatrixFromSheetXML(_ xml: String, sharedStrings: [String]) -> [[String]] {
        var cellMap: [String: String] = [:]
        let pattern = #"<c r="([A-Z]+)(\d+)"([^>]*)>([\s\S]*?)</c>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        regex.enumerateMatches(in: xml, options: [], range: range) { result, _, _ in
            guard let res = result, res.numberOfRanges >= 5,
                  let cRange = Range(res.range(at: 1), in: xml),
                  let rRange = Range(res.range(at: 2), in: xml),
                  let aRange = Range(res.range(at: 3), in: xml),
                  let innerRange = Range(res.range(at: 4), in: xml) else { return }
            let col = String(xml[cRange])
            let row = String(xml[rRange])
            let attrs = String(xml[aRange])
            let inner = String(xml[innerRange])
            let addr = "\(col)\(row)"
            let value = stringFromCellInner(inner: inner, attributes: attrs, sharedStrings: sharedStrings)
            cellMap[addr] = value
        }

        var maxRow = 1
        for k in cellMap.keys {
            let digits = k.filter { $0.isNumber }
            if let n = Int(digits), n > maxRow { maxRow = n }
        }

        var maxColIdx = 0
        for k in cellMap.keys {
            let letters = k.filter { $0.isLetter }
            let idx = columnLettersToIndex(letters)
            if idx > maxColIdx { maxColIdx = idx }
        }

        var matrix: [[String]] = []
        for r in 1...maxRow {
            var rowVals: [String] = []
            for cIdx in 0...maxColIdx {
                let letters = indexToColumnLetters(cIdx)
                let addr = "\(letters)\(r)"
                rowVals.append(cellMap[addr] ?? "")
            }
            matrix.append(rowVals)
        }
        return matrix
    }

    private static func stringFromCellInner(inner: String, attributes: String, sharedStrings: [String]) -> String {
        if attributes.contains("t=\"s\"") || attributes.contains("t='s'") {
            if let v = firstMatch(inner, pattern: #"<v>([^<]*)</v>"#),
               let idx = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)),
               idx >= 0, idx < sharedStrings.count {
                return sharedStrings[idx]
            }
            return ""
        }
        if let t = firstMatch(inner, pattern: #"<t[^>]*>([^<]*)</t>"#) {
            return decodeXmlEntities(t)
        }
        if let v = firstMatch(inner, pattern: #"<v>([^<]*)</v>"#) {
            return decodeXmlEntities(v)
        }
        return ""
    }

    private static func columnLettersToIndex(_ letters: String) -> Int {
        var n = 0
        for u in letters.unicodeScalars {
            guard u.value >= 65 && u.value <= 90 else { continue }
            n = n * 26 + Int(u.value - 65) + 1
        }
        return max(0, n - 1)
    }

    private static func indexToColumnLetters(_ index: Int) -> String {
        var n = index + 1
        var s = ""
        while n > 0 {
            let rem = (n - 1) % 26
            let ch = UnicodeScalar(65 + rem)!
            s = String(Character(ch)) + s
            n = (n - 1) / 26
        }
        return s
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func decodeXmlEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    // MARK: - Header matrix → rows

    private static let headerAliases: [String: [String]] = [
        "plate": ["plate", "plaka", "license plate", "license", "plate number", "kennzeichen", "registration"],
        "make": ["make", "marka", "brand", "hersteller"],
        "model": ["model", "modell"],
        "category": ["category", "kategori", "vehicle category", "cat", "fahrzeugkategorie"],
        "vin": ["vin", "vin number", "chassis", "fahrgestell", "fahrgestellnummer", "rahmen"],
    ]

    private static func normalizeHeader(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private struct FleetHeaderIndices {
        let plate: Int
        let make: Int
        let model: Int
        let category: Int
        let vin: Int?
    }

    private static func resolveHeaderIndices(_ headerRow: [String]) -> FleetHeaderIndices? {
        var idxPlate = -1
        var idxMake = -1
        var idxModel = -1
        var idxCat = -1
        var idxVin: Int?
        for (i, cell) in headerRow.enumerated() {
            let h = normalizeHeader(cell)
            if idxPlate < 0, headerAliases["plate"]?.contains(h) == true { idxPlate = i }
            if idxMake < 0, headerAliases["make"]?.contains(h) == true { idxMake = i }
            if idxModel < 0, headerAliases["model"]?.contains(h) == true { idxModel = i }
            if idxCat < 0, headerAliases["category"]?.contains(h) == true { idxCat = i }
            if idxVin == nil, headerAliases["vin"]?.contains(h) == true { idxVin = i }
        }
        guard idxPlate >= 0, idxMake >= 0, idxModel >= 0, idxCat >= 0 else { return nil }
        return FleetHeaderIndices(plate: idxPlate, make: idxMake, model: idxModel, category: idxCat, vin: idxVin)
    }

    private static func matrixToFleetRows(_ matrix: [[String]], franchiseId: String) -> (rows: [FleetVehicleImportRow], issues: [String]) {
        var issues: [String] = []
        guard let header = matrix.first else {
            issues.append(FleetListImportParserError.emptyFile.localizedDescription)
            return ([], issues)
        }
        guard let idx = resolveHeaderIndices(header) else {
            issues.append(FleetListImportParserError.missingHeaders.localizedDescription)
            return ([], issues)
        }

        var rows: [FleetVehicleImportRow] = []
        for r in 1..<matrix.count {
            let line = matrix[r]
            func cell(_ i: Int) -> String {
                guard i >= 0, i < line.count else { return "" }
                return String(line[i]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let rawPlate = cell(idx.plate)
            let make = cell(idx.make)
            let model = cell(idx.model)
            let catRaw = cell(idx.category)
            let vinRaw: String? = idx.vin.map { cell($0) }
            if rawPlate.isEmpty, make.isEmpty, model.isEmpty, catRaw.isEmpty { continue }

            let plate: String
            do {
                plate = try storedPlate(franchiseId: franchiseId, rawPlate: rawPlate)
            } catch {
                issues.append("Row \(r + 1): \(error.localizedDescription)")
                continue
            }
            guard !make.isEmpty, !model.isEmpty, !catRaw.isEmpty else {
                issues.append("Row \(r + 1): missing make, model, or category.")
                continue
            }
            let kategori = VehicleCategory.normalizeName(catRaw)
            let vinTrim = vinRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
            let vinVal = (vinTrim?.isEmpty == false) ? vinTrim : nil
            rows.append(FleetVehicleImportRow(
                sourceRow: r + 1,
                plateStored: plate,
                marka: make,
                model: model,
                kategori: kategori,
                vin: vinVal,
                garageBranchStorageKey: nil
            ))
        }
        return (rows, issues)
    }
}
