import SwiftUI
import Kingfisher

struct ExitDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    let exit: ExitIslemi
    @State private var silmeOnayiGoster = false
    @State private var pdfOlusturuluyor = false
    @State private var pdfURL: URL?
    @State private var pdfPaylas = false
    @State private var fotografGoster = false
    @State private var seciliFotografIndex: Int = 0
    @State private var showEditSheet = false
    @Environment(\.dismiss) var dismiss
    
    var arac: Arac? {
        viewModel.araclar.first(where: { $0.id == exit.aracId })
    }
    
    var body: some View {
        List {
            headerSection
            aracBilgileriSection
            
            if !exit.notlar.isEmpty {
                notlarSection
            }
            
            if !exit.fotograflar.isEmpty {
                fotograflarSection
            }
            
            silmeSection
        }
        .navigationTitle("Check Out Details")
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
        .fullScreenCover(isPresented: $fotografGoster) {
            if !exit.fotograflar.isEmpty {
                PhotoGalleryView(photoURLs: exit.fotograflar, initialIndex: seciliFotografIndex)
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
                        ExitIslemView(
                            arac: arac,
                            existingExit: exit, // Pass existing exit for editing
                            onExitCompleted: { updatedExit in
                                // Update is handled by viewModel
                                // Just dismiss the sheet
                            }
                        )
                    }
                }
            }
        }
        .alert("Delete Check Out Record", isPresented: $silmeOnayiGoster) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.exitSil(exit)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this check out record?")
        }
    }
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                if exit.status == .inProgress {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Check Out Saved (In Progress)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Check Out Completed")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
    
    private var aracBilgileriSection: some View {
        Section("Vehicle Information") {
            HStack {
                Label("Plate", systemImage: "number.square.fill")
                    .foregroundColor(.secondary)
                Spacer()
                Text(exit.aracPlaka)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Label("Process Date", systemImage: "calendar")
                    .foregroundColor(.secondary)
                Spacer()
                Text(exit.createdAt.formatted(date: .long, time: .shortened))
                    .fontWeight(.semibold)
            }
            
            if !exit.resKodu.isEmpty {
                HStack {
                    Label("RES Code", systemImage: "number.square.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(exit.resKodu)
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var notlarSection: some View {
        Section("Notes") {
            Text(exit.notlar)
                .font(.body)
        }
    }
    
    private var fotograflarSection: some View {
        Section("Photos (\(exit.fotograflar.count))") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(exit.fotograflar.enumerated()), id: \.offset) { index, urlString in
                        ExitFotoButton(
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
            
            // Show PDF button for completed exits
            if exit.status == .completed {
                pdfButton
            }
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
                    Text("Generating PDF...")
                } else {
                    Image(systemName: "doc.fill")
                    Text("Generate PDF")
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
                Label("Delete Check Out Record", systemImage: "trash.fill")
            }
        }
    }
    
    func generatePDF() {
        guard let arac = arac else { return }
        pdfOlusturuluyor = true
        
        ExitPDFGenerator.shared.generateExitPDF(
            exit: exit,
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

struct ExitFotoButton: View {
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
                
                Text("Foto \(index + 1)")
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

