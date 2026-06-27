import Foundation

/// Plate scan → active rental resolution for return / check-in.
enum WheelSysPlateScannerService {

    static func normalizePlate(_ rawPlate: String) -> String {
        WheelSysPlateNormalizer.canonical(rawPlate)
    }

    /// Search journal check-ins, daily view check-ins, then cached fleet for an active return.
    /// Never loads live fleet chart on the scan path — avoids slow WebView errors during plate scan.
    static func findActiveRentalsForPlate(
        plate rawPlate: String,
        franchiseId: String,
        selectedDate: String,
        station: String = "ZRH",
        journalSnapshot: WheelSysJournalSnapshot? = nil
    ) async -> [WheelSysReturnCandidate] {
        let plate = normalizePlate(rawPlate)
        guard !plate.isEmpty else { return [] }

        var candidates: [WheelSysReturnCandidate] = []
        var seenRentalIds = Set<Int>()

        func appendUnique(_ candidate: WheelSysReturnCandidate) {
            guard candidate.rentalEntityId > 0 else { return }
            guard !seenRentalIds.contains(candidate.rentalEntityId) else { return }
            seenRentalIds.insert(candidate.rentalEntityId)
            candidates.append(candidate)
        }

        let snapshot: WheelSysJournalSnapshot?
        let daily: WheelSysDailyViewAllResult?

        if let journalSnapshot {
            snapshot = journalSnapshot
            daily = try? await WheelSysDailyViewService.loadAll(
                franchiseId: franchiseId,
                selectedDate: selectedDate,
                station: station
            )
        } else {
            async let snapshotTask = WheelSysJournalAPIService.loadSnapshot(
                franchiseId: franchiseId,
                selectedDate: selectedDate,
                station: station
            )
            async let dailyTask = WheelSysDailyViewService.loadAll(
                franchiseId: franchiseId,
                selectedDate: selectedDate,
                station: station
            )
            snapshot = try? await snapshotTask
            daily = try? await dailyTask
        }

        if let snapshot {
            for row in WheelSysJournalService.getReturnCandidates(from: snapshot) {
                if row.normalizedPlate == plate, let rentalId = row.rentalEntityId, rentalId > 0 {
                    appendUnique(candidateFromJournalCheckin(row))
                }
            }
        }

        if let daily {
            for row in daily.checkins where row.normalizedPlate == plate {
                if let rentalId = row.rentalEntityId, rentalId > 0 {
                    appendUnique(candidateFromDailyCheckin(row))
                }
            }

            for row in daily.checkouts where row.normalizedPlate == plate {
                if let rentalId = row.rentalEntityId, rentalId > 0 {
                    appendUnique(candidateFromDailyCheckout(row))
                }
            }
        }

        if candidates.isEmpty {
            let fleetCandidate = await candidateFromCachedFleet(
                rawPlate: rawPlate,
                normalizedPlate: plate,
                station: station
            )
            if let fleetCandidate {
                appendUnique(fleetCandidate)
            }
        }

        return candidates
    }

    static func findActiveRentalForPlate(
        plate: String,
        franchiseId: String,
        selectedDate: String,
        station: String = "ZRH",
        journalSnapshot: WheelSysJournalSnapshot? = nil
    ) async -> WheelSysReturnCandidate? {
        let all = await findActiveRentalsForPlate(
            plate: plate,
            franchiseId: franchiseId,
            selectedDate: selectedDate,
            station: station,
            journalSnapshot: journalSnapshot
        )
        return all.count == 1 ? all.first : nil
    }

    // MARK: - Fleet cache (no live fleet chart on scan)

