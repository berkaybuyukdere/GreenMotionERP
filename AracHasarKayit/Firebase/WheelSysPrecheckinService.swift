import Foundation
import FirebaseAuth
import FirebaseFunctions

enum WheelSysPrecheckinServiceError: LocalizedError {
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

/// Calls the WheelSys pre-check-in callables (`wheelsysGetPrecheckinContext`,
/// `wheelsysSubmitPrecheckin`) and parses their `[String: Any]` payloads.
/// Region + session bootstrapping mirror `WheelSysVehicleDamageService`.
enum WheelSysPrecheckinService {
    private static let functions = Functions.functions(region: "europe-west6")
    private static var contextFetchTasks: [String: Task<WheelSysPrecheckinContext, Error>] = [:]

    // MARK: - Fetch context

    static func fetchContext(
        franchiseId: String,
        rentalId: Int?,
        resNo: String?,
        rntNo: String?,
        plateNo: String?,
        date: String? = nil,
        station: String = "ZRH"
    ) async throws -> WheelSysPrecheckinContext {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysPrecheckinServiceError.notAuthenticated
        }

        let fid = franchiseId.uppercased()
        let cacheKey = "\(fid):\(rentalId ?? 0):\(station.uppercased())"
        if let existing = contextFetchTasks[cacheKey] {
            return try await existing.value
        }

        let task = Task<WheelSysPrecheckinContext, Error> {
            try await fetchContextUncached(
                franchiseId: fid,
                rentalId: rentalId,
                resNo: resNo,
                rntNo: rntNo,
                plateNo: plateNo,
                date: date,
                station: station
            )
        }
        contextFetchTasks[cacheKey] = task
        defer { contextFetchTasks.removeValue(forKey: cacheKey) }
        return try await task.value
    }

    private static func fetchContextUncached(
        franchiseId fid: String,
        rentalId: Int?,
        resNo: String?,
        rntNo: String?,
        plateNo: String?,
        date: String?,
        station: String
    ) async throws -> WheelSysPrecheckinContext {
        let cid = WheelSysDebug.newCorrelationId()
        WheelSysDebug.logCH(
            franchiseId: fid,
            "Precheckin",
            "fetchContext start rentalId=\(rentalId.map(String.init) ?? "nil") " +
            "res=\(resNo ?? "nil") rnt=\(rntNo ?? "nil") plate=\(plateNo ?? "nil") " +
            "station=\(station.uppercased())",
            cid: cid
        )

        await WheelSysVehicleDamageService.ensureSessionReady(franchiseId: fid)

        var payload: [String: Any] = [
            "franchiseId": fid,
            "station": station.uppercased(),
        ]
        if let rentalId { payload["rentalId"] = rentalId }
        if let resNo = trimmedOrNil(resNo) { payload["resNo"] = resNo }
        if let rntNo = trimmedOrNil(rntNo) { payload["rntNo"] = rntNo }
        if let plateNo = trimmedOrNil(plateNo) { payload["plateNo"] = plateNo }
        if let date = trimmedOrNil(date) { payload["date"] = date }

        let result: HTTPSCallableResult
        do {
            WheelSysDebug.logCH(
                franchiseId: fid,
                "Precheckin",
                "calling wheelsysGetPrecheckinContext",
                cid: cid
            )
            result = try await functions.httpsCallable("wheelsysGetPrecheckinContext").call(payload)
        } catch {
            let mapped = describePrecheckinCallableError(error)
            WheelSysDebug.errorCH(franchiseId: fid, "Precheckin", "context callable failed: \(mapped)", cid: cid)
            throw WheelSysPrecheckinServiceError.operationFailed(mapped)
        }

        guard let dict = result.data as? [String: Any] else {
            WheelSysDebug.errorCH(franchiseId: fid, "Precheckin", "invalid context response shape", cid: cid)
            throw WheelSysPrecheckinServiceError.operationFailed("Invalid response.")
        }
        let success = dict["success"] as? Bool ?? false
        guard success else {
            let msg = stringValue(dict["message"]) ?? "WheelSys pre-check-in lookup failed."
            WheelSysDebug.errorCH(franchiseId: fid, "Precheckin", "context not success msg=\(msg)", cid: cid)
            throw WheelSysPrecheckinServiceError.operationFailed(msg)
        }

        let context = parseContext(dict)
        WheelSysDebug.logCH(
            franchiseId: fid,
            "PrecheckinContext",
            "pageTitle=\(context.eligibility?.pageTitle ?? "nil") " +
            "rdStatus=\(context.eligibility?.rdStatus ?? "nil") " +
            "rdUsageType=\(context.eligibility?.rdUsageType ?? "nil") " +
            "eligible=\(context.eligibility?.eligibleForPrecheckin ?? true)",
            cid: cid
        )
        WheelSysDebug.logCH(
            franchiseId: fid,
            "Precheckin",
            "context ok rentalId=\(context.rental.rentalId) plate=\(context.vehicle.plateNo) " +
            "damages=\(context.existingDamages.count) ready=\(context.precheckinStatus.ready) " +
            "eligible=\(context.eligibility?.eligibleForPrecheckin ?? true) " +
            "blockers=\(context.precheckinStatus.blockers.count)",
            cid: cid
        )
        if context.canSubmit == false, let msg = context.statusIneligibleMessage {
            WheelSysDebug.warnCH(
                franchiseId: fid,
                "PrecheckinUI",
                "Pre-check-in disabled: \(msg)",
                cid: cid
            )
        }
        return context
    }

