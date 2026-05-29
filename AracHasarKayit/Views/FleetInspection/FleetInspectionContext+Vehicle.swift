import UIKit

extension FleetInspectionContext {
    /// Live rental inspection context from vehicle detail (check-out / return history).
    static func fromVehicle(
        arac: Arac,
        exits: [ExitIslemi],
        returns: [IadeIslemi],
        operatorName: String
    ) -> FleetInspectionContext {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.dateFormat = "dd MMM yyyy"
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "en_GB")
        tf.dateFormat = "HH:mm"

        let sortedExits = exits.sorted { max($0.createdAt, $0.exitTarihi) > max($1.createdAt, $1.exitTarihi) }
        let sortedReturns = returns.sorted { max($0.createdAt, $0.iadeTarihi) > max($1.createdAt, $1.iadeTarihi) }

        let latestExit = sortedExits.first
        let latestReturn = sortedReturns.first

        let lastReturnRecency = sortedReturns
            .filter { $0.status == .completed }
            .map { max($0.createdAt, $0.iadeTarihi) }
            .max()

        let openExit: ExitIslemi? = {
            guard let ex = latestExit, ex.status == .completed || ex.status == .parked else { return nil }
            let handover = max(ex.createdAt, ex.exitTarihi)
            if let cutoff = lastReturnRecency, handover <= cutoff { return nil }
            return ex
        }()

        let returnAfterOpen: IadeIslemi? = {
            guard let ex = openExit else { return latestReturn }
            let handover = max(ex.createdAt, ex.exitTarihi)
            return sortedReturns.first { max($0.createdAt, $0.iadeTarihi) > handover }
        }()

        let pendingReturn = openExit != nil && (returnAfterOpen == nil || returnAfterOpen?.status != .completed)

        let exitDate = openExit.map { max($0.createdAt, $0.exitTarihi) } ?? latestExit.map { max($0.createdAt, $0.exitTarihi) }
        let handoverDateStr = exitDate.map { df.string(from: $0) } ?? "—"
        let handoverTimeStr = exitDate.map { tf.string(from: $0) } ?? "—"

        let returnDate = returnAfterOpen.map { max($0.createdAt, $0.iadeTarihi) }
        let returnDateStr = returnDate.map { df.string(from: $0) } ?? "—"
        let returnTimeStr = returnDate.map { tf.string(from: $0) } ?? "—"

        let resCode = openExit?.resKodu ?? latestExit?.resKodu ?? ""
        let customerName = [
            openExit?.customerFirstName ?? latestExit?.customerFirstName,
            openExit?.customerLastName ?? latestExit?.customerLastName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        let handoverKm = openExit?.km.map { "\($0) km" } ?? latestExit?.km.map { "\($0) km" } ?? "—"
        let returnKm = returnAfterOpen?.km.map { "\($0) km" } ?? "—"
        let fuelHO = openExit?.yakitSeviyesi ?? latestExit?.yakitSeviyesi ?? "—"
        let fuelRT = returnAfterOpen?.yakitSeviyesi ?? "—"

        let rentalStatus: String = {
            if pendingReturn { return "On Rent" }
            if latestReturn?.status == .completed { return "Returned" }
            return "Available"
        }()

        let handoverStatus = openExit != nil ? "Customer Accepted" : (latestExit == nil ? "—" : "—")
        let returnStatus = pendingReturn ? "Pending" : (returnAfterOpen?.status == .completed ? "Complete" : "—")
        let returnColor = pendingReturn ? FleetInspectionTheme.accent : FleetInspectionTheme.clearGreen

        let inspId: String = {
            if let ex = openExit ?? latestExit {
                return "INSP-\(ex.id.uuidString.prefix(8).uppercased())"
            }
            return "INSP-\(arac.id.uuidString.prefix(8).uppercased())"
        }()

        let timestamp = exitDate ?? Date()

        return FleetInspectionContext(
            branchName: openExit?.pickUpBranch ?? openExit?.bayiAdi ?? latestExit?.pickUpBranch ?? "—",
            operatorName: operatorName,
            inspectionId: inspId,
            timestampFormatted: "\(df.string(from: timestamp)), \(tf.string(from: timestamp))",
            reservationStatus: pendingReturn ? "Active" : "Closed",
            reservationCode: resCode.isEmpty ? "RES-—" : (resCode.uppercased().hasPrefix("RES") ? resCode : "RES-\(resCode)"),
            rentalAgreementNumber: openExit?.navKodu ?? latestExit?.navKodu ?? "—",
            customerName: customerName.isEmpty ? "—" : customerName,
            customerEmail: openExit?.customerEmail ?? latestExit?.customerEmail ?? "—",
            customerPhone: "—",
            pickupBranch: openExit?.pickUpBranch ?? latestExit?.pickUpBranch ?? "—",
            returnBranch: openExit?.dropOffBranch ?? latestExit?.dropOffBranch ?? "—",
            rentalStatus: rentalStatus,
            paymentStatus: "—",
            depositStatus: "—",
            vehicleBrand: arac.marka,
            vehicleModel: arac.model,
            licensePlate: arac.plaka,
            vehicleGroup: arac.kategori,
            vehicleYear: "—",
            vin: arac.vin ?? "—",
            fuelType: "—",
            transmission: "—",
            color: "—",
            mileageHandover: handoverKm,
            mileageReturn: returnKm,
            fuelHandover: fuelHO,
            fuelReturn: fuelRT,
            handoverDate: handoverDateStr,
            handoverTime: handoverTimeStr,
            handoverOperator: openExit?.createdBy ?? operatorName,
            handoverStatus: handoverStatus,
            handoverOverlayLabel: openExit != nil ? "HANDOVER — \(handoverDateStr), \(handoverTimeStr)" : "HANDOVER — —",
            handoverHeroImage: nil,
            returnDate: returnDateStr,
            returnTime: returnTimeStr,
            returnOperator: returnAfterOpen?.createdBy ?? "—",
            returnStatus: returnStatus,
            returnStatusColor: returnColor,
            returnOverlayLabel: pendingReturn ? "RETURN — pending" : "RETURN — \(returnDateStr), \(returnTimeStr)",
            returnHeroImage: nil,
            photoSlots: FleetInspectionContext.defaultPhotoSlots(handover: [], returnPhotos: []),
            damageRows: FleetInspectionContext.damageRows(from: arac.hasarKayitlari),
            timelineSteps: buildTimeline(
                exitDate: exitDate,
                returnDate: returnDate,
                pendingReturn: pendingReturn,
                operatorName: operatorName,
                handoverDateStr: handoverDateStr,
                handoverTimeStr: handoverTimeStr,
                returnDateStr: returnDateStr,
                returnTimeStr: returnTimeStr,
                returnComplete: returnAfterOpen?.status == .completed
            ),
            vehicle: arac,
            vehicleDamages: arac.hasarKayitlari.sorted { $0.tarih > $1.tarih },
            showsRentalFlowAnimation: pendingReturn
        )
    }

