import SwiftUI

struct LaunchScreenView: View {
    @State private var animasyon = false
    @Binding var gosteriliyor: Bool
    
    var body: some View {
        ZStack {
            // Yeşil arka plan - gradient
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.05, green: 0.5, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer()
                
                // Logo veya ikon
                Image(systemName: "car.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.white.opacity(0.9))
                    .scaleEffect(animasyon ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animasyon)
                
                VStack(spacing: 8) {
                    // Ana başlık
                    Text("Green Motion AG")
                        .font(.system(size: 42, weight: .thin))
                        .foregroundColor(.white)
                        .tracking(2)
                    
                    // Alt başlık
                    Text("Zurich")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(6)
                }
                .opacity(animasyon ? 1 : 0.3)
                
                Spacer()
                Spacer()
            }
        }
        .onAppear {
            animasyon = true
            
            // 2.5 saniye sonra kaybol
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    gosteriliyor = false
                }
            }
        }
    }
}
