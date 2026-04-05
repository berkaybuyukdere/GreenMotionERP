import SwiftUI

struct LaunchScreenView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var animasyon = false
    @State private var showX = false
    @State private var erpOpacity: Double = 0.0
    @Binding var gosteriliyor: Bool
    /// When false, the view does not auto-dismiss (e.g. session restore at app launch).
    var autoDismiss: Bool = true
    private var selectedCountry: Country { UserDefaults.standard.selectedCountry }
    
    var body: some View {
        ZStack {
            // Background adapts to color scheme
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // MARK: - ERPX Branding with Animation
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // ERP letters - animated opacity
                        HStack(spacing: 0) {
                            Text("E")
                                .font(.system(size: 72, weight: .thin, design: .default))
                            Text("R")
                                .font(.system(size: 72, weight: .thin, design: .default))
                            Text("P")
                                .font(.system(size: 72, weight: .thin, design: .default))
                        }
                        .foregroundColor(colorScheme == .dark ? 
                            Color.white.opacity(erpOpacity) : 
                            Color.black.opacity(erpOpacity))
                        
                        // X letter - appears first
                        Text("X")
                            .font(.system(size: 72, weight: .bold, design: .default))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .opacity(showX ? 1.0 : 0.0)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Spacer()
                
                Spacer()
                
                // MARK: - Bottom Info
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(selectedCountry.flag)
                            .font(.system(size: 14))
                        Text(selectedCountry.name)
                            .font(.system(size: 14, weight: .light, design: .default))
                            .foregroundColor(.gray)
                    }
                    .opacity(animasyon ? 1 : 0)
                    
                    // Animated loading indicator
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.gray.opacity(0.6))
                                .frame(width: 8, height: 8)
                                .scaleEffect(animasyon ? 1 : 0.5)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                    value: animasyon
                                )
                        }
                    }
                    .padding(.bottom, 8)
                    .opacity(animasyon ? 1 : 0)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Start animation sequence
            // First show X
            withAnimation(.easeOut(duration: 0.5)) {
                showX = true
            }
            
            // Then fade in ERP letters
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 1.0)) {
                    erpOpacity = 1.0
                }
            }
            
            // Show other elements
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.8)) {
                    animasyon = true
                }
            }
            
            if autoDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        gosteriliyor = false
                    }
                }
            }
        }
    }
}

#Preview {
    LaunchScreenView(gosteriliyor: .constant(true))
}
