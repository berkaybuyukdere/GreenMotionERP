import SwiftUI

enum FleetRichTextStyle {
    case standard
    case onOutgoingBubble
    case onIncomingBubble
}

struct FleetRichTextView: View {
    let text: String
    let vehicles: [Arac]
    var style: FleetRichTextStyle = .standard
    var onOpenPlate: ((String) -> Void)?
    var onOpenRES: ((String) -> Void)?

    private var tokens: [FleetTextTokenKind] {
        FleetTextTokenParser.tokenize(text, knownPlates: FleetTextTokenParser.knownPlates(from: vehicles))
    }

    private var isBubbleStyle: Bool {
        style == .onOutgoingBubble || style == .onIncomingBubble
    }

    var body: some View {
        Group {
            if isBubbleStyle {
                Text(attributed)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(attributed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            handleURL(url)
            return .handled
        })
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for token in tokens {
            switch token {
            case .plain(let s):
                var plain = AttributedString(s)
                plain.font = .system(size: MessagesTheme.messageFontSize)
                plain.kern = MessagesTheme.messageKern
                switch style {
                case .onOutgoingBubble:
                    plain.foregroundColor = .white
                case .onIncomingBubble:
                    plain.foregroundColor = .white
                case .standard:
                    break
                }
                result.append(plain)
            case .resCode(let code):
                var part = AttributedString(code)
                part.font = .system(size: MessagesTheme.messageFontSize, weight: .heavy)
                part.kern = MessagesTheme.messageKern
                applyHighlight(&part, tokenColor: resHighlightColor, borderColor: resBorderColor, foreground: resForegroundColor)
                if onOpenRES != nil, let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    part.link = URL(string: "fleetres://\(encoded)")
                }
                result.append(part)
            case .plate(let plate):
                var part = AttributedString(plate)
                part.font = .system(size: MessagesTheme.messageFontSize, weight: .heavy)
                part.kern = MessagesTheme.messageKern
                applyHighlight(&part, tokenColor: plateHighlightColor, borderColor: plateBorderColor, foreground: plateForegroundColor)
                if onOpenPlate != nil, let encoded = plate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                    part.link = URL(string: "fleetplate://\(encoded)")
                }
                result.append(part)
            }
        }
        return result
    }

    private var resForegroundColor: Color {
        switch style {
        case .onOutgoingBubble: return Color(red: 1, green: 0.95, blue: 0.75)
        case .onIncomingBubble: return Color.white.opacity(0.92)
        case .standard: return Color.orange
        }
    }

    private var resHighlightColor: Color {
        switch style {
        case .onOutgoingBubble: return Color.white.opacity(0.34)
        case .onIncomingBubble: return Color.white.opacity(0.22)
        case .standard: return Color.orange.opacity(0.32)
        }
    }

    private var resBorderColor: Color {
        switch style {
        case .onOutgoingBubble: return Color(red: 1, green: 0.88, blue: 0.45)
        case .onIncomingBubble: return Color.white.opacity(0.85)
        case .standard: return Color.orange
        }
    }

    private var plateForegroundColor: Color {
        switch style {
        case .onOutgoingBubble: return Color(red: 0.82, green: 0.94, blue: 1)
        case .onIncomingBubble: return Color.white
        case .standard: return MessagesTheme.iosBlue
        }
    }

    private var plateHighlightColor: Color {
        switch style {
        case .onOutgoingBubble: return Color.white.opacity(0.28)
        case .onIncomingBubble: return Color.white.opacity(0.2)
        case .standard: return MessagesTheme.iosBlue.opacity(0.24)
        }
    }

    private var plateBorderColor: Color {
        switch style {
        case .onOutgoingBubble: return Color(red: 0.65, green: 0.88, blue: 1)
        case .onIncomingBubble: return Color.white.opacity(0.75)
        case .standard: return MessagesTheme.iosBlue
        }
    }

    private func applyHighlight(_ part: inout AttributedString, tokenColor: Color, borderColor: Color, foreground: Color) {
        part.foregroundColor = foreground
        part.backgroundColor = tokenColor
        part.underlineStyle = .single
        if style == .standard {
            part.underlineColor = UIColor(borderColor)
        }
    }

    private func handleURL(_ url: URL) {
        switch url.scheme {
        case "fleetres":
            let code = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !code.isEmpty { onOpenRES?(code.removingPercentEncoding ?? code) }
        case "fleetplate":
            let plate = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !plate.isEmpty { onOpenPlate?(plate.removingPercentEncoding ?? plate) }
        default:
            break
        }
    }
}

struct FleetTokenNavigationHandler {
    let viewModel: AracViewModel

    func vehicle(forPlate normalized: String) -> Arac? {
        viewModel.araclar.first {
            FleetTextTokenParser.normalizePlate($0.plaka) == normalized
        }
    }

    func damageMatch(forRES resCode: String) -> (arac: Arac, hasar: HasarKaydi)? {
        let target = TrafficAccidentContract.canonicalRES(from: resCode)
        for arac in viewModel.araclar {
            if let hasar = arac.hasarKayitlari.first(where: {
                TrafficAccidentContract.canonicalRES(from: $0.resKodu) == target
            }) {
                return (arac, hasar)
            }
        }
        return nil
    }
}
