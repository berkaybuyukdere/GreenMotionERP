import SwiftUI

/// Modern Apple-style toast notification manager
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var toast: ToastModel?
    
    private init() {}
    
    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 2.5) {
        // Cancel any existing toast
        toast = nil
        
        // Show new toast after a tiny delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.toast = ToastModel(message: message, type: type)
            }
            
            // Auto dismiss
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
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(toast.type.color)
            
            Text(toast.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.leading)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Toast overlay
            if let toast = toastManager.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 50)
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

