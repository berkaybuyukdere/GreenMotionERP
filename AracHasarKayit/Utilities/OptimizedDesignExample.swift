import SwiftUI

/// Optimized Design Example - Shows how to use AppTheme consistently
/// This is a reusable template for all new views
struct OptimizedDesignExample: View {
    @State private var resKodu = ""
    @State private var km = ""
    @State private var tarih = Date()
    @State private var notlar = ""
    @State private var isUploading = false
    @State private var hasUnsavedChanges = false
    @State private var showImagePicker = false
    
    var body: some View {
        Form {
            // Info Section
            Section("Vehicle Information") {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.blue)
                    Text("RES Code")
                    Spacer()
                    TextField("RES-123", text: $resKodu)
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Image(systemName: "gauge.medium.badge.plus")
                        .foregroundColor(.green)
                    Text("Kilometers")
                    Spacer()
                    TextField("0", text: $km)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                
                DatePicker("Date", selection: $tarih, displayedComponents: .date)
            }
            
            // Photos Section
            Section("Photos") {
                HStack(spacing: 12) {
                    Button {
                        showImagePicker = true
                    } label: {
                        Label("Add Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button {
                        // Take photo action
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            
            // Notes Section
            Section("Notes") {
                TextEditor(text: $notlar)
                    .frame(height: 100)
            }
            
            // Action Buttons Section - OPTIMIZED WITH AppTheme
            Section {
                // Primary Action Button
                Button {
                    // Complete action
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Save & Complete")
                    }
                }
                .buttonStyle(SuccessButtonStyle())
                .disabled(resKodu.isEmpty || km.isEmpty)
                
                // Secondary Action Button
                Button {
                    // Save in progress
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Save (In Progress)")
                    }
                }
                .buttonStyle(WarningButtonStyle())
                .disabled(resKodu.isEmpty || km.isEmpty || isUploading)
            } footer: {
                Text("Use 'Save' to continue editing later, or 'Complete' to finish.")
                    .font(AppTheme.captionFont)
            }
        }
        .navigationTitle("Example Form")
    }
}

// MARK: - Reusable Components

/// Consistent photo grid component
struct OptimizedPhotoGrid: View {
    let photos: [UIImage]
    let onDelete: (Int) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(photos.indices, id: \.self) { index in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photos[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .cornerRadius(AppTheme.cornerRadius)
                            .clipped()
                        
                        Button {
                            onDelete(index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .background(Color.white.clipShape(Circle()))
                        }
                        .offset(x: 8, y: -8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// Consistent text field with icon
struct OptimizedTextField: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            Text(title)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Consistent date picker with icon
struct OptimizedDatePicker: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var date: Date
    var displayedComponents: DatePicker.Components = [.date]
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            DatePicker(title, selection: $date, displayedComponents: displayedComponents)
        }
    }
}

/// Consistent section with header and footer
struct OptimizedSection<Content: View>: View {
    let header: String
    let footer: String?
    let content: () -> Content
    
    init(_ header: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content
    }
    
    var body: some View {
        Section {
            content()
        } header: {
            Text(header)
                .font(AppTheme.headlineFont)
                .foregroundColor(.primary)
        } footer: {
            if let footer = footer {
                Text(footer)
                    .font(AppTheme.captionFont)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Loading overlay for uploads
struct LoadingOverlay: View {
    let message: String
    let progress: Double
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primary))
                .scaleEffect(1.2)
            
            Text(message)
                .font(AppTheme.headlineFont)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

/// Empty state view
struct OptimizedEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let iconColor: Color
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(iconColor)
            
            Text(title)
                .font(AppTheme.titleFont)
                .foregroundColor(.primary)
            
            Text(message)
                .font(AppTheme.bodyFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

/// Success toast view
struct OptimizedToastView: View {
    let message: String
    let type: ToastType
    
    enum ToastType {
        case success
        case error
        case warning
        case info
        
        var color: Color {
            switch self {
            case .success: return AppTheme.success
            case .error: return AppTheme.danger
            case .warning: return AppTheme.warning
            case .info: return AppTheme.info
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
            
            Text(message)
                .font(AppTheme.bodyFont)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: type.color.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Usage Example

struct OptimizedViewExample: View {
    @State private var showToast = false
    @State private var isLoading = false
    @State private var progress: Double = 0.0
    
    var body: some View {
        VStack(spacing: 20) {
            // Example: Loading overlay
            if isLoading {
                LoadingOverlay(message: "Uploading...", progress: progress)
            }
            
            // Example: Toast
            if showToast {
                OptimizedToastView(
                    message: "✓ Operation completed successfully",
                    type: .success
                )
            }
            
            // Example: Empty state
            OptimizedEmptyState(
                icon: "photo.on.rectangle",
                title: "No Photos",
                message: "Add photos by tapping the button below.",
                iconColor: AppTheme.info
            )
            
            Spacer()
            
            // Example: Buttons with AppTheme
            VStack(spacing: 12) {
                Button {
                    isLoading = true
                    // Simulate progress
                    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        if progress < 1.0 {
                            progress += 0.1
                        } else {
                            timer.invalidate()
                            isLoading = false
                            showToast = true
                            progress = 0.0
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Upload")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button {
                    showToast = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Show Toast")
                    }
                }
                .buttonStyle(WarningButtonStyle())
            }
            .padding()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

