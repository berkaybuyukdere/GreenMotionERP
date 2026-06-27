import SwiftUI
import PhotosUI
import AVFoundation
import AudioToolbox

enum AnnouncementColorKey: String, CaseIterable, Identifiable {
    case purple, orange, red, blue, yellow, indigo, cyan, mint, pink, green

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .purple: return PalantirTheme.purple
        case .orange: return PalantirTheme.warning
        case .red: return PalantirTheme.critical
        case .blue: return PalantirTheme.accent
        case .yellow: return PalantirTheme.warning
        case .indigo: return PalantirTheme.accent
        case .cyan: return PalantirTheme.accent
        case .mint: return PalantirTheme.success
        case .pink: return PalantirTheme.purple
        case .green: return PalantirTheme.success
        }
    }

    var label: String { rawValue.capitalized }
}

enum AnnouncementIconPalette {
    static func palette(colorKey: String) -> AnnouncementColorKey {
        AnnouncementColorKey(rawValue: colorKey) ?? .purple
    }

    static func colors(for icon: String, colorKey: String) -> (fg: Color, bg: Color) {
        let key = palette(colorKey: colorKey)
        return (key.color, key.color.opacity(0.18))
    }

    static let iconChoices = [
        "megaphone.fill", "bell.fill", "exclamationmark.triangle.fill",
        "info.circle.fill", "star.fill", "calendar", "car.fill", "wrench.and.screwdriver.fill"
    ]

    @ViewBuilder
    static func badge(icon: String, colorKey: String, size: CGFloat = 44, dimmed: Bool = false) -> some View {
        let palette = colors(for: icon, colorKey: colorKey)
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(palette.fg)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(palette.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(palette.fg.opacity(0.28), lineWidth: 1.5)
            )
            .opacity(dimmed ? 0.9 : 1)
    }
}

enum MessagesTheme {
    static let iosBlue = PalantirTheme.accent
    static let iosGreen = PalantirTheme.success
    static let iosGray = PalantirTheme.textMuted
    static let iosGray6 = PalantirTheme.background
    static let iosGray4 = PalantirTheme.border

    static let outgoingBubble = iosBlue
    static let incomingBubble = iosGreen

    static func chatBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(uiColor: .systemGroupedBackground) : iosGray6
    }

    static func mutedText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(uiColor: .secondaryLabel) : iosGray
    }

    static func composerFieldBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : Color(uiColor: .systemBackground)
    }

    static func composerBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(uiColor: .separator) : iosGray4
    }

    static func dateChipBackground(for scheme: ColorScheme) -> Color {
        PalantirTheme.surfaceHigh
    }

    static func dateChipText(for scheme: ColorScheme) -> Color {
        PalantirTheme.textMuted
    }

    static let chatBackground = iosGray6

    static let messageFontSize: CGFloat = 16
    static let messageFont = Font.system(size: messageFontSize)
    static let messageKern: CGFloat = -0.2
    static let messageLineSpacing: CGFloat = messageFontSize * 0.35
    static let timestampFont = Font.system(size: 11)
    static let senderNameFont = Font.system(size: 12, weight: .semibold)

    static let bubblePaddingH: CGFloat = 12
    static let bubblePaddingV: CGFloat = 8
    static var maxBubbleWidth: CGFloat { min(UIScreen.main.bounds.width * 0.72, 320) }
    static let samePersonGap: CGFloat = 2
    static let differentPersonGap: CGFloat = 10
    static let avatarSize: CGFloat = 32
    static let composerCornerRadius: CGFloat = 20

    enum BubbleGroupPosition {
        case single, top, middle, bottom
    }

    static func bubbleShape(outgoing: Bool, position: BubbleGroupPosition) -> UnevenRoundedRectangle {
        let r: CGFloat = 18
        let s: CGFloat = 4
        switch (outgoing, position) {
        case (true, .single), (true, .top):
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: s, topTrailingRadius: r)
        case (true, .middle):
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: s, topTrailingRadius: s)
        case (true, .bottom):
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: s)
        case (false, .single), (false, .top):
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: s, bottomTrailingRadius: r, topTrailingRadius: r)
        case (false, .middle):
            return UnevenRoundedRectangle(topLeadingRadius: s, bottomLeadingRadius: s, bottomTrailingRadius: r, topTrailingRadius: r)
        case (false, .bottom):
            return UnevenRoundedRectangle(topLeadingRadius: s, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: r)
        }
    }
}