    // MARK: - Submit

    static func submit(
        franchiseId: String,
        rentalId: Int,
        confirmCustomer: Bool,
        confirmVehicle: Bool,
        confirmDamagesReviewed: Bool,
        confirmInsuranceReviewed: Bool,
        checkInMileage: Int? = nil,
        checkInFuel: Int? = nil,
        checkInUserId: String? = nil,
        checkInDate: String? = nil,
        checkInTime: String? = nil,
        notes: String?,
        station: String = "ZRH"
    ) async throws -> WheelSysPrecheckinSubmitResult {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysPrecheckinServiceError.notAuthenticated
        }

        let cid = WheelSysDebug.newCorrelationId()
        let fid = franchiseId.uppercased()
        WheelSysDebug.logCH(
            franchiseId: fid,
            "Precheckin",
            "submit start rentalId=\(rentalId) checkInKm=\(checkInMileage.map(String.init) ?? "nil") " +
            "checkInFuel=\(checkInFuel.map(String.init) ?? "nil") confirmCustomer=\(confirmCustomer) " +
            "confirmVehicle=\(confirmVehicle) confirmDamages=\(confirmDamagesReviewed) " +
            "confirmInsurance=\(confirmInsuranceReviewed)",
            cid: cid
        )

        await WheelSysVehicleDamageService.ensureSessionReady(franchiseId: fid)
        if !WheelSysCookieCache.serverSessionValid {
            _ = await WheelSysVehicleDamageService.syncClientCookieToServerIfNeeded(franchiseId: fid)
        }

        guard WheelSysCookieCache.isValid || WheelSysCookieCache.serverSessionValid else {
            throw WheelSysPrecheckinServiceError.operationFailed(
                "wheelsys_fleet.session_expired".localized
            )
        }

        let submitParams = ServerSubmitParams(
            franchiseId: fid,
            rentalId: rentalId,
            confirmCustomer: confirmCustomer,
            confirmVehicle: confirmVehicle,
            confirmDamagesReviewed: confirmDamagesReviewed,
            confirmInsuranceReviewed: confirmInsuranceReviewed,
            checkInMileage: checkInMileage,
            checkInFuel: checkInFuel,
            checkInUserId: checkInUserId,
            notes: notes,
            station: station,
            cid: cid
        )

        // Fast path (physical device): one server round-trip when Firestore session is warm.
        if WheelSysCookieCache.serverSessionValid {
            do {
                WheelSysDebug.logCH(
                    franchiseId: fid,
                    "Precheckin",
                    "submit mode=server primary rentalId=\(rentalId)",
                    cid: cid
                )
                let serverResult = try await submitViaServerCallable(params: submitParams)
                logServerSubmitFailureIfNeeded(serverResult, franchiseId: fid, cid: cid)
                if serverResult.success {
                    WheelSysDebug.logCH(
                        franchiseId: fid,
                        "Precheckin",
                        "submit ok server afterSave rentalId=\(rentalId)",
                        cid: cid
                    )
                    return serverResult
                }
                let mileageRetry = isMileageSyncErrorMessage(serverResult.message)
                if isRequiredErrorMessage(serverResult.message), !mileageRetry {
                    return serverResult
                }
                if !serverResult.retryable, !mileageRetry {
                    return serverResult
                }
            } catch {
                WheelSysDebug.warnCH(
                    franchiseId: fid,
                    "Precheckin",
                    "server submit threw: \(error.localizedDescription) — trying webview",
                    cid: cid
                )
            }
        }

