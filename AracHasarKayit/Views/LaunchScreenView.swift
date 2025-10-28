import SwiftUI

struct LaunchScreenView: View {
    @State private var animasyon = false
    @State private var logoRotation: Double = 0
    @State private var shimmerOffset: CGFloat = -200
    @Binding var gosteriliyor: Bool
    
    var body: some View {
        ZStack {
            // MARK: - Premium Gradient Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.15, blue: 0.25),
                    Color(red: 0.02, green: 0.08, blue: 0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle grid pattern overlay
            GeometryReader { geometry in
                Path { path in
                    let gridSize: CGFloat = 40
                    for x in stride(from: 0, through: geometry.size.width, by: gridSize) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    for y in stride(from: 0, through: geometry.size.height, by: gridSize) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.02), lineWidth: 1)
            }
            
            VStack(spacing: 0) {
                Spacer()
                
                // MARK: - Animated Logo with Glow Effect
                ZStack {
                    // Outer glow rings
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.3), Color.blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 160 + CGFloat(index * 20), height: 160 + CGFloat(index * 20))
                            .opacity(animasyon ? 0.4 - Double(index) * 0.1 : 0)
                            .scaleEffect(animasyon ? 1 : 0.8)
                            .animation(
                                .easeOut(duration: 1.5)
                                .delay(Double(index) * 0.15)
                                .repeatForever(autoreverses: true),
                                value: animasyon
                            )
                    }
                    
                    // Main logo circle with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.8, blue: 0.4),
                                    Color(red: 0.1, green: 0.6, blue: 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.green.opacity(0.5), radius: 20, x: 0, y: 10)
                        .scaleEffect(animasyon ? 1 : 0.5)
                        .rotationEffect(.degrees(logoRotation))
                    
                    // Car icon
                    Image(systemName: "car.fill")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                        .scaleEffect(animasyon ? 1 : 0.5)
                        .opacity(animasyon ? 1 : 0)
                }
                .padding(.bottom, 50)
                
                // MARK: - Company Name with Shimmer Effect
                VStack(spacing: 16) {
                    ZStack {
                        Text("GREEN MOTION")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .tracking(4)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, Color(red: 0.8, green: 0.8, blue: 0.9)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        
                        // Shimmer effect
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.6),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 100)
                            .offset(x: shimmerOffset)
                            .mask(
                                Text("GREEN MOTION")
                                    .font(.system(size: 42, weight: .black, design: .rounded))
                                    .tracking(4)
                            )
                    }
                    .opacity(animasyon ? 1 : 0)
                    .offset(y: animasyon ? 0 : 30)
                    
                    // Location badge
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text("ZÜRICH • SWITZERLAND")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .tracking(3)
                    }
                    .foregroundColor(Color(red: 0.6, green: 0.9, blue: 0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .opacity(animasyon ? 1 : 0)
                    .offset(y: animasyon ? 0 : -20)
                }
                
                
                Spacer()
                
                // MARK: - Bottom Info with Progress Indicator
                VStack(spacing: 16) {
                    Text("Fleet Management System")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Animated loading indicator
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.green.opacity(0.8))
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
                    
                    Text("Version 1.0")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .opacity(animasyon ? 1 : 0)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animasyon = true
            }
            
            // Logo rotation animation
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                logoRotation = 360
            }
            
            // Shimmer animation
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
            
            // Auto dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    gosteriliyor = false
                }
            }
        }
    }
}

#Preview {
    LaunchScreenView(gosteriliyor: .constant(true))
}
