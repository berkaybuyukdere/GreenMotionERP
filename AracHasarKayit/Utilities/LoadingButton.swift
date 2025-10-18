import SwiftUI

/// AirDrop-style loading button with circular progress ring
struct LoadingButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label
    @Binding var isLoading: Bool
    @Binding var progress: Double // 0.0 to 1.0
    
    var isDisabled: Bool = false
    var color: Color = .blue
    
    @State private var animationAmount: Double = 0
    
    init(
        action: @escaping () -> Void,
        isLoading: Binding<Bool>,
        progress: Binding<Double>,
        isDisabled: Bool = false,
        color: Color = .blue,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self._isLoading = isLoading
        self._progress = progress
        self.isDisabled = isDisabled
        self.color = color
        self.label = label
    }
    
    var body: some View {
        Button(action: {
            if !isLoading && !isDisabled {
                action()
            }
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(isDisabled ? 0.3 : 1.0))
                
                // Label or loading indicator
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    label()
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
        .disabled(isDisabled || isLoading)
        .frame(height: 50)
    }
}

/// Convenience extension for simple text labels
extension LoadingButton where Label == Text {
    init(
        _ title: String,
        action: @escaping () -> Void,
        isLoading: Binding<Bool>,
        progress: Binding<Double>,
        isDisabled: Bool = false,
        color: Color = .blue
    ) {
        self.init(
            action: action,
            isLoading: isLoading,
            progress: progress,
            isDisabled: isDisabled,
            color: color,
            label: { Text(title) }
        )
    }
}

/// Convenience extension for icon + text
extension LoadingButton where Label == HStack<TupleView<(Image, Text)>> {
    init(
        systemImage: String,
        title: String,
        action: @escaping () -> Void,
        isLoading: Binding<Bool>,
        progress: Binding<Double>,
        isDisabled: Bool = false,
        color: Color = .blue
    ) {
        self.init(
            action: action,
            isLoading: isLoading,
            progress: progress,
            isDisabled: isDisabled,
            color: color,
            label: {
                HStack {
                    Image(systemName: systemImage)
                    Text(title)
                }
            }
        )
    }
}

// MARK: - Preview
struct LoadingButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            LoadingButtonDemo()
        }
        .padding()
    }
    
    struct LoadingButtonDemo: View {
        @State private var isLoading = false
        @State private var progress: Double = 0.0
        
        var body: some View {
            VStack(spacing: 20) {
                // Example 1: Simple text
                LoadingButton(
                    "Save Vehicle",
                    action: simulateUpload,
                    isLoading: $isLoading,
                    progress: $progress,
                    color: .green
                )
                
                // Example 2: With icon
                LoadingButton(
                    systemImage: "checkmark.circle.fill",
                    title: "Complete",
                    action: simulateUpload,
                    isLoading: $isLoading,
                    progress: $progress,
                    color: .blue
                )
                
                // Example 3: Custom label
                LoadingButton(
                    action: simulateUpload,
                    isLoading: $isLoading,
                    progress: $progress,
                    color: .orange
                ) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Upload Photos")
                    }
                }
            }
        }
        
        func simulateUpload() {
            isLoading = true
            progress = 0.0
            
            // Simulate upload progress
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                progress += 0.05
                if progress >= 1.0 {
                    timer.invalidate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLoading = false
                        progress = 0.0
                    }
                }
            }
        }
    }
}

