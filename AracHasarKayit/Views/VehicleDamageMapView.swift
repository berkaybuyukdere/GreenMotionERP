import SwiftUI
import UIKit

// MARK: - Damage Zone Model

enum CarDamageZone: String, Codable, CaseIterable {
    case frontBumper      = "front_bumper"
    case hood             = "hood"
    case windshield       = "windshield"
    case leftMirror       = "left_mirror"
    case rightMirror      = "right_mirror"
    case roof             = "roof"
    case rearWindow       = "rear_window"
    case trunk            = "trunk"
    case rearBumper       = "rear_bumper"
    case leftFrontFender  = "left_front_fender"
    case leftFrontDoor    = "left_front_door"
    case leftRearDoor     = "left_rear_door"
    case leftRearFender   = "left_rear_fender"
    case rightFrontFender = "right_front_fender"
    case rightFrontDoor   = "right_front_door"
    case rightRearDoor    = "right_rear_door"
    case rightRearFender  = "right_rear_fender"
    case underbody        = "underbody"
    case interior         = "interior"

    var displayName: String {
        switch self {
        case .frontBumper:      return "Front Bumper"
        case .hood:             return "Hood"
        case .windshield:       return "Windshield"
        case .leftMirror:       return "Left Mirror"
        case .rightMirror:      return "Right Mirror"
        case .roof:             return "Roof"
        case .rearWindow:       return "Rear Window"
        case .trunk:            return "Trunk"
        case .rearBumper:       return "Rear Bumper"
        case .leftFrontFender:  return "Left Front Fender"
        case .leftFrontDoor:    return "Left Front Door"
        case .leftRearDoor:     return "Left Rear Door"
        case .leftRearFender:   return "Left Rear Fender"
        case .rightFrontFender: return "Right Front Fender"
        case .rightFrontDoor:   return "Right Front Door"
        case .rightRearDoor:    return "Right Rear Door"
        case .rightRearFender:  return "Right Rear Fender"
        case .underbody:        return "Underbody"
        case .interior:         return "Interior"
        }
    }

    var shortLabel: String {
        switch self {
        case .frontBumper:      return "Front\nBumper"
        case .hood:             return "Hood"
        case .windshield:       return "W/S"
        case .leftMirror:       return "LM"
        case .rightMirror:      return "RM"
        case .roof:             return "Roof"
        case .rearWindow:       return "R/W"
        case .trunk:            return "Trunk"
        case .rearBumper:       return "Rear\nBumper"
        case .leftFrontFender:  return "LF\nFend"
        case .leftFrontDoor:    return "LF\nDoor"
        case .leftRearDoor:     return "LR\nDoor"
        case .leftRearFender:   return "LR\nFend"
        case .rightFrontFender: return "RF\nFend"
        case .rightFrontDoor:   return "RF\nDoor"
        case .rightRearDoor:    return "RR\nDoor"
        case .rightRearFender:  return "RR\nFend"
        case .underbody:        return "Under"
        case .interior:         return "Interior"
        }
    }

    /// Zone rect in a 300 × 400 logical canvas. nil = not on top-down diagram.
    var canvasRect: CGRect? {
        switch self {
        case .frontBumper:      return CGRect(x: 90,  y:   5, width: 120, height: 28)
        case .hood:             return CGRect(x: 65,  y:  33, width: 170, height: 77)
        case .windshield:       return CGRect(x: 80,  y: 110, width: 140, height: 32)
        case .leftMirror:       return CGRect(x: 27,  y: 118, width: 28,  height: 26)
        case .rightMirror:      return CGRect(x: 245, y: 118, width: 28,  height: 26)
        case .roof:             return CGRect(x: 65,  y: 142, width: 170, height: 108)
        case .rearWindow:       return CGRect(x: 80,  y: 250, width: 140, height: 32)
        case .trunk:            return CGRect(x: 65,  y: 282, width: 170, height: 77)
        case .rearBumper:       return CGRect(x: 90,  y: 359, width: 120, height: 28)
        case .leftFrontFender:  return CGRect(x: 5,   y:  33, width: 60,  height: 77)
        case .leftFrontDoor:    return CGRect(x: 5,   y: 110, width: 60,  height: 86)
        case .leftRearDoor:     return CGRect(x: 5,   y: 196, width: 60,  height: 86)
        case .leftRearFender:   return CGRect(x: 5,   y: 282, width: 60,  height: 77)
        case .rightFrontFender: return CGRect(x: 235, y:  33, width: 60,  height: 77)
        case .rightFrontDoor:   return CGRect(x: 235, y: 110, width: 60,  height: 86)
        case .rightRearDoor:    return CGRect(x: 235, y: 196, width: 60,  height: 86)
        case .rightRearFender:  return CGRect(x: 235, y: 282, width: 60,  height: 77)
        case .underbody:        return nil
        case .interior:         return nil
        }
    }
}

