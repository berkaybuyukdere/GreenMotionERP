import SwiftUI

/// Displays upload progress for photos and data
struct UploadProgressView: View {
    let progress: Double // 0.0 to 1.0
    let currentItem: Int
    let totalItems: Int
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .tint(.green)
                .frame(height: 8)
                .padding(.horizontal)
            
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("\(currentItem)/\(totalItems) completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

/// Loading state for long operations
struct LoadingStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.blue)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Error display view
struct ErrorView: View {
    let error: String
    let retryAction: (() -> Void)?
    
    init(error: String, retryAction: (() -> Void)? = nil) {
        self.error = error
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let retry = retryAction {
                Button {
                    retry()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

/// Empty state view for damage records
struct EmptyDamageView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("No Damage Records")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("This vehicle has no recorded damages.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

/// Empty state view for returns
struct EmptyReturnView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 60))
                .foregroundColor(.purple)
            
            Text("No Return Operations")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("No return operations recorded for this vehicle.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

