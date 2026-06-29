import SwiftUI

// MARK: - Formatting helpers

enum PalantirRentalJourneyFormatters {
    static let journeyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    static func formatJourneyDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return journeyDateFormatter.string(from: date)
    }

    static func formatFuel(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "—"
        }
        if trimmed.contains("/") { return trimmed }
        if let eighths = Int(trimmed) { return "\(eighths)/8" }
        return trimmed
    }

    static func kmDelta(checkout: Int?, returnKm: Int?) -> (text: String, isPositive: Bool)? {
        guard let checkout, let returnKm, returnKm >= checkout else { return nil }
        let delta = returnKm - checkout
        guard delta > 0 else { return ("0 km", false) }
        return ("+\(delta) km", true)
    }

    static func rentalDays(from checkoutDate: Date?, to returnDate: Date?) -> String? {
        guard let from = checkoutDate, let to = returnDate else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        let days = cal.dateComponents([.day], from: start, to: end).day ?? 0
        let count = max(1, days + 1)
        return String(format: "wheelsys.return.rental_days_value".localized, count)
    }

    static func reservationLabel(franchiseId: String) -> String {
        let id = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if id.hasPrefix("TR") { return "NAV Code".localized }
        if id.hasPrefix("DE") { return "RNT Code".localized }
        return "RES Code".localized
    }
}

// MARK: - Animated checkout → return connector (one-way glow, left → right)

struct PalantirOpsKmFlowConnector: View {
    var isActive: Bool

    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Capsule()
                    .fill(PalantirTheme.purple.opacity(0.18))
                    .frame(height: 3)
                if isActive {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    PalantirTheme.purple.opacity(0.35),
                                    PalantirTheme.purple,
                                    PalantirTheme.purple.opacity(0.35),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 22, height: 3)
                        .offset(x: (pulsePhase - 0.5) * 34)
                }
            }
            .frame(width: 40, height: 8)

            ZStack {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(PalantirTheme.textMuted.opacity(0.35))
                if isActive {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PalantirTheme.purple)
                        .mask(arrowPulseMask)
                }
            }
        }
        .frame(width: 44)
        .accessibilityHidden(true)
        .onAppear { restartAnimation() }
        .onChange(of: isActive) { _, _ in restartAnimation() }
    }

    private var arrowPulseMask: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.42)
            .offset(x: -geo.size.width * 0.22 + pulsePhase * geo.size.width * 0.95)
        }
    }

    private func restartAnimation() {
        pulsePhase = 0
        guard isActive else { return }
        withAnimation(.linear(duration: 1.55).repeatForever(autoreverses: false)) {
            pulsePhase = 1
        }
    }
}

struct PalantirLiveKmSymmetricCompareRow<Left: View, Right: View>: View {
    let leftTitle: String
    let rightTitle: String
    let baselineKm: Int?
    let currentKm: Int?
    var animateFlow: Bool = true
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    private var flowActive: Bool {
        guard let baselineKm, let currentKm, currentKm > baselineKm else { return false }
        return true
    }