// MARK: - Car Silhouette

private struct CarTopSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.30, y: h * 0.01))
        p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.01))
        p.addCurve(to: CGPoint(x: w * 0.97, y: h * 0.15),
                   control1: CGPoint(x: w * 0.85, y: h * 0.01),
                   control2: CGPoint(x: w * 0.97, y: h * 0.07))
        p.addLine(to: CGPoint(x: w * 0.97, y: h * 0.90))
        p.addCurve(to: CGPoint(x: w * 0.70, y: h * 0.99),
                   control1: CGPoint(x: w * 0.97, y: h * 0.97),
                   control2: CGPoint(x: w * 0.85, y: h * 0.99))
        p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.99))
        p.addCurve(to: CGPoint(x: w * 0.03, y: h * 0.90),
                   control1: CGPoint(x: w * 0.15, y: h * 0.99),
                   control2: CGPoint(x: w * 0.03, y: h * 0.97))
        p.addLine(to: CGPoint(x: w * 0.03, y: h * 0.15))
        p.addCurve(to: CGPoint(x: w * 0.30, y: h * 0.01),
                   control1: CGPoint(x: w * 0.03, y: h * 0.07),
                   control2: CGPoint(x: w * 0.15, y: h * 0.01))
        p.closeSubpath()
        return p
    }
}

// MARK: - Zone Color Helper

private func zoneColor(for count: Int) -> Color {
    if count == 0 { return Color.green.opacity(0.15) }
    if count <= 2  { return Color.orange.opacity(0.65) }
    return Color.red.opacity(0.75)
}

private func zoneBorderColor(for count: Int) -> Color {
    if count == 0 { return Color.green.opacity(0.5) }
    if count <= 2  { return Color.orange }
    return Color.red
}

// MARK: - Car Damage Diagram

private struct CarDamageDiagram: View {
    let damages: [HasarKaydi]
    let onZoneTap: (CarDamageZone) -> Void

    private let canvasW: CGFloat = 300
    private let canvasH: CGFloat = 400

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / canvasW, geo.size.height / canvasH)
            let ox = (geo.size.width  - canvasW * scale) / 2
            let oy = (geo.size.height - canvasH * scale) / 2

            ZStack(alignment: .topLeading) {
                // Car silhouette background
                CarTopSilhouette()
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        CarTopSilhouette()
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1.5 * scale)
                    )
                    .frame(width: canvasW * scale, height: canvasH * scale)
                    .offset(x: ox, y: oy)

                // Direction label
                Text("▲ FRONT")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundColor(.secondary)
                    .offset(x: ox + canvasW * scale * 0.38, y: oy - 14 * scale)

                // Zone buttons
                ForEach(CarDamageZone.allCases.filter { $0.canvasRect != nil }, id: \.rawValue) { zone in
                    if let rect = zone.canvasRect {
                        let count = damages.filter { $0.damageZone == zone.rawValue }.count
                        let scaledRect = CGRect(
                            x: ox + rect.minX * scale,
                            y: oy + rect.minY * scale,
                            width: rect.width * scale,
                            height: rect.height * scale
                        )
                        Button { onZoneTap(zone) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 3 * scale)
                                    .fill(zoneColor(for: count))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3 * scale)
                                            .stroke(zoneBorderColor(for: count), lineWidth: count > 0 ? 1.5 * scale : 0.8 * scale)
                                    )
                                VStack(spacing: 1) {
                                    Text(zone.shortLabel)
                                        .font(.system(size: max(5, min(9, rect.width * scale * 0.18)), weight: .semibold))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(count > 0 ? .white : Color(.label).opacity(0.7))
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: max(6, min(11, rect.width * scale * 0.22)), weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .frame(width: scaledRect.width, height: scaledRect.height)
                        }
                        .buttonStyle(.plain)
                        .position(x: scaledRect.midX, y: scaledRect.midY)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Legend View

