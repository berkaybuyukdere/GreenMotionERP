//
//  DemoBannerView.swift
//  AracHasarKayit
//
//  Demo account warning banner
//

import SwiftUI

/// A banner view that shows remaining days for demo accounts
struct DemoBannerView: View {
    let daysRemaining: Int
    let onDismiss: () -> Void
    
    @State private var isVisible = true
    
    private var bannerColor: Color {
        if daysRemaining <= 3 {
            return .red
        } else if daysRemaining <= 7 {
            return .orange
        } else {
            return .yellow
        }
    }
    
    private var textColor: Color {
        if daysRemaining <= 7 {
            return .white
        } else {
            return .black
        }
    }
    
    var body: some View {
        if isVisible {
            HStack {
                Image(systemName: daysRemaining <= 7 ? "exclamationmark.triangle.fill" : "clock.fill")
                    .foregroundColor(textColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo Account")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(textColor.opacity(0.9))
                    
                    if daysRemaining > 0 {
                        Text("\(daysRemaining) days remaining")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(textColor)
                    } else {
                        Text("Demo expired")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(textColor)
                    }
                }
                
                Spacer()
                
                if daysRemaining <= 7 {
                    Text("Contact sales to upgrade")
                        .font(.caption2)
                        .foregroundColor(textColor.opacity(0.8))
                }
                
                Button(action: {
                    withAnimation {
                        isVisible = false
                        onDismiss()
                    }
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(textColor.opacity(0.7))
                        .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bannerColor)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// A view modifier that adds demo banner on top of the content
struct DemoBannerModifier: ViewModifier {
    let isDemo: Bool
    let demoExpiresAt: Date?
    @State private var isDismissed = false
    
    private var daysRemaining: Int? {
        guard let expiresAt = demoExpiresAt else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiresAt)
        return components.day
    }
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if isDemo, let days = daysRemaining, !isDismissed {
                DemoBannerView(daysRemaining: days) {
                    isDismissed = true
                }
            }
            
            content
        }
    }
}

extension View {
    /// Adds a demo banner if the user is on a demo account
    func demoBanner(isDemo: Bool, expiresAt: Date?) -> some View {
        modifier(DemoBannerModifier(isDemo: isDemo, demoExpiresAt: expiresAt))
    }
}

/// Demo status manager for checking and displaying demo status
class DemoStatusManager: ObservableObject {
    @Published var isDemo: Bool = false
    @Published var daysRemaining: Int?
    @Published var shouldShowExpiredAlert = false
    
    func updateStatus(isDemo: Bool, expiresAt: Date?) {
        self.isDemo = isDemo
        
        if isDemo, let expiresAt = expiresAt {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: Date(), to: expiresAt)
            daysRemaining = components.day
            
            // Check if expired
            if let days = daysRemaining, days <= 0 {
                shouldShowExpiredAlert = true
            }
        } else {
            daysRemaining = nil
        }
    }
    
    /// Checks if the demo is expired
    var isExpired: Bool {
        guard let days = daysRemaining else { return false }
        return days <= 0
    }
    
    /// Status text for display
    var statusText: String {
        guard isDemo else { return "Production Account" }
        
        if let days = daysRemaining {
            if days <= 0 {
                return "Demo Expired"
            } else if days == 1 {
                return "Demo: 1 day left"
            } else {
                return "Demo: \(days) days left"
            }
        }
        return "Demo Account"
    }
}

// MARK: - Preview

struct DemoBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DemoBannerView(daysRemaining: 25) {}
            DemoBannerView(daysRemaining: 7) {}
            DemoBannerView(daysRemaining: 3) {}
            DemoBannerView(daysRemaining: 0) {}
        }
    }
}