extension View {
    func messagesTextStyle() -> some View {
        self
            .font(MessagesTheme.messageFont)
            .kerning(MessagesTheme.messageKern)
            .lineSpacing(MessagesTheme.messageLineSpacing)
    }

    func messagesComposerFieldStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: MessagesTheme.composerCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: MessagesTheme.composerCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MessagesTheme.composerCornerRadius, style: .continuous)
                    .strokeBorder(MessagesTheme.iosGray4.opacity(0.55), lineWidth: 1)
            )
    }

    func messagesNavigationChrome(titleDisplayMode: Binding<NavigationBarItem.TitleDisplayMode>) -> some View {
        self
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(titleDisplayMode.wrappedValue == .inline ? .visible : .automatic, for: .navigationBar)
    }
}

enum ChatSoundPlayer {
    static func playSent() {
        AudioServicesPlaySystemSound(1004)
    }

    static func playReceived() {
        AudioServicesPlaySystemSound(1003)
    }
}

struct ChatAvatarView: View {
    let name: String
    let uid: String
    var size: CGFloat = MessagesTheme.avatarSize

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private var background: Color {
        let hash = abs(uid.hashValue)
        let hues: [Color] = [.blue, .purple, .orange, .teal, .indigo, .pink, .mint, .cyan]
        return hues[hash % hues.count]
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [background, background.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            }
    }
}

struct TypingIndicatorView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(MessagesTheme.iosGray)
                    .frame(width: 7, height: 7)
                    .offset(y: phase == index ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MessagesTheme.incomingBubble)
        .clipShape(MessagesTheme.bubbleShape(outgoing: false, position: .single))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                phase = 2
            }
        }
    }
}

struct ComposerMediaPickerBar: View {
    @Binding var galleryItems: [PhotosPickerItem]
    var maxSelection: Int = 8
    var onCamera: () -> Void
    var onFileImport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            mediaSlot {
                PhotosPicker(selection: $galleryItems, maxSelectionCount: maxSelection, matching: .images) {
                    mediaButtonLabel(icon: "photo.on.rectangle.angled", title: "Gallery".localized, tint: MessagesTheme.iosBlue)
                }
            }
            mediaSlot {
                Button(action: onCamera) {
                    mediaButtonLabel(icon: "camera.fill", title: "Take Photo".localized, tint: MessagesTheme.iosGreen)
                }
                .buttonStyle(.plain)
            }
            mediaSlot {
                Button(action: onFileImport) {
                    mediaButtonLabel(icon: "paperclip", title: "announcements.attach_file".localized, tint: .orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mediaSlot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
    }

    private func mediaButtonLabel(icon: String, title: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14))
                .overlay(Rectangle().stroke(tint.opacity(0.35), lineWidth: 1))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PalantirTheme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PalantirTheme.surface)
        .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
    }
}

struct PalantirMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PalantirTheme.textPrimary)
            Text(title)
                .font(PalantirTheme.labelFont(10))
                .foregroundStyle(PalantirTheme.textMuted)
                .textCase(.uppercase)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PalantirTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PalantirTheme.border, lineWidth: 1)
        )
    }
}

struct PalantirListRowAccent: View {
    let leadingIcon: String
    let leadingTint: Color
    let title: String
    let subtitle: String
    let trailing: String
    let trailingTint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: leadingIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(leadingTint)
                .frame(width: 40, height: 40)
                .background(leadingTint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Text(subtitle)
                    .font(PalantirTheme.dataFont(12))
                    .foregroundStyle(PalantirTheme.textMuted)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.caption.weight(.bold))
                .foregroundStyle(trailingTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(trailingTint.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(PalantirTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(PalantirTheme.border, lineWidth: 1)
        )
    }
}
