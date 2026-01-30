import SwiftUI
import Kingfisher

struct IadeDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let iade: IadeIslemi
    @State private var silmeOnayiGoster = false
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    @State private var fotografGoster = false
    @State private var seciliFotografIndex: Int = 0
    @State private var showEditSheet = false
    @Environment(\.dismiss) var dismiss
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == iade.aracId })
    }
    
    var body: some View {
        List {
            headerSection
            aracBilgileriSection
            
            if !iade.notlar.isEmpty {
                notlarSection
            }
            
            if !iade.fotograflar.isEmpty {
                fotograflarSection
            }
            
            silmeSection
        }
        .navigationTitle("Return Details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $fotografGoster) {
            if !iade.fotograflar.isEmpty {
                PhotoGalleryView(photoURLs: iade.fotograflar, initialIndex: seciliFotografIndex)
            }
        }
        .sheet(isPresented: $pdfPaylas) {
            if let url = pdfURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let arac = arac {
                SheetWrapper {
                    NavigationView {
                        IadeIslemView(
                            arac: arac,
                            existingIade: iade, // Pass existing iade for editing
                            onIadeCompleted: { updatedIade in
                                // Update is handled by viewModel
                                // Just dismiss the sheet
                            }
                        )
                    }
                }
            }
        }
        .alert("Delete Return Record".localized, isPresented: $silmeOnayiGoster) {
            Button("Cancel".localized, role: .cancel) { }
            Button("Delete".localized, role: .destructive) {
                viewModel.iadeSil(iade)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this return record?".localized)
        }
    }
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                if iade.status == .inProgress {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Return Saved (In Progress)".localized)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.purple)
                    
                    Text("Return Completed".localized)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
    
    private var aracBilgileriSection: some View {
        Section("Vehicle Information".localized) {
            HStack {
                Label("Plate".localized, systemImage: "number.square.fill")
                    .foregroundColor(.secondary)
                Spacer()
                Text(iade.aracPlaka)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Label("Return Date".localized, systemImage: "calendar")
                    .foregroundColor(.secondary)
                Spacer()
                Text(iade.iadeTarihi.formatted(date: .long, time: .shortened))
                    .fontWeight(.semibold)
            }
        }
    }
    
    private var notlarSection: some View {
        Section("Notes".localized) {
            Text(iade.notlar)
                .font(.body)
        }
    }
    
    private var fotograflarSection: some View {
        Section(String(format: "Photos (%d)".localized, iade.fotograflar.count)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(iade.fotograflar.enumerated()), id: \.offset) { index, urlString in
                        IadeFotoButton(
                            urlString: urlString,
                            index: index,
                            onTap: {
                                seciliFotografIndex = index
                                fotografGoster = true
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Show edit button for in-progress returns, PDF button for completed
            if iade.status == .inProgress {
                editButton
            } else {
                pdfButton
            }
        }
    }
    
    private var editButton: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack {
                Image(systemName: "pencil.circle.fill")
                Text("Edit Return".localized)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding()
            .background(Color.orange)
            .cornerRadius(12)
        }
    }
    
    private var pdfButton: some View {
        Button {
            generatePDF()
        } label: {
            HStack {
                if pdfOlusturuluyor {
                    ProgressView()
                        .tint(.white)
                    Text("PDF generating...".localized)
                } else {
                    Image(systemName: "doc.fill")
                    Text("Generate Return PDF".localized)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.white)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
        }
        .disabled(pdfOlusturuluyor)
    }
    
    private var silmeSection: some View {
        Section {
            Button(role: .destructive) {
                silmeOnayiGoster = true
            } label: {
                Label("Delete Return Record".localized, systemImage: "trash.fill")
            }
        }
    }
    
    func generatePDF() {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        
        IadePDFGenerator.shared.generateIadePDF(
            iade: iade,
            arac: arac
        ) { url in
            DispatchQueue.main.async {
                pdfOlusturuluyor = false
                if let url = url {
                    pdfURL = url
                    pdfPaylas = true
                }
            }
        }
    }
}

struct IadeFotoButton: View {
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
                
                Text(String(format: "Foto %d".localized, index + 1))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
    }
    
    func loadImage() {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        KingfisherManager.shared.retrieveImage(with: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    self.image = value.image
                case .failure(let error):
                    print("❌ Failed to load image: \(error.localizedDescription)")
                }
                self.isLoading = false
            }
        }
    }
}
