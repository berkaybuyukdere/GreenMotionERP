import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseCore
import UIKit

enum WheelSysVehicleDamageServiceError: LocalizedError {
    case notAuthenticated
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in.".localized
        case .operationFailed(let msg):
            return WheelSysUserFacingError.message(forRaw: msg)
        }
    }
}

enum WheelSysVehicleDamageService {
    private static let functions = Functions.functions(region: "europe-west6")
    private static let previewRegion = "europe-west6"

    /// Probes backend session and marks `WheelSysCookieCache.serverSessionValid` when callables can run.
    static func ensureSessionReady(franchiseId: String) async {
        let fid = franchiseId.uppercased()
        if WheelSysCookieCache.serverSessionValid {
            WheelSysDebug.logCH(franchiseId: fid, "Damage", "session ready — server flag cached")
            return
        }
        if WheelSysCookieCache.isValid {
            _ = await syncClientCookieToServerIfNeeded(franchiseId: fid)
            if WheelSysCookieCache.serverSessionValid {
                WheelSysDebug.logCH(franchiseId: fid, "Damage", "session ready — client cookie synced to server")
                return
            }
        }
        do {
            let status = try await WheelSysCheckinService.sessionStatus(franchiseId: fid)
            let valid = status.hasSession && status.isValid
            WheelSysCookieCache.markServerSessionValid(valid)
            WheelSysDebug.logCH(
                franchiseId: fid,
                "Damage",
                "session probe hasSession=\(status.hasSession) isValid=\(status.isValid)"
            )
            if valid, WheelSysCookieCache.isValid {
                _ = await syncClientCookieToServerIfNeeded(franchiseId: fid)
            }
        } catch {
            WheelSysDebug.warnCH(
                franchiseId: fid,
                "Damage",
                "session probe failed: \(error.localizedDescription)"
            )
        }
    }

