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

enum LoginFranchiseLoader {
    private static let functions = Functions.functions()

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
                guard !docId.isEmpty, !fid.isEmpty else { return nil }
                return LoginFranchiseOption(
                    documentId: docId,
                    franchiseId: fid.uppercased(),
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
