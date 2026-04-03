import Foundation

// MARK: - German Bundesland

enum GermanBundesland: String, CaseIterable {
    case BW = "Baden-Württemberg"
    case BY = "Bayern"
    case BE = "Berlin"
    case BB = "Brandenburg"
    case HB = "Bremen"
    case HH = "Hamburg"
    case HE = "Hessen"
    case MV = "Mecklenburg-Vorpommern"
    case NI = "Niedersachsen"
    case NW = "Nordrhein-Westfalen"
    case RP = "Rheinland-Pfalz"
    case SL = "Saarland"
    case SN = "Sachsen"
    case ST = "Sachsen-Anhalt"
    case SH = "Schleswig-Holstein"
    case TH = "Thüringen"
}

// MARK: - German Kennzeichen entry

struct GermanKennzeichen {
    let code: String
    let name: String
    let bundesland: GermanBundesland
}

// MARK: - GermanPlateDatabase

/// Complete list of current German Kfz-Unterscheidungszeichen (license plate codes)
/// covering all 16 Bundesländer. Includes codes that were historically abolished
/// and later reintroduced under the "Kennzeichenliberalisierung" reform (2012+).
enum GermanPlateDatabase {

    // ── Fast lookup set (uppercase) ───────────────────────────────────────────
    static let validCodes: Set<String> = {
        Set(allKennzeichen.map(\.code))
    }()

    static func isValid(_ code: String) -> Bool {
        validCodes.contains(code.uppercased())
    }

    /// Look up the Bundesland and city name for a plate code.
    static func lookup(_ code: String) -> GermanKennzeichen? {
        allKennzeichen.first { $0.code == code.uppercased() }
    }

    // MARK: - OCR corrections (Unterscheidungszeichen)

    /// Fixed misreads where Vision often outputs a **wrong letter** (HU seal, FE-Schrift, lighting).
    /// Keys are what Vision outputs; values are the correct district code.
    /// Extend whenever a field report reveals a new consistent misread pattern.
    ///
    /// IMPORTANT: Add a key here whenever you add to `ocrMisreadAreaCodes` so that
    /// `isKnownMisread` can filter stale regex-fallback results.
    static let ocrMisreadAreaCodes: [String: String] = [
        // ── Wolfsburg (WOB) — most common field report ────────────────────────
        // The HU/TÜV seal sits between "WO" and "B"; OCR scrambles them as "WBS".
        "WBS": "WOB",
        // Additional Wolfsburg misreads observed in field:
        "W0B": "WOB",   // O misread as digit 0
        "W0BS": "WOB",  // Both: digit 0 + sticker S
        "WOBS": "WOB",  // Sticker S appended
        // ── Other common S/O seal confusions ─────────────────────────────────
        "OLS": "OL",    // Oldenburg: O-L-sticker → "OLS"
        "OSN": "OS",    // Osnabrück: sticker after "OS"
        // ── Digit/letter mix-ups (vision in high-contrast mode) ───────────────
        "0F":  "OF",    // Offenbach
        "0B":  "OB",    // Oberhausen
        "0L":  "OL",    // Oldenburg via digit-O
        "0S":  "OS",    // Osnabrück via digit-O
        "5":   "S",     // Stuttgart (single char)
        "8":   "B",     // Berlin (single char)
    ]

    /// Returns true when the given string is a known OCR misread of another district
    /// code. Used to reject regex-fallback results that would return a wrong code.
    static func isKnownMisread(_ code: String) -> Bool {
        ocrMisreadAreaCodes[code.uppercased()] != nil
    }

    /// Returns a corrected 1–3 letter district code when OCR matches a known wrong
    /// pattern or a single confusable-character flip yields a valid code.
    ///
    /// Confusable pairs that Vision commonly mixes up on German FE-Schrift plates:
    ///   S ↔ O  (HU/TÜV seal looks like an "S" when partially overlapping a glyph)
    ///   B ↔ 8  (rarely, only when OCR is in numeric mode)
    ///   0 ↔ O
    static func correctOCRAreaToken(_ raw: String) -> String {
        let u = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, u.count <= 3 else { return raw }
        let lettersOnly = u.filter(\.isLetter)
        guard lettersOnly.count == u.count else { return raw }

        // Check if this exact string is a documented misread → return corrected code.
        if let fixed = ocrMisreadAreaCodes[u] { return fixed }
        if isValid(u) { return u }

        // Try every single-position confusable flip and return the first that yields
        // a valid district code. Pairs to try: S→O, O→S.
        // We intentionally do NOT apply generic B↔8 swaps here because district
        // codes never contain digits; if a digit is present the guard above fires.
        let confusables: [(Character, Character)] = [("S", "O"), ("O", "S")]
        var chars = Array(u)
        for (from, to) in confusables {
            for i in chars.indices where chars[i] == from {
                chars[i] = to
                let cand = String(chars)
                if isValid(cand) { return cand }
                chars[i] = from    // restore
            }
        }
        return u
    }

    /// Fixes merged compact OCR strings like `WBSZK295` → `WOBZK295`.
    ///
    /// Strategy: try treating the first 1, 2, and 3 characters as an area-code
    /// candidate, correct each with `correctOCRAreaToken`, and when the corrected
    /// version is both valid **and** different from what the OCR produced, replace
    /// the prefix and return the result.  Trying shorter prefixes first lets a
    /// 1- or 2-char code win when applicable (e.g. "B" for Berlin).
    static func correctOCRCompactPrefix(_ compact: String) -> String {
        let c = compact.uppercased()
        guard c.count >= 2 else { return compact }

        // First pass: try all prefix lengths using the explicit misread map.
        // This is separate from the generic flipper so known bad codes (e.g. "WBS")
        // are corrected before we try shorter valid prefixes (e.g. "WB").
        for prefixLen in stride(from: min(3, c.count - 1), through: 1, by: -1) {
            let prefix = String(c.prefix(prefixLen))
            guard prefix.allSatisfy(\.isLetter) else { continue }
            if let knownFix = ocrMisreadAreaCodes[prefix], isValid(knownFix) {
                return knownFix + c.dropFirst(prefixLen)
            }
        }

        // Second pass: generic single-character confusable flip.
        // Tries prefix lengths shortest-first (1→3) so a 1-char valid code (B, K, M…)
        // wins if found before a 3-char code whose prefix is already valid.
        for prefixLen in 1...min(3, c.count - 1) {
            let prefix = String(c.prefix(prefixLen))
            guard prefix.allSatisfy(\.isLetter) else { continue }
            let fixed = correctOCRAreaToken(prefix)
            if fixed != prefix, isValid(fixed) {
                return fixed + c.dropFirst(prefixLen)
            }
        }
        return compact
    }