private struct DamageMapLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .green.opacity(0.5), label: "No Damage")
            legendItem(color: .orange, label: "1–2 Damages")
            legendItem(color: .red, label: "3+ Damages")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.6))
                .frame(width: 14, height: 10)
            Text(label)
        }
    }
}

// MARK: - Zone Detail Sheet

private struct ZoneDamageDetailSheet: View {
    @EnvironmentObject var viewModel: AracViewModel
    let zone: CarDamageZone
    let arac: Arac
    let damages: [HasarKaydi]
    @Binding var showAddDamage: Bool
    @Binding var zoneForAdd: CarDamageZone?
    @Environment(\.dismiss) var dismiss

    var zoneDamages: [HasarKaydi] {
        damages.filter { $0.damageZone == zone.rawValue }
    }

    var body: some View {
        NavigationView {
            List {
                if zoneDamages.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 36))
                                .foregroundColor(.green)
                            Text("No damage recorded for this zone.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    Section("Damage Records (\(zoneDamages.count))") {
                        ForEach(zoneDamages) { hasar in
                            NavigationLink(destination: HasarDetayView(hasar: hasar, aracId: arac.id, aracPlaka: arac.plakaFormatli)) {
                                HasarSatirView(hasar: hasar)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        zoneForAdd = zone
                        showAddDamage = true
                        dismiss()
                    } label: {
                        Label("Add Damage to \(zone.displayName)", systemImage: "plus.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(zone.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Zone Summary Grid

private struct ZoneSummaryGrid: View {
    let damages: [HasarKaydi]
    let onZoneTap: (CarDamageZone) -> Void

    private var damagedZones: [(CarDamageZone, Int)] {
        CarDamageZone.allCases.compactMap { zone in
            let count = damages.filter { $0.damageZone == zone.rawValue }.count
            return count > 0 ? (zone, count) : nil
        }.sorted { $0.1 > $1.1 }
    }

    private var unlocated: [HasarKaydi] {
        damages.filter { $0.damageZone == nil || $0.damageZone?.isEmpty == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if damagedZones.isEmpty && unlocated.isEmpty {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("No damages recorded for this vehicle.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                if !damagedZones.isEmpty {
                    ForEach(damagedZones, id: \.0.rawValue) { (zone, count) in
                        Button { onZoneTap(zone) } label: {
                            HStack {
                                Circle()
                                    .fill(count > 2 ? Color.red : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(zone.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(count) record\(count > 1 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                if !unlocated.isEmpty {
                    HStack {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 8, height: 8)
                        Text("Unlocated (Legacy) Damages")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(unlocated.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - PDF Export

/// Single canonical reservation label for PDF (Germany → RNT, Turkey → NAV, else RES).
private func displayReservationCodeForDamagePDF(_ raw: String, franchiseId: String?) -> String {
    var c = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let upper = c.uppercased()
    for p in ["RES-", "RNT-", "NAV-"] {
        if upper.hasPrefix(p) {
            c = String(c.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
    }
    if c.isEmpty { return "—" }
    let f = (franchiseId ?? "").uppercased()
    if f.hasPrefix("TR") { return "NAV-\(c)" }
    if f.hasPrefix("DE") { return "RNT-\(c)" }
    return "RES-\(c)"
}

private func isSabihaGokcenFranchiseForDamagePDF(_ franchiseId: String?) -> Bool {
    let normalized = (franchiseId ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
    return normalized.contains("SABIHA") || normalized.contains("SAW")
}

private func buildDamageMapPDF(arac: Arac, damages: [HasarKaydi]) -> Data {
    let pageW: CGFloat = 595.2
    let pageH: CGFloat = 841.8
    let margin: CGFloat = 40
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))

    return renderer.pdfData { ctx in
        ctx.beginPage()
        let cg = ctx.cgContext

        // Header
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.label
        ]

        var y = margin
        NSString(string: "Vehicle Damage Map Report").draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        if isSabihaGokcenFranchiseForDamagePDF(arac.franchiseId),
           let logo = UIImage(named: "usave_logo") {
            logo.draw(in: CGRect(x: pageW - margin - 108, y: y - 2, width: 108, height: 36))
        }
        y += 24
        NSString(string: "\(arac.plakaFormatli) · \(arac.marka) \(arac.model)").draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
        y += 16
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        NSString(string: "Generated: \(date)").draw(at: CGPoint(x: margin, y: y), withAttributes: subAttrs)
        y += 20

        // Horizontal rule
        cg.setStrokeColor(UIColor.separator.cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: margin, y: y))
        cg.addLine(to: CGPoint(x: pageW - margin, y: y))
        cg.strokePath()
        y += 16

        // Draw simplified top-down car diagram with zones
        let diagramW: CGFloat = 180
        let diagramH: CGFloat = 240
        let diagramX = (pageW - diagramW) / 2
        let diagramY = y
        let scaleX = diagramW / 300
        let scaleY = diagramH / 400

        // Background
        cg.setFillColor(UIColor.systemGray6.cgColor)
        let bodyPath = UIBezierPath()
        let bw = diagramW, bh = diagramH, bx = diagramX, by = diagramY
        bodyPath.move(to: CGPoint(x: bx + bw * 0.30, y: by + bh * 0.01))
        bodyPath.addLine(to: CGPoint(x: bx + bw * 0.70, y: by + bh * 0.01))
        bodyPath.addCurve(to: CGPoint(x: bx + bw * 0.97, y: by + bh * 0.15),
                          controlPoint1: CGPoint(x: bx + bw * 0.85, y: by + bh * 0.01),
                          controlPoint2: CGPoint(x: bx + bw * 0.97, y: by + bh * 0.07))
        bodyPath.addLine(to: CGPoint(x: bx + bw * 0.97, y: by + bh * 0.90))
        bodyPath.addCurve(to: CGPoint(x: bx + bw * 0.70, y: by + bh * 0.99),
                          controlPoint1: CGPoint(x: bx + bw * 0.97, y: by + bh * 0.97),
                          controlPoint2: CGPoint(x: bx + bw * 0.85, y: by + bh * 0.99))
        bodyPath.addLine(to: CGPoint(x: bx + bw * 0.30, y: by + bh * 0.99))
        bodyPath.addCurve(to: CGPoint(x: bx + bw * 0.03, y: by + bh * 0.90),
                          controlPoint1: CGPoint(x: bx + bw * 0.15, y: by + bh * 0.99),
                          controlPoint2: CGPoint(x: bx + bw * 0.03, y: by + bh * 0.97))
        bodyPath.addLine(to: CGPoint(x: bx + bw * 0.03, y: by + bh * 0.15))
        bodyPath.addCurve(to: CGPoint(x: bx + bw * 0.30, y: by + bh * 0.01),
                          controlPoint1: CGPoint(x: bx + bw * 0.03, y: by + bh * 0.07),
                          controlPoint2: CGPoint(x: bx + bw * 0.15, y: by + bh * 0.01))
        bodyPath.close()
        bodyPath.fill()
        cg.setStrokeColor(UIColor.separator.cgColor)
        cg.setLineWidth(1)
        bodyPath.stroke()

        // Draw each zone
        for zone in CarDamageZone.allCases {
            guard let rect = zone.canvasRect else { continue }
            let count = damages.filter { $0.damageZone == zone.rawValue }.count
            let zx = diagramX + rect.minX * scaleX
            let zy = diagramY + rect.minY * scaleY
            let zw = rect.width * scaleX
            let zh = rect.height * scaleY
            let zRect = CGRect(x: zx, y: zy, width: zw, height: zh)

            if count > 0 {
                let fill = count > 2 ? UIColor.systemRed.withAlphaComponent(0.7) : UIColor.systemOrange.withAlphaComponent(0.65)
                cg.setFillColor(fill.cgColor)
            } else {
                cg.setFillColor(UIColor.systemGreen.withAlphaComponent(0.2).cgColor)
            }
            let path = UIBezierPath(roundedRect: zRect, cornerRadius: 2)
            path.fill()
            cg.setStrokeColor(UIColor.separator.cgColor)
            cg.setLineWidth(0.4)
            path.stroke()

            // Zone label
            let fontSize: CGFloat = max(4, min(6, zw * 0.16))
            let zAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: count > 0 ? .bold : .regular),
                .foregroundColor: count > 0 ? UIColor.white : UIColor.darkGray
            ]
            let labelText = zone.shortLabel.replacingOccurrences(of: "\n", with: " ")
            let str = count > 0 ? "\(labelText) (\(count))" : labelText
            let nsStr = NSString(string: str)
            let textSize = nsStr.size(withAttributes: zAttrs)
            nsStr.draw(at: CGPoint(x: zx + (zw - textSize.width) / 2, y: zy + (zh - textSize.height) / 2), withAttributes: zAttrs)
        }

        // FRONT label above diagram
        NSString(string: "▲ FRONT").draw(at: CGPoint(x: diagramX + diagramW / 2 - 18, y: diagramY - 14), withAttributes: subAttrs)

        y = diagramY + diagramH + 24

        // Legend
        func drawLegendSwatch(x: CGFloat, y: CGFloat, color: UIColor, label: String) {
            let swatchRect = CGRect(x: x, y: y, width: 14, height: 8)
            cg.setFillColor(color.cgColor)
            UIBezierPath(roundedRect: swatchRect, cornerRadius: 2).fill()
            NSString(string: label).draw(at: CGPoint(x: x + 18, y: y - 1), withAttributes: subAttrs)
        }
        let legendY = y
        drawLegendSwatch(x: margin, y: legendY, color: .systemGreen.withAlphaComponent(0.4), label: "No damage")
        drawLegendSwatch(x: margin + 90, y: legendY, color: .systemOrange.withAlphaComponent(0.65), label: "1–2 damages")
        drawLegendSwatch(x: margin + 195, y: legendY, color: .systemRed.withAlphaComponent(0.7), label: "3+ damages")
        y = legendY + 24

        // Divider
        cg.setStrokeColor(UIColor.separator.cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: margin, y: y))
        cg.addLine(to: CGPoint(x: pageW - margin, y: y))
        cg.strokePath()
        y += 14

        // Summary header
        NSString(string: "Damage Summary by Zone").draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += 22

        // Group damages by zone
        let grouped = Dictionary(grouping: damages) { $0.damageZone ?? "" }
        let sortedZones = CarDamageZone.allCases.filter { zone in
            (grouped[zone.rawValue]?.count ?? 0) > 0
        }

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none

        for zone in sortedZones {
            let records = grouped[zone.rawValue] ?? []
            if records.isEmpty { continue }

            // Zone header
            cg.setFillColor(UIColor.systemOrange.withAlphaComponent(0.15).cgColor)
            cg.fill(CGRect(x: margin, y: y, width: pageW - margin * 2, height: 18))
            NSString(string: zone.displayName + " (\(records.count))").draw(at: CGPoint(x: margin + 4, y: y + 2), withAttributes: labelAttrs)
            y += 20

            for (i, hasar) in records.enumerated() {
                if y > pageH - 80 {
                    ctx.beginPage()
                    y = margin
                }
                let prefix = "  \(i + 1). "
                let resDisp = displayReservationCodeForDamagePDF(hasar.resKodu, franchiseId: arac.franchiseId)
                let detail = "\(resDisp)  ·  \(df.string(from: hasar.tarih))  ·  \(hasar.notlar.isEmpty ? "—" : hasar.notlar)"
                NSString(string: prefix + detail).draw(at: CGPoint(x: margin, y: y), withAttributes: valueAttrs)
                y += 14
            }
            y += 6
        }

        // Unlocated
        let unlocated = damages.filter { $0.damageZone == nil || $0.damageZone?.isEmpty == true }
        if !unlocated.isEmpty {
            if y > pageH - 80 { ctx.beginPage(); y = margin }
            cg.setFillColor(UIColor.systemGray4.withAlphaComponent(0.3).cgColor)
            cg.fill(CGRect(x: margin, y: y, width: pageW - margin * 2, height: 18))
            NSString(string: "Unlocated Damages (\(unlocated.count))").draw(at: CGPoint(x: margin + 4, y: y + 2), withAttributes: labelAttrs)
            y += 20
            for (i, hasar) in unlocated.enumerated() {
                if y > pageH - 60 { ctx.beginPage(); y = margin }
                let resDisp = displayReservationCodeForDamagePDF(hasar.resKodu, franchiseId: arac.franchiseId)
                let detail = "  \(i + 1). \(resDisp)  ·  \(df.string(from: hasar.tarih))  ·  \(hasar.notlar.isEmpty ? "—" : hasar.notlar)"
                NSString(string: detail).draw(at: CGPoint(x: margin, y: y), withAttributes: valueAttrs)
                y += 14
            }
        }

        // Footer
        let totalStr = "Total: \(damages.count) damage record\(damages.count != 1 ? "s" : "")"
        NSString(string: totalStr).draw(at: CGPoint(x: margin, y: pageH - margin - 20), withAttributes: subAttrs)
    }
}

// MARK: - Main View

struct VehicleDamageMapView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let arac: Arac

    @State private var selectedZone: CarDamageZone?
    @State private var showZoneSheet = false
    @State private var showAddDamage = false
    @State private var zoneForAdd: CarDamageZone?
    @State private var pdfData: Data?
    @State private var showShareSheet = false

    var damages: [HasarKaydi] {
        viewModel.conditionFormDamages(for: arac.id) + viewModel.legacyDamagesWithoutLocation(for: arac.id)
    }

    var totalDamaged: Int {
        Set(damages.compactMap { $0.damageZone }.filter { !$0.isEmpty }).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Summary strip
                HStack(spacing: 20) {
                    summaryPill(value: "\(damages.count)", label: "Total Records", color: damages.isEmpty ? .green : .orange, icon: "exclamationmark.triangle.fill")
                    summaryPill(value: "\(totalDamaged)", label: "Zones Affected", color: totalDamaged == 0 ? .green : .red, icon: "map.fill")
                }
                .padding(.horizontal)
                .padding(.top, 12)

                // Car diagram
                ZStack {
                    Color(.systemGroupedBackground)
                    VStack(spacing: 6) {
                        CarDamageDiagram(damages: damages) { zone in
                            selectedZone = zone
                            showZoneSheet = true
                        }
                        .aspectRatio(300.0 / 400.0, contentMode: .fit)
                        .frame(maxWidth: 260)
                        .padding(.top, 16)

                        DamageMapLegend()
                            .padding(.bottom, 12)
                    }
                }
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.top, 12)

                // Zone damage summary
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Affected Zones")
                            .font(.headline)
                        Spacer()
                        Button {
                            zoneForAdd = nil
                            showAddDamage = true
                        } label: {
                            Label("Add Damage", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    ZoneSummaryGrid(damages: damages) { zone in
                        selectedZone = zone
                        showZoneSheet = true
                    }
                    .padding(.bottom, 8)
                }

                // Off-diagram zones (underbody, interior)
                let offDiagram = [CarDamageZone.underbody, .interior].filter { zone in
                    damages.contains(where: { $0.damageZone == zone.rawValue })
                }
                if !offDiagram.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Other Zones")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(offDiagram, id: \.rawValue) { zone in
                            Button { selectedZone = zone; showZoneSheet = true } label: {
                                let count = damages.filter { $0.damageZone == zone.rawValue }.count
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                    Text(zone.displayName)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(10)
                                .padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 8)
                }

                Spacer(minLength: 32)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Damage Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    pdfData = buildDamageMapPDF(arac: arac, damages: damages)
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showZoneSheet) {
            if let zone = selectedZone {
                ZoneDamageDetailSheet(
                    zone: zone,
                    arac: arac,
                    damages: damages,
                    showAddDamage: $showAddDamage,
                    zoneForAdd: $zoneForAdd
                )
                .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showAddDamage) {
            SheetWrapper {
                NavigationView {
                    HasarEkleView(aracId: arac.id, initialZone: zoneForAdd)
                }
            }
            .environmentObject(viewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            if let data = pdfData {
                ActivityViewController(activityItems: [data])
            }
        }
    }

    private func summaryPill(value: String, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}