    private static func buildTimeline(
        exitDate: Date?,
        returnDate: Date?,
        pendingReturn: Bool,
        operatorName: String,
        handoverDateStr: String,
        handoverTimeStr: String,
        returnDateStr: String,
        returnTimeStr: String,
        returnComplete: Bool
    ) -> [FleetInspectionTimelineStep] {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_GB")
        df.dateFormat = "dd MMM yyyy"
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "en_GB")
        tf.dateFormat = "HH:mm"

        let createdDate = exitDate.map { Calendar.current.date(byAdding: .hour, value: -2, to: $0) ?? $0 } ?? Date()
        let createdStr = df.string(from: createdDate)
        let createdTime = tf.string(from: createdDate)

        var steps: [FleetInspectionTimelineStep] = [
            .init(title: "Reservation created", date: createdStr, time: createdTime, actor: "System", status: "Done", statusColor: FleetInspectionTheme.clearGreen, isComplete: true),
            .init(title: "Vehicle prepared", date: handoverDateStr, time: handoverTimeStr == "—" ? "—" : handoverTimeStr, actor: "Fleet", status: "Done", statusColor: FleetInspectionTheme.clearGreen, isComplete: exitDate != nil)
        ]

        if exitDate != nil {
            steps.append(.init(title: "Check-out inspection", date: handoverDateStr, time: handoverTimeStr, actor: operatorName, status: "Complete", statusColor: FleetInspectionTheme.clearGreen, isComplete: true))
            steps.append(.init(title: "Customer signature", date: handoverDateStr, time: handoverTimeStr, actor: operatorName, status: "Signed", statusColor: FleetInspectionTheme.clearGreen, isComplete: true))
        }

        if pendingReturn {
            steps.append(.init(title: "Return inspection", date: "—", time: "—", actor: "—", status: "Pending", statusColor: FleetInspectionTheme.accent, isComplete: false))
            steps.append(.init(title: "PDF report", date: "—", time: "—", actor: "—", status: "Waiting", statusColor: FleetInspectionTheme.missingGray, isComplete: false))
        } else if returnComplete {
            steps.append(.init(title: "Return inspection", date: returnDateStr, time: returnTimeStr, actor: operatorName, status: "Complete", statusColor: FleetInspectionTheme.clearGreen, isComplete: true))
            steps.append(.init(title: "PDF report", date: returnDateStr, time: returnTimeStr, actor: "System", status: "Done", statusColor: FleetInspectionTheme.clearGreen, isComplete: true))
        } else {
            steps.append(.init(title: "Return inspection", date: "—", time: "—", actor: "—", status: "Waiting", statusColor: FleetInspectionTheme.missingGray, isComplete: false))
            steps.append(.init(title: "PDF report", date: "—", time: "—", actor: "—", status: "Waiting", statusColor: FleetInspectionTheme.missingGray, isComplete: false))
        }

        return steps
    }

}