    // ── Master table ─────────────────────────────────────────────────────────
    static let allKennzeichen: [GermanKennzeichen] = bw + by + be + bb + hb + hh + he + mv + ni + nw + rp + sl + sn + st + sh + th + extra

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Baden-Württemberg
    // ─────────────────────────────────────────────────────────────────────────
    private static let bw: [GermanKennzeichen] = [
        .init(code: "AA",  name: "Ostalbkreis (Aalen)",              bundesland: .BW),
        .init(code: "BAD", name: "Baden-Baden",                       bundesland: .BW),
        .init(code: "BB",  name: "Böblingen",                         bundesland: .BW),
        .init(code: "BC",  name: "Biberach an der Riß",               bundesland: .BW),
        .init(code: "BK",  name: "Rems-Murr-Kreis (Backnang)",        bundesland: .BW),
        .init(code: "BL",  name: "Zollernalbkreis (Balingen)",        bundesland: .BW),
        .init(code: "BR",  name: "Breisgau-Hochschwarzwald",          bundesland: .BW),
        .init(code: "BÜ",  name: "Bühl (Landkreis Rastatt)",          bundesland: .BW),
        .init(code: "CW",  name: "Calw",                               bundesland: .BW),
        .init(code: "DN",  name: "Schwarzwald-Baar-Kreis (Donaueschingen)", bundesland: .BW),
        .init(code: "EM",  name: "Emmendingen",                       bundesland: .BW),
        .init(code: "EN",  name: "Enzkreis",                          bundesland: .BW),
        .init(code: "ES",  name: "Esslingen",                         bundesland: .BW),
        .init(code: "FDS", name: "Freudenstadt",                      bundesland: .BW),
        .init(code: "FN",  name: "Bodenseekreis (Friedrichshafen)",   bundesland: .BW),
        .init(code: "FR",  name: "Freiburg im Breisgau",              bundesland: .BW),
        .init(code: "GD",  name: "Schwäbisch Gmünd (Ostalbkreis)",    bundesland: .BW),
        .init(code: "GP",  name: "Göppingen",                         bundesland: .BW),
        .init(code: "GÜ",  name: "Gütersloh – BW hist.",              bundesland: .BW),
        .init(code: "HA",  name: "Heidelberg (hist.)",                bundesland: .BW),
        .init(code: "HD",  name: "Heidelberg / Rhein-Neckar-Kreis",   bundesland: .BW),
        .init(code: "HDH", name: "Heidenheim",                        bundesland: .BW),
        .init(code: "HG",  name: "Bad Homburg (hist. BW)",            bundesland: .BW),
        .init(code: "HK",  name: "Heilbronn (Landkreis)",             bundesland: .BW),
        .init(code: "HN",  name: "Heilbronn (Stadt)",                 bundesland: .BW),
        .init(code: "HOB", name: "Horb am Neckar (hist.)",            bundesland: .BW),
        .init(code: "HR",  name: "Herrenberg (hist.)",                bundesland: .BW),
        .init(code: "KA",  name: "Karlsruhe",                         bundesland: .BW),
        .init(code: "KN",  name: "Konstanz",                          bundesland: .BW),
        .init(code: "KÜN", name: "Hohenlohekreis (Künzelsau)",        bundesland: .BW),
        .init(code: "LB",  name: "Ludwigsburg",                       bundesland: .BW),
        .init(code: "LÖ",  name: "Lörrach",                           bundesland: .BW),
        .init(code: "MA",  name: "Mannheim",                          bundesland: .BW),
        .init(code: "MOS", name: "Konstanz (hist. Möhringen?)",       bundesland: .BW),
        .init(code: "MÜ",  name: "Mühldorf (hist. BW)",               bundesland: .BW),
        .init(code: "NA",  name: "Nagold (hist.)",                    bundesland: .BW),
        .init(code: "NG",  name: "Nürtingen (hist.)",                 bundesland: .BW),
        .init(code: "NK",  name: "Neckar-Odenwald-Kreis (Mosbach)",   bundesland: .BW),
        .init(code: "ÖHR", name: "Öhringen (hist.)",                  bundesland: .BW),
        .init(code: "OG",  name: "Ortenaukreis (Offenburg)",          bundesland: .BW),
        .init(code: "PF",  name: "Pforzheim",                         bundesland: .BW),
        .init(code: "RA",  name: "Rastatt",                           bundesland: .BW),
        .init(code: "RN",  name: "Rottweil",                          bundesland: .BW),
        .init(code: "RT",  name: "Reutlingen",                        bundesland: .BW),
        .init(code: "RW",  name: "Rottweil (hist.)",                  bundesland: .BW),
        .init(code: "S",   name: "Stuttgart",                         bundesland: .BW),
        .init(code: "SHA", name: "Schwäbisch Hall",                   bundesland: .BW),
        .init(code: "SIG", name: "Sigmaringen",                       bundesland: .BW),
        .init(code: "SK",  name: "Sinsheim (hist.)",                  bundesland: .BW),
        .init(code: "TBB", name: "Main-Tauber-Kreis (Tauberbischofsheim)", bundesland: .BW),
        .init(code: "TÜ",  name: "Tübingen",                          bundesland: .BW),
        .init(code: "TUT", name: "Tuttlingen",                        bundesland: .BW),
        .init(code: "ÜB",  name: "Überlingen (hist.)",                bundesland: .BW),
        .init(code: "UL",  name: "Ulm",                               bundesland: .BW),
        .init(code: "VS",  name: "Schwarzwald-Baar-Kreis (Villingen-Schwenningen)", bundesland: .BW),
        .init(code: "WN",  name: "Rems-Murr-Kreis (Waiblingen)",      bundesland: .BW),
        .init(code: "WOS", name: "Wolfach-Schramberg (hist.)",        bundesland: .BW),
        .init(code: "WT",  name: "Waldshut-Tiengen",                  bundesland: .BW),
        .init(code: "ZW",  name: "Zweibrücken (hist. BW)",            bundesland: .BW),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Bayern
    // ─────────────────────────────────────────────────────────────────────────
    private static let by: [GermanKennzeichen] = [
        .init(code: "A",   name: "Augsburg (Stadt)",                  bundesland: .BY),
        .init(code: "AB",  name: "Aschaffenburg",                     bundesland: .BY),
        .init(code: "AIC", name: "Aichach-Friedberg",                 bundesland: .BY),
        .init(code: "ALZ", name: "Alzenau / Main-Spessart (hist.)",   bundesland: .BY),
        .init(code: "AM",  name: "Amberg (Stadt)",                    bundesland: .BY),
        .init(code: "AN",  name: "Ansbach",                           bundesland: .BY),
        .init(code: "AÖ",  name: "Altötting",                         bundesland: .BY),
        .init(code: "AS",  name: "Amberg-Sulzbach",                   bundesland: .BY),
        .init(code: "ASD", name: "Aschendorf (hist.)",                bundesland: .BY),
        .init(code: "BA",  name: "Bamberg",                           bundesland: .BY),
        .init(code: "BGL", name: "Berchtesgadener Land",              bundesland: .BY),
        .init(code: "BOG", name: "Straubing-Bogen",                   bundesland: .BY),
        .init(code: "BRK", name: "Rosenheim (Landkreis / Bad Aibling)", bundesland: .BY),
        .init(code: "BT",  name: "Bayreuth",                          bundesland: .BY),
        .init(code: "BUL", name: "Burglengenfeld (hist.)",            bundesland: .BY),
        .init(code: "CHA", name: "Cham",                              bundesland: .BY),
        .init(code: "CO",  name: "Coburg",                            bundesland: .BY),
        .init(code: "DAH", name: "Dachau",                            bundesland: .BY),
        .init(code: "DEG", name: "Deggendorf",                        bundesland: .BY),
        .init(code: "DGF", name: "Dingolfing-Landau",                 bundesland: .BY),
        .init(code: "DLG", name: "Dillingen an der Donau",            bundesland: .BY),
        .init(code: "DON", name: "Donau-Ries",                        bundesland: .BY),
        .init(code: "EBE", name: "Ebersberg",                         bundesland: .BY),
        .init(code: "ED",  name: "Erding",                            bundesland: .BY),
        .init(code: "EI",  name: "Eichstätt",                         bundesland: .BY),
        .init(code: "EIL", name: "Eichstätt (hist.)",                 bundesland: .BY),
        .init(code: "ER",  name: "Erlangen (Stadt)",                  bundesland: .BY),
        .init(code: "ERH", name: "Erlangen-Höchstadt",                bundesland: .BY),
        .init(code: "ESB", name: "Neumarkt i.d.OPf. (hist.)",        bundesland: .BY),
        .init(code: "FDB", name: "Fürstenfeldbruck (hist.)",          bundesland: .BY),
        .init(code: "FED", name: "Fürth (Land, hist.)",               bundesland: .BY),
        .init(code: "FFB", name: "Fürstenfeldbruck",                  bundesland: .BY),
        .init(code: "FO",  name: "Forchheim",                         bundesland: .BY),
        .init(code: "FRG", name: "Freyung-Grafenau",                  bundesland: .BY),
        .init(code: "FRZ", name: "Freising (hist.)",                  bundesland: .BY),
        .init(code: "FS",  name: "Freising",                          bundesland: .BY),
        .init(code: "FÜ",  name: "Fürth (Stadt)",                     bundesland: .BY),
        .init(code: "FÜS", name: "Füssen (hist. / Ostallgäu)",        bundesland: .BY),
        .init(code: "GA",  name: "Garmisch-Partenkirchen (hist.)",    bundesland: .BY),
        .init(code: "GAP", name: "Garmisch-Partenkirchen",            bundesland: .BY),
        .init(code: "GRI", name: "Rottal-Inn (Griesbach)",            bundesland: .BY),
        .init(code: "GUN", name: "Weißenburg-Gunzenhausen (hist.)",   bundesland: .BY),
        .init(code: "HAS", name: "Haßberge",                          bundesland: .BY),
        .init(code: "HO",  name: "Hof",                               bundesland: .BY),
        .init(code: "IGB", name: "Ingolstadt (hist.)",                bundesland: .BY),
        .init(code: "IN",  name: "Ingolstadt",                        bundesland: .BY),
        .init(code: "KE",  name: "Kempten",                           bundesland: .BY),
        .init(code: "KEH", name: "Kelheim",                           bundesland: .BY),
        .init(code: "KEM", name: "Kemnath / Tirschenreuth (hist.)",   bundesland: .BY),
        .init(code: "KF",  name: "Kaufbeuren",                        bundesland: .BY),
        .init(code: "KG",  name: "Bad Kissingen",                     bundesland: .BY),
        .init(code: "KU",  name: "Kulmbach",                          bundesland: .BY),
        .init(code: "LA",  name: "Landshut",                          bundesland: .BY),
        .init(code: "LAN", name: "Landsberg am Lech (hist.)",         bundesland: .BY),
        .init(code: "LAU", name: "Nürnberger Land (Lauf a.d.Pegnitz)", bundesland: .BY),
        .init(code: "LIF", name: "Lichtenfels",                       bundesland: .BY),
        .init(code: "LL",  name: "Landsberg am Lech",                 bundesland: .BY),
        .init(code: "M",   name: "München (Stadt)",                   bundesland: .BY),
        .init(code: "MB",  name: "Miesbach",                          bundesland: .BY),
        .init(code: "MIL", name: "Miltenberg",                        bundesland: .BY),
        .init(code: "MK",  name: "Main-Spessart (hist.)",             bundesland: .BY),
        .init(code: "MM",  name: "Memmingen",                         bundesland: .BY),
        .init(code: "MN",  name: "Unterallgäu",                       bundesland: .BY),
        .init(code: "MSP", name: "Main-Spessart",                     bundesland: .BY),
        .init(code: "MÜ",  name: "Mühldorf am Inn",                   bundesland: .BY),
        .init(code: "MZG", name: "Mühldorf (hist.)",                  bundesland: .BY),
        .init(code: "N",   name: "Nürnberg",                          bundesland: .BY),
        .init(code: "NAB", name: "Nabburg (hist.)",                   bundesland: .BY),
        .init(code: "ND",  name: "Neuburg-Schrobenhausen",            bundesland: .BY),
        .init(code: "NEA", name: "Neustadt an der Aisch-Bad Windsheim", bundesland: .BY),
        .init(code: "NES", name: "Rhön-Grabfeld (Neustadt a.d.Saale)", bundesland: .BY),
        .init(code: "NEW", name: "Neustadt an der Waldnaab",          bundesland: .BY),
        .init(code: "NM",  name: "Neumarkt in der Oberpfalz",         bundesland: .BY),
        .init(code: "NÜ",  name: "Nürnberger Land",                   bundesland: .BY),
        .init(code: "NYS", name: "Nördlingen (hist.)",                bundesland: .BY),
        .init(code: "OA",  name: "Oberallgäu",                        bundesland: .BY),
        .init(code: "OAL", name: "Ostallgäu",                         bundesland: .BY),
        .init(code: "OB",  name: "Obernburg (hist.)",                 bundesland: .BY),
        .init(code: "OBN", name: "Obernburg (hist.)",                 bundesland: .BY),
        .init(code: "PA",  name: "Passau",                            bundesland: .BY),
        .init(code: "PAN", name: "Rottal-Inn (Pfarrkirchen)",         bundesland: .BY),
        .init(code: "PEG", name: "Pegnitz (hist.)",                   bundesland: .BY),
        .init(code: "PH",  name: "Pfaffenhofen an der Ilm",           bundesland: .BY),
        .init(code: "PIR", name: "Pirmasens (hist.)",                 bundesland: .BY),
        .init(code: "PLÖ", name: "Plön (hist.)",                      bundesland: .BY),
        .init(code: "R",   name: "Regensburg",                        bundesland: .BY),
        .init(code: "RD",  name: "Rendsburg-Eckernförde (hist.)",     bundesland: .BY),
        .init(code: "REG", name: "Regen",                             bundesland: .BY),
        .init(code: "REH", name: "Regen (hist.)",                     bundesland: .BY),
        .init(code: "REI", name: "Reichenhall (hist. BGL)",           bundesland: .BY),
        .init(code: "RID", name: "Neumarkt i.d.OPf. (hist.)",        bundesland: .BY),
        .init(code: "RO",  name: "Rosenheim",                         bundesland: .BY),
        .init(code: "ROK", name: "Rosenheim (hist.)",                 bundesland: .BY),
        .init(code: "ROT", name: "Roth",                              bundesland: .BY),
        .init(code: "SC",  name: "Schwabach",                         bundesland: .BY),
        .init(code: "SE",  name: "Ebersberg (hist.)",                 bundesland: .BY),
        .init(code: "SR",  name: "Straubing",                         bundesland: .BY),
        .init(code: "STA", name: "Starnberg",                         bundesland: .BY),
        .init(code: "STB", name: "Straubing (hist.)",                 bundesland: .BY),
        .init(code: "STE", name: "Stehlin (hist.)",                   bundesland: .BY),
        .init(code: "TE",  name: "Tirschenreuth (hist.)",             bundesland: .BY),
        .init(code: "TIR", name: "Tirschenreuth",                     bundesland: .BY),
        .init(code: "TS",  name: "Traunstein",                        bundesland: .BY),
        .init(code: "TÖL", name: "Bad Tölz-Wolfratshausen",           bundesland: .BY),
        .init(code: "VIB", name: "Vilsbiburg (hist.)",                bundesland: .BY),
        .init(code: "VO",  name: "Vohenstrauß (hist.)",               bundesland: .BY),
        .init(code: "WEN", name: "Weiden in der Oberpfalz",           bundesland: .BY),
        .init(code: "WM",  name: "Weilheim-Schongau",                 bundesland: .BY),
        .init(code: "WND", name: "Wunsiedel im Fichtelgebirge (hist.)", bundesland: .BY),
        .init(code: "WOS", name: "Wolfratshausen (hist.)",            bundesland: .BY),
        .init(code: "WS",  name: "Wasserburg am Inn (hist.)",         bundesland: .BY),
        .init(code: "WUG", name: "Weißenburg-Gunzenhausen",           bundesland: .BY),
        .init(code: "WUN", name: "Wunsiedel im Fichtelgebirge",       bundesland: .BY),
        .init(code: "WÜ",  name: "Würzburg",                          bundesland: .BY),
        .init(code: "ZW",  name: "Zweibrücken (hist.)",               bundesland: .BY),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Berlin
    // ─────────────────────────────────────────────────────────────────────────
    private static let be: [GermanKennzeichen] = [
        .init(code: "B",   name: "Berlin",                            bundesland: .BE),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Brandenburg
    // ─────────────────────────────────────────────────────────────────────────
    private static let bb: [GermanKennzeichen] = [
        .init(code: "BAR", name: "Barnim",                            bundesland: .BB),
        .init(code: "BRB", name: "Brandenburg an der Havel",          bundesland: .BB),
        .init(code: "CB",  name: "Cottbus",                           bundesland: .BB),
        .init(code: "EE",  name: "Elbe-Elster",                       bundesland: .BB),
        .init(code: "FF",  name: "Frankfurt (Oder)",                   bundesland: .BB),
        .init(code: "HVL", name: "Havelland",                         bundesland: .BB),
        .init(code: "LDS", name: "Dahme-Spreewald",                   bundesland: .BB),
        .init(code: "LOS", name: "Oder-Spree",                        bundesland: .BB),
        .init(code: "MOL", name: "Märkisch-Oderland",                 bundesland: .BB),
        .init(code: "MOS", name: "Märkisch-Oderland (hist.)",         bundesland: .BB),
        .init(code: "MYK", name: "Märkisch-Oderland (hist.)",         bundesland: .BB),
        .init(code: "OHV", name: "Oberhavel",                         bundesland: .BB),
        .init(code: "OPR", name: "Ostprignitz-Ruppin",                bundesland: .BB),
        .init(code: "OSL", name: "Oberspreewald-Lausitz",             bundesland: .BB),
        .init(code: "P",   name: "Potsdam",                           bundesland: .BB),
        .init(code: "PM",  name: "Potsdam-Mittelmark",                bundesland: .BB),
        .init(code: "PR",  name: "Prignitz",                          bundesland: .BB),
        .init(code: "SPN", name: "Spree-Neiße",                       bundesland: .BB),
        .init(code: "TF",  name: "Teltow-Fläming",                    bundesland: .BB),
        .init(code: "UM",  name: "Uckermark",                         bundesland: .BB),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Bremen
    // ─────────────────────────────────────────────────────────────────────────
    private static let hb: [GermanKennzeichen] = [
        .init(code: "HB",  name: "Bremen",                            bundesland: .HB),
        .init(code: "BHV", name: "Bremerhaven",                       bundesland: .HB),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Hamburg
    // ─────────────────────────────────────────────────────────────────────────
    private static let hh: [GermanKennzeichen] = [
        .init(code: "HH",  name: "Hamburg",                           bundesland: .HH),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Hessen
    // ─────────────────────────────────────────────────────────────────────────
    private static let he: [GermanKennzeichen] = [
        .init(code: "AB",  name: "Aschaffenburg (hist.)",             bundesland: .HE),
        .init(code: "ABI", name: "Anhalt-Bitterfeld",                 bundesland: .ST), // placed here hist.
        .init(code: "BI",  name: "Bielefeld (hist. HE)",              bundesland: .HE),
        .init(code: "DA",  name: "Darmstadt",                         bundesland: .HE),
        .init(code: "DB",  name: "Darmstadt (hist.)",                 bundesland: .HE),
        .init(code: "DILL",name: "Dillenburg (hist.)",                bundesland: .HE),
        .init(code: "ERB", name: "Erbach / Odenwaldkreis",            bundesland: .HE),
        .init(code: "FB",  name: "Fulda-Hünfeld (hist.)",             bundesland: .HE),
        .init(code: "FD",  name: "Fulda",                             bundesland: .HE),
        .init(code: "FKB", name: "Frankenberg (hist.)",               bundesland: .HE),
        .init(code: "GI",  name: "Gießen",                            bundesland: .HE),
        .init(code: "GR",  name: "Groß-Gerau",                        bundesland: .HE),
        .init(code: "GS",  name: "Goslar (hist. HE)",                 bundesland: .HE),
        .init(code: "HEF", name: "Hersfeld-Rotenburg",                bundesland: .HE),
        .init(code: "HEI", name: "Dithmarschen (hist.)",              bundesland: .HE),
        .init(code: "HG",  name: "Hochtaunuskreis",                   bundesland: .HE),
        .init(code: "HI",  name: "Hildesheim (hist. HE)",             bundesland: .HE),
        .init(code: "HOR", name: "Hochtaunus (hist.)",                bundesland: .HE),
        .init(code: "HR",  name: "Hersfeld-Rotenburg (hist.)",        bundesland: .HE),
        .init(code: "KS",  name: "Kassel",                            bundesland: .HE),
        .init(code: "KT",  name: "Kassel (hist.)",                    bundesland: .HE),
        .init(code: "LDK", name: "Lahn-Dill-Kreis",                   bundesland: .HE),
        .init(code: "LM",  name: "Limburg-Weilburg",                  bundesland: .HE),
        .init(code: "MKK", name: "Main-Kinzig-Kreis",                 bundesland: .HE),
        .init(code: "MR",  name: "Marburg-Biedenkopf",                bundesland: .HE),
        .init(code: "MTK", name: "Main-Taunus-Kreis",                 bundesland: .HE),
        .init(code: "MYK", name: "Mayen-Koblenz (hist.)",             bundesland: .HE),
        .init(code: "NI",  name: "Nienburg (hist.)",                  bundesland: .HE),
        .init(code: "ODW", name: "Odenwaldkreis",                     bundesland: .HE),
        .init(code: "OF",  name: "Offenbach am Main",                 bundesland: .HE),
        .init(code: "OH",  name: "Ostholstein (hist.)",               bundesland: .HE),
        .init(code: "RB",  name: "Rotenburg (hist.)",                 bundesland: .HE),
        .init(code: "RDA", name: "Rheingau-Taunus (hist.)",           bundesland: .HE),
        .init(code: "RTK", name: "Rheingau-Taunus-Kreis",             bundesland: .HE),
        .init(code: "VB",  name: "Vogelsbergkreis",                   bundesland: .HE),
        .init(code: "WI",  name: "Wiesbaden",                         bundesland: .HE),
        .init(code: "WKRS",name: "Waldeck-Frankenberg (hist.)",       bundesland: .HE),
        .init(code: "WIL", name: "Bernkastel-Wittlich (hist. HE)",    bundesland: .HE),
        .init(code: "WLFT",name: "Waldeck-Frankenberg (hist.)",       bundesland: .HE),
        .init(code: "WND", name: "Weilburg (hist.)",                  bundesland: .HE),
        .init(code: "WT",  name: "Waldshut-Tiengen (hist.)",          bundesland: .HE),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Mecklenburg-Vorpommern
    // ─────────────────────────────────────────────────────────────────────────
    private static let mv: [GermanKennzeichen] = [
        .init(code: "ABG", name: "Altenburger Land (hist. MV)",       bundesland: .TH),
        .init(code: "DBR", name: "Bad Doberan (hist.)",               bundesland: .MV),
        .init(code: "DM",  name: "Demmin (hist.)",                    bundesland: .MV),
        .init(code: "GN",  name: "Greifswald / Güstrow (hist.)",      bundesland: .MV),
        .init(code: "GW",  name: "Greifswald (hist.)",                bundesland: .MV),
        .init(code: "GÜ",  name: "Güstrow (hist.)",                   bundesland: .MV),
        .init(code: "HGW", name: "Hansestadt Greifswald",             bundesland: .MV),
        .init(code: "HRO", name: "Hansestadt Rostock",                bundesland: .MV),
        .init(code: "LWL", name: "Ludwigslust (hist.)",               bundesland: .MV),
        .init(code: "LUP", name: "Ludwigslust-Parchim",               bundesland: .MV),
        .init(code: "MQ",  name: "Müritz (hist.)",                    bundesland: .MV),
        .init(code: "MSE", name: "Mecklenburgische Seenplatte",        bundesland: .MV),
        .init(code: "MST", name: "Mecklenburg-Strelitz (hist.)",      bundesland: .MV),
        .init(code: "MÜR", name: "Müritz (hist.)",                    bundesland: .MV),
        .init(code: "MV",  name: "Mecklenburg-Vorpommern (hist.)",    bundesland: .MV),
        .init(code: "NB",  name: "Neubrandenburg (hist.)",            bundesland: .MV),
        .init(code: "NM",  name: "Neubrandenburg (hist.)",            bundesland: .MV),
        .init(code: "NVP", name: "Nordvorpommern (hist.)",            bundesland: .MV),
        .init(code: "OVP", name: "Vorpommern-Greifswald",             bundesland: .MV),
        .init(code: "PCH", name: "Parchim (hist.)",                   bundesland: .MV),
        .init(code: "PL",  name: "Parchim (hist.)",                   bundesland: .MV),
        .init(code: "RÜG", name: "Rügen",                             bundesland: .MV),
        .init(code: "RUG", name: "Rügen",                             bundesland: .MV),
        .init(code: "SBG", name: "Stralsund (hist.)",                 bundesland: .MV),
        .init(code: "SDH", name: "Südostholstein (hist.)",            bundesland: .MV),
        .init(code: "SN",  name: "Schwerin (kreisfreie Stadt)",        bundesland: .MV),
        .init(code: "STD", name: "Stade (hist. MV)",                  bundesland: .MV),
        .init(code: "STL", name: "Stralsund (hist.)",                 bundesland: .MV),
        .init(code: "VK",  name: "Vorpommern-Greifswald (hist.)",     bundesland: .MV),
        .init(code: "VR",  name: "Vorpommern-Rügen",                  bundesland: .MV),
        .init(code: "VRS", name: "Vorpommern-Stralsund (hist.)",      bundesland: .MV),
        .init(code: "WME", name: "Westmecklenburg (hist.)",           bundesland: .MV),
        .init(code: "WOL", name: "Wolgast (hist.)",                   bundesland: .MV),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Niedersachsen
    // ─────────────────────────────────────────────────────────────────────────
    private static let ni: [GermanKennzeichen] = [
        .init(code: "AHL", name: "Ahlen (hist.)",                     bundesland: .NI),
        .init(code: "AUR", name: "Aurich",                            bundesland: .NI),
        .init(code: "BHV", name: "Bremerhaven (hist.)",               bundesland: .NI),
        .init(code: "BOH", name: "Bocholt (hist.)",                   bundesland: .NI),
        .init(code: "BS",  name: "Braunschweig",                      bundesland: .NI),
        .init(code: "BÜZ", name: "Bützow (hist.)",                    bundesland: .NI),
        .init(code: "CLP", name: "Cloppenburg",                       bundesland: .NI),
        .init(code: "CUX", name: "Cuxhaven",                          bundesland: .NI),
        .init(code: "DAN", name: "Lüchow-Dannenberg",                 bundesland: .NI),
        .init(code: "DH",  name: "Diepholz",                          bundesland: .NI),
        .init(code: "EL",  name: "Emsland",                           bundesland: .NI),
        .init(code: "EMD", name: "Emden",                             bundesland: .NI),
        .init(code: "EMS", name: "Emsland (hist.)",                   bundesland: .NI),
        .init(code: "FRI", name: "Friesland",                         bundesland: .NI),
        .init(code: "GF",  name: "Gifhorn",                           bundesland: .NI),
        .init(code: "GOS", name: "Goslar",                            bundesland: .NI),
        .init(code: "GS",  name: "Goslar (hist.)",                    bundesland: .NI),
        .init(code: "GTH", name: "Gotha (hist.)",                     bundesland: .NI),
        .init(code: "GZ",  name: "Gronau (hist.)",                    bundesland: .NI),
        .init(code: "HAM", name: "Hameln-Pyrmont",                    bundesland: .NI),
        .init(code: "HE",  name: "Helmstedt",                         bundesland: .NI),
        .init(code: "HEL", name: "Helgoland (hist.)",                 bundesland: .NI),
        .init(code: "HK",  name: "Holzminden (hist.)",                bundesland: .NI),
        .init(code: "HL",  name: "Lübeck (hist. NI)",                 bundesland: .NI),
        .init(code: "HOL", name: "Holzminden",                        bundesland: .NI),
        .init(code: "HOM", name: "Homburg (hist. NI)",                bundesland: .NI),
        .init(code: "HRO", name: "Rostock (hist. NI)",                bundesland: .NI),
        .init(code: "HS",  name: "Heinsberg (hist. NI)",              bundesland: .NI),
        .init(code: "LER", name: "Leer",                              bundesland: .NI),
        .init(code: "LG",  name: "Lüneburg",                          bundesland: .NI),
        .init(code: "LK",  name: "Landkreis (hist.)",                 bundesland: .NI),
        .init(code: "NOH", name: "Grafschaft Bentheim",               bundesland: .NI),
        .init(code: "NOM", name: "Northeim",                          bundesland: .NI),
        .init(code: "NOR", name: "Aurich (hist.)",                    bundesland: .NI),
        .init(code: "OHZ", name: "Osterholz",                         bundesland: .NI),
        .init(code: "OL",  name: "Oldenburg (Stadt)",                 bundesland: .NI),
        .init(code: "OLP", name: "Cloppenburg (hist.)",               bundesland: .NI),
        .init(code: "OS",  name: "Osnabrück",                         bundesland: .NI),
        .init(code: "PE",  name: "Peine",                             bundesland: .NI),
        .init(code: "POR", name: "Peine-Osterode (hist.)",            bundesland: .NI),
        .init(code: "REH", name: "Uelzen (hist.)",                    bundesland: .NI),
        .init(code: "ROW", name: "Rotenburg (Wümme)",                 bundesland: .NI),
        .init(code: "SFA", name: "Soltau-Fallingbostel",              bundesland: .NI),
        .init(code: "SHG", name: "Schaumburg",                        bundesland: .NI),
        .init(code: "SHS", name: "Schaumburg-Lippe (hist.)",          bundesland: .NI),
        .init(code: "STA", name: "Stade",                             bundesland: .NI),
        .init(code: "STD", name: "Stade",                             bundesland: .NI),
        .init(code: "UE",  name: "Uelzen",                            bundesland: .NI),
        .init(code: "VEC", name: "Vechta",                            bundesland: .NI),
        .init(code: "VER", name: "Verden",                            bundesland: .NI),
        .init(code: "WAT", name: "Wattenscheid (hist.)",              bundesland: .NI),
        .init(code: "WF",  name: "Wolfenbüttel",                      bundesland: .NI),
        .init(code: "WL",  name: "Harburg (Landkreis)",               bundesland: .NI),
        .init(code: "WND", name: "Wunstorf (hist.)",                  bundesland: .NI),
        .init(code: "WOB", name: "Wolfsburg",                         bundesland: .NI),
        .init(code: "WST", name: "Ammerland (Westerstede)",           bundesland: .NI),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Nordrhein-Westfalen
    // ─────────────────────────────────────────────────────────────────────────
    private static let nw: [GermanKennzeichen] = [
        .init(code: "AC",  name: "Aachen",                            bundesland: .NW),
        .init(code: "AHL", name: "Ahlen (hist.)",                     bundesland: .NW),
        .init(code: "AK",  name: "Altenkirchen (RP hist.)",           bundesland: .NW),
        .init(code: "BIR", name: "Birkenfeld (hist. NW)",             bundesland: .NW),
        .init(code: "BM",  name: "Rhein-Erft-Kreis (Bergheim)",       bundesland: .NW),
        .init(code: "BN",  name: "Bonn",                              bundesland: .NW),
        .init(code: "BO",  name: "Bochum",                            bundesland: .NW),
        .init(code: "BOH", name: "Bocholt (hist.)",                   bundesland: .NW),
        .init(code: "BOR", name: "Borken",                            bundesland: .NW),
        .init(code: "BOT", name: "Bottrop",                           bundesland: .NW),
        .init(code: "BI",  name: "Bielefeld",                         bundesland: .NW),
        .init(code: "COE", name: "Coesfeld",                          bundesland: .NW),
        .init(code: "D",   name: "Düsseldorf",                        bundesland: .NW),
        .init(code: "DN",  name: "Düren",                             bundesland: .NW),
        .init(code: "DO",  name: "Dortmund",                          bundesland: .NW),
        .init(code: "DT",  name: "Detmold (hist.)",                   bundesland: .NW),
        .init(code: "DU",  name: "Duisburg",                          bundesland: .NW),
        .init(code: "DW",  name: "Düren (hist.)",                     bundesland: .NW),
        .init(code: "E",   name: "Essen",                             bundesland: .NW),
        .init(code: "EN",  name: "Ennepe-Ruhr-Kreis",                 bundesland: .NW),
        .init(code: "ER",  name: "Erkelenz (hist.)",                  bundesland: .NW),
        .init(code: "EU",  name: "Euskirchen",                        bundesland: .NW),
        .init(code: "GE",  name: "Gelsenkirchen",                     bundesland: .NW),
        .init(code: "GM",  name: "Gummersbach / Oberbergischer Kreis", bundesland: .NW),
        .init(code: "GT",  name: "Gütersloh",                         bundesland: .NW),
        .init(code: "GV",  name: "Grevenbroich (hist.)",              bundesland: .NW),
        .init(code: "H",   name: "Hannover (hist. NW)",               bundesland: .NW),
        .init(code: "HA",  name: "Hagen",                             bundesland: .NW),
        .init(code: "HAL", name: "Haltern (hist.)",                   bundesland: .NW),
        .init(code: "HER", name: "Herne",                             bundesland: .NW),
        .init(code: "HF",  name: "Herford",                           bundesland: .NW),
        .init(code: "HS",  name: "Heinsberg",                         bundesland: .NW),
        .init(code: "IM",  name: "Immenhausen (hist.)",               bundesland: .NW),
        .init(code: "IGB", name: "Ibbenbüren (hist.)",                bundesland: .NW),
        .init(code: "ISD", name: "Iserlohn (hist.)",                  bundesland: .NW),
        .init(code: "K",   name: "Köln",                              bundesland: .NW),
        .init(code: "KE",  name: "Kempen (hist.)",                    bundesland: .NW),
        .init(code: "KLE", name: "Kleve",                             bundesland: .NW),
        .init(code: "KR",  name: "Krefeld",                           bundesland: .NW),
        .init(code: "KÜN", name: "Küng (hist.)",                      bundesland: .NW),
        .init(code: "LEM", name: "Lemgo (hist.)",                     bundesland: .NW),
        .init(code: "LEV", name: "Leverkusen",                        bundesland: .NW),
        .init(code: "LIP", name: "Lippe",                             bundesland: .NW),
        .init(code: "LN",  name: "Lennep (hist.)",                    bundesland: .NW),
        .init(code: "ME",  name: "Mettmann",                          bundesland: .NW),
        .init(code: "MES", name: "Meschede (hist.)",                  bundesland: .NW),
        .init(code: "MG",  name: "Mönchengladbach",                   bundesland: .NW),
        .init(code: "MH",  name: "Mülheim an der Ruhr",               bundesland: .NW),
        .init(code: "MI",  name: "Minden-Lübbecke",                   bundesland: .NW),
        .init(code: "MK",  name: "Märkisches Sauerland (MK)",         bundesland: .NW),
        .init(code: "MS",  name: "Münster",                           bundesland: .NW),
        .init(code: "MÜ",  name: "Mülheim (hist.)",                   bundesland: .NW),
        .init(code: "MYK", name: "Mayen-Koblenz (hist.)",             bundesland: .NW),
        .init(code: "NE",  name: "Rhein-Kreis Neuss",                 bundesland: .NW),
        .init(code: "NI",  name: "Nienburg (hist.)",                  bundesland: .NW),
        .init(code: "NOM", name: "Northeim (hist.)",                  bundesland: .NW),
        .init(code: "OB",  name: "Oberhausen",                        bundesland: .NW),
        .init(code: "OE",  name: "Olpe",                              bundesland: .NW),
        .init(code: "OHA", name: "Osterode am Harz (hist.)",          bundesland: .NW),
        .init(code: "PB",  name: "Paderborn",                         bundesland: .NW),
        .init(code: "POR", name: "Peine-Osterode (hist.)",            bundesland: .NW),
        .init(code: "RE",  name: "Recklinghausen",                    bundesland: .NW),
        .init(code: "REI", name: "Remscheid (hist.)",                 bundesland: .NW),
        .init(code: "RS",  name: "Remscheid",                         bundesland: .NW),
        .init(code: "SE",  name: "Segeberg (hist.)",                  bundesland: .NW),
        .init(code: "SG",  name: "Solingen",                          bundesland: .NW),
        .init(code: "SI",  name: "Siegen-Wittgenstein",               bundesland: .NW),
        .init(code: "SO",  name: "Soest",                             bundesland: .NW),
        .init(code: "ST",  name: "Steinfurt",                         bundesland: .NW),
        .init(code: "STE", name: "Steinfurt (hist.)",                 bundesland: .NW),
        .init(code: "VIE", name: "Viersen",                           bundesland: .NW),
        .init(code: "VK",  name: "Völklingen (hist.)",                bundesland: .NW),
        .init(code: "WA",  name: "Warburg (hist.)",                   bundesland: .NW),
        .init(code: "WAF", name: "Warendorf",                         bundesland: .NW),
        .init(code: "WAT", name: "Wattenscheid (hist.)",              bundesland: .NW),
        .init(code: "WES", name: "Wesel",                             bundesland: .NW),
        .init(code: "WIT", name: "Witten (hist.)",                    bundesland: .NW),
        .init(code: "WL",  name: "Harburg (hist.)",                   bundesland: .NW),
        .init(code: "WND", name: "Sankt Wendel (hist.)",              bundesland: .NW),
        .init(code: "WOR", name: "Worms (hist.)",                     bundesland: .NW),
        .init(code: "W",   name: "Wuppertal",                         bundesland: .NW),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Rheinland-Pfalz
    // ─────────────────────────────────────────────────────────────────────────
    private static let rp: [GermanKennzeichen] = [
        .init(code: "AK",  name: "Altenkirchen (Westerwald)",         bundesland: .RP),
        .init(code: "ALF", name: "Altenahr / Ahrweiler (hist.)",      bundesland: .RP),
        .init(code: "AW",  name: "Ahrweiler",                         bundesland: .RP),
        .init(code: "AZ",  name: "Alzey-Worms",                       bundesland: .RP),
        .init(code: "BAD", name: "Bad Dürkheim (hist.)",              bundesland: .RP),
        .init(code: "BIR", name: "Birkenfeld",                        bundesland: .RP),
        .init(code: "BIT", name: "Bitburg-Prüm / Eifelkreis",         bundesland: .RP),
        .init(code: "BKS", name: "Bad Kreuznach (hist.)",             bundesland: .RP),
        .init(code: "COC", name: "Cochem-Zell",                       bundesland: .RP),
        .init(code: "DAW", name: "Daun (hist.)",                      bundesland: .RP),
        .init(code: "DUW", name: "Bad Dürkheim",                      bundesland: .RP),
        .init(code: "EMS", name: "Rhein-Lahn-Kreis (Bad Ems)",        bundesland: .RP),
        .init(code: "EW",  name: "Eifel (hist.)",                     bundesland: .RP),
        .init(code: "FK",  name: "Frankenthal (Pfalz)",               bundesland: .RP),
        .init(code: "GEN", name: "Gensungen (hist.)",                 bundesland: .RP),
        .init(code: "GL",  name: "Germersheim (hist.)",               bundesland: .RP),
        .init(code: "GER", name: "Germersheim",                       bundesland: .RP),
        .init(code: "GRZ", name: "Grünstadt (hist.)",                 bundesland: .RP),
        .init(code: "GW",  name: "Grünstadt (hist.)",                 bundesland: .RP),
        .init(code: "HK",  name: "Bad Kreuznach",                     bundesland: .RP),
        .init(code: "KH",  name: "Bad Kreuznach",                     bundesland: .RP),
        .init(code: "KIB", name: "Donnersbergkreis",                  bundesland: .RP),
        .init(code: "KL",  name: "Kaiserslautern",                    bundesland: .RP),
        .init(code: "KO",  name: "Koblenz",                           bundesland: .RP),
        .init(code: "KUS", name: "Kusel",                             bundesland: .RP),
        .init(code: "LA",  name: "Landau in der Pfalz (hist.)",       bundesland: .RP),
        .init(code: "LD",  name: "Landau in der Pfalz",               bundesland: .RP),
        .init(code: "LU",  name: "Ludwigshafen am Rhein",             bundesland: .RP),
        .init(code: "MAI", name: "Mayen-Koblenz (Mayen)",             bundesland: .RP),
        .init(code: "MO",  name: "Montabaur (hist.)",                 bundesland: .RP),
        .init(code: "MON", name: "Montabaur (hist.)",                 bundesland: .RP),
        .init(code: "MYK", name: "Mayen-Koblenz",                     bundesland: .RP),
        .init(code: "MZG", name: "Merzig (SL)",                       bundesland: .SL),
        .init(code: "NA",  name: "Nahe (hist.)",                      bundesland: .RP),
        .init(code: "NEW", name: "Neustadt a.d.Weinstr.",             bundesland: .RP),
        .init(code: "NW",  name: "Neustadt a.d.Weinstr. (hist.)",     bundesland: .RP),
        .init(code: "OL",  name: "Ostholstein (hist.)",               bundesland: .RP),
        .init(code: "PL",  name: "Pirmasens (Landkreis)",             bundesland: .RP),
        .init(code: "PIR", name: "Pirmasens",                         bundesland: .RP),
        .init(code: "PS",  name: "Pirmasens (Stadt)",                 bundesland: .RP),
        .init(code: "RP",  name: "Rheinland-Pfalz (hist.)",           bundesland: .RP),
        .init(code: "SD",  name: "Speyer-Neustadt (hist.)",           bundesland: .RP),
        .init(code: "SIM", name: "Rhein-Hunsrück-Kreis",              bundesland: .RP),
        .init(code: "SIK", name: "Siegen (hist.)",                    bundesland: .RP),
        .init(code: "SP",  name: "Speyer",                            bundesland: .RP),
        .init(code: "TRI", name: "Trier",                             bundesland: .RP),
        .init(code: "TS",  name: "Trier-Saarburg",                    bundesland: .RP),
        .init(code: "TSE", name: "Trier-Saarburg (hist.)",            bundesland: .RP),
        .init(code: "VG",  name: "Vorpommern-Greifswald (hist.)",     bundesland: .RP),
        .init(code: "VR",  name: "Vulkaneifel",                       bundesland: .RP),
        .init(code: "WIL", name: "Bernkastel-Wittlich",               bundesland: .RP),
        .init(code: "WOR", name: "Worms",                             bundesland: .RP),
        .init(code: "WOR", name: "Worms",                             bundesland: .RP),
        .init(code: "WOS", name: "Wolfstein (hist.)",                 bundesland: .RP),
        .init(code: "WND", name: "Bad Kreuznach (hist.)",             bundesland: .RP),
        .init(code: "ZE",  name: "Zell (Mosel) (hist.)",              bundesland: .RP),
        .init(code: "ZW",  name: "Zweibrücken",                       bundesland: .RP),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Saarland
    // ─────────────────────────────────────────────────────────────────────────
    private static let sl: [GermanKennzeichen] = [
        .init(code: "HOM", name: "Homburg",                           bundesland: .SL),
        .init(code: "IGB", name: "Sankt Ingbert (hist.)",             bundesland: .SL),
        .init(code: "MK",  name: "Merzig-Wadern (hist.)",             bundesland: .SL),
        .init(code: "MZG", name: "Merzig-Wadern",                     bundesland: .SL),
        .init(code: "NK",  name: "Neunkirchen",                       bundesland: .SL),
        .init(code: "NKS", name: "Neunkirchen (hist.)",               bundesland: .SL),
        .init(code: "RP",  name: "Rheinland-Pfalz (hist.)",           bundesland: .SL),
        .init(code: "SAR", name: "Saarlouis (hist.)",                 bundesland: .SL),
        .init(code: "SB",  name: "Saarbrücken",                       bundesland: .SL),
        .init(code: "SDK", name: "Saarbrücken (hist.)",               bundesland: .SL),
        .init(code: "SLS", name: "Saarlouis",                         bundesland: .SL),
        .init(code: "SPK", name: "Neunkirchen/St.Wendel (hist.)",     bundesland: .SL),
        .init(code: "SWL", name: "St. Wendel (hist.)",                bundesland: .SL),
        .init(code: "VK",  name: "Völklingen",                        bundesland: .SL),
        .init(code: "WND", name: "Sankt Wendel",                      bundesland: .SL),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Sachsen
    // ─────────────────────────────────────────────────────────────────────────
    private static let sn: [GermanKennzeichen] = [
        .init(code: "ASL", name: "Aschersleben (hist.)",              bundesland: .SN),
        .init(code: "BIW", name: "Bischofswerda (hist.)",             bundesland: .SN),
        .init(code: "BLK", name: "Burgenlandkreis",                   bundesland: .ST),
        .init(code: "BZ",  name: "Bautzen",                           bundesland: .SN),
        .init(code: "C",   name: "Chemnitz",                          bundesland: .SN),
        .init(code: "DD",  name: "Dresden",                           bundesland: .SN),
        .init(code: "DEL", name: "Delitzsch (hist.)",                 bundesland: .SN),
        .init(code: "DL",  name: "Döbeln",                            bundesland: .SN),
        .init(code: "ERZ", name: "Erzgebirgskreis",                   bundesland: .SN),
        .init(code: "FG",  name: "Mittelsachsen (Freiberg)",          bundesland: .SN),
        .init(code: "GR",  name: "Görlitz",                           bundesland: .SN),
        .init(code: "GZ",  name: "Grimma (hist.)",                    bundesland: .SN),
        .init(code: "HY",  name: "Hoyerswerda (hist.)",               bundesland: .SN),
        .init(code: "L",   name: "Leipzig",                           bundesland: .SN),
        .init(code: "LC",  name: "Chemnitz (hist.)",                  bundesland: .SN),
        .init(code: "LEI", name: "Leipzig (hist.)",                   bundesland: .SN),
        .init(code: "LK",  name: "Lkr. Leipzig (hist.)",              bundesland: .SN),
        .init(code: "MEI", name: "Meißen",                            bundesland: .SN),
        .init(code: "MGN", name: "Schmalkalden-Meiningen (hist.)",    bundesland: .SN),
        .init(code: "MS",  name: "Mittelsachsen (hist.)",             bundesland: .SN),
        .init(code: "MW",  name: "Mittweida (hist.)",                 bundesland: .SN),
        .init(code: "NOL", name: "Niederschlesischer Oberlausitzkreis (hist.)", bundesland: .SN),
        .init(code: "NS",  name: "Niesky (hist.)",                    bundesland: .SN),
        .init(code: "PL",  name: "Plauen (hist.)",                    bundesland: .SN),
        .init(code: "RC",  name: "Reichenbach (hist.)",               bundesland: .SN),
        .init(code: "RIE", name: "Riesa (hist.)",                     bundesland: .SN),
        .init(code: "RK",  name: "Rochlitz (hist.)",                  bundesland: .SN),
        .init(code: "SLO", name: "Schleiz (hist.)",                   bundesland: .SN),
        .init(code: "STL", name: "Stollberg (hist.)",                 bundesland: .SN),
        .init(code: "TDO", name: "Torgau-Oschatz (hist.)",            bundesland: .SN),
        .init(code: "V",   name: "Vogtlandkreis",                     bundesland: .SN),
        .init(code: "WEI", name: "Weißwasser (hist.)",                bundesland: .SN),
        .init(code: "WIL", name: "Wilkau-Haßlau (hist.)",             bundesland: .SN),
        .init(code: "WIT", name: "Wittenberg (hist.)",                bundesland: .SN),
        .init(code: "WSW", name: "Weißwasser (hist.)",                bundesland: .SN),
        .init(code: "Z",   name: "Zwickau",                           bundesland: .SN),
        .init(code: "ZE",  name: "Zerbst (hist.)",                    bundesland: .SN),
        .init(code: "ZW",  name: "Zwickauer Land (hist.)",            bundesland: .SN),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Sachsen-Anhalt
    // ─────────────────────────────────────────────────────────────────────────
    private static let st: [GermanKennzeichen] = [
        .init(code: "ABI", name: "Anhalt-Bitterfeld",                 bundesland: .ST),
        .init(code: "ASD", name: "Aschersleben-Staßfurt (hist.)",     bundesland: .ST),
        .init(code: "ASL", name: "Aschersleben (hist.)",              bundesland: .ST),
        .init(code: "BK",  name: "Bernburg (hist.)",                  bundesland: .ST),
        .init(code: "BLK", name: "Burgenlandkreis",                   bundesland: .ST),
        .init(code: "BMS", name: "Bitterfeld-Mulde (hist.)",          bundesland: .ST),
        .init(code: "BOR", name: "Borken (hist.)",                    bundesland: .ST),
        .init(code: "BTF", name: "Bitterfeld (hist.)",                bundesland: .ST),
        .init(code: "DE",  name: "Dessau-Roßlau",                     bundesland: .ST),
        .init(code: "EIL", name: "Eilenburg (hist.)",                 bundesland: .ST),
        .init(code: "GK",  name: "Gräfenhainichen (hist.)",           bundesland: .ST),
        .init(code: "GRK", name: "Quedlinburg (hist.)",               bundesland: .ST),
        .init(code: "HAL", name: "Halle an der Saale",                bundesland: .ST),
        .init(code: "HDL", name: "Halberstadt (hist.)",               bundesland: .ST),
        .init(code: "JL",  name: "Jerichower Land",                   bundesland: .ST),
        .init(code: "KEL", name: "Kehl (hist.)",                      bundesland: .ST),
        .init(code: "KBK", name: "Köthen (hist.)",                    bundesland: .ST),
        .init(code: "KET", name: "Köthen (hist.)",                    bundesland: .ST),
        .init(code: "MAK", name: "Magdeburg (hist.)",                 bundesland: .ST),
        .init(code: "MD",  name: "Magdeburg",                         bundesland: .ST),
        .init(code: "MER", name: "Merseburg",                         bundesland: .ST),
        .init(code: "MGN", name: "Meiningen (hist.)",                 bundesland: .ST),
        .init(code: "ML",  name: "Mansfelder Land (hist.)",           bundesland: .ST),
        .init(code: "MSH", name: "Mansfeld-Südharz",                  bundesland: .ST),
        .init(code: "NAU", name: "Nauen (hist.)",                     bundesland: .ST),
        .init(code: "OK",  name: "Ohrekreis (hist.)",                 bundesland: .ST),
        .init(code: "OHZ", name: "Osterholz (hist.)",                 bundesland: .ST),
        .init(code: "PEG", name: "Pegnitz (hist.)",                   bundesland: .ST),
        .init(code: "PL",  name: "Potsdam (hist.)",                   bundesland: .ST),
        .init(code: "QB",  name: "Quedlinburg",                       bundesland: .ST),
        .init(code: "QFT", name: "Quedlinburg (hist.)",               bundesland: .ST),
        .init(code: "QLB", name: "Quedlinburg (hist.)",               bundesland: .ST),
        .init(code: "SAL", name: "Saale (hist.)",                     bundesland: .ST),
        .init(code: "SAW", name: "Altmarkkreis Salzwedel",            bundesland: .ST),
        .init(code: "SBK", name: "Schönebeck (hist.)",                bundesland: .ST),
        .init(code: "SDL", name: "Stendal",                           bundesland: .ST),
        .init(code: "SK",  name: "Saalkreis (hist.)",                 bundesland: .ST),
        .init(code: "SLK", name: "Salzlandkreis",                     bundesland: .ST),
        .init(code: "SMS", name: "Schmalkalden (hist.)",              bundesland: .ST),
        .init(code: "WOR", name: "Worms (hist.)",                     bundesland: .ST),
        .init(code: "WOS", name: "Wolmirstedt (hist.)",               bundesland: .ST),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Schleswig-Holstein
    // ─────────────────────────────────────────────────────────────────────────
    private static let sh: [GermanKennzeichen] = [
        .init(code: "BOR", name: "Borken (hist. SH)",                 bundesland: .SH),
        .init(code: "ECA", name: "Eckernförde (hist.)",               bundesland: .SH),
        .init(code: "ECKA",name: "Eckernförde (hist.)",               bundesland: .SH),
        .init(code: "FL",  name: "Flensburg",                         bundesland: .SH),
        .init(code: "HEI", name: "Dithmarschen (Heide)",              bundesland: .SH),
        .init(code: "HL",  name: "Lübeck",                            bundesland: .SH),
        .init(code: "HOR", name: "Horst (hist.)",                     bundesland: .SH),
        .init(code: "HST", name: "Stralsund (hist.)",                 bundesland: .SH),
        .init(code: "IZ",  name: "Steinburg",                         bundesland: .SH),
        .init(code: "KI",  name: "Kiel",                              bundesland: .SH),
        .init(code: "LG",  name: "Lauenburg / Lüneburg (hist.)",      bundesland: .SH),
        .init(code: "NF",  name: "Nordfriesland",                     bundesland: .SH),
        .init(code: "NOD", name: "Nordfriesland (hist.)",             bundesland: .SH),
        .init(code: "OD",  name: "Stormarn",                          bundesland: .SH),
        .init(code: "OH",  name: "Ostholstein",                       bundesland: .SH),
        .init(code: "PI",  name: "Pinneberg",                         bundesland: .SH),
        .init(code: "PLÖ", name: "Plön",                              bundesland: .SH),
        .init(code: "PLO", name: "Plön (alt.)",                       bundesland: .SH),
        .init(code: "RD",  name: "Rendsburg-Eckernförde",             bundesland: .SH),
        .init(code: "RDS", name: "Rendsburg-Eckernförde (hist.)",     bundesland: .SH),
        .init(code: "SDS", name: "Schleswig (hist.)",                 bundesland: .SH),
        .init(code: "SE",  name: "Segeberg",                          bundesland: .SH),
        .init(code: "SL",  name: "Schleswig-Flensburg",               bundesland: .SH),
        .init(code: "SLE", name: "Schleswig (hist.)",                 bundesland: .SH),
        .init(code: "STD", name: "Stade (hist.)",                     bundesland: .SH),
        .init(code: "STL", name: "Steinburg (hist.)",                 bundesland: .SH),
        .init(code: "VO",  name: "Vorpommern (hist. SH)",             bundesland: .SH),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Thüringen
    // ─────────────────────────────────────────────────────────────────────────
    private static let th: [GermanKennzeichen] = [
        .init(code: "ABG", name: "Altenburger Land",                  bundesland: .TH),
        .init(code: "AP",  name: "Weimarer Land (Apolda)",            bundesland: .TH),
        .init(code: "APC", name: "Weimarer Land (hist.)",             bundesland: .TH),
        .init(code: "APD", name: "Arnstadt (hist.)",                  bundesland: .TH),
        .init(code: "ARN", name: "Ilm-Kreis (Arnstadt)",              bundesland: .TH),
        .init(code: "BAD", name: "Schmalkalden-Meiningen (hist.)",    bundesland: .TH),
        .init(code: "BAL", name: "Bad Langensalza (hist.)",           bundesland: .TH),
        .init(code: "BLN", name: "Saalfeld-Rudolstadt (hist.)",       bundesland: .TH),
        .init(code: "EF",  name: "Erfurt",                            bundesland: .TH),
        .init(code: "EIC", name: "Eichsfeld",                         bundesland: .TH),
        .init(code: "EIS", name: "Eisenach",                          bundesland: .TH),
        .init(code: "GAB", name: "Grabfeld (hist.)",                  bundesland: .TH),
        .init(code: "GEI", name: "Gera (hist.)",                      bundesland: .TH),
        .init(code: "GHA", name: "Greiz (hist.)",                     bundesland: .TH),
        .init(code: "GK",  name: "Gotha (hist.)",                     bundesland: .TH),
        .init(code: "GRZ", name: "Greiz",                             bundesland: .TH),
        .init(code: "GT",  name: "Gotha",                             bundesland: .TH),
        .init(code: "GTH", name: "Gotha (hist.)",                     bundesland: .TH),
        .init(code: "GYA", name: "Gera (hist.)",                      bundesland: .TH),
        .init(code: "G",   name: "Gera",                              bundesland: .TH),
        .init(code: "HBN", name: "Hildburghausen",                    bundesland: .TH),
        .init(code: "HEL", name: "Helbe (hist.)",                     bundesland: .TH),
        .init(code: "HIK", name: "Hildburghausen (hist.)",            bundesland: .TH),
        .init(code: "HI",  name: "Hildesheim",                        bundesland: .NI),
        .init(code: "HOR", name: "Hörselbergkreis (hist.)",           bundesland: .TH),
        .init(code: "HTW", name: "Jena (hist.)",                      bundesland: .TH),
        .init(code: "IK",  name: "Ilm-Kreis",                         bundesland: .TH),
        .init(code: "J",   name: "Jena",                              bundesland: .TH),
        .init(code: "JE",  name: "Jena (hist.)",                      bundesland: .TH),
        .init(code: "KFB", name: "Kreisfreie Stadt Jena (hist.)",     bundesland: .TH),
        .init(code: "KYF", name: "Kyffhäuserkreis",                   bundesland: .TH),
        .init(code: "LEI", name: "Leipzig (hist.)",                   bundesland: .TH),
        .init(code: "LOS", name: "Losa (hist.)",                      bundesland: .TH),
        .init(code: "MGN", name: "Schmalkalden-Meiningen",            bundesland: .TH),
        .init(code: "MHL", name: "Mühlhausen",                        bundesland: .TH),
        .init(code: "NDH", name: "Nordhausen",                        bundesland: .TH),
        .init(code: "NK",  name: "Nordhausen (hist.)",                bundesland: .TH),
        .init(code: "NOL", name: "Nordhausen (hist.)",                bundesland: .TH),
        .init(code: "OAL", name: "Ostallgäu (hist.)",                 bundesland: .TH),
        .init(code: "PAF", name: "Pfaffenhofen (hist. TH)",           bundesland: .TH),
        .init(code: "POS", name: "Pössneck (hist.)",                  bundesland: .TH),
        .init(code: "ROK", name: "Saalfeld-Rudolstadt (hist.)",       bundesland: .TH),
        .init(code: "RSN", name: "Rosenberg (hist.)",                 bundesland: .TH),
        .init(code: "RTW", name: "Roth (hist.)",                      bundesland: .TH),
        .init(code: "SAL", name: "Saale-Holzland-Kreis",              bundesland: .TH),
        .init(code: "SHL", name: "Schmalkalden (Stadt) (hist.)",      bundesland: .TH),
        .init(code: "SHK", name: "Saale-Holzland-Kreis (hist.)",      bundesland: .TH),
        .init(code: "SLF", name: "Saalfeld-Rudolstadt",               bundesland: .TH),
        .init(code: "SM",  name: "Schmalkalden-Meiningen (hist.)",    bundesland: .TH),
        .init(code: "SMS", name: "Schmalkalden (hist.)",              bundesland: .TH),
        .init(code: "SON", name: "Sonneberg",                         bundesland: .TH),
        .init(code: "SOK", name: "Saale-Orla-Kreis",                  bundesland: .TH),
        .init(code: "SPK", name: "Sömmerda (hist.)",                  bundesland: .TH),
        .init(code: "SRB", name: "Sonneberg (hist.)",                 bundesland: .TH),
        .init(code: "SRH", name: "Saale-Orla (hist.)",               bundesland: .TH),
        .init(code: "SRN", name: "Saalfeld (hist.)",                  bundesland: .TH),
        .init(code: "SRS", name: "Saalfeld-Rudolstadt (hist.)",       bundesland: .TH),
        .init(code: "STK", name: "Stadtilm (hist.)",                  bundesland: .TH),
        .init(code: "SÖM", name: "Sömmerda",                          bundesland: .TH),
        .init(code: "TDK", name: "Torgau-Delitzsch (hist.)",          bundesland: .TH),
        .init(code: "UH",  name: "Unstrut-Hainich-Kreis",             bundesland: .TH),
        .init(code: "W",   name: "Weimar",                            bundesland: .TH),
        .init(code: "WAK", name: "Wartburgkreis",                     bundesland: .TH),
        .init(code: "WE",  name: "Weimar (hist.)",                    bundesland: .TH),
        .init(code: "WEI", name: "Weimarer Land",                     bundesland: .TH),
        .init(code: "WSW", name: "Weißensee (hist.)",                 bundesland: .TH),
    ]

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Additional important single-letter and missing codes
    // ─────────────────────────────────────────────────────────────────────────
    private static let extra: [GermanKennzeichen] = [
        // Single-letter codes (Großstädte)
        .init(code: "F",   name: "Frankfurt am Main",                 bundesland: .HE),
        .init(code: "H",   name: "Hannover (Region)",                 bundesland: .NI),
        // Hessen codes not covered above
        .init(code: "GI",  name: "Gießen",                            bundesland: .HE),
        .init(code: "GR",  name: "Groß-Gerau",                        bundesland: .HE),
        .init(code: "LDK", name: "Lahn-Dill-Kreis",                   bundesland: .HE),
        .init(code: "LM",  name: "Limburg-Weilburg",                  bundesland: .HE),
        .init(code: "MKK", name: "Main-Kinzig-Kreis",                 bundesland: .HE),
        .init(code: "MTK", name: "Main-Taunus-Kreis",                 bundesland: .HE),
        .init(code: "ODW", name: "Odenwaldkreis",                     bundesland: .HE),
        .init(code: "RTK", name: "Rheingau-Taunus-Kreis",             bundesland: .HE),
        .init(code: "VB",  name: "Vogelsbergkreis",                   bundesland: .HE),
        // NW codes not covered above
        .init(code: "GT",  name: "Gütersloh",                         bundesland: .NW),
        .init(code: "EU",  name: "Euskirchen",                        bundesland: .NW),
        .init(code: "GM",  name: "Oberbergischer Kreis (Gummersbach)", bundesland: .NW),
        .init(code: "HF",  name: "Herford",                           bundesland: .NW),
        .init(code: "ME",  name: "Mettmann",                          bundesland: .NW),
        .init(code: "NE",  name: "Rhein-Kreis Neuss",                 bundesland: .NW),
        .init(code: "OE",  name: "Olpe",                              bundesland: .NW),
        .init(code: "PB",  name: "Paderborn",                         bundesland: .NW),
        .init(code: "RE",  name: "Recklinghausen",                    bundesland: .NW),
        .init(code: "RS",  name: "Remscheid",                         bundesland: .NW),
        .init(code: "SG",  name: "Solingen",                          bundesland: .NW),
        .init(code: "SI",  name: "Siegen-Wittgenstein",               bundesland: .NW),
        .init(code: "SO",  name: "Soest",                             bundesland: .NW),
        .init(code: "VIE", name: "Viersen",                           bundesland: .NW),
        .init(code: "WAF", name: "Warendorf",                         bundesland: .NW),
        .init(code: "WES", name: "Wesel",                             bundesland: .NW),
        // NI codes not covered
        .init(code: "CLP", name: "Cloppenburg",                       bundesland: .NI),
        .init(code: "CUX", name: "Cuxhaven",                          bundesland: .NI),
        .init(code: "EMD", name: "Emden",                             bundesland: .NI),
        .init(code: "FRI", name: "Friesland",                         bundesland: .NI),
        .init(code: "GF",  name: "Gifhorn",                           bundesland: .NI),
        .init(code: "GOS", name: "Goslar",                            bundesland: .NI),
        .init(code: "HAM", name: "Hameln-Pyrmont",                    bundesland: .NI),
        .init(code: "HI",  name: "Hildesheim",                        bundesland: .NI),
        .init(code: "LER", name: "Leer",                              bundesland: .NI),
        .init(code: "LG",  name: "Lüneburg",                          bundesland: .NI),
        .init(code: "NOH", name: "Grafschaft Bentheim",               bundesland: .NI),
        .init(code: "NOM", name: "Northeim",                          bundesland: .NI),
        .init(code: "OHZ", name: "Osterholz",                         bundesland: .NI),
        .init(code: "OL",  name: "Oldenburg",                         bundesland: .NI),
        .init(code: "OS",  name: "Osnabrück",                         bundesland: .NI),
        .init(code: "PE",  name: "Peine",                             bundesland: .NI),
        .init(code: "ROW", name: "Rotenburg (Wümme)",                 bundesland: .NI),
        .init(code: "SFA", name: "Heidekreis / Soltau-Fallingbostel", bundesland: .NI),
        .init(code: "SHG", name: "Schaumburg",                        bundesland: .NI),
        .init(code: "UE",  name: "Uelzen",                            bundesland: .NI),
        .init(code: "VEC", name: "Vechta",                            bundesland: .NI),
        .init(code: "VER", name: "Verden",                            bundesland: .NI),
        .init(code: "WF",  name: "Wolfenbüttel",                      bundesland: .NI),
        .init(code: "WL",  name: "Harburg (Landkreis)",               bundesland: .NI),
        .init(code: "WST", name: "Ammerland (Westerstede)",           bundesland: .NI),
        // MV codes
        .init(code: "MSE", name: "Mecklenburgische Seenplatte",        bundesland: .MV),
        .init(code: "LUP", name: "Ludwigslust-Parchim",               bundesland: .MV),
        .init(code: "OVP", name: "Vorpommern-Greifswald",             bundesland: .MV),
        .init(code: "RÜG", name: "Rügen",                             bundesland: .MV),
        .init(code: "VR",  name: "Vorpommern-Rügen",                  bundesland: .MV),
        // BB codes
        .init(code: "BAR", name: "Barnim",                            bundesland: .BB),
        .init(code: "BRB", name: "Brandenburg an der Havel",          bundesland: .BB),
        .init(code: "CB",  name: "Cottbus",                           bundesland: .BB),
        .init(code: "EE",  name: "Elbe-Elster",                       bundesland: .BB),
        .init(code: "FF",  name: "Frankfurt (Oder)",                   bundesland: .BB),
        .init(code: "HVL", name: "Havelland",                         bundesland: .BB),
        .init(code: "LDS", name: "Dahme-Spreewald",                   bundesland: .BB),
        .init(code: "LOS", name: "Oder-Spree",                        bundesland: .BB),
        .init(code: "MOL", name: "Märkisch-Oderland",                 bundesland: .BB),
        .init(code: "OHV", name: "Oberhavel",                         bundesland: .BB),
        .init(code: "OPR", name: "Ostprignitz-Ruppin",                bundesland: .BB),
        .init(code: "OSL", name: "Oberspreewald-Lausitz",             bundesland: .BB),
        .init(code: "P",   name: "Potsdam",                           bundesland: .BB),
        .init(code: "PM",  name: "Potsdam-Mittelmark",                bundesland: .BB),
        .init(code: "PR",  name: "Prignitz",                          bundesland: .BB),
        .init(code: "SPN", name: "Spree-Neiße",                       bundesland: .BB),
        .init(code: "TF",  name: "Teltow-Fläming",                    bundesland: .BB),
        .init(code: "UM",  name: "Uckermark",                         bundesland: .BB),
        // SH codes
        .init(code: "FL",  name: "Flensburg",                         bundesland: .SH),
        .init(code: "HEI", name: "Dithmarschen (Heide)",              bundesland: .SH),
        .init(code: "HL",  name: "Lübeck",                            bundesland: .SH),
        .init(code: "IZ",  name: "Steinburg",                         bundesland: .SH),
        .init(code: "KI",  name: "Kiel",                              bundesland: .SH),
        .init(code: "NF",  name: "Nordfriesland",                     bundesland: .SH),
        .init(code: "OD",  name: "Stormarn",                          bundesland: .SH),
        .init(code: "OH",  name: "Ostholstein",                       bundesland: .SH),
        .init(code: "PI",  name: "Pinneberg",                         bundesland: .SH),
        .init(code: "PLÖ", name: "Plön",                              bundesland: .SH),
        .init(code: "RD",  name: "Rendsburg-Eckernförde",             bundesland: .SH),
        .init(code: "SE",  name: "Segeberg",                          bundesland: .SH),
        .init(code: "SL",  name: "Schleswig-Flensburg",               bundesland: .SH),
        // SL codes
        .init(code: "HOM", name: "Homburg",                           bundesland: .SL),
        .init(code: "MZG", name: "Merzig-Wadern",                     bundesland: .SL),
        .init(code: "NK",  name: "Neunkirchen",                       bundesland: .SL),
        .init(code: "SB",  name: "Saarbrücken",                       bundesland: .SL),
        .init(code: "SLS", name: "Saarlouis",                         bundesland: .SL),
        .init(code: "VK",  name: "Völklingen",                        bundesland: .SL),
        .init(code: "WND", name: "Sankt Wendel",                      bundesland: .SL),
        // ST codes
        .init(code: "ABI", name: "Anhalt-Bitterfeld",                 bundesland: .ST),
        .init(code: "BLK", name: "Burgenlandkreis",                   bundesland: .ST),
        .init(code: "DE",  name: "Dessau-Roßlau",                     bundesland: .ST),
        .init(code: "HAL", name: "Halle (Saale)",                     bundesland: .ST),
        .init(code: "JL",  name: "Jerichower Land",                   bundesland: .ST),
        .init(code: "MD",  name: "Magdeburg",                         bundesland: .ST),
        .init(code: "MER", name: "Merseburg",                         bundesland: .ST),
        .init(code: "MSH", name: "Mansfeld-Südharz",                  bundesland: .ST),
        .init(code: "QB",  name: "Quedlinburg",                       bundesland: .ST),
        .init(code: "SAW", name: "Altmarkkreis Salzwedel",            bundesland: .ST),
        .init(code: "SDL", name: "Stendal",                           bundesland: .ST),
        .init(code: "SK",  name: "Saalekreis",                        bundesland: .ST),
        .init(code: "SLK", name: "Salzlandkreis",                     bundesland: .ST),
        .init(code: "WB",  name: "Wittenberg",                        bundesland: .ST),
        // TH codes
        .init(code: "ABG", name: "Altenburger Land",                  bundesland: .TH),
        .init(code: "AP",  name: "Weimarer Land (Apolda)",            bundesland: .TH),
        .init(code: "ARN", name: "Ilm-Kreis (Arnstadt)",              bundesland: .TH),
        .init(code: "EF",  name: "Erfurt",                            bundesland: .TH),
        .init(code: "EIC", name: "Eichsfeld",                         bundesland: .TH),
        .init(code: "EIS", name: "Eisenach",                          bundesland: .TH),
        .init(code: "G",   name: "Gera",                              bundesland: .TH),
        .init(code: "GRZ", name: "Greiz",                             bundesland: .TH),
        .init(code: "GTH", name: "Gotha",                             bundesland: .TH),
        .init(code: "HBN", name: "Hildburghausen",                    bundesland: .TH),
        .init(code: "IK",  name: "Ilm-Kreis",                         bundesland: .TH),
        .init(code: "J",   name: "Jena",                              bundesland: .TH),
        .init(code: "KYF", name: "Kyffhäuserkreis",                   bundesland: .TH),
        .init(code: "MGN", name: "Schmalkalden-Meiningen",            bundesland: .TH),
        .init(code: "MHL", name: "Mühlhausen",                        bundesland: .TH),
        .init(code: "NDH", name: "Nordhausen",                        bundesland: .TH),
        .init(code: "SAL", name: "Saale-Holzland-Kreis",              bundesland: .TH),
        .init(code: "SHK", name: "Saale-Holzland-Kreis",              bundesland: .TH),
        .init(code: "SLF", name: "Saalfeld-Rudolstadt",               bundesland: .TH),
        .init(code: "SON", name: "Sonneberg",                         bundesland: .TH),
        .init(code: "SOK", name: "Saale-Orla-Kreis",                  bundesland: .TH),
        .init(code: "SÖM", name: "Sömmerda",                          bundesland: .TH),
        .init(code: "UH",  name: "Unstrut-Hainich-Kreis",             bundesland: .TH),
        .init(code: "WAK", name: "Wartburgkreis",                     bundesland: .TH),
        .init(code: "WEI", name: "Weimarer Land",                     bundesland: .TH),
    ]
}
