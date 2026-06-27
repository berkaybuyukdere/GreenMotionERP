import Foundation

/// Builds CH return prefill the same way as Journal → Return: journal/daily candidates,
/// then enriches from live rental preview / pre-check-in context (authoritative km / customer / RES).
enum WheelSysReturnPrefillResolver {

    @MainActor
    static func resolveForVehicleReturn(
        arac: Arac,
        franchiseId: String,
        linkedExit: ExitIslemi? = nil
    ) async -> WheelSysReturnOperationPrefill? {
        let fid = franchiseId.uppercased()
        let selectedDate = WheelSysJournalService.formatZurichDay(WheelSysJournalService.todayZurich())

        await WheelSysVehicleDamageService.ensureSessionReady(franchiseId: fid)
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        await WheelSysVehicleFleetStatusStore.shared.refreshIfNeeded()

        let candidates = await WheelSysPlateScannerService.findActiveRentalsForPlate(
            plate: arac.plaka,
            franchiseId: fid,
            selectedDate: selectedDate
        )

        let storedRentalId = arac.wheelsysRentalEntityId ?? 0
        let candidate = candidates.first(where: { $0.rentalEntityId == storedRentalId && storedRentalId > 0 })
            ?? candidates.first

        let fleetVehicle = WheelSysVehicleFleetStatusStore.shared.fleetVehicle(for: arac)
        let base: WheelSysReturnOperationPrefill

        if let candidate, candidate.rentalEntityId > 0 {
            base = WheelSysJournalService.buildReturnPrefill(
                from: candidate,
                entryPoint: .plateScanReturn
            )
        } else if storedRentalId > 0 {
            base = WheelSysReturnOperationPrefill(
                rentalEntityId: storedRentalId,
                resNo: "",
                raNo: nil,
                confirmationNo: nil,
                driverName: "",
                customerEmail: nil,
                vehicleEntityId: arac.wheelsysVehicleId ?? fleetVehicle?.vehicleId,
                checkoutMileage: fleetVehicle?.mileage,
                checkoutFuel: 8,
                checkinMileageHint: fleetVehicle?.mileage,
                checkinFuelHint: 8,
                dateFrom: linkedExit?.exitTarihi,
                dateTo: linkedExit?.plannedReturnAt ?? linkedExit?.exitTarihi,
                entryPoint: .plateScanReturn
            )
        } else {
            return nil
        }

        let previewEnriched = await enrichFromRentalPreview(
            base: base,
            franchiseId: fid
        )
        return await enrichFromPrecheckinContext(
            base: previewEnriched,
            franchiseId: fid,
            plate: arac.plaka
        )
    }

    private static func enrichFromRentalPreview(
        base: WheelSysReturnOperationPrefill,
        franchiseId: String
    ) async -> WheelSysReturnOperationPrefill {
        guard base.rentalEntityId > 0 else { return base }

        let preview: WheelSysRentalPreview
        do {
            preview = try await WheelSysCheckinService.loadPreview(
                franchiseId: franchiseId,
                entityId: String(base.rentalEntityId),
                expectedResNo: nil,
                lockEntityId: true
            )
        } catch {
            WheelSysDebug.warnCH(
                franchiseId: franchiseId,
                "ReturnPrefill",
                "preview enrich failed rentalId=\(base.rentalEntityId): \(error.localizedDescription)"
            )
            return base
        }

        let customerName = [preview.customerFirstName, preview.customerLastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let resNo = preview.resNo.isEmpty ? base.resNo : preview.resNo
        let raNo = preview.raNo.isEmpty ? base.raNo : preview.raNo
        let checkoutKm = preview.mileageFrom > 0 ? preview.mileageFrom : base.checkoutMileage
        let checkoutFuel = preview.fuelFrom > 0 ? preview.fuelFrom : base.checkoutFuel
        let checkinKm = WheelSysReturnMileageFuel.effectiveCheckinMileage(
            preview.mileageTo > 0 ? preview.mileageTo : nil
        ) ?? WheelSysReturnMileageFuel.effectiveCheckinMileage(base.checkinMileageHint)
        let checkinFuel = WheelSysReturnMileageFuel.effectiveCheckinFuel(
            preview.fuelTo > 0 ? preview.fuelTo : nil,
            checkout: checkoutFuel
        ) ?? WheelSysReturnMileageFuel.effectiveCheckinFuel(base.checkinFuelHint, checkout: checkoutFuel)
        let vehicleId = preview.vehicleEntityId.isEmpty ? base.vehicleEntityId : preview.vehicleEntityId

        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "ReturnPrefill",
            "preview enriched rentalId=\(base.rentalEntityId) res=\(resNo) " +
            "checkoutKm=\(checkoutKm ?? 0) customer=\(customerName)"
        )

        return WheelSysReturnOperationPrefill(
            rentalEntityId: base.rentalEntityId,
            resNo: resNo,
            raNo: raNo,
            confirmationNo: base.confirmationNo,
            driverName: customerName.isEmpty ? base.driverName : customerName,
            customerEmail: base.customerEmail,
            vehicleEntityId: vehicleId,
            checkoutMileage: checkoutKm,
            checkoutFuel: checkoutFuel,
            checkinMileageHint: checkinKm,
            checkinFuelHint: checkinFuel,
            dateFrom: base.dateFrom,
            dateTo: base.dateTo,
            entryPoint: base.entryPoint
        )
    }

