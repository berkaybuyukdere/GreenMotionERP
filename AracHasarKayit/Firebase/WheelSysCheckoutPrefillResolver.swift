import Foundation

/// Resolves journal / vehicle checkout prefill via booking.aspx (not rental.aspx).
enum WheelSysCheckoutPrefillResolver {

    /// Journal assign / row checkout — uses booking preview for name, email, RES.
    @MainActor
    static func resolveForJournalRow(
        row: WheelSysJournalRow,
        franchiseId: String,
        assignedPlate: String?,
        customerEmail: String? = nil,
        customerNameHint: String? = nil
    ) async -> WheelSysCheckoutPrefill {
        let fid = franchiseId.uppercased()
        let plate = assignedPlate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = row.vehicleGroup.isEmpty ? "-" : row.vehicleGroup

        var name = normalizedPersonName(customerNameHint)
        var email = customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        var resOverride: String?
        var bookingPreview: WheelSysBookingPreview?

        let trace = PerfTrace.begin("checkout.prefill.booking", detail: "entity=\(row.effectiveBookingEntityId)")
        if let booking = try? await WheelSysCheckinService.loadBookingPreview(
            franchiseId: fid,
            entityId: row.effectiveBookingEntityId,
            resNo: displayDocNo(for: row),
            displayDocNo: displayDocNo(for: row)
        ) {
            bookingPreview = booking
            if !booking.resNo.isEmpty {
                resOverride = booking.resNo
            }
            if name == nil, let driver = booking.driverName {
                name = normalizedPersonName(driver)
            }
            if let full = booking.displayCustomerName {
                name = normalizedPersonName(full) ?? name
            }
            if (email?.isEmpty != false), let em = booking.customerEmail, !em.isEmpty {
                email = em
            }
            PerfTrace.end(trace, note: "res=\(booking.resNo) name=\(name ?? "-")")
        } else {
            PerfTrace.end(trace, note: "booking preview miss")
        }

        if name == nil {
            let fleet = row.driverNameFromFleet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fleet.isEmpty, fleet != "-" { name = fleet }
        }

        let base = WheelSysJournalService.buildCheckoutPrefill(
            from: row,
            customerName: name,
            customerEmail: email?.isEmpty == false ? email : nil,
            assignedPlate: plate,
            vehicleGroup: group,
            resNoOverride: resOverride
        )
        let fleetMileage = fleetMileageHint(forPlate: plate)
        return enrichCheckoutPrefill(base, booking: bookingPreview, fleetMileage: fleetMileage)
    }

    @MainActor
    static func resolveForVehicleCheckout(
        arac: Arac,
        franchiseId: String,
        station: String = "ZRH"
    ) async -> WheelSysCheckoutPrefill? {
        let fid = franchiseId.uppercased()
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()

        guard let row = await checkoutRowAssignedToVehicle(
            arac: arac,
            franchiseId: fid,
            station: station
        ) else { return nil }

        return await resolveForJournalRow(
            row: row,
            franchiseId: fid,
            assignedPlate: arac.plakaFormatli,
            customerNameHint: row.driverNameFromFleet
        )
    }

    static func enrichCheckoutPrefill(
        _ prefill: WheelSysCheckoutPrefill,
        booking: WheelSysBookingPreview?,
        fleetMileage: Int?
    ) -> WheelSysCheckoutPrefill {
        let mileage = fleetMileage.flatMap { $0 > 0 ? $0 : nil } ?? prefill.checkoutMileage
        return WheelSysCheckoutPrefill(
            bookingEntityId: prefill.bookingEntityId,
            resNo: prefill.resNo,
            customerName: prefill.customerName ?? booking?.displayCustomerName,
            customerEmail: prefill.customerEmail ?? booking?.customerEmail,
            confirmationNo: prefill.confirmationNo ?? booking?.confirmationNo,
            vehicleGroup: prefill.vehicleGroup,
            eventDateTime: prefill.eventDateTime ?? booking?.dateFrom,
            plannedReturnDate: prefill.plannedReturnDate ?? booking?.dateTo,
            assignedPlate: prefill.assignedPlate,
            isUnassigned: prefill.isUnassigned,
            insurance: booking?.insurance ?? prefill.insurance,
            rentalDays: booking?.rentalDays ?? prefill.rentalDays,
            checkoutMileage: mileage,
            irn: booking?.irn ?? prefill.irn
        )
    }

