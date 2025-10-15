import SwiftUI

struct LaunchScreenView: View {
    @State private var animasyon = false
    @Binding var gosteriliyor: Bool
    @State private var logoParlama = false
    
    var body: some View {
        ZStack {
            // MARK: - Dinamik Arka Plan Gradient (animasyonlu)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.green.opacity(0.85),
                    Color(red: 0.0, green: 0.3, blue: 0.1)
                ]),
                startPoint: animasyon ? .topLeading : .bottomTrailing,
                endPoint: animasyon ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animasyon)
            
            VStack(spacing: 30) {
                Spacer()
                
                // MARK: - 3D Logolu Görsel
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.2), Color.clear],
                                center: .center,
                                startRadius: 5,
                                endRadius: 120
                            )
                        )
                        .frame(width: 160, height: 160)
                        .blur(radius: 10)
                        .scaleEffect(logoParlama ? 1.15 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: logoParlama)
                    
                    Image(systemName: "car.rear.waves.up.fill")
                        .font(.system(size: 80, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white)
                        .rotation3DEffect(.degrees(animasyon ? 0 : 360), axis: (x: 0, y: 1, z: 0))
                        .shadow(color: .white.opacity(0.6), radius: 20, x: 0, y: 0)
                        .scaleEffect(animasyon ? 1.1 : 0.8)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animasyon)
                }
                
                // MARK: - Başlıklar
                VStack(spacing: 8) {
                    Text("Green Motion AG")
                        .font(.system(size: 44, weight: .thin, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.2), radius: 10, x: 0, y: 5)
                        .opacity(animasyon ? 1 : 0)
                        .transition(.opacity)
                    
                    Text("Zurich • Switzerland")
                        .font(.system(size: 20, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(3)
                        .opacity(animasyon ? 0.9 : 0)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // MARK: - Alt yazı animasyonu
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                        .opacity(animasyon ? 1 : 0.3)
                    Text("Sustainable Mobility for the Future")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .italic()
                        .opacity(animasyon ? 1 : 0.3)
                }
                .padding(.bottom, 40)
                .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2)) {
                animasyon = true
                logoParlama = true
            }
            
            // MARK: - 3 saniye sonra geçiş
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    gosteriliyor = false
                }
            }
        }
    }
}

#Preview {
    LaunchScreenView(gosteriliyor: .constant(true))
}