    @MainActor
    private static func candidateFromCachedFleet(
        rawPlate: String,
        normalizedPlate plate: String,
        station: String
    ) -> WheelSysReturnCandidate? {
        WheelSysVehicleFleetStatusStore.shared.bootstrapFromDiskIfNeeded()
        guard let fleet = WheelSysVehicleFleetStatusStore.shared.fleet,
              let rentalId = WheelSysCheckinService.findRentalEntityId(in: fleet, for: rawPlate) else {
            return nil
        }
        let vehicle = fleet.vehicles.first {
            WheelSysPlateNormalizer.equal($0.plate, rawPlate)
        }
        return WheelSysReturnCandidate(
            id: "fleet-cache-\(rentalId)",
            rentalEntityId: rentalId,
            vehicleEntityId: vehicle?.vehicleId,
            plate: vehicle?.plate ?? rawPlate,
            normalizedPlate: plate,
            resNo: "",
            raNo: nil,
            irn: nil,
            driverName: fleet.allEvents.first(where: { $0.rentalEntityId == rentalId })?.driverName ?? "",
            model: vehicle?.model,
            station: vehicle?.station ?? station,
            dateFrom: nil,
            dateTo: nil,
            checkoutMileage: vehicle?.mileage,
            checkoutFuel: nil,
            source: "fleet_cache"
        )
    }

    // MARK: - Mappers

    private static func candidateFromJournalCheckin(_ row: WheelSysJournalCheckin) -> WheelSysReturnCandidate {
        WheelSysReturnCandidate(
            id: "journal-\(row.id)",
            rentalEntityId: row.rentalEntityId ?? 0,
            vehicleEntityId: row.vehicleEntityId,
            plate: row.plate,
            normalizedPlate: row.normalizedPlate,
            resNo: row.reservationCode.isEmpty ? row.resNo : row.reservationCode,
            raNo: row.rentalAgreementDocNo.isEmpty ? nil : row.rentalAgreementDocNo,
            irn: row.confirmationNo.isEmpty ? nil : row.confirmationNo,
            driverName: row.driverName,
            model: row.model,
            station: row.stationFrom ?? "ZRH",
            dateFrom: row.dateFrom,
            dateTo: row.dateTo,
            checkoutMileage: row.mileage,
            checkoutFuel: row.fuel,
            source: "journal_checkins"
        )
    }

    private static func candidateFromDailyCheckin(_ row: WheelSysDailyViewCheckin) -> WheelSysReturnCandidate {
        let doc = row.displayDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let resFromRaw = row.rawFields.first { key, value in
            ["resNo", "ResNo", "resno", "resDocNo"].contains(key) && WheelSysResCode.isReservationCode(value)
        }?.value
        let resNo: String = {
            if WheelSysResCode.isReservationCode(doc) { return doc }
            if let raw = resFromRaw, WheelSysResCode.isReservationCode(raw) { return raw }
            return ""
        }()
        return WheelSysReturnCandidate(
            id: row.id,
            rentalEntityId: row.rentalEntityId ?? 0,
            vehicleEntityId: row.vehicleEntityId,
            plate: row.plate,
            normalizedPlate: row.normalizedPlate,
            resNo: resNo,
            raNo: doc.uppercased().hasPrefix("RNT") ? doc : nil,
            irn: row.voucherNo,
            driverName: row.driverName,
            model: nil,
            station: "ZRH",
            dateFrom: row.dateFrom,
            dateTo: row.dateTo,
            checkoutMileage: row.mileage,
            checkoutFuel: row.fuel,
            source: "dailyview_checkins"
        )
    }

    private static func candidateFromDailyCheckout(_ row: WheelSysDailyViewCheckout) -> WheelSysReturnCandidate {
        let doc = row.displayDocNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let conf = row.confirmationNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let resNo: String = {
            if WheelSysResCode.isReservationCode(doc) { return doc }
            if WheelSysResCode.isReservationCode(conf) { return conf }
            return ""
        }()
        return WheelSysReturnCandidate(
            id: row.id,
            rentalEntityId: row.rentalEntityId ?? 0,
            vehicleEntityId: nil,
            plate: row.plate,
            normalizedPlate: row.normalizedPlate,
            resNo: resNo,
            raNo: doc.uppercased().hasPrefix("RNT") ? doc : nil,
            irn: row.irn,
            driverName: row.driverName,
            model: nil,
            station: "ZRH",
            dateFrom: row.dateFrom,
            dateTo: row.dateTo,
            checkoutMileage: nil,
            checkoutFuel: row.fuel,
            source: "dailyview_checkouts"
        )
    }
}
