import UIKit

/// Switzerland (CH) damage report PDF.
/// Delegates to the shared Green Motion branded template (`SwissReportPDFTemplate`)
/// so app + web produce the same document. Branch name is dynamic (no hardcoded city).
enum SwitzerlandDamageReportPDFLayout {

    static func render(
        hasar: HasarKaydi,
        aracPlaka: String,
        vehicleBrand: String,
        vehicleModel: String,
        resCodeLine: String,
        resLabel: String,
        images: [(image: UIImage, isHandover: Bool)],
        branchName: String? = nil
    ) -> Data? {
        let branch = SwissReportPDFTemplate.branchName(
            franchiseId: hasar.franchiseId,
            explicit: branchName
        )

        let zone = (hasar.damageZone ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let type = (hasar.damageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return SwissReportPDFTemplate.renderDamage(
            branch: branch,
            plate: aracPlaka,
            make: vehicleBrand,
            model: vehicleModel,
            resLabel: resLabel,
            resCode: resCodeLine,
            handoverDate: hasar.handoverTarihi,
            returnDate: hasar.tarih,
            damageLocation: zone.isEmpty ? "—" : zone,
            damageType: type.isEmpty ? "Damage" : type,
            photos: images.map(\.image)
        )
    }
}