    /// When WKWebView login succeeded but Firestore session is cold, push client cookie to server.
    static func syncClientCookieToServerIfNeeded(franchiseId: String) async -> Bool {
        guard WheelSysCookieCache.isValid,
              let cookie = WheelSysCookieCache.lastCookie else {
            return false
        }
        let fid = franchiseId.uppercased()
        WheelSysDebug.logCH(franchiseId: fid, "Damage", "syncing client cookie to server session store")
        do {
            try await WheelSysCheckinService.saveSessionCookie(franchiseId: fid, sessionCookie: cookie)
            WheelSysCookieCache.markServerSessionValid(true)
            WheelSysDebug.logCH(franchiseId: fid, "Damage", "client cookie synced to server")
            return true
        } catch {
            WheelSysDebug.warnCH(
                franchiseId: fid,
                "Damage",
                "client cookie sync failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private static func isSessionRelatedError(_ raw: String) -> Bool {
        WheelSysSessionPromptCenter.isSessionMessage(
            WheelSysUserFacingError.message(forRaw: raw)
        )
    }

    /// True only when the failure is a genuine session error AND there is no
    /// usable session left. When a session is still usable the failure is
    /// treated as transient (callers should offer a retry instead of telling
    /// the user their session expired).
    static func isSessionExpiryUserVisible(_ error: Error) -> Bool {
        guard WheelSysSessionPromptCenter.isSessionError(error) else { return false }
        return !WheelSysCookieCache.hasUsableSession
    }

    /// Ensures fleet chart is loaded so `vehicleEntityId` can be resolved before GetDamages.
    @MainActor
    static func ensureFleetReady(for arac: Arac) async {
        let store = WheelSysVehicleFleetStatusStore.shared
        store.bootstrapFromDiskIfNeeded()
        if resolveVehicleEntityId(for: arac) != nil {
            await store.refreshIfNeeded()
            return
        }
        await store.refresh(force: true)
    }

    @MainActor
    static func resolveVehicleEntityId(for arac: Arac) -> String? {
        let fleetVehicle = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: arac)
            ?? WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: arac.plaka)
        if let stored = arac.wheelsysVehicleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }
        if let fleetId = fleetVehicle?.vehicleId.trimmingCharacters(in: .whitespacesAndNewlines),
           !fleetId.isEmpty {
            return fleetId
        }
        return nil
    }

    static func fetchDamageHistory(
        arac: Arac,
        franchiseId: String,
        station: String = "ZRH",
        rentalId: Int? = nil,
        allowSessionRecoveryRetry: Bool = true
    ) async throws -> WheelSysVehicleDamageHistoryResponse {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysVehicleDamageServiceError.notAuthenticated
        }

        let cid = WheelSysDebug.newCorrelationId()
        let fid = franchiseId.uppercased()
        WheelSysDebug.logCH(
            franchiseId: fid,
            "Damage",
            "fetch start plate=\(arac.plaka) station=\(station.uppercased()) " +
            "clientCookie=\(WheelSysCookieCache.isValid) serverSession=\(WheelSysCookieCache.serverSessionValid)",
            cid: cid
        )

        await ensureSessionReady(franchiseId: fid)

        do {
            let parsed = try await callDamageHistoryCallable(
                arac: arac,
                franchiseId: fid,
                station: station,
                rentalId: rentalId,
                cid: cid
            )
            WheelSysVehicleDamageDiskCache.save(parsed, franchiseId: fid, plate: arac.plaka)
            return parsed
        } catch let firstError {
            let raw = describeDamageError(firstError)
            guard allowSessionRecoveryRetry, isSessionRelatedError(raw) else {
                throw firstError
            }

            WheelSysDebug.warnCH(
                franchiseId: fid,
                "Damage",
                "session-related failure — attempting recovery raw=\(raw)",
                cid: cid
            )

            if WheelSysCookieCache.isValid {
                _ = await syncClientCookieToServerIfNeeded(franchiseId: fid)
            } else {
                await ensureSessionReady(franchiseId: fid)
            }

            guard WheelSysCookieCache.hasUsableSession else {
                WheelSysDebug.errorCH(
                    franchiseId: fid,
                    "Damage",
                    "recovery skipped — no usable session after probe",
                    cid: cid
                )
                throw firstError
            }

            do {
                let parsed = try await callDamageHistoryCallable(
                    arac: arac,
                    franchiseId: fid,
                    station: station,
                    rentalId: rentalId,
                    cid: cid
                )
                WheelSysVehicleDamageDiskCache.save(parsed, franchiseId: fid, plate: arac.plaka)
                WheelSysDebug.logCH(franchiseId: fid, "Damage", "fetch ok after session recovery", cid: cid)
                return parsed
            } catch {
                WheelSysDebug.errorCH(
                    franchiseId: fid,
                    "Damage",
                    "retry failed: \(describeDamageError(error))",
                    cid: cid
                )
                throw error
            }
        }
    }

    private static func describeDamageError(_ error: Error) -> String {
        if let op = error as? WheelSysVehicleDamageServiceError,
           case .operationFailed(let msg) = op {
            return msg
        }
        return WheelSysCheckinService.describeCallableError(error)
    }

    private static func callDamageHistoryCallable(
        arac: Arac,
        franchiseId fid: String,
        station: String,
        rentalId: Int?,
        cid: String
    ) async throws -> WheelSysVehicleDamageHistoryResponse {
        var payload: [String: Any] = [
            "franchiseId": fid,
            "station": station.uppercased(),
            "plate": arac.plaka,
            "plateNo": arac.plaka,
        ]
        if let rentalId, rentalId > 0 {
            payload["rentalId"] = rentalId
            WheelSysDebug.logCH(
                franchiseId: fid,
                "Damage",
                "using rental-scoped GetDamages rentalId=\(rentalId)",
                cid: cid
            )
        }
        if let entityId = await MainActor.run(body: { resolveVehicleEntityId(for: arac) }),
           !entityId.isEmpty {
            payload["vehicleEntityId"] = entityId
            payload["wheelsysVehicleId"] = entityId
            WheelSysDebug.logCH(
                franchiseId: fid,
                "Damage",
                "resolved vehicleEntityId=\(entityId)",
                cid: cid
            )
        } else {
            WheelSysDebug.warnCH(
                franchiseId: fid,
                "Damage",
                "no vehicleEntityId — plate-only lookup",
                cid: cid
            )
        }

        let result: HTTPSCallableResult
        do {
            WheelSysDebug.logCH(
                franchiseId: fid,
                "Damage",
                "calling wheelsysGetVehicleDamageHistory",
                cid: cid
            )
            result = try await functions.httpsCallable("wheelsysGetVehicleDamageHistory").call(payload)
        } catch {
            let mapped = describeDamageError(error)
            WheelSysDebug.errorCH(
                franchiseId: fid,
                "Damage",
                "callable failed: \(mapped)",
                cid: cid
            )
            throw WheelSysVehicleDamageServiceError.operationFailed(mapped)
        }
        guard let dict = result.data as? [String: Any] else {
            WheelSysDebug.errorCH(franchiseId: fid, "Damage", "invalid response shape", cid: cid)
            throw WheelSysVehicleDamageServiceError.operationFailed("Invalid response.")
        }
        let parsed = try parseHistoryResponse(dict)
        WheelSysDebug.logCH(
            franchiseId: fid,
            "Damage",
            "fetch ok vehicleId=\(parsed.vehicleId) damageCount=\(parsed.damageCount) resolvedEntity=\(parsed.resolvedVehicleEntityId)",
            cid: cid
        )
        return parsed
    }

    static func previewURL(for previewPath: String) -> URL? {
        let trimmed = previewPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let projectId = FirebaseApp.app()?.options.projectID ?? "greenmotionapp-33413"
        let base = "https://\(previewRegion)-\(projectId).cloudfunctions.net/"
        let normalizedPath = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let raw = base + normalizedPath
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded) {
            return url
        }
        return URL(string: raw)
    }

    private static func makePreviewRequest(url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let cookie = WheelSysCookieCache.lastCookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    private static func isPreviewAuthStatus(_ code: Int) -> Bool {
        code == 401 || code == 403 || code == 419 || code == 440
    }

    private static func fetchPreviewData(
        url: URL,
        user: User,
        forceTokenRefresh: Bool = false
    ) async throws -> (Data, Int) {
        let token = try await user.getIDToken(forcingRefresh: forceTokenRefresh)
        let request = makePreviewRequest(url: url, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }

    static func loadPreviewImage(previewPath: String) async throws -> UIImage {
        guard let user = Auth.auth().currentUser else {
            throw WheelSysVehicleDamageServiceError.notAuthenticated
        }
        guard let url = previewURL(for: previewPath) else {
            throw WheelSysVehicleDamageServiceError.operationFailed("Invalid preview path.")
        }

        let first = try await fetchPreviewData(url: url, user: user)
        var data = first.0
        var statusCode = first.1

        if isPreviewAuthStatus(statusCode) {
            let fid = FirebaseService.shared.currentFranchiseId.uppercased()
            await ensureSessionReady(franchiseId: fid)
            _ = await syncClientCookieToServerIfNeeded(franchiseId: fid)
            let retry = try await fetchPreviewData(url: url, user: user, forceTokenRefresh: true)
            data = retry.0
            statusCode = retry.1
        }

        guard (200...299).contains(statusCode) else {
            let message = isPreviewAuthStatus(statusCode)
                ? "WheelSys session expired."
                : "Attachment preview failed."
            throw WheelSysVehicleDamageServiceError.operationFailed(message)
        }
        guard let image = UIImage(data: data) else {
            throw WheelSysVehicleDamageServiceError.operationFailed("Invalid image data.")
        }
        return image
    }

    private static func parseHistoryResponse(_ dict: [String: Any]) throws -> WheelSysVehicleDamageHistoryResponse {
        let success = dict["success"] as? Bool ?? false
        if !success {
            let msg = dict["message"] as? String ?? "WheelSys damage history failed."
            throw WheelSysVehicleDamageServiceError.operationFailed(msg)
        }

        let vehicleId = intValue(dict["vehicleId"]) ?? 0
        let resolved = stringValue(dict["resolvedVehicleEntityId"]) ?? String(vehicleId)
        let syncedAt = stringValue(dict["syncedAt"]) ?? ISO8601DateFormatter().string(from: Date())
        let damageCount = intValue(dict["damageCount"]) ?? (dict["damages"] as? [[String: Any]])?.count ?? 0
        let rows = dict["damages"] as? [[String: Any]] ?? []
        let damages = rows.compactMap(parseDamageRecord)

        return WheelSysVehicleDamageHistoryResponse(
            vehicleId: vehicleId,
            resolvedVehicleEntityId: resolved,
            damages: damages,
            damageCount: damageCount,
            syncedAt: syncedAt
        )
    }

    private static func parseDamageRecord(_ row: [String: Any]) -> WheelSysVehicleDamageRecord? {
        let damageId = stringValue(row["damageId"]) ?? UUID().uuidString
        let vehicleId = intValue(row["vehicleId"]) ?? 0
        let attachmentRows = row["attachments"] as? [[String: Any]] ?? []
        let attachments = attachmentRows.compactMap(parseAttachment)
        let relatedRows = row["relatedItems"] as? [[String: Any]] ?? []
        let relatedItems = relatedRows.map {
            WheelSysVehicleDamageRelatedItem(
                type: stringValue($0["type"]) ?? "unknown",
                label: stringValue($0["label"]) ?? "",
                url: stringValue($0["url"])
            )
        }

        return WheelSysVehicleDamageRecord(
            damageId: damageId,
            damageNo: stringValue(row["damageNo"]),
            vehicleId: vehicleId,
            plateNo: stringValue(row["plateNo"]),
            normalizedPlateNo: stringValue(row["normalizedPlateNo"]),
            damageType: stringValue(row["damageType"]),
            area: stringValue(row["area"]),
            element: stringValue(row["element"]),
            action: stringValue(row["action"]),
            memo: stringValue(row["memo"]),
            chargeText: stringValue(row["chargeText"]),
            chargeAmount: doubleValue(row["chargeAmount"]),
            currency: stringValue(row["currency"]),
            relatedRentalNo: stringValue(row["relatedRentalNo"]),
            addedOn: stringValue(row["addedOn"]),
            recordedBy: stringValue(row["recordedBy"]),
            recordedOn: stringValue(row["recordedOn"]),
            labourHours: stringValue(row["labourHours"]),
            attachments: attachments,
            relatedItems: relatedItems,
            source: stringValue(row["source"]) ?? "wheelsys.car.aspx",
            syncedAt: stringValue(row["syncedAt"]) ?? ""
        )
    }

    private static func parseAttachment(_ row: [String: Any]) -> WheelSysVehicleDamageAttachment? {
        guard let attachmentId = stringValue(row["attachmentId"]), !attachmentId.isEmpty else { return nil }
        return WheelSysVehicleDamageAttachment(
            attachmentId: attachmentId,
            filename: stringValue(row["filename"]) ?? attachmentId,
            fileType: stringValue(row["fileType"]) ?? "other",
            previewable: row["previewable"] as? Bool ?? false,
            previewPath: stringValue(row["previewPath"])
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let n = Int(s) { return n }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let n = Double(s) { return n }
        return nil
    }
}
