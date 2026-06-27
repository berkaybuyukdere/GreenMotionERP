import SwiftUI

// MARK: - Sizing (~+5% over baseline Palantir form tokens)

private enum WheelSysPalantirFormMetrics {
    static let sectionSpacing: CGFloat = 11
    static let cardPadding: CGFloat = 15
    static let fieldSpacing: CGFloat = 6
    static let innerSpacing: CGFloat = 13
    static let scrollSpacing: CGFloat = 15
    static let scrollHPadding: CGFloat = 13
    static let scrollVPadding: CGFloat = 11
    static let titleFont: CGFloat = 11
    static let labelFont: CGFloat = 9
    static let fieldFont: CGFloat = 14
    static let inputPaddingH: CGFloat = 11
    static let inputPaddingV: CGFloat = 11
    static let buttonPaddingV: CGFloat = 15
    static let headerBarPaddingH: CGFloat = 13
    static let headerBarPaddingV: CGFloat = 11
}

// MARK: - Section card (ScrollView-based CH checkout / return forms)

struct WheelSysPalantirSectionCard<Content: View, Footer: View>: View {
    let title: String
    var icon: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footerView: () -> Footer

    init(
        title: String,
        icon: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footerView: @escaping () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.footer = footer
        self.content = content
        self.footerView = footerView
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PalantirTheme.accent)
                }
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(WheelSysPalantirFormMetrics.titleFont))
                    .foregroundStyle(PalantirTheme.textPrimary)
                    .tracking(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WheelSysPalantirFormMetrics.headerBarPaddingH)
            .padding(.vertical, WheelSysPalantirFormMetrics.headerBarPaddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PalantirTheme.surfaceHigh)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundStyle(PalantirTheme.accent),
                alignment: .top
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(PalantirTheme.border),
                alignment: .bottom
            )

            VStack(alignment: .leading, spacing: WheelSysPalantirFormMetrics.innerSpacing) {
                content()
            }
            .padding(WheelSysPalantirFormMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PalantirTheme.surface)
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(PalantirTheme.labelFont(WheelSysPalantirFormMetrics.titleFont))
                    .foregroundStyle(PalantirTheme.textMuted)
                    .padding(.horizontal, 2)
                    .padding(.top, WheelSysPalantirFormMetrics.fieldSpacing)
            }
            footerView()
        }
    }
}

// MARK: - Fields

struct WheelSysPalantirField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: WheelSysPalantirFormMetrics.fieldSpacing) {
            Text(label.uppercased())
                .font(PalantirTheme.labelFont(WheelSysPalantirFormMetrics.labelFont))
                .foregroundStyle(PalantirTheme.textMuted)
            content()
        }
    }
}

struct WheelSysPalantirTextInput: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var disabled: Bool = false

    var body: some View {
        WheelSysPalantirField(label: label) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .font(PalantirTheme.dataFont(WheelSysPalantirFormMetrics.fieldFont))
                .foregroundStyle(PalantirTheme.textPrimary)
                .padding(.horizontal, WheelSysPalantirFormMetrics.inputPaddingH)
                .padding(.vertical, WheelSysPalantirFormMetrics.inputPaddingV)
                .background(PalantirTheme.background.opacity(0.55))
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
                .disabled(disabled)
        }
    }
}

struct WheelSysPalantirResCodeInput: View {
    let label: String
    let prefix: String
    @Binding var digits: String

    var body: some View {
        WheelSysPalantirField(label: label) {
            HStack(spacing: 6) {
                Text(prefix)
                    .font(PalantirTheme.dataFont(WheelSysPalantirFormMetrics.fieldFont))
                    .foregroundStyle(PalantirTheme.warning)
                TextField("Enter numbers".localized, text: $digits)
                    .keyboardType(.numberPad)
                    .font(PalantirTheme.dataFont(WheelSysPalantirFormMetrics.fieldFont))
                    .foregroundStyle(PalantirTheme.textPrimary)
            }
            .padding(.horizontal, WheelSysPalantirFormMetrics.inputPaddingH)
            .padding(.vertical, WheelSysPalantirFormMetrics.inputPaddingV)
            .background(PalantirTheme.background.opacity(0.55))
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
    }
}

struct WheelSysPalantirDateInput: View {
    let label: String
    @Binding var date: Date
    var components: DatePicker.Components = [.date]

    var body: some View {
        WheelSysPalantirField(label: label) {
            DatePicker("", selection: $date, displayedComponents: components)
                .labelsHidden()
                .font(PalantirTheme.dataFont(WheelSysPalantirFormMetrics.fieldFont))
                .foregroundStyle(PalantirTheme.textPrimary)
                .padding(.horizontal, WheelSysPalantirFormMetrics.inputPaddingH)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PalantirTheme.background.opacity(0.55))
                .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
    }
}

struct WheelSysPalantirFuelSlider: View {
    let label: String
    @Binding var eighths: Int
    var tint: Color = PalantirTheme.accent

