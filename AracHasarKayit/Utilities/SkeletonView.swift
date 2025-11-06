import SwiftUI

/// Skeleton view for loading states
struct SkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat = 20
    var cornerRadius: CGFloat = 8
    
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.3))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
                    .animation(
                        Animation.linear(duration: 1.5)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            )
            .onAppear {
                isAnimating = true
            }
    }
}

/// Skeleton list row
struct SkeletonListRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView(width: 50, height: 50, cornerRadius: 8)
            
            VStack(alignment: .leading, spacing: 8) {
                SkeletonView(width: 200, height: 16)
                SkeletonView(width: 150, height: 14)
            }
            
            Spacer()
        }
        .padding()
    }
}

/// Skeleton card
struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonView(width: nil, height: 20)
            SkeletonView(width: nil, height: 16)
            SkeletonView(width: 100, height: 14)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(radius: 2)
    }
}

/// Loading state with skeleton
struct SkeletonLoadingView<Content: View>: View {
    let isLoading: Bool
    let content: () -> Content
    
    var body: some View {
        if isLoading {
            VStack(spacing: 16) {
                ForEach(0..<5) { _ in
                    SkeletonListRow()
                }
            }
        } else {
            content()
        }
    }
}

