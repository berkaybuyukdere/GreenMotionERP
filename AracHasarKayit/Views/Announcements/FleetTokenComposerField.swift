import SwiftUI

struct FleetTokenComposerField: View {
    @Binding var text: String
    let vehicles: [Arac]
    var placeholder: String

    @State private var suggestions: [String] = []
    @State private var suggestionKind: FleetAutocompleteKind?
    @State private var activePrefix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !suggestions.isEmpty, let kind = suggestionKind {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { item in
                            Button {
                                applySuggestion(item, kind: kind)
                            } label: {
                                suggestionChip(item, kind: kind, prefix: activePrefix)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                }
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .messagesTextStyle()
                .onChange(of: text) { _, newValue in
                    refreshSuggestions(for: newValue)
                }
        }
    }

    @ViewBuilder
    private func suggestionChip(_ item: String, kind: FleetAutocompleteKind, prefix: String) -> some View {
        let label = displayLabel(item, kind: kind)
        let normalizedLabel = kind == .plate ? FleetTextTokenParser.normalizePlate(label) : label.uppercased()
        let normalizedPrefix = kind == .plate ? FleetTextTokenParser.normalizePlate(prefix) : prefix.uppercased()

        if !normalizedPrefix.isEmpty, normalizedLabel.hasPrefix(normalizedPrefix), normalizedPrefix.count < normalizedLabel.count {
            HStack(spacing: 0) {
                Text(String(label.prefix(normalizedPrefix.count)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MessagesTheme.iosBlue)
                Text(String(label.dropFirst(normalizedPrefix.count)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MessagesTheme.iosBlue.opacity(0.72))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MessagesTheme.iosBlue.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(MessagesTheme.iosBlue.opacity(0.45), lineWidth: 1.5))
        } else {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MessagesTheme.iosBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MessagesTheme.iosBlue.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(MessagesTheme.iosBlue.opacity(0.35), lineWidth: 1))
        }
    }

    private func displayLabel(_ item: String, kind: FleetAutocompleteKind) -> String {
        switch kind {
        case .plate:
            if let arac = vehicles.first(where: { FleetTextTokenParser.normalizePlate($0.plaka) == item }) {
                return arac.plakaFormatli
            }
            return item
        case .res:
            return item
        }
    }

    private func applySuggestion(_ item: String, kind: FleetAutocompleteKind) {
        guard let token = FleetTextTokenParser.activeToken(in: text) else {
            text += item
            suggestions = []
            return
        }
        let replacement: String
        switch kind {
        case .plate:
            replacement = vehicles.first(where: { FleetTextTokenParser.normalizePlate($0.plaka) == item })?.plakaFormatli ?? item
        case .res:
            replacement = item
        }
        text = (text as NSString).replacingCharacters(in: token.range, with: replacement)
        suggestions = []
        suggestionKind = nil
        activePrefix = ""
    }

    private func refreshSuggestions(for value: String) {
        guard let token = FleetTextTokenParser.activeToken(in: value) else {
            suggestions = []
            suggestionKind = nil
            activePrefix = ""
            return
        }
        let prefix = token.prefix
        activePrefix = prefix
        if FleetTextTokenParser.looksLikePlatePrefix(prefix) {
            suggestions = FleetTextTokenParser.plateSuggestions(prefix: prefix, vehicles: vehicles)
            suggestionKind = .plate
        } else if FleetTextTokenParser.looksLikeRESPrefix(prefix) {
            suggestions = FleetTextTokenParser.resSuggestions(prefix: prefix, vehicles: vehicles)
            suggestionKind = .res
        } else {
            suggestions = []
            suggestionKind = nil
            activePrefix = ""
        }
    }
}

enum FleetAutocompleteKind {
    case plate, res
}
