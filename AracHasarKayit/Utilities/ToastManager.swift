import SwiftUI

class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var toast: ToastModel?
    
    private init() {}
    
    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 2.5, playHaptic: Bool = true) {
        toast = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.toast = ToastModel(message: message, type: type)
            }
            if playHaptic {
                self.playHaptic(for: type)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.dismiss()
            }
        }
    }
    
    func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            toast = nil
        }
    }

    private func playHaptic(for type: ToastType) {
        switch type {
        case .success:
            HapticManager.shared.success()
        case .error:
            HapticManager.shared.error()
        case .warning:
            HapticManager.shared.warning()
        case .info:
            HapticManager.shared.selection()
        }
    }
}

struct ToastModel: Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
}

enum ToastType {
    case success
    case error
    case warning
    case info
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return PalantirTheme.success
        case .error: return PalantirTheme.critical
        case .warning: return PalantirTheme.warning
        case .info: return PalantirTheme.accent
        }
    }

    var background: Color {
        color.opacity(0.1)
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastModel
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(toast.type.color)
            
            Text(toast.message)
                .font(PalantirTheme.bodyFont(13))
                .foregroundStyle(PalantirTheme.textPrimary)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(toast.type.background)
        .overlay(Rectangle().stroke(toast.type.color.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 13)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content

            if let toast = toastManager.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 42)
                        .onTapGesture {
                            toastManager.dismiss()
                        }
                    
                    Spacer()
                }
                .zIndex(999)
            }
        }
    }
}

extension View {
    func toastView() -> some View {
        modifier(ToastModifier())
    }
}

