import CoreGraphics
import Foundation

@MainActor
final class ConditionFormViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var allDamages: [HasarKaydi]

    /// ID of the currently highlighted region overlay on the canvas.
    @Published var selectedRegionId: String?
    /// Which VehicleViewBlock the draft marker is placed in.
    @Published var draftViewBlockId: String?
    /// Normalised (0–1) X within the current draftViewBlock.
    @Published var pointXNorm: Double = 0.5
    /// Normalised (0–1) Y within the current draftViewBlock.
    @Published var pointYNorm: Double = 0.5

    /// The damage record currently loaded into the editor (nil = new record mode).
    @Published var selectedDamageId: UUID?

    /// Records the user has checked for inclusion in the condition form / PDF export.
    @Published var conditionFormRecordIds: Set<UUID> = []
    @Published var selectionLockedToRecordId: UUID?

    // Editor fields
    @Published var notes: String = ""
    @Published var damageType: String
    @Published var damageSeverity: String
    @Published var reservationCode: String = ""
    @Published var kmValue: String = ""

    let arac: Arac

    static let damageTypes = [
        "Scratch/Scuff",
        "Parking Dent",
        "Dent",
        "Broken/Damaged",
        "Missing",
        "Paint Damage",
        "Panel Replacement",
        "Tire Damage",
        "Rim Damage",
        "Missing Part"
    ]
    static let severityLevels = ["Small", "Medium", "Large", "Any"]
    static let legalInformation: [String] = [
        "By signing this form, you confirm the following:",
        "You have been made aware of your excess/liability for the duration of your hire and have been presented with waiver reduction options, enabling you to make an informed decision before taking the vehicle.",
        "You have been instructed to inspect the vehicle thoroughly, including both the exterior (wheels and tyres included) and interior, and to take photographs of its condition before driving away. Any additional damage not already noted should be documented and submitted.",
        "If you collect the vehicle in conditions where visibility is limited (such as at night, or when it is wet or dark), you may reinspect the vehicle and send any additional photographs of damage within 2 hours of your rental start time. Submissions after this time may not be considered.",
        "If you return the vehicle outside of office hours using a drop box, you remain responsible for the vehicle’s condition until it is inspected when the office reopens.",
        "On return, you may choose to wait 30 minutes to 1 hour while the vehicle is cleaned and inspected in your presence. If you choose not to wait, you accept that any changes in the condition of the vehicle identified during the final inspection (after cleaning) will be communicated to you within 4 working days of the return.",
        "You are liable for all damages unless you are covered by a Green Motion insurance product. Damage costs will be deducted from your deposit, and if the amount exceeds your deposit, the difference will be charged or invoiced to you.",
        "A processing fee of CHF 100 will apply in the event of damage."
    ]
    static let typeConditionReference: [String] = [
        "Rear Bumper - Scratch/Scuff - Small/Medium/Large",
        "Rear Bumper - Parking Dent",
        "Front Wing - Scratch/Scuff",
        "Front Wing - Parking Dent",
        "Door (Front/Rear) - Scratch/Scuff",
        "Door (Front/Rear) - Parking Dent",
        "Roof - Any Dent",
        "Mirror Housing - Scratch/Scuff + Paint Damage"
    ]
    /// Unique component names extracted from DamageMatrix (Type and Condition column).
    static let uniqueDamageMatrixComponents: [String] = [
        "A/B/C Pillar", "Aerial", "Badge", "Bonnet", "Bumper Moulding", "Bumper skirt",
        "Child Seat", "Diamond Cut/polished Alloy", "Door (Front/Rear)", "Door Glass",
        "Door Handle", "Door Seal", "Front Bumper", "Front Fog Lamp", "Front Grille",
        "Front Wing", "Fuel Flap", "Headlight (Right/Left)", "Indicator", "Indicator (Right/Left)",
        "Internal Damage", "Left Front skirt (Right/Left)", "Mirror Housing", "Mirror glass",
        "Moulding", "Number Plate", "Painted Alloy/Steel Wheel", "Plastic Wheel Trim",
        "Rear Badge", "Rear Boot lock", "Rear Bumper", "Rear Fog Lamp", "Rear Light",
        "Rear Screen", "Rear Spoiler", "Rear Wing", "Rear and Sliding Doors",
        "Rear plate light", "Rear valance", "Repeater", "Right Front skirt", "Roof", "Sill",
        "Tailgate/Boot Lid", "Tow Eye Cover", "Tyres", "Undercarriage", "VAN",
        "Wheel Arch / Door Apeture", "Windscreen", "Wing Trims", "Wiper Arm", "Wiper Blades"
    ]
    static let damageMatrixStats: [String] = [
        "Total Type+Condition rows analyzed: 256",
        "Unique component names: 53",
        "Action distribution: Repair 167, Assess 71, Replace 15, Do nothing 3",
        "Condition distribution: Scratch/Scuff 54, Dent 46, Parking Dent 26, Broken/Damaged 33, Missing 30, Panel Replacement 15"
    ]

    // MARK: - Init

    init(arac: Arac) {
        self.arac          = arac
        self.allDamages    = arac.hasarKayitlari
        self.damageType    = Self.damageTypes.first  ?? "Scratch"
        self.damageSeverity = Self.severityLevels.first ?? "Small"
        self.kmValue       = String(arac.hasarKayitlari.map(\.km).max() ?? 0)
    }

    // MARK: - Computed Properties

    /// Draft marker position in absolute ref-space, derived from the current view block + normalised coords.
    var draftRefX: CGFloat {
        guard let blockId = draftViewBlockId,
              let block   = VehicleViewBlock.block(id: blockId) else {
            return VehicleRef.canvasWidth / 2
        }
        return block.normToRef(CGPoint(x: pointXNorm, y: pointYNorm)).x
    }

    var draftRefY: CGFloat {
        guard let blockId = draftViewBlockId,
              let block   = VehicleViewBlock.block(id: blockId) else {
            return VehicleRef.canvasHeight / 2
        }
        return block.normToRef(CGPoint(x: pointXNorm, y: pointYNorm)).y
    }

    /// Saved condition-form damages (have a canvas marker), sorted by marker number.
    var conditionDamages: [HasarKaydi] {
        allDamages
            .filter { $0.isConditionForm == true }
            .sorted { ($0.markerNumber ?? 0) < ($1.markerNumber ?? 0) }
    }

    var nextMarkerNumber: Int {
        (conditionDamages.compactMap(\.markerNumber).max() ?? 0) + 1
    }

    var selectedDamage: HasarKaydi? {
        guard let id = selectedDamageId else { return nil }
        return allDamages.first(where: { $0.id == id })
    }

    // MARK: - Canvas Interaction

    /// Called when the user taps the canvas at absolute ref-space coords.
    func handleCanvasTap(refX: CGFloat, refY: CGFloat) {
        let block = VehicleViewBlock.fullCanvas
        draftViewBlockId = block.id
        let clamped = CGPoint(
            x: refX.clamped(0, VehicleRef.canvasWidth),
            y: refY.clamped(0, VehicleRef.canvasHeight)
        )
        let norm = block.refToNorm(clamped)
        pointXNorm = Double(norm.x.clamped(0, 1))
        pointYNorm = Double(norm.y.clamped(0, 1))
    }

    /// Called while the draft marker is being dragged; absolute ref-space coords.
    func handleDraftDrag(refX: CGFloat, refY: CGFloat) {
        guard let blockId = draftViewBlockId,
              let block   = VehicleViewBlock.block(id: blockId) else { return }
        let clamped = CGPoint(
            x: refX.clamped(block.refX, block.refX + block.refW),
            y: refY.clamped(block.refY, block.refY + block.refH)
        )
        let norm = block.refToNorm(clamped)
        pointXNorm = Double(norm.x.clamped(0, 1))
        pointYNorm = Double(norm.y.clamped(0, 1))
    }

    // MARK: - Record Selection (Checkbox List)

    func isChecked(_ id: UUID) -> Bool { conditionFormRecordIds.contains(id) }

    func toggleCheck(_ id: UUID) {
        if let locked = selectionLockedToRecordId, locked != id {
            return
        }
        if conditionFormRecordIds.contains(id) {
            conditionFormRecordIds.remove(id)
            if selectedDamageId == id { selectedDamageId = nil }
        } else {
            conditionFormRecordIds.insert(id)
        }
    }

    func selectAllRecords(_ damages: [HasarKaydi]) {
        conditionFormRecordIds = Set(damages.map { $0.id })
    }

    func deselectAllRecords() {
        if selectionLockedToRecordId != nil { return }
        conditionFormRecordIds.removeAll()
        selectedDamageId = nil
    }

    // MARK: - Editor Population

    /// Load an existing damage record into the editor for canvas placement.
    func selectDamage(_ hasar: HasarKaydi) {
        selectedDamageId  = hasar.id
        notes             = hasar.notlar
        damageType        = hasar.damageType ?? damageType
        damageSeverity    = hasar.damageSeverity ?? damageSeverity
        reservationCode   = hasar.resKodu
        kmValue           = String(hasar.km)
        selectedRegionId  = hasar.conditionRegionId ?? hasar.damageZone
        draftViewBlockId  = hasar.conditionViewBlockId

        if let nx = hasar.conditionPointX, let ny = hasar.conditionPointY {
            pointXNorm = nx
            pointYNorm = ny
        } else if let regionId = selectedRegionId {
            selectRegionCenter(regionId)
        } else {
            // Default draft to canvas centre
            draftViewBlockId = VehicleViewBlock.centerTop.id
            pointXNorm = 0.5
            pointYNorm = 0.5
        }
    }

    func selectRegionCenter(_ regionId: String) {
        selectedRegionId = regionId
        guard let region = VehicleRegionDef.region(id: regionId),
              let block  = VehicleViewBlock.block(id: region.viewBlockId) else { return }
        draftViewBlockId = block.id
        let norm = block.refToNorm(region.refCenter)
        pointXNorm = Double(norm.x.clamped(0, 1))
        pointYNorm = Double(norm.y.clamped(0, 1))
    }

    func clearSelection() {
        selectedDamageId  = nil
        selectedRegionId  = nil
        draftViewBlockId  = nil
        selectionLockedToRecordId = nil
        notes             = ""
        damageType        = Self.damageTypes.first  ?? "Scratch"
        damageSeverity    = Self.severityLevels.first ?? "Small"
        reservationCode   = ""
    }

    // MARK: - Save

    /// Updates the selected existing record as a condition-form mapped marker.
    /// New record creation is intentionally disabled to prevent accidental duplicates.
    func registerRecord(using aracViewModel: AracViewModel, completion: @escaping (Bool) -> Void) {
        guard selectedDamage != nil else {
            completion(false)
            return
        }
        if draftViewBlockId == nil {
            draftViewBlockId = VehicleViewBlock.fullCanvas.id
            pointXNorm = 0.5
            pointYNorm = 0.5
        }
        let safeKM   = Int(kmValue) ?? 0
        let res      = reservationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let markerNo = selectedDamage?.markerNumber ?? nextMarkerNumber
        let resolvedRes = res.isEmpty ? "CF-\(markerNo)" : res
        let photos   = selectedDamage?.fotograflar ?? []

        var merged = HasarKaydi(
            aracId:              arac.id,
            aracPlaka:           arac.plaka,
            tarih:               selectedDamage?.tarih ?? Date(),
            handoverTarihi:      selectedDamage?.handoverTarihi ?? Date(),
            resKodu:             resolvedRes,
            km:                  safeKM,
            fotograflar:         photos,
            durum:               selectedDamage?.durum ?? .inProgress,
            notlar:              notes,
            status:              selectedDamage?.status ?? .completed,
            createdBy:           selectedDamage?.createdBy,
            franchiseId:         arac.franchiseId,
            damageZone:          selectedRegionId ?? selectedDamage?.damageZone,
            isConditionForm:     true,
            conditionRegionId:   selectedRegionId,
            conditionPointX:     pointXNorm,
            conditionPointY:     pointYNorm,
            damageType:          damageType,
            damageSeverity:      damageSeverity,
            markerNumber:        markerNo,
            conditionViewBlockId: draftViewBlockId
        )
        merged.id = selectedDamage?.id ?? UUID()

        aracViewModel.hasarGuncelle(aracId: arac.id, hasar: merged)

        upsertLocalDamage(merged)
        // After register, clear list selection state as requested.
        conditionFormRecordIds.removeAll()
        selectionLockedToRecordId = nil
        selectedDamageId = nil
        completion(true)
    }

    // MARK: - Sync

    func sync(with currentDamages: [HasarKaydi]) {
        allDamages = currentDamages
    }

    // MARK: - Private Helpers

    private func upsertLocalDamage(_ d: HasarKaydi) {
        if let idx = allDamages.firstIndex(where: { $0.id == d.id }) {
            allDamages[idx] = d
        } else {
            allDamages.append(d)
        }
    }

    func unmapDamageLocally(_ id: UUID) {
        if let idx = allDamages.firstIndex(where: { $0.id == id }) {
            allDamages[idx].isConditionForm = false
            allDamages[idx].conditionRegionId = nil
            allDamages[idx].conditionPointX = nil
            allDamages[idx].conditionPointY = nil
            allDamages[idx].conditionViewBlockId = nil
            allDamages[idx].markerNumber = nil
            allDamages[idx].damageZone = nil
        }
        conditionFormRecordIds.remove(id)
        if selectedDamageId == id {
            selectedDamageId = nil
        }
    }

    private func activeBlockIdForPlacement() -> String {
        if let regionId = selectedRegionId,
           let region = VehicleRegionDef.region(id: regionId) {
            return region.viewBlockId
        }
        if let draftViewBlockId {
            return draftViewBlockId
        }
        return VehicleViewBlock.centerTop.id
    }
}

// MARK: - CGFloat clamping helper (file-private)
private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        Swift.max(lo, Swift.min(hi, self))
    }
}