    private static func enrichFromPrecheckinContext(
        base: WheelSysReturnOperationPrefill,
        franchiseId: String,
        plate: String
    ) async -> WheelSysReturnOperationPrefill {
        guard base.rentalEntityId > 0 else { return base }

        let ctx: WheelSysPrecheckinContext
        do {
            ctx = try await WheelSysPrecheckinService.fetchContext(
                franchiseId: franchiseId,
                rentalId: base.rentalEntityId,
                resNo: base.resNo.isEmpty ? nil : base.resNo,
                rntNo: base.raNo,
                plateNo: plate
            )
        } catch {
            WheelSysDebug.warnCH(
                franchiseId: franchiseId,
                "ReturnPrefill",
                "precheckin context enrich failed rentalId=\(base.rentalEntityId): \(error.localizedDescription)"
            )
            return base
        }

        let customerName = resolvedCustomerName(from: ctx.customer)
        let email = ctx.customer.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resNo = trimmedOrNil(ctx.rental.resNo) ?? base.resNo
        let raNo = trimmedOrNil(ctx.rental.rntNo) ?? base.raNo
        let checkoutKm = ctx.mileageFuel.checkoutMileage ?? base.checkoutMileage
        let checkoutFuel = ctx.mileageFuel.checkoutFuel ?? base.checkoutFuel
        let fleetHintKm = await MainActor.run {
            WheelSysVehicleFleetStatusStore.shared.fleetVehicle(forPlate: plate)?.mileage
        }
        let checkinKm = WheelSysReturnMileageFuel.effectiveCheckinMileage(ctx.mileageFuel.currentReturnMileage)
            ?? WheelSysReturnMileageFuel.effectiveCheckinMileage(base.checkinMileageHint)
            ?? WheelSysReturnMileageFuel.effectiveCheckinMileage(fleetHintKm)
        let checkinFuel = WheelSysReturnMileageFuel.effectiveCheckinFuel(
            ctx.mileageFuel.currentReturnFuel,
            checkout: checkoutFuel
        ) ?? WheelSysReturnMileageFuel.effectiveCheckinFuel(base.checkinFuelHint, checkout: checkoutFuel)
        let vehicleId = ctx.vehicle.vehicleId.map(String.init)
            ?? base.vehicleEntityId

        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "ReturnPrefill",
            "enriched rentalId=\(base.rentalEntityId) customer=\(customerName) " +
            "checkoutKm=\(checkoutKm ?? 0) checkinKm=\(checkinKm ?? 0) res=\(resNo)"
        )

        return WheelSysReturnOperationPrefill(
            rentalEntityId: base.rentalEntityId,
            resNo: resNo,
            raNo: raNo,
            confirmationNo: trimmedOrNil(ctx.rental.irn) ?? base.confirmationNo,
            driverName: customerName.isEmpty ? base.driverName : customerName,
            customerEmail: (email?.isEmpty == false) ? email : base.customerEmail,
            vehicleEntityId: vehicleId,
            checkoutMileage: checkoutKm,
            checkoutFuel: checkoutFuel,
            checkinMileageHint: checkinKm,
            checkinFuelHint: checkinFuel,
            dateFrom: base.dateFrom,
            dateTo: base.dateTo,
            entryPoint: base.entryPoint
        )
    }

    private static func resolvedCustomerName(from customer: WheelSysPrecheckinCustomer) -> String {
        let full = customer.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        return [customer.firstName, customer.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
