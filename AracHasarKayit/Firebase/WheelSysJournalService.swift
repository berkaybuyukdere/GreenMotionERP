import Foundation
import FirebaseAuth

// MARK: - Journal service

enum WheelSysJournalService {

    static let rentalDomain = 101
    private static let zurichTimeZone = TimeZone(identifier: "Europe/Zurich")!

    static var zurichCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zurichTimeZone
        return cal
    }

    // MARK: Fleet → journal rows

    static func buildJournalRows(
        from fleet: WheelSysFleetChartResult,
        selectedDay: Date,
        stationFilter: String = "all"
    ) -> (checkout: [WheelSysJournalRow], returns: [WheelSysJournalRow]) {
        let dayStart = startOfDayZurich(selectedDay)
        let vehicleByResource = Dictionary(uniqueKeysWithValues: fleet.vehicles.map { ($0.vehicleId, $0) })

        let rentalEvents = fleet.allEvents.filter { isJournalFleetEvent($0) && $0.rentalEntityId != nil }
        print("[Journal] selectedDate=\(formatZurichDay(dayStart))")
        print("[Journal] allEventsCount=\(fleet.allEvents.count)")
        print("[Journal] rentalEventsCount=\(rentalEvents.count)")

        let missingStart = rentalEvents.filter { resolveEventInstant(raw: $0.start, timeText: $0.startTimeText) == nil }.count
        let missingEnd = rentalEvents.filter { resolveEventInstant(raw: $0.end, timeText: $0.endTimeText) == nil }.count
        print("[Journal] rentalEventsMissingStart=\(missingStart) missingEnd=\(missingEnd)")

        if let sample = rentalEvents.first {
            let parsedStart = resolveEventInstant(raw: sample.start, timeText: sample.startTimeText)
            let parsedEnd = resolveEventInstant(raw: sample.end, timeText: sample.endTimeText)
            print("[Journal] sample rental event domain=\(sample.domain) type=\(sample.type) start=\(sample.start) end=\(sample.end) entityId=\(sample.rentalEntityId.map(String.init) ?? "nil")")
            print("[Journal] sample parsedStartDay=\(parsedStart.map(formatZurichDay) ?? "nil") parsedEndDay=\(parsedEnd.map(formatZurichDay) ?? "nil") selectedDay=\(formatZurichDay(dayStart))")
        }

        var skippedStation = 0
        var matchedCheckout = 0
        var matchedReturn = 0

        var checkout: [WheelSysJournalRow] = []
        var returns: [WheelSysJournalRow] = []

        for event in rentalEvents {
            guard let entityId = event.rentalEntityId else { continue }
            let vehicle = vehicleByResource[event.vehicleId]

            if let station = vehicle?.station, !matchesStation(station, filter: stationFilter) {
                skippedStation += 1
                continue
            }
            if vehicle == nil {
                if event.type != "booking" && stationFilter != "all" { continue }
                let sf = event.stationFrom
                if !sf.isEmpty, stationFilter != "all",
                   !matchesStation(sf, filter: stationFilter) {
                    continue
                }
            }

            let startDate = resolveEventInstant(raw: event.start, timeText: event.startTimeText)
            let endDate = resolveEventInstant(raw: event.end, timeText: event.endTimeText)
            let plate = vehicle?.plate ?? ""
            let isUnassigned = event.type == "booking" || plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if let startDate, isSameDayZurich(startDate, as: dayStart) {
                matchedCheckout += 1
                checkout.append(makeRow(
                    event: event,
                    vehicle: vehicle,
                    kind: .checkout,
                    eventDateTime: startDate,
                    entityId: entityId
                ))
            }

            if let endDate, isSameDayZurich(endDate, as: dayStart) {
                matchedReturn += 1
                returns.append(makeRow(
                    event: event,
                    vehicle: vehicle,
                    kind: .return,
                    eventDateTime: endDate,
                    entityId: entityId
                ))
            }
        }

        checkout.sort { $0.eventDateTime < $1.eventDateTime }
        returns.sort { $0.eventDateTime < $1.eventDateTime }

        checkout = checkout.enumerated().map { idx, row in
            var copy = row
            copy.rowNumber = idx + 1
            return copy
        }
        returns = returns.enumerated().map { idx, row in
            var copy = row
            copy.rowNumber = idx + 1
            return copy
        }

        print("[Journal] skippedStation=\(skippedStation) matchedCheckout=\(matchedCheckout) matchedReturn=\(matchedReturn)")
        print("[Journal] checkoutRows=\(checkout.count)")
        print("[Journal] returnRows=\(returns.count)")

        return (checkout, returns)
    }

    // MARK: Rental detail

    static func fetchRentalDetailDiagnostics(entityId: Int) async throws -> WheelSysRentalDiagnostics {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysCheckinServiceError.notAuthenticated
        }
        print("[Journal] fetchRentalDetailDiagnostics entityId=\(entityId)")
        return try await WheelSysRentalWebViewFetcher.fetchDiagnostics(entityId: entityId)
    }

    static func fetchRentalDetail(entityId: Int) async throws -> WheelSysRentalDetail {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysCheckinServiceError.notAuthenticated
        }
        print("[Journal] enrich detail started entityId=\(entityId)")
        return try await WheelSysRentalWebViewFetcher.fetchRentalDetail(entityId: entityId)
    }

    static func submitReturnUpdate(
        franchiseId: String,
        request: WheelSysReturnUpdateRequest,
        onJournalReload: (() async -> Void)? = nil
    ) async throws -> WheelSysReturnSaveResult {
        print("[Journal] WheelSys pre-check-in started rentalId=\(request.rentalEntityId) km=\(request.checkInMileage) fuel=\(request.checkInFuel)")
        let now = request.actualCheckInDateTime ?? WheelSysZurichDateTime.now()
        let precheckin = try await WheelSysPrecheckinService.submit(
            franchiseId: franchiseId,
            rentalId: request.rentalEntityId,
            confirmCustomer: true,
            confirmVehicle: true,
            confirmDamagesReviewed: true,
            confirmInsuranceReviewed: true,
            checkInMileage: request.checkInMileage,
            checkInFuel: request.checkInFuel,
            checkInUserId: request.checkInUserId,
            checkInDate: WheelSysZurichDateTime.formatDate(now),
            checkInTime: WheelSysZurichDateTime.formatTime(now),
            notes: nil,
            station: request.station
        )

        let result = WheelSysReturnSaveResult(
            success: precheckin.success,
            message: precheckin.message ?? (precheckin.success
                ? "wheelsys.precheckin.submit_success".localized
                : "wheelsys.precheckin.submit_failed".localized),
            mileageFrom: nil,
            mileageTo: request.checkInMileage,
            milesDriven: nil,
            fuelTo: request.checkInFuel,
            verifiedMileageTo: precheckin.success ? request.checkInMileage : nil,
            vehicleEntityId: request.vehicleEntityIdHint ?? request.fleetCarId,
            dailyViewAvailableVerified: nil,
            verificationPending: false,
            verificationAttempts: nil,
            entryPoint: request.entryPoint
        )

        if result.success {
            _ = await WheelSysReturnSyncManager.refreshAfterReturnSave(
                franchiseId: franchiseId,
                selectedDate: WheelSysJournalService.formatZurichDay(WheelSysJournalService.todayZurich()),
                station: request.station,
                rentalId: request.rentalEntityId,
                vehicleId: result.vehicleEntityId,
                plate: request.plate,
                expectedMileage: request.checkInMileage,
                expectedFuel: request.checkInFuel,
                onJournalReload: onJournalReload
            )
        }

        print("[Journal] WheelSys pre-check-in finished rentalId=\(request.rentalEntityId) success=\(result.success)")
        return result
    }

    static func getReturnCandidates(from snapshot: WheelSysJournalSnapshot) -> [WheelSysJournalCheckin] {
        snapshot.checkIns
    }

    static func findReturnCandidatesByPlate(
        plate: String,
        snapshot: WheelSysJournalSnapshot?
    ) -> [WheelSysJournalCheckin] {
        let norm = WheelSysPlateNormalizer.canonical(plate)
        guard !norm.isEmpty, let snapshot else { return [] }
        return snapshot.checkIns.filter { $0.normalizedPlate == norm }
    }

    static func returnCandidate(from row: WheelSysJournalRow, snapshot: WheelSysJournalSnapshot?) -> WheelSysReturnCandidate? {
        guard let prefill = buildReturnPrefill(from: row, snapshot: snapshot) else { return nil }
        return WheelSysReturnCandidate(
            id: row.id,
            rentalEntityId: prefill.rentalEntityId,
            vehicleEntityId: prefill.vehicleEntityId,
            plate: row.plate,
            normalizedPlate: row.normalizedPlate,
            resNo: prefill.resNo,
            raNo: prefill.raNo,
            irn: prefill.confirmationNo,
            driverName: prefill.driverName,
            model: row.model,
            station: row.station.isEmpty ? "ZRH" : row.station,
            dateFrom: prefill.dateFrom.map { formatZurichDay($0) },
            dateTo: prefill.dateTo.map { formatZurichDay($0) },
            checkoutMileage: prefill.checkoutMileage,
            checkoutFuel: prefill.checkoutFuel,
            source: "journal_return"
        )
    }

    static func buildReturnPrefill(
        from row: WheelSysJournalRow,
        snapshot: WheelSysJournalSnapshot?
    ) -> WheelSysReturnOperationPrefill? {
        guard row.kind == .return, row.rentalEntityId > 0 else { return nil }

        let checkin = snapshot?.checkIns.first(where: { item in
            if let rentalId = item.rentalEntityId, rentalId == row.rentalEntityId { return true }
            return item.normalizedPlate == row.normalizedPlate && !row.normalizedPlate.isEmpty
        })

        let resNo = resolvedResNo(for: row, checkin: checkin)

        let driver = row.driverNameFromFleet.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = driver.isEmpty ? (checkin?.driverName ?? "") : driver
        let raNo = row.rentalNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ra = (raNo?.isEmpty == false) ? raNo : nil

        return WheelSysReturnOperationPrefill(
            rentalEntityId: row.rentalEntityId,
            resNo: resNo,
            raNo: ra,
            confirmationNo: {
                let t = row.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }(),
            driverName: name,
            customerEmail: nil,
            vehicleEntityId: checkin?.vehicleEntityId ?? (row.resourceId.isEmpty ? nil : row.resourceId),
            checkoutMileage: checkin?.mileage,
            checkoutFuel: checkin?.fuel,
            checkinMileageHint: nil,
            checkinFuelHint: checkin?.fuel,
            dateFrom: row.eventStart ?? parseFleetEventDate(checkin?.dateFrom ?? ""),
            dateTo: row.eventEnd ?? row.eventDateTime,
            entryPoint: .journalReturn
        )
    }

    static func buildReturnPrefill(
        from candidate: WheelSysReturnCandidate,
        entryPoint: WheelSysReturnEntryPoint
    ) -> WheelSysReturnOperationPrefill {
        WheelSysReturnOperationPrefill(
            rentalEntityId: candidate.rentalEntityId,
            resNo: candidate.resNo,
            raNo: candidate.raNo,
            confirmationNo: candidate.irn,
            driverName: candidate.driverName,
            customerEmail: nil,
            vehicleEntityId: candidate.vehicleEntityId,
            checkoutMileage: candidate.checkoutMileage,
            checkoutFuel: candidate.checkoutFuel,
            checkinMileageHint: nil,
            checkinFuelHint: candidate.checkoutFuel,
            dateFrom: parseFleetEventDate(candidate.dateFrom ?? ""),
            dateTo: parseFleetEventDate(candidate.dateTo ?? ""),
            entryPoint: entryPoint
        )
    }

    /// Prefill for CH checkout after journal row selection or vehicle assignment.
    static func buildCheckoutPrefill(
        from row: WheelSysJournalRow,
        customerName: String?,
        customerEmail: String?,
        assignedPlate: String?,
        vehicleGroup: String,
        resNoOverride: String? = nil
    ) -> WheelSysCheckoutPrefill {
        var resNo = resNoOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if resNo.isEmpty {
            resNo = (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if resNo.isEmpty { resNo = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let normalized = WheelSysResCode.normalizedReservationCode(resNo) {
            resNo = normalized
        }
        let plate = assignedPlate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? row.plate
        let unassigned = plate.isEmpty || plate == "-" || plate == "—"
        let conf = row.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WheelSysCheckoutPrefill(
            bookingEntityId: row.effectiveBookingEntityId,
            resNo: resNo,
            customerName: (name?.isEmpty == false && name != "-") ? name : nil,
            customerEmail: email?.isEmpty == false ? email : nil,
            confirmationNo: conf.isEmpty ? nil : conf,
            vehicleGroup: vehicleGroup,
            eventDateTime: row.eventStart ?? row.eventDateTime,
            plannedReturnDate: row.eventEnd,
            assignedPlate: unassigned ? nil : plate,
            isUnassigned: unassigned,
            insurance: nil,
            rentalDays: nil,
            checkoutMileage: nil,
            irn: nil
        )
    }

    private static func resolvedResNo(
        for row: WheelSysJournalRow,
        checkin: WheelSysJournalCheckin?
    ) -> String {
        if let checkin {
            let fromCheckin = checkin.reservationCode
            if !fromCheckin.isEmpty { return fromCheckin }
            let rawRes = checkin.resNo.trimmingCharacters(in: .whitespacesAndNewlines)
            if WheelSysResCode.isReservationCode(rawRes) {
                return WheelSysResCode.normalizedReservationCode(rawRes) ?? rawRes
            }
        }
        let fromRow = (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
        if WheelSysResCode.isReservationCode(fromRow) {
            return WheelSysResCode.normalizedReservationCode(fromRow) ?? fromRow
        }
        if let normalized = WheelSysResCode.normalizedReservationCode(fromRow) {
            return normalized
        }
        return ""
    }

    // MARK: Zurich calendar

    static func startOfDayZurich(_ date: Date) -> Date {
        let comps = zurichCalendar.dateComponents([.year, .month, .day], from: date)
        return zurichCalendar.date(from: comps) ?? date
    }

    static func isSameDayZurich(_ date: Date, as day: Date) -> Bool {
        formatZurichDay(date) == formatZurichDay(day)
    }

    static func todayZurich() -> Date {
        startOfDayZurich(Date())
    }

    // MARK: Date parsing

    static func parseFleetEventDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/Date(") {
            var inner = trimmed.dropFirst(6)
            if inner.hasSuffix(")/") { inner = inner.dropLast(2) }
            else if inner.hasSuffix(")") { inner = inner.dropLast() }
            let numPart = inner.split(whereSeparator: { $0 == "+" || $0 == "-" }).first
            if let ms = Int64(numPart ?? "") {
                return Date(timeIntervalSince1970: Double(ms) / 1000.0)
            }
        }

        if let ms = Int64(trimmed.filter { $0.isNumber }), trimmed.count >= 10, trimmed.allSatisfy({ $0.isNumber }) {
            return Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }

        // WheelSys fleet events often use local wall time without timezone suffix.
        if isTimezonelessISOInstant(trimmed) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = zurichTimeZone
            for fmt in [
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm",
            ] {
                df.dateFormat = fmt
                if let d = df.date(from: trimmed) { return d }
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = zurichTimeZone
        for fmt in [
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "dd/MM/yyyy HH:mm",
            "dd.MM.yyyy HH:mm",
        ] {
            df.dateFormat = fmt
            if let d = df.date(from: trimmed) { return d }
        }
        return nil
    }

    static func normalizePlate(_ plate: String) -> String {
        plate
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    static func parseRentalNumber(from title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        if let range = title.range(of: "RNT-\\d+", options: .regularExpression) {
            return String(title[range])
        }
        return nil
    }

    // MARK: Private

    private static func isRentalFleetEvent(_ event: WheelSysFleetEvent) -> Bool {
        event.domain == rentalDomain || event.type == "rental"
    }

    private static func isJournalFleetEvent(_ event: WheelSysFleetEvent) -> Bool {
        isRentalFleetEvent(event) || event.domain == 100 || event.type == "booking"
    }

    private static func resolveEventInstant(raw: String, timeText: String) -> Date? {
        if let parsed = parseFleetEventDate(raw) { return parsed }
        let t = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let parsed = parseFleetEventDate(t) { return parsed }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = zurichTimeZone
        for fmt in ["dd/MM/yyyy HH:mm", "dd.MM.yyyy HH:mm", "dd/MM/yyyy", "dd.MM.yyyy"] {
            df.dateFormat = fmt
            if let d = df.date(from: t) { return d }
        }
        return nil
    }

    private static func makeRow(
        event: WheelSysFleetEvent,
        vehicle: WheelSysFleetVehicle?,
        kind: WheelSysJournalRowKind,
        eventDateTime: Date,
        entityId: Int
    ) -> WheelSysJournalRow {
        let rowId = "\(kind.rawValue)-\(event.vehicleId)-\(event.id)-\(Int(eventDateTime.timeIntervalSince1970))"
        let plate = vehicle?.plate ?? ""
        let unassigned = event.type == "booking" || plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return WheelSysJournalRow(
            id: rowId,
            kind: kind,
            rowNumber: 0,
            plate: plate,
            normalizedPlate: normalizePlate(plate),
            resourceId: event.vehicleId,
            model: vehicle?.model ?? "",
            station: vehicle?.station ?? event.stationFrom,
            vehicleGroup: event.initialCarGroup.isEmpty ? (vehicle?.group ?? "") : event.initialCarGroup,
            eventStart: parseFleetEventDate(event.start),
            eventEnd: parseFleetEventDate(event.end),
            eventDateTime: eventDateTime,
            rentalEntityId: entityId,
            bookingEntityId: unassigned ? entityId : nil,
            rentalUrl: unassigned
                ? WheelSysJournalRow.bookingPageURL(entityId: entityId)
                : WheelSysJournalRow.rentalPageURL(entityId: entityId),
            driverNameFromFleet: event.driverName,
            resCode: "",
            displayDocNo: "",
            mainDocNo: "",
            confirmationReference: "",
            linkedResCode: nil,
            irn: nil,
            voucherNo: nil,
            rentalTitle: nil,
            rentalNumber: nil,
            enrichmentStatus: .notLoaded,
            eventType: event.type,
            isUnassigned: unassigned
        )
    }

    static func formatZurichDay(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeZone = zurichTimeZone
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private static func matchesStation(_ station: String, filter: String) -> Bool {
        guard filter != "all" else { return true }
        let a = station.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let b = filter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if a == b { return true }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        return false
    }

    private static func isTimezonelessISOInstant(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#, options: .regularExpression) != nil else {
            return false
        }
        if value.hasSuffix("Z") { return false }
        if value.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil { return false }
        return true
    }
}