    private var display: String { "\(eighths)/8" }

    var body: some View {
        WheelSysPalantirField(label: label) {
            VStack(spacing: 8) {
                HStack {
                    Spacer(minLength: 0)
                    Text(display)
                        .font(PalantirTheme.dataFont(WheelSysPalantirFormMetrics.fieldFont))
                        .foregroundStyle(tint)
                }
                Slider(
                    value: Binding(
                        get: { Double(eighths) },
                        set: { eighths = min(8, max(0, Int($0.rounded()))) }
                    ),
                    in: 0...8,
                    step: 1
                )
                .tint(tint)
            }
            .padding(.horizontal, WheelSysPalantirFormMetrics.inputPaddingH)
            .padding(.vertical, WheelSysPalantirFormMetrics.inputPaddingV)
            .background(PalantirTheme.background.opacity(0.55))
            .overlay(Rectangle().stroke(PalantirTheme.border, lineWidth: 1))
        }
    }
}

struct WheelSysPalantirToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var tint: Color = PalantirTheme.accent

    var body: some View {
        Button {
            isOn.toggle()
            HapticManager.shared.light()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? tint : PalantirTheme.textMuted)
                Text(label)
                    .font(PalantirTheme.bodyFont(WheelSysPalantirFormMetrics.fieldFont))
                    .foregroundStyle(PalantirTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WheelSysPalantirFormMetrics.inputPaddingH)
            .padding(.vertical, WheelSysPalantirFormMetrics.inputPaddingV)
            .background(isOn ? tint.opacity(0.12) : PalantirTheme.background.opacity(0.55))
            .overlay(Rectangle().stroke(isOn ? tint.opacity(0.45) : PalantirTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct WheelSysPalantirPrimaryButton: View {
    let title: String
    var icon: String = "checkmark.circle.fill"
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    private var labelColor: Color {
        (disabled || isLoading) ? PalantirTheme.textMuted : PalantirTheme.onAccent
    }

    private var fillColor: Color {
        (disabled || isLoading) ? PalantirTheme.surfaceHigh : PalantirTheme.accent
    }

    var body: some View {
        Button {
            guard !disabled && !isLoading else { return }
            HapticManager.shared.selection()
            HapticManager.shared.medium()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(labelColor)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title.uppercased())
                    .font(PalantirTheme.labelFont(12))
                    .tracking(0.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WheelSysPalantirFormMetrics.buttonPaddingV)
            .foregroundStyle(labelColor)
            .background(fillColor)
            .overlay(
                Rectangle().stroke(
                    (disabled || isLoading) ? PalantirTheme.border : PalantirTheme.accent.opacity(0.35),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
    }
}

struct WheelSysPalantirSecondaryButton: View {
    let title: String
    var icon: String
    var tint: Color = PalantirTheme.accent
    /// Centered stack for equal-width side-by-side actions (e.g. scan photo buttons).
    var compact: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(title)
                            .font(PalantirTheme.labelFont(11))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(title)
                            .font(PalantirTheme.labelFont(12))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 13)
                }
            }
            .foregroundStyle(tint)
            .background(tint.opacity(0.1))
            .overlay(Rectangle().stroke(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct WheelSysPalantirInsetDivider: View {
    var body: some View {
        Rectangle()
            .fill(PalantirTheme.border)
            .frame(height: 1)
    }
}

/// Scroll container for full Palantir CH operation forms.
struct WheelSysPalantirFormScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: WheelSysPalantirFormMetrics.scrollSpacing) {
                content()
            }
            .padding(.horizontal, WheelSysPalantirFormMetrics.scrollHPadding)
            .padding(.vertical, WheelSysPalantirFormMetrics.scrollVPadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PalantirTheme.background)
    }
}

/// Styles a legacy `Form` when Palantir scroll layout is not used.
struct WheelSysPalantirFormListStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(PalantirTheme.background)
            .tint(PalantirTheme.accent)
    }
}

extension View {
    func wheelSysPalantirFormListStyle() -> some View {
        modifier(WheelSysPalantirFormListStyle())
    }

    @ViewBuilder
    func palantirFormListStyleWhen(enabled: Bool) -> some View {
        if enabled {
            self.wheelSysPalantirFormListStyle()
        } else {
            self
        }
    }

    func wheelSysPalantirListRow() -> some View {
        listRowInsets(EdgeInsets(top: 11, leading: 15, bottom: 11, trailing: 15))
            .listRowBackground(PalantirTheme.surface)
            .listRowSeparatorTint(PalantirTheme.border)
    }
}
