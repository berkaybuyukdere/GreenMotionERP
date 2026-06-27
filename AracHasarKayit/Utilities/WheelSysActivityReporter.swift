import Foundation

/// Central hook for WheelSys operational events: recent activities, live feed, franchise notifications.
enum WheelSysActivityReporter {

    enum Operation: Equatable {
        case precheckin(plate: String, rntNo: String?, resNo: String?, rentalId: Int)
        case checkinSync(plate: String, resNo: String?, km: Int?)
        case noteSaved(plate: String, entityId: String)
        case noteDeleted(plate: String, entityId: String)
        case ntrOpen(plate: String, docNo: String)
        case ntrClose(plate: String, docNo: String?)
        case vehicleAssigned(plate: String, resNo: String?)
        case vehicleRemoved(resNo: String?)
        case vehicleChanged(plate: String, resNo: String?)
    }

    @MainActor
    static func record(
        _ operation: Operation,
        viewModel: AracViewModel?,
        userProfile: UserProfile?
    ) {
        let payload = buildPayload(for: operation)
        if let viewModel {
            viewModel.activityEkle(
                payload.activityType,
                aciklama: payload.activityDescription,
                aracPlaka: payload.plate,
                detayliAciklama: payload.detail
            )
        } else {
            persistActivityDirectly(payload, userProfile: userProfile)
        }

        LiveActivityTracker.shared.record(
            payload.liveKind,
            title: payload.liveTitle,
            subtitle: payload.liveSubtitle,
            plate: payload.plate,
            recordId: payload.recordId,
            userProfile: userProfile,
            force: true
        )

        NotificationManager.shared.sendWheelSysOperationNotification(
            title: payload.notificationTitle,
            body: payload.notificationBody(userName: resolvedUserName(userProfile)),
            plate: payload.plate,
            operationKey: payload.operationKey,
            recordId: payload.recordId
        )
    }

    // MARK: - Payload

    private struct Payload {
        let activityType: ActivityType
        let activityDescription: String
        let detail: String?
        let plate: String?
        let liveKind: LiveActivityKind
        let liveTitle: String
        let liveSubtitle: String
        let notificationTitle: String
        let operationKey: String
        let recordId: String?

