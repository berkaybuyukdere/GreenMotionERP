import SwiftUI

/// Generic loading state management
enum LoadingState<T> {
    case idle
    case loading
    case success(T)
    case failure(Error)
    
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
    
    var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }
    
    var hasValue: T? {
        if case .success(let value) = self {
            return value
        }
        return nil
    }
    
    var error: Error? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
    
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
    
    var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }
}

/// Loading state view modifier
struct LoadingStateViewModifier<T>: ViewModifier {
    @Binding var state: LoadingState<T>
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if state.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(20)
                .background(Color.black.opacity(0.7))
                .cornerRadius(16)
            }
            
            if let error = state.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Button("OK") {
                        state = .idle
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .padding(20)
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
            }
        }
    }
}

extension View {
    func loadingState<T>(_ state: Binding<LoadingState<T>>) -> some View {
        modifier(LoadingStateViewModifier(state: state))
    }
}

