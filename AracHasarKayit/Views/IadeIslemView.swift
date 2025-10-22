import SwiftUI

struct IadeIslemView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    let arac: Arac
    var onIadeCompleted: ((IadeIslemi) -> Void)? = nil
    
    @State private var iadeTarihi = Date()
    @State private var notlar = ""
    @State private var fotograflar: [UIImage] = [] // Photos from gallery
    @State private var cameraPhotos: [UIImage] = [] // Photos from camera
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadedPhotoURLs: [String] = []
    
    var body: some View {
        Form {
            Section("İade Bilgileri") {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.purple)
                    Text("Araç")
                    Spacer()
                    Text(arac.plakaFormatli)
                        .foregroundColor(.secondary)
                }
                
                DatePicker("İade Tarihi", selection: $iadeTarihi, displayedComponents: [.date, .hourAndMinute])
            }
            
            Section("Notlar") {
                TextEditor(text: $notlar)
                    .frame(height: 100)
            }
            
            Section("Fotoğraflar") {
                let allPhotos = fotograflar + cameraPhotos
                
                if !allPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // Gallery photos
                            ForEach(fotograflar.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: fotograflar[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Button {
                                            fotograflar.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white.clipShape(Circle()))
                                        }
                                        
                                        Text("Gallery")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    .padding(4)
                                }
                            }
                            
                            // Camera photos
                            ForEach(cameraPhotos.indices, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: cameraPhotos[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Button {
                                            cameraPhotos.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .background(Color.white.clipShape(Circle()))
                                        }
                                        
                                        Text("Camera")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                }
                
                Button {
                    showImagePicker = true
                } label: {
                    Label("Add Photo from Gallery", systemImage: "photo.on.rectangle.angled")
                        .foregroundColor(.blue)
                }
                
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo with Camera", systemImage: "camera.fill")
                        .foregroundColor(.green)
                }
            }
            
            Section {
                Button {
                    kaydet()
                } label: {
                    if isUploading {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Uploading Photos...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Complete Return")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isUploading)
            }
        }
        .navigationTitle("Return Process")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $fotograflar)
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            // After camera dismisses, check if we should reopen for more photos
            if let _ = capturedImage {
                // Photo was taken, reopen camera if under limit
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if cameraPhotos.count < 20 && !showImagePicker {
                        showCamera = true
                    }
                }
            }
        }) {
            CameraPicker(selectedImage: $capturedImage)
        }
        .onChange(of: capturedImage) { newImage in
            // Only process camera photos, not gallery photos
            guard let newImage = newImage, !showImagePicker else { return }
            
            // Add to camera photos array
            cameraPhotos.append(newImage)
            
            // Clear the captured image to prepare for next capture
            capturedImage = nil
        }
    }
    
    func kaydet() {
        isUploading = true
        uploadedPhotoURLs = []
        
        // Combine all photos: gallery photos first, then camera photos
        let allPhotosToUpload = fotograflar + cameraPhotos
        
        let group = DispatchGroup()
        
        for foto in allPhotosToUpload {
            group.enter()
            let path = "iade_fotograflari/\(UUID().uuidString).jpg"
            CachedImageManager.shared.uploadImage(foto, path: path) { url, error in
                if let url = url {
                    uploadedPhotoURLs.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let yeniIade = IadeIslemi(
                aracId: arac.id,
                aracPlaka: arac.plakaFormatli,
                iadeTarihi: iadeTarihi,
                fotograflar: uploadedPhotoURLs,
                notlar: notlar
            )
            
            viewModel.iadeEkle(yeniIade)
            
            // 🔔 Send notification for return processed
            let userName = authManager.userProfile?.fullName ?? "Unknown User"
            notificationManager.sendReturnNotification(
                carPlate: arac.plakaFormatli,
                userName: userName
            )
            
            isUploading = false
            
            // Show success toast with checkmark icon
            ToastManager.shared.show("✓ Return Completed", type: .success)
            
            // Call the completion callback with the new iade
            onIadeCompleted?(yeniIade)
            
            dismiss()
        }
    }
}