        var webParsed: WheelSysPrecheckinSubmitResult?
        if WheelSysCookieCache.isValid {
            do {
                WheelSysDebug.logCH(
                    franchiseId: fid,
                    "Precheckin",
                    "submit mode=webview rentalId=\(rentalId)",
                    cid: cid
                )
                let webResult = try await WheelSysPrecheckinWebViewFetcher.submit(
                    rentalId: rentalId,
                    checkInMileage: checkInMileage,
                    checkInFuel: checkInFuel,
                    checkInUserId: checkInUserId,
                    checkInDate: checkInDate,
                    checkInTime: checkInTime
                )
                webParsed = mapWebViewSubmitResult(webResult, fallbackRentalId: rentalId)
                if let debug = webParsed?.debug {
                    WheelSysDebug.logCH(
                        franchiseId: fid,
                        "Precheckin",
                        "submit debug afterSave=\(debug.containsAfterSave) precheckin=\(debug.containsPrecheckin) " +
                        "source=PrecheckinWebView len=\(debug.responseLength ?? 0)",
                        cid: cid
                    )
                }
                if webParsed?.success == true {
                    WheelSysDebug.logCH(
                        franchiseId: fid,
                        "Precheckin",
                        "submit ok webview rentalId=\(rentalId)",
                        cid: cid
                    )
                    return webParsed!
                }
                if webParsed?.retryable == false {
                    return webParsed!
                }
            } catch let error as WheelSysPrecheckinWebViewError {
                WheelSysDebug.warnCH(
                    franchiseId: fid,
                    "Precheckin",
                    "webview submit failed: \(error.localizedDescription)",
                    cid: cid
                )
            } catch {
                WheelSysDebug.warnCH(
                    franchiseId: fid,
                    "Precheckin",
                    "webview submit failed: \(error.localizedDescription)",
                    cid: cid
                )
            }
        }

        guard WheelSysCookieCache.serverSessionValid else {
            if let webParsed {
                return webParsed
            }
            throw WheelSysPrecheckinServiceError.operationFailed(
                "wheelsys.precheckin.submit_failed".localized
            )
        }

