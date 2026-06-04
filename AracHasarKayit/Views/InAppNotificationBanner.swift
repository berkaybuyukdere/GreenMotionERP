import SwiftUI
import AudioToolbox

// MARK: - In-App Notification Item
struct InAppNotificationItem: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
    var action: (() -> Void)?
}

// MARK: - In-App Notification Manager
/// Shows at most **one** banner at a time. A new notification replaces any previous (queue removed).
class InAppNotificationManager: ObservableObject {
    static let shared = InAppNotificationManager()

    @Published var currentNotification: InAppNotificationItem?
    private var dismissTimer: Timer?
    private var pendingShowWorkItem: DispatchWorkItem?

    /// Success-style banner after operations finish; defaults to 2s so it does not stack with sheets/dismiss.
    func showAfterDelay(
        _ delay: TimeInterval = 2.0,
        icon: String,
        iconColor: Color,
        title: String,
        body: String,
        action: (() -> Void)? = nil
    ) {
        pendingShowWorkItem?.cancel()
        let item = InAppNotificationItem(icon: icon, iconColor: iconColor, title: title, body: body, action: action)
        let work = DispatchWorkItem { [weak self] in
            self?.presentItem(item)
        }
        pendingShowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func show(icon: String, iconColor: Color, title: String, body: String, action: (() -> Void)? = nil) {
        pendingShowWorkItem?.cancel()
        let item = InAppNotificationItem(icon: icon, iconColor: iconColor, title: title, body: body, action: action)
        DispatchQueue.main.async { [weak self] in
            self?.presentItem(item)
        }
    }

    private func presentItem(_ item: InAppNotificationItem) {
        dismissTimer?.invalidate()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentNotification = item
        }
        AudioServicesPlaySystemSound(SystemSoundID(1007))
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.dismissAnimated()
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.pendingShowWorkItem?.cancel()
            self.pendingShowWorkItem = nil
            self.dismissAnimated()
        }
    }

    private func dismissAnimated() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentNotification = nil
        }
    }
}

// MARK: - In-App Notification Banner View
struct InAppNotificationBanner: View {
    let item: InAppNotificationItem
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var opacity: Double = 1.0

    var body: some View {
        Button {
            item.action?()
            onDismiss()
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.iconColor)
                        .frame(width: 44, height: 44)
                    Image(systemName: item.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(item.body)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
            )
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .offset(y: dragOffset)
        .opacity(opacity)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let y = value.translation.height
                    if y < 0 {
                        dragOffset = y
                        opacity = max(0, min(1, 1.0 + Double(y) / 80.0))
                    }
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = -120
                            opacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            dragOffset = 0
                            opacity = 1
                        }
                    }
                }
        )
    }
}

// MARK: - Notification Banner Host (attach to root view)
struct NotificationBannerHost: ViewModifier {
    @ObservedObject var manager = InAppNotificationManager.shared

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let item = manager.currentNotification {
                InAppNotificationBanner(item: item) {
                    manager.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
                .padding(.top, 8)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: manager.currentNotification?.id)
            }
        }
    }
}

extension View {
    func inAppNotificationBanner() -> some View {
        modifier(NotificationBannerHost())
    }
}