    /// Plate-exact journal row only — scans today + next two Zurich days. Never guesses from category or list order.
    @MainActor
    private static func checkoutRowAssignedToVehicle(
        arac: Arac,
        franchiseId: String,
        station: String
    ) async -> WheelSysJournalRow? {
        let plateNorm = WheelSysPlateNormalizer.canonical(arac.plaka)
        guard !plateNorm.isEmpty else { return nil }

        var day = WheelSysJournalService.todayZurich()
        let calendar = WheelSysJournalService.zurichCalendar
        var days: [Date] = [day]
        for _ in 1..<3 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: days.last!) else { break }
            days.append(next)
        }

        return await withTaskGroup(of: WheelSysJournalRow?.self) { group in
            for scanDay in days {
                group.addTask {
                    let selectedDate = WheelSysJournalService.formatZurichDay(scanDay)
                    guard let snapshot = try? await WheelSysJournalAPIService.loadSnapshot(
                        franchiseId: franchiseId,
                        selectedDate: selectedDate,
                        station: station
                    ) else { return nil }
                    return plateMatchedCheckoutRow(plateNorm: plateNorm, in: snapshot)
                }
            }
            for await match in group {
                if let match { return match }
            }
            return nil
        }
    }

    @MainActor
    private static func fleetMileageHint(forPlate plate: String?) -> Int? {
        guard let plate, !plate.isEmpty else { return nil }
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        let mileage = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: plate)?.mileage
        guard let mileage, mileage > 0 else { return nil }
        return mileage
    }

    /// Restore journal prefill when reopening a parked checkout (booking id or RES lookup).
    @MainActor
    static func resolveForParkedExit(
        exit: ExitIslemi,
        arac: Arac,
        franchiseId: String
    ) async -> WheelSysCheckoutPrefill? {
        let fid = franchiseId.uppercased()
        let resRaw = exit.resKodu.trimmingCharacters(in: .whitespacesAndNewlines)
        let resDigits = resRaw
            .replacingOccurrences(of: "RES-", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "RNT-", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resNo = resRaw.isEmpty ? "" : (resRaw.uppercased().hasPrefix("RES-") ? resRaw : "RES-\(resDigits)")

        if let bookingId = exit.wheelSysSnapshot?.bookingEntityId, bookingId > 0,
           let booking = try? await WheelSysCheckinService.loadBookingPreview(
               franchiseId: fid,
               entityId: bookingId,
               resNo: resNo.isEmpty ? nil : resNo,
               displayDocNo: resNo
           ) {
            return parkedPrefill(from: booking, exit: exit, arac: arac, bookingEntityId: bookingId)
        }

        if let row = await checkoutRowAssignedToVehicle(arac: arac, franchiseId: fid, station: "ZRH") {
            return await resolveForJournalRow(
                row: row,
                franchiseId: fid,
                assignedPlate: arac.plakaFormatli,
                customerNameHint: normalizedPersonName(exit.customerFullName)
            )
        }
        return nil
    }

    private static func parkedPrefill(
        from booking: WheelSysBookingPreview,
        exit: ExitIslemi,
        arac: Arac,
        bookingEntityId: Int
    ) -> WheelSysCheckoutPrefill {
        let snap = exit.wheelSysSnapshot
        let name = normalizedPersonName(exit.customerFullName)
        let emailRaw = exit.customerEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = emailRaw.isEmpty ? nil : emailRaw
        return WheelSysCheckoutPrefill(
            bookingEntityId: bookingEntityId,
            resNo: booking.resNo.isEmpty ? exit.resKodu : booking.resNo,
            customerName: name ?? booking.displayCustomerName,
            customerEmail: email ?? booking.customerEmail,
            confirmationNo: booking.confirmationNo,
            vehicleGroup: booking.carGroup.isEmpty ? arac.kategori : booking.carGroup,
            eventDateTime: exit.exitTarihi,
            plannedReturnDate: exit.plannedReturnAt ?? booking.dateTo,
            assignedPlate: arac.plakaFormatli,
            isUnassigned: false,
            insurance: booking.insurance,
            rentalDays: snap?.rentalDays ?? booking.rentalDays,
            checkoutMileage: exit.km ?? fleetMileageHint(forPlate: arac.plakaFormatli),
            irn: booking.irn
        )
    }

    private static func displayDocNo(for row: WheelSysJournalRow) -> String {
        let main = row.mainDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !main.isEmpty { return main }
        return (row.linkedResCode ?? row.resCode).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPersonName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-" else { return nil }
        return trimmed
    }

    private static func plateMatchedCheckoutRow(
        plateNorm: String,
        in snapshot: WheelSysJournalSnapshot
    ) -> WheelSysJournalRow? {
        WheelSysJournalRowMapper.checkoutRows(from: snapshot).first { row in
            let p = row.plate.trimmingCharacters(in: .whitespacesAndNewlines)
            return !p.isEmpty && WheelSysPlateNormalizer.canonical(p) == plateNorm
        }
    }
}