        WheelSysDebug.logCH(
            franchiseId: fid,
            "Precheckin",
            "submit mode=server fallback rentalId=\(rentalId)",
            cid: cid
        )
        let serverResult = try await submitViaServerCallable(params: submitParams)
        logServerSubmitFailureIfNeeded(serverResult, franchiseId: fid, cid: cid)
        if let webParsed, webParsed.success {
            return webParsed
        }
        return serverResult
    }

    private struct ServerSubmitParams {
        let franchiseId: String
        let rentalId: Int
        let confirmCustomer: Bool
        let confirmVehicle: Bool
        let confirmDamagesReviewed: Bool
        let confirmInsuranceReviewed: Bool
        let checkInMileage: Int?
        let checkInFuel: Int?
        let checkInUserId: String?
        let notes: String?
        let station: String
        let cid: String
    }

    private static func isRequiredErrorMessage(_ message: String?) -> Bool {
        let normalized = message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.contains("requirederror")
            || normalized.contains("required field")
            || normalized.contains("missing required")
    }

    private static func isMileageSyncErrorMessage(_ message: String?) -> Bool {
        let normalized = message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.contains("travelled mileage")
            || normalized.contains("no travelled")
    }

    private static func logServerSubmitFailureIfNeeded(
        _ result: WheelSysPrecheckinSubmitResult,
        franchiseId: String,
        cid: String
    ) {
        guard !result.success else { return }
        let msg = result.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let snippet = result.debug?.sanitizedSnippet ?? ""
        WheelSysDebug.errorCH(
            franchiseId: franchiseId,
            "Precheckin",
            "server submit failed msg=\(msg) snippet=\(snippet.prefix(200))",
            cid: cid
        )
    }

    private static func submitViaServerCallable(params: ServerSubmitParams) async throws -> WheelSysPrecheckinSubmitResult {
        try await submitViaServerCallable(
            franchiseId: params.franchiseId,
            rentalId: params.rentalId,
            confirmCustomer: params.confirmCustomer,
            confirmVehicle: params.confirmVehicle,
            confirmDamagesReviewed: params.confirmDamagesReviewed,
            confirmInsuranceReviewed: params.confirmInsuranceReviewed,
            checkInMileage: params.checkInMileage,
            checkInFuel: params.checkInFuel,
            checkInUserId: params.checkInUserId,
            notes: params.notes,
            station: params.station,
            cid: params.cid
        )
    }

    private static func submitViaServerCallable(
        franchiseId: String,
        rentalId: Int,
        confirmCustomer: Bool,
        confirmVehicle: Bool,
        confirmDamagesReviewed: Bool,
        confirmInsuranceReviewed: Bool,
        checkInMileage: Int?,
        checkInFuel: Int?,
        checkInUserId: String?,
        notes: String?,
        station: String,
        cid: String
    ) async throws -> WheelSysPrecheckinSubmitResult {
        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "rentalId": rentalId,
            "station": station.uppercased(),
            "confirmCustomer": confirmCustomer,
            "confirmVehicle": confirmVehicle,
            "confirmDamagesReviewed": confirmDamagesReviewed,
            "confirmInsuranceReviewed": confirmInsuranceReviewed,
        ]
        if let checkInMileage { payload["checkInMileage"] = checkInMileage }
        if let checkInFuel { payload["checkInFuel"] = checkInFuel }
        if let checkInUserId = trimmedOrNil(checkInUserId) { payload["checkInUserId"] = checkInUserId }
        if let notes = trimmedOrNil(notes) { payload["notes"] = notes }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("wheelsysSubmitPrecheckin").call(payload)
        } catch {
            let mapped = describePrecheckinCallableError(error)
            WheelSysDebug.errorCH(
                franchiseId: franchiseId,
                "Precheckin",
                "server submit callable failed: \(mapped)",
                cid: cid
            )
            throw WheelSysPrecheckinServiceError.operationFailed(mapped)
        }

        guard let dict = result.data as? [String: Any] else {
            throw WheelSysPrecheckinServiceError.operationFailed("Invalid response.")
        }
        return parseSubmitResult(dict, fallbackRentalId: rentalId)
    }

    // MARK: - Parsing

    private static func parseContext(_ dict: [String: Any]) -> WheelSysPrecheckinContext {
        let rentalDict = dict["rental"] as? [String: Any] ?? [:]
        let rental = WheelSysPrecheckinRental(
            rentalId: intValue(rentalDict["rentalId"]) ?? 0,
            rntNo: stringValue(rentalDict["rntNo"]),
            resNo: stringValue(rentalDict["resNo"]),
            irn: stringValue(rentalDict["irn"]),
            voucherNo: stringValue(rentalDict["voucherNo"]),
            confirmationNo: stringValue(rentalDict["confirmationNo"])
        )

        let customerDict = dict["customer"] as? [String: Any] ?? [:]
        let customer = WheelSysPrecheckinCustomer(
            driverId: intValue(customerDict["driverId"]),
            firstName: stringValue(customerDict["firstName"]),
            lastName: stringValue(customerDict["lastName"]),
            fullName: stringValue(customerDict["fullName"]) ?? "",
            email: stringValue(customerDict["email"])
        )

        let vehicleDict = dict["vehicle"] as? [String: Any] ?? [:]
        let vehicle = WheelSysPrecheckinVehicle(
            vehicleId: intValue(vehicleDict["vehicleId"]),
            plateNo: stringValue(vehicleDict["plateNo"]) ?? "",
            normalizedPlateNo: stringValue(vehicleDict["normalizedPlateNo"]) ?? "",
            model: stringValue(vehicleDict["model"]),
            modelId: intValue(vehicleDict["modelId"]),
            bookedGroup: stringValue(vehicleDict["bookedGroup"]),
            chargedGroup: stringValue(vehicleDict["chargedGroup"])
        )

        let mfDict = dict["mileageFuel"] as? [String: Any] ?? [:]
        let mileageFuel = WheelSysPrecheckinMileageFuel(
            checkoutMileage: positiveIntValue(mfDict["checkoutMileage"]),
            checkoutFuel: intValue(mfDict["checkoutFuel"]),
            currentReturnMileage: positiveIntValue(mfDict["currentReturnMileage"]),
            currentReturnFuel: positiveIntValue(mfDict["currentReturnFuel"]),
            milesDriven: positiveIntValue(mfDict["milesDriven"])
        )

        var insurance: WheelSysPrecheckinInsurance?
        if let insDict = dict["insurance"] as? [String: Any] {
            insurance = WheelSysPrecheckinInsurance(
                excessAmount: doubleValue(insDict["excessAmount"]),
                cdp: stringValue(insDict["cdp"]),
                insuranceCharge: doubleValue(insDict["insuranceCharge"]),
                damageCharge: doubleValue(insDict["damageCharge"]),
                damageExcess: doubleValue(insDict["damageExcess"]),
                currency: stringValue(insDict["currency"]) ?? "CHF"
            )
        }

        var bodyDiagram: WheelSysPrecheckinBodyDiagram?
        if let bdDict = dict["bodyDiagram"] as? [String: Any] {
            bodyDiagram = WheelSysPrecheckinBodyDiagram(
                imageUrl: stringValue(bdDict["imageUrl"]),
                width: intValue(bdDict["width"]),
                height: intValue(bdDict["height"])
            )
        }

        let damageRows = dict["existingDamages"] as? [[String: Any]] ?? []
        let existingDamages = damageRows.map(parseDamage)

        var carUsability: WheelSysPrecheckinCarUsability?
        if let cuDict = dict["carUsability"] as? [String: Any] {
            carUsability = WheelSysPrecheckinCarUsability(
                isUsable: cuDict["isUsable"] as? Bool ?? true,
                warnings: stringArray(cuDict["warnings"])
            )
        }

        let statusDict = dict["precheckinStatus"] as? [String: Any] ?? [:]
        let precheckinStatus = WheelSysPrecheckinStatus(
            ready: statusDict["ready"] as? Bool ?? false,
            blockers: stringArray(statusDict["blockers"]),
            warnings: stringArray(statusDict["warnings"])
        )

        var eligibility: WheelSysPrecheckinEligibility?
        if let elDict = dict["precheckinEligibility"] as? [String: Any] {
            eligibility = WheelSysPrecheckinEligibility(
                eligible: elDict["eligible"] as? Bool ?? true,
                reasonCode: stringValue(elDict["reasonCode"]),
                reason: stringValue(elDict["reason"]),
                pageTitle: stringValue(elDict["pageTitle"]),
                dbgInitialStatus: stringValue(elDict["dbgInitialStatus"]),
                rdStatus: stringValue(elDict["rdStatus"]),
                rdUsageType: stringValue(elDict["rdUsageType"]),
                rdDispDocno_text: stringValue(elDict["rdDispDocno_text"]),
                rdRaDocNo_text: stringValue(elDict["rdRaDocNo_text"]),
                rdResDocNo_text: stringValue(elDict["rdResDocNo_text"]),
                rdDateTo_text: stringValue(elDict["rdDateTo_text"]),
                rdTimeTo_text: stringValue(elDict["rdTimeTo_text"])
            )
        }

        let syncedAt = stringValue(dict["syncedAt"]) ?? ISO8601DateFormatter().string(from: Date())

        return WheelSysPrecheckinContext(
            rental: rental,
            customer: customer,
            vehicle: vehicle,
            mileageFuel: mileageFuel,
            insurance: insurance,
            bodyDiagram: bodyDiagram,
            existingDamages: existingDamages,
            carUsability: carUsability,
            precheckinStatus: precheckinStatus,
            eligibility: eligibility,
            syncedAt: syncedAt
        )
    }

    private static func parseDamage(_ row: [String: Any]) -> WheelSysPrecheckinDamage {
        var position: WheelSysPrecheckinDamagePosition?
        if let posDict = row["position"] as? [String: Any] {
            position = WheelSysPrecheckinDamagePosition(
                x: doubleValue(posDict["x"]),
                y: doubleValue(posDict["y"]),
                markerWidth: doubleValue(posDict["markerWidth"]),
                markerHeight: doubleValue(posDict["markerHeight"])
            )
        }

        var attachment: WheelSysPrecheckinDamageAttachment?
        if let attDict = row["attachment"] as? [String: Any] {
            attachment = WheelSysPrecheckinDamageAttachment(
                uid: stringValue(attDict["uid"]),
                name: stringValue(attDict["name"]),
                previewable: attDict["previewable"] as? Bool ?? false,
                previewPath: stringValue(attDict["previewPath"])
            )
        }

        var flags: WheelSysPrecheckinDamageFlags?
        if let flagsDict = row["flags"] as? [String: Any] {
            flags = WheelSysPrecheckinDamageFlags(
                isReadOnly: flagsDict["isReadOnly"] as? Bool ?? false,
                isFixed: flagsDict["isFixed"] as? Bool ?? false,
                excessCovered: flagsDict["excessCovered"] as? Bool ?? false
            )
        }

        return WheelSysPrecheckinDamage(
            damageId: stringValue(row["damageId"]) ?? UUID().uuidString,
            uid: stringValue(row["uid"]),
            vehicleId: intValue(row["vehicleId"]),
            plateNo: stringValue(row["plateNo"]),
            damageType: stringValue(row["damageType"]),
            actionName: stringValue(row["actionName"]),
            memo: stringValue(row["memo"]),
            netCharge: doubleValue(row["netCharge"]),
            relatedRentalNo: stringValue(row["relatedRentalNo"]),
            addedByName: stringValue(row["addedByName"]),
            entryDate: stringValue(row["entryDate"]),
            position: position,
            areaName: stringValue(row["areaName"]),
            elementName: stringValue(row["elementName"]),
            attachment: attachment,
            flags: flags
        )
    }

    private static func mapWebViewSubmitResult(
        _ web: WheelSysPrecheckinWebViewResult,
        fallbackRentalId: Int
    ) -> WheelSysPrecheckinSubmitResult {
        var afterSave: [String: Any]?
        if let payload = web.afterSave {
            afterSave = [
                "success": payload.success ?? false,
                "message": payload.resolvedMessage ?? "",
            ]
        } else if let json = web.afterSaveFullJson,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            afterSave = obj
        } else if web.afterSaveSuccess != nil || web.afterSaveMessage != nil {
            afterSave = [
                "success": web.afterSaveSuccess ?? false,
                "message": web.afterSaveMessage ?? "",
            ]
        }

        let debug = WheelSysPrecheckinSubmitDebug(
            httpStatus: web.httpStatus,
            responseLength: web.responseLength,
            containsAfterSave: web.containsAfterSave ?? false,
            containsPrecheckin: web.containsPrecheckin ?? false,
            containsRecordChanged: (web.responsePreview ?? "").localizedCaseInsensitiveContains("Record was changed"),
            containsValidation: false,
            postbackSource: "PrecheckinWebView",
            sanitizedSnippet: (web.afterSaveFullJson ?? web.afterSaveSnippet).map { String($0.prefix(500)) }
        )

        let displayMessage: String
        if web.success {
            let afterSaveText = web.afterSave?.resolvedMessage ?? web.afterSaveMessage
            let trimmedAfterSave = afterSaveText?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedAfterSave.isEmpty {
                displayMessage = "wheelsys.precheckin.submit_success".localized
            } else if let cleaned = userFacingSubmitMessage(trimmedAfterSave, stage: web.stage) {
                displayMessage = cleaned
            } else {
                displayMessage = "wheelsys.precheckin.submit_success".localized
            }
        } else {
            let wheelsysMessage = web.afterSave?.resolvedMessage
                ?? web.afterSaveMessage
                ?? web.message
                ?? web.reason
            displayMessage = userFacingSubmitMessage(wheelsysMessage, stage: web.stage)
                ?? "wheelsys.precheckin.submit_failed".localized
        }

        return WheelSysPrecheckinSubmitResult(
            success: web.success,
            message: displayMessage,
            rentalId: web.rentalId ?? fallbackRentalId,
            rntNo: web.snapshot?.rdDispDocno_text ?? web.rentalStatus?.rdDispDocno_text,
            resNo: web.rentalStatus?.rdResDocNo_text,
            operation: "PRECHECKIN",
            afterSave: afterSave,
            syncedAt: ISO8601DateFormatter().string(from: Date()),
            retryable: !web.success && web.stage == "precheckin_postback",
            warnings: [],
            debug: debug
        )
    }

    /// Plain-text Wheelsys message for UI; strip HTML / RequiredError blobs only.
    private static func userFacingSubmitMessage(_ raw: String?, stage: String?) -> String? {
        if stage == "status_not_eligible" {
            return raw ?? "wheelsys.precheckin.status_not_eligible".localized
        }
        if stage == "validation_failed" || stage == "calcrates_failed" {
            return raw ?? "wheelsys.precheckin.submit_failed".localized
        }
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("<") || trimmed.contains("RequiredError") {
            return nil
        }
        if trimmed.count > 400 {
            return String(trimmed.prefix(400))
        }
        return trimmed
    }

    /// Strip raw HTML / RequiredError snippets from legacy callable errors.
    private static func sanitizeSubmitMessage(_ raw: String?) -> String? {
        userFacingSubmitMessage(raw, stage: nil)
    }

    private static func parseSubmitResult(
        _ dict: [String: Any],
        fallbackRentalId: Int
    ) -> WheelSysPrecheckinSubmitResult {
        var debug: WheelSysPrecheckinSubmitDebug?
        if let debugDict = dict["debug"] as? [String: Any] {
            debug = WheelSysPrecheckinSubmitDebug(
                httpStatus: intValue(debugDict["httpStatus"]),
                responseLength: intValue(debugDict["responseLength"]),
                containsAfterSave: debugDict["containsAfterSave"] as? Bool ?? false,
                containsPrecheckin: debugDict["containsPrecheckin"] as? Bool ?? false,
                containsRecordChanged: debugDict["containsRecordChanged"] as? Bool ?? false,
                containsValidation: debugDict["containsValidation"] as? Bool ?? false,
                postbackSource: stringValue(debugDict["postbackSource"]),
                sanitizedSnippet: stringValue(debugDict["sanitizedSnippet"])
            )
        }
        let rawMessage = stringValue(dict["message"])
        let displayMessage: String?
        if let rawMessage, !rawMessage.isEmpty {
            displayMessage = rawMessage
        } else if dict["success"] as? Bool == true {
            displayMessage = nil
        } else {
            displayMessage = "wheelsys.precheckin.submit_failed".localized
        }
        return WheelSysPrecheckinSubmitResult(
            success: dict["success"] as? Bool ?? false,
            message: displayMessage,
            rentalId: intValue(dict["rentalId"]) ?? fallbackRentalId,
            rntNo: stringValue(dict["rntNo"]),
            resNo: stringValue(dict["resNo"]),
            operation: stringValue(dict["operation"]) ?? "PRECHECKIN",
            afterSave: dict["afterSave"] as? [String: Any],
            syncedAt: stringValue(dict["syncedAt"]) ?? ISO8601DateFormatter().string(from: Date()),
            retryable: dict["retryable"] as? Bool ?? false,
            warnings: stringArray(dict["warnings"]),
            debug: debug
        )
    }

    // MARK: - Value helpers

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    /// WheelSys uses 0 for "not checked in yet" — treat as absent in UI/submit defaults.
    private static func positiveIntValue(_ value: Any?) -> Int? {
        guard let n = intValue(value), n > 0 else { return nil }
        return n
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let n = Double(s) { return n }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let arr = value as? [Any] else { return [] }
        return arr.compactMap { stringValue($0) }
    }

    /// Avoid mapping pre-check-in failures to generic Fleet Chart copy.
    private static func describePrecheckinCallableError(_ error: Error) -> String {
        let mapped = WheelSysCheckinService.describeCallableError(error)
        if mapped == "wheelsys_fleet.unknown_error".localized {
            return "wheelsys.precheckin.submit_failed".localized
        }
        return mapped
    }
}
