//
//  LoginFranchiseLoader.swift
//  AracHasarKayit
//
//  Loads franchise choices for the login screen via Cloud Function (pre-auth).
//

import Foundation
import FirebaseFunctions

struct LoginFranchiseOption: Identifiable, Hashable {
    var id: String { documentId }
    /// Firestore document ID (e.g. CH, TR_SABIHAGOKCEN)
    let documentId: String
    /// Same as users.franchiseId (e.g. CH, TR_SABIHAGOKCEN)
    let franchiseId: String
    let displayName: String
    let flag: String
    let currencyCode: String?
}

/// Ensures login franchise picker cannot show or accept a branch from another country.
enum LoginFranchiseCountryGuard {
    static func normalizedCountryCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func normalizedFranchiseId(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// True when `franchiseId` / document `countryCode` belong to the selected login country.
    static func franchiseBelongsToCountry(
        franchiseId: String,
        documentCountryCode: String?,
        selectedCountryCode: String
    ) -> Bool {
        let country = normalizedCountryCode(selectedCountryCode)
        let fid = normalizedFranchiseId(franchiseId)
        guard !country.isEmpty, !fid.isEmpty else { return false }

        let docCountry = normalizedCountryCode(documentCountryCode ?? "")
        if !docCountry.isEmpty, docCountry != country {
            return false
        }

        switch country {
        case "TR":
            return fid == "TR" || fid.hasPrefix("TR_")
        case "CH":
            return fid == "CH" || fid.hasPrefix("CH_")
        case "DE":
            return fid == "DE" || fid.hasPrefix("DE_")
        case "UK":
            return fid == "UK" || fid.hasPrefix("UK_")
        default:
            if fid == country { return true }
            return fid.hasPrefix("\(country)_")
        }
    }

    static func filterOptions(
        _ options: [LoginFranchiseOption],
        countryCode: String
    ) -> [LoginFranchiseOption] {
        options.filter {
            franchiseBelongsToCountry(
                franchiseId: $0.franchiseId,
                documentCountryCode: nil,
                selectedCountryCode: countryCode
            )
        }
    }

    /// Picks the first valid selection for this country (never reuses another country's branch).
    static func resolveInitialSelection(
        options: [LoginFranchiseOption],
        countryCode: String,
        savedFranchiseId: String?
    ) -> String {
        let filtered = filterOptions(options, countryCode: countryCode)
        guard !filtered.isEmpty else { return "" }
        if let saved = savedFranchiseId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty,
           filtered.contains(where: { $0.franchiseId == normalizedFranchiseId(saved) }) {
            return normalizedFranchiseId(saved)
        }
        return filtered[0].franchiseId
    }
}

enum LoginFranchiseLoader {
    /// Must match Cloud Functions region (`setGlobalOptions` in `functions/index.js`).
    private static let functions = Functions.functions(region: "us-central1")

    /// Maps Firebase Callable errors (e.g. NOT FOUND before deploy) to a user-facing string.
    static func userFacingLoadError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FunctionsErrorDomain, ns.code == FunctionsErrorCode.notFound.rawValue {
            return NSLocalizedString("franchise_list_service_unavailable", comment: "")
        }
        let upper = ns.localizedDescription.uppercased()
        if upper.contains("NOT FOUND") {
            return NSLocalizedString("franchise_list_service_unavailable", comment: "")
        }
        return ns.localizedDescription
    }

    static func fetchOptions(countryCode: String, completion: @escaping (Result<[LoginFranchiseOption], Error>) -> Void) {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 2 else {
            completion(.success([]))
            return
        }

        let callable = functions.httpsCallable("listFranchisesForLogin")
        callable.call(["countryCode": code]) { result, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            guard let data = result?.data as? [String: Any],
                  let raw = data["franchises"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    completion(.success([]))
                }
                return
            }
            let options: [LoginFranchiseOption] = raw.compactMap { row in
                let docId = String(describing: row["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let fid = String(describing: row["franchiseId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let name = String(describing: row["name"] ?? docId).trimmingCharacters(in: .whitespacesAndNewlines)
                let flag = String(describing: row["flag"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let currencyCodeRaw = String(describing: row["currency"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rowCountry = String(describing: row["countryCode"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !docId.isEmpty, !fid.isEmpty else { return nil }
                let normalizedFid = fid.uppercased()
                guard LoginFranchiseCountryGuard.franchiseBelongsToCountry(
                    franchiseId: normalizedFid,
                    documentCountryCode: rowCountry.isEmpty ? nil : rowCountry,
                    selectedCountryCode: code
                ) else {
                    return nil
                }
                return LoginFranchiseOption(
                    documentId: docId,
                    franchiseId: normalizedFid,
                    displayName: name.isEmpty ? fid : name,
                    flag: flag,
                    currencyCode: currencyCodeRaw.isEmpty ? nil : currencyCodeRaw.uppercased()
                )
            }
            DispatchQueue.main.async {
                completion(.success(options))
            }
        }
    }
}