    private var deltaText: String? {
        guard let baselineKm, let currentKm, currentKm > baselineKm else { return nil }
        return String(format: "+%d km", currentKm - baselineKm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                WheelSysPalantirOpsSidePanel(
                    title: leftTitle,
                    icon: "arrow.up.right.circle",
                    tint: PalantirTheme.accent,
                    symmetric: true,
                    content: left
                )
                PalantirOpsKmFlowConnector(isActive: animateFlow && flowActive)
                    .padding(.top, 52)
                WheelSysPalantirOpsSidePanel(
                    title: rightTitle,
                    icon: "arrow.down.left.circle",
                    tint: PalantirTheme.success,
                    symmetric: true,
                    content: right
                )
            }
            if let deltaText {
                HStack(spacing: 8) {
                    Image(systemName: "road.lanes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PalantirTheme.purple)
                    Text(deltaText)
                        .font(PalantirTheme.dataFont(13).weight(.semibold))
                        .foregroundStyle(PalantirTheme.purple)
                    Spacer(minLength: 0)
                    if let baselineKm, let currentKm {
                        Text("\(baselineKm) → \(currentKm) km")
                            .font(PalantirTheme.labelFont(10))
                            .foregroundStyle(PalantirTheme.textMuted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(PalantirTheme.purple.opacity(0.08))
                .overlay(Rectangle().stroke(PalantirTheme.purple.opacity(0.22), lineWidth: 1))
            }
        }
    }
}

// MARK: - Read-only symmetric journey card

struct PalantirCheckoutReturnCompareCard: View {
    struct Side {
        let reservationCode: String
        let customerName: String
        let customerEmail: String
        let dateLabel: String
        let dateText: String
        let kmText: String
        let fuelText: String
    }

    let checkout: Side
    let returnSide: Side
    let checkoutKm: Int?
    let returnKm: Int?
    let checkoutDate: Date?
    let returnDate: Date?
    let franchiseId: String

    private var kmDelta: (text: String, isPositive: Bool)? {
        PalantirRentalJourneyFormatters.kmDelta(checkout: checkoutKm, returnKm: returnKm)
    }

    private var flowActive: Bool {
        kmDelta != nil
    }

    var body: some View {
        WheelSysPalantirSectionCard(
            title: "wheelsys.return.checkout_vs_return".localized,
            icon: "arrow.left.arrow.right"
        ) {
            HStack(alignment: .top, spacing: 6) {
                sidePanel(
                    title: "wheelsys.return.checkout_side".localized,
                    icon: "arrow.up.right.circle",
                    tint: PalantirTheme.accent,
                    side: checkout
                )
                PalantirOpsKmFlowConnector(isActive: flowActive)
                    .padding(.top, 52)
                sidePanel(
                    title: "wheelsys.return.return_side".localized,
                    icon: "arrow.down.left.circle",
                    tint: PalantirTheme.success,
                    side: returnSide
                )
            }

            if let kmDelta {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("wheelsys.return.checkout_km".localized.uppercased())
                                .font(PalantirTheme.labelFont(8))
                                .foregroundStyle(PalantirTheme.textMuted)
                            Text(checkout.kmText)
                                .font(PalantirTheme.dataFont(22).weight(.bold))
                                .foregroundStyle(PalantirTheme.accent)
                        }
                        Spacer(minLength: 8)
                        Text(kmDelta.text)
                            .font(PalantirTheme.dataFont(15).weight(.bold))
                            .foregroundStyle(PalantirTheme.purple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PalantirTheme.purple.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(PalantirTheme.purple.opacity(0.35), lineWidth: 1)
                            )
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\("wheelsys.return.return_side".localized) KM".uppercased())
                                .font(PalantirTheme.labelFont(8))
                                .foregroundStyle(PalantirTheme.textMuted)
                            Text(returnSide.kmText)
                                .font(PalantirTheme.dataFont(22).weight(.bold))
                                .foregroundStyle(PalantirTheme.success)
                        }
                    }

                    if let days = PalantirRentalJourneyFormatters.rentalDays(
                        from: checkoutDate,
                        to: returnDate
                    ) {
                        WheelSysPalantirDiffMetric(
                            label: "wheelsys.return.rental_days".localized,
                            value: days
                        )
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func sidePanel(title: String, icon: String, tint: Color, side: Side) -> some View {
        WheelSysPalantirOpsSidePanel(
            title: title,
            icon: icon,
            tint: tint,
            symmetric: true
        ) {
            metric(label: PalantirRentalJourneyFormatters.reservationLabel(franchiseId: franchiseId), value: side.reservationCode)
            metric(label: "Customer".localized, value: side.customerName)
            if !side.customerEmail.isEmpty {
                metric(label: "Email".localized, value: side.customerEmail)
            }
            metric(label: side.dateLabel, value: side.dateText)
            metric(label: "KM".localized, value: side.kmText)
            metric(label: "Fuel level".localized, value: side.fuelText)
        }
    }

    private func metric(label: String, value: String) -> some View {
        WheelSysPalantirDiffMetric(label: label, value: value)
            .frame(minHeight: 40, alignment: .topLeading)
    }
}

extension PalantirCheckoutReturnCompareCard {
    static func from(exit: ExitIslemi, returnRecord: IadeIslemi) -> PalantirCheckoutReturnCompareCard {
        let franchiseId = exit.franchiseId.isEmpty ? returnRecord.franchiseId : exit.franchiseId
        let resRaw = (exit.navKodu ?? exit.resKodu).trimmingCharacters(in: .whitespacesAndNewlines)
        let navReturn = returnRecord.navKodu?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resCode = navReturn.isEmpty ? resRaw : navReturn

        return PalantirCheckoutReturnCompareCard(
            checkout: Side(
                reservationCode: resCode.isEmpty ? "—" : resCode,
                customerName: exit.customerFullName.isEmpty ? "—" : exit.customerFullName,
                customerEmail: (exit.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                dateLabel: "wheelsys.return.checkout_date".localized,
                dateText: PalantirRentalJourneyFormatters.formatJourneyDate(exit.exitTarihi),
                kmText: exit.km.map { "\($0)" } ?? "—",
                fuelText: PalantirRentalJourneyFormatters.formatFuel(exit.yakitSeviyesi)
            ),
            returnSide: Side(
                reservationCode: resCode.isEmpty ? "—" : resCode,
                customerName: returnRecord.customerFullName.isEmpty ? "—" : returnRecord.customerFullName,
                customerEmail: (returnRecord.customerEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                dateLabel: "Return Date".localized,
                dateText: PalantirRentalJourneyFormatters.formatJourneyDate(returnRecord.iadeTarihi),
                kmText: returnRecord.km.map { "\($0)" } ?? "—",
                fuelText: PalantirRentalJourneyFormatters.formatFuel(returnRecord.yakitSeviyesi)
            ),
            checkoutKm: exit.km,
            returnKm: returnRecord.km,
            checkoutDate: exit.exitTarihi,
            returnDate: returnRecord.iadeTarihi,
            franchiseId: franchiseId
        )
    }
}
