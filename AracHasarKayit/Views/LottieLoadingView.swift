import SwiftUI
import Lottie

/// Lottie-based loading view for better UX
struct LottieLoadingView: View {
    var animationName: String? = nil
    
    var body: some View {
        ZStack {
            if let animationName = animationName {
                LottieView(name: animationName, loopMode: .loop)
                    .frame(width: 200, height: 200)
            } else {
                // Fallback to ProgressView if animation fails to load
                ProgressView()
                    .scaleEffect(1.5)
            }
        }
    }
}

/// Simple loading spinner using Lottie (if animation file is available)
struct LottieSpinner: View {
    var size: CGFloat = 50
    var color: Color = .blue
    
    var body: some View {
        // Placeholder - in production, load actual Lottie animation
        ProgressView()
            .scaleEffect(size / 50)
            .tint(color)
    }
}

/// Success animation view
struct LottieSuccessView: View {
    @Binding var isAnimating: Bool
    
    var body: some View {
        // Placeholder - in production, load success animation
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.system(size: 60))
            .scaleEffect(isAnimating ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isAnimating)
    }
}

/// Error animation view
struct LottieErrorView: View {
    @Binding var isAnimating: Bool
    
    var body: some View {
        // Placeholder - in production, load error animation
        Image(systemName: "xmark.circle.fill")
            .foregroundColor(.red)
            .font(.system(size: 60))
            .scaleEffect(isAnimating ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isAnimating)
    }
}

/// Lottie view wrapper for SwiftUI
struct LottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop
    var animationSpeed: CGFloat = 1.0
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let animationView = LottieAnimationView(name: name)
        animationView.loopMode = loopMode
        animationView.animationSpeed = animationSpeed
        animationView.contentMode = .scaleAspectFit
        animationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationView)
        
        NSLayoutConstraint.activate([
            animationView.widthAnchor.constraint(equalTo: view.widthAnchor),
            animationView.heightAnchor.constraint(equalTo: view.heightAnchor),
            animationView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        animationView.play()
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update if needed
    }
}