        func notificationBody(userName: String) -> String {
            switch activityType {
            case .wheelsysPrecheckin:
                if let plate, !plate.isEmpty {
                    return String(format: "wheelsys.notif.precheckin.body".localized, userName, plate)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysCheckinSync:
                if let plate, !plate.isEmpty {
                    return String(format: "wheelsys.notif.checkin_sync.body".localized, userName, plate)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysNoteSaved:
                if let plate, !plate.isEmpty {
                    return String(format: "wheelsys.notif.note_saved.body".localized, userName, plate)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysNoteDeleted:
                if let plate, !plate.isEmpty {
                    return String(format: "wheelsys.notif.note_deleted.body".localized, userName, plate)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysNtrOpen:
                if let plate, !plate.isEmpty {
                    return String(format: "wheelsys.notif.ntr_open.body".localized, userName, plate)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysNtrClose:
                if let plate, !plate.isEmpty {
                    return String(format: "wheelsys.notif.ntr_close.body".localized, userName, plate)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysVehicleAssigned:
                if let plate, !plate.isEmpty, let res = detail, !res.isEmpty {
                    return String(format: "wheelsys.notif.vehicle_assigned.body".localized, userName, plate, res)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysVehicleRemoved:
                if let res = detail, !res.isEmpty {
                    return String(format: "wheelsys.notif.vehicle_removed.body".localized, userName, res)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            case .wheelsysVehicleChanged:
                if let plate, !plate.isEmpty, let res = detail, !res.isEmpty {
                    return String(format: "wheelsys.notif.vehicle_changed.body".localized, userName, plate, res)
                }
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            default:
                return String(format: "wheelsys.notif.generic.body".localized, userName, activityDescription)
            }
        }
    }

    private static func buildPayload(for operation: Operation) -> Payload {
        switch operation {
        case let .precheckin(plate, rntNo, resNo, rentalId):
            let detail = [rntNo, resNo].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return Payload(
                activityType: .wheelsysPrecheckin,
                activityDescription: String(format: "wheelsys.activity.precheckin".localized, plate),
                detail: detail.isEmpty ? nil : detail,
                plate: plate,
                liveKind: .wheelsysPrecheckin,
                liveTitle: "WheelSys pre-check-in",
                liveSubtitle: detail.isEmpty ? plate : "\(plate) · \(detail)",
                notificationTitle: "wheelsys.notif.precheckin.title".localized,
                operationKey: "precheckin",
                recordId: "rental-\(rentalId)"
            )

        case let .checkinSync(plate, resNo, km):
            let res = resNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let kmPart = km.map { "\($0) km" } ?? ""
            let subtitle = [res, kmPart].filter { !$0.isEmpty }.joined(separator: " · ")
            return Payload(
                activityType: .wheelsysCheckinSync,
                activityDescription: String(format: "wheelsys.activity.checkin_sync".localized, plate),
                detail: res.isEmpty ? kmPart : res,
                plate: plate,
                liveKind: .wheelsysCheckinSync,
                liveTitle: "WheelSys check-in sync",
                liveSubtitle: subtitle.isEmpty ? plate : subtitle,
                notificationTitle: "wheelsys.notif.checkin_sync.title".localized,
                operationKey: "checkin_sync",
                recordId: res.isEmpty ? nil : "res-\(res)"
            )

        case let .noteSaved(plate, entityId):
            return Payload(
                activityType: .wheelsysNoteSaved,
                activityDescription: String(format: "wheelsys.activity.note_saved".localized, plate),
                detail: entityId,
                plate: plate,
                liveKind: .wheelsysNoteSaved,
                liveTitle: "WheelSys note saved",
                liveSubtitle: plate,
                notificationTitle: "wheelsys.notif.note_saved.title".localized,
                operationKey: "note_saved",
                recordId: entityId
            )

        case let .noteDeleted(plate, entityId):
            return Payload(
                activityType: .wheelsysNoteDeleted,
                activityDescription: String(format: "wheelsys.activity.note_deleted".localized, plate),
                detail: entityId,
                plate: plate,
                liveKind: .wheelsysNoteDeleted,
                liveTitle: "WheelSys note deleted",
                liveSubtitle: plate,
                notificationTitle: "wheelsys.notif.note_deleted.title".localized,
                operationKey: "note_deleted",
                recordId: entityId
            )

        case let .ntrOpen(plate, docNo):
            return Payload(
                activityType: .wheelsysNtrOpen,
                activityDescription: String(format: "wheelsys_ntr.activity_open".localized, plate),
                detail: docNo,
                plate: plate,
                liveKind: .wheelsysNtrOpen,
                liveTitle: "WheelSys NTR opened",
                liveSubtitle: docNo,
                notificationTitle: "wheelsys.notif.ntr_open.title".localized,
                operationKey: "ntr_open",
                recordId: docNo
            )

        case let .ntrClose(plate, docNo):
            return Payload(
                activityType: .wheelsysNtrClose,
                activityDescription: String(format: "wheelsys_ntr.activity_close".localized, plate),
                detail: docNo,
                plate: plate,
                liveKind: .wheelsysNtrClose,
                liveTitle: "WheelSys NTR closed",
                liveSubtitle: docNo ?? plate,
                notificationTitle: "wheelsys.notif.ntr_close.title".localized,
                operationKey: "ntr_close",
                recordId: docNo
            )

        case let .vehicleAssigned(plate, resNo):
            let res = resNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Payload(
                activityType: .wheelsysVehicleAssigned,
                activityDescription: res.isEmpty
                    ? String(format: "wheelsys.activity.vehicle_assigned_short".localized, plate)
                    : String(format: "wheelsys.activity.vehicle_assigned".localized, plate, res),
                detail: res.isEmpty ? nil : res,
                plate: plate,
                liveKind: .wheelsysVehicleAssigned,
                liveTitle: "WheelSys vehicle assigned",
                liveSubtitle: res.isEmpty ? plate : "\(plate) · \(res)",
                notificationTitle: "wheelsys.notif.vehicle_assigned.title".localized,
                operationKey: "vehicle_assigned",
                recordId: res.isEmpty ? nil : "res-\(res)"
            )

        case let .vehicleRemoved(resNo):
            let res = resNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Payload(
                activityType: .wheelsysVehicleRemoved,
                activityDescription: res.isEmpty
                    ? "wheelsys.activity.vehicle_removed_short".localized
                    : String(format: "wheelsys.activity.vehicle_removed".localized, res),
                detail: res.isEmpty ? nil : res,
                plate: nil,
                liveKind: .wheelsysVehicleRemoved,
                liveTitle: "WheelSys vehicle removed",
                liveSubtitle: res,
                notificationTitle: "wheelsys.notif.vehicle_removed.title".localized,
                operationKey: "vehicle_removed",
                recordId: res.isEmpty ? nil : "res-\(res)"
            )

        case let .vehicleChanged(plate, resNo):
            let res = resNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Payload(
                activityType: .wheelsysVehicleChanged,
                activityDescription: res.isEmpty
                    ? String(format: "wheelsys.activity.vehicle_changed_short".localized, plate)
                    : String(format: "wheelsys.activity.vehicle_changed".localized, plate, res),
                detail: res.isEmpty ? nil : res,
                plate: plate,
                liveKind: .wheelsysVehicleChanged,
                liveTitle: "WheelSys vehicle changed",
                liveSubtitle: res.isEmpty ? plate : "\(plate) · \(res)",
                notificationTitle: "wheelsys.notif.vehicle_changed.title".localized,
                operationKey: "vehicle_changed",
                recordId: res.isEmpty ? nil : "res-\(res)"
            )
        }
    }

    private static func resolvedUserName(_ userProfile: UserProfile?) -> String {
        if let name = userProfile?.fullName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let display = userProfile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        return "Unknown User"
    }

    private static func persistActivityDirectly(_ payload: Payload, userProfile: UserProfile?) {
        var kullaniciAdi: String?
        var kullaniciEmail: String?
        if let profile = userProfile {
            let display = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            kullaniciEmail = profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
            kullaniciAdi = display.isEmpty ? kullaniciEmail : display
        }
        let activity = Activity(
            tip: payload.activityType,
            aciklama: payload.activityDescription,
            tarih: Date(),
            aracPlaka: payload.plate,
            detayliAciklama: payload.detail,
            kullaniciAdi: kullaniciAdi,
            kullaniciEmail: kullaniciEmail
        )
        FirebaseService.shared.saveActivity(activity) { error in
            if let error {
                print("❌ WheelSys activity save failed: \(error.localizedDescription)")
            }
        }
    }
}
