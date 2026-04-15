import SwiftUI
import Kingfisher

struct OfficeReturnDetailView: View {
    let returnOp: OfficeReturn
    @EnvironmentObject var viewModel: AracViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var showPhotoPreview = false
    
    var body: some View {
        List {
            // Header Section
            headerSection
            
            // Details Section
            detailsSection
            
            // Notes Section
            if !returnOp.notes.isEmpty {
                notesSection
            }
            
            // Photos Section
            if !returnOp.photos.isEmpty {
                photosSection
            }
            
            // Actions Section
            actionsSection
        }
        .navigationTitle("Return Details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationView {
                OfficeReturnEkleView(editingReturn: returnOp)
                    .environmentObject(viewModel)
            }
        }
        .fullScreenCover(isPresented: $showPhotoPreview) {
            if !returnOp.photos.isEmpty {
                NativePhotoGalleryView(urlStrings: returnOp.photos, initialIndex: selectedPhotoIndex)
            }
        }
        .alert("Delete Return".localized, isPresented: $showDeleteConfirmation) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Delete".localized, role: .destructive) {
                viewModel.officeReturnSil(returnOp)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this return? This action cannot be undone.".localized)
        }
    }
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: returnOp.reason.icon)
                    .font(.system(size: 50))
                    .foregroundColor(getColor())
                
                Text(returnOp.reason.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(AppCurrency.format(returnOp.amount))
                    .font(.title3)
                    .foregroundColor(getColor())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
    
    private var detailsSection: some View {
        Section("Details".localized) {
            HStack {
                Label("Date".localized, systemImage: "calendar")
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDate(returnOp.date))
                    .fontWeight(.semibold)
            }
            
            HStack {
                Label("Amount".localized, systemImage: "dollarsign.circle")
                    .foregroundColor(.secondary)
                Spacer()
                Text(AppCurrency.format(returnOp.amount))
                    .fontWeight(.semibold)
                    .foregroundColor(getColor())
            }
            
            if !returnOp.photos.isEmpty {
                HStack {
                    Label("Photos".localized, systemImage: "photo")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(returnOp.photos.count)")
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes".localized) {
            Text(returnOp.notes)
                .font(AppTheme.bodyFont)
        }
    }
    
    private var photosSection: some View {
        Section(String(format: "Photos (%d)".localized, returnOp.photos.count)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(returnOp.photos.enumerated()), id: \.offset) { index, urlString in
                        PhotoThumbnailView(
                            urlString: urlString,
                            index: index,
                            onTap: {
                                selectedPhotoIndex = index
                                showPhotoPreview = true
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Return".localized, systemImage: "trash.fill")
            }
        }
    }
    
    private func getColor() -> Color {
        switch returnOp.reason.color {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "gray": return .gray
        default: return .indigo
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct PhotoThumbnailView: View {
    let urlString: String
    let index: Int
    let onTap: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .cornerRadius(12)
                        .clipped()
                } else if isLoading {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .cornerRadius(12)
                        
                        ProgressView()
                    }
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 120)
                            .cornerRadius(12)
                        
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    }
                }
                
                Text(String(format: "Photo %d".localized, index + 1))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
    }
    
    func loadImage() {
        StorageImageLoader.shared.loadImage(from: urlString) { loadedImage in
            if loadedImage == nil {
                print("❌ Failed to load image from all candidates")
            }
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

