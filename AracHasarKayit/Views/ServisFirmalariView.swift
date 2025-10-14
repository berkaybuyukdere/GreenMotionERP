import SwiftUI

struct ServisFirmalariView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State private var aramaMetni = ""
    @State private var yeniFirmaGoster = false
    
    
    var filtreliFirmalar: [ServisFirma] {
        if aramaMetni.isEmpty {
            return viewModel.servisFirmalari.sorted { $0.ad < $1.ad }
        } else {
            return viewModel.servisFirmalari.filter { firma in
                firma.ad.localizedCaseInsensitiveContains(aramaMetni) ||
                firma.telefon.localizedCaseInsensitiveContains(aramaMetni) ||
                firma.adres.localizedCaseInsensitiveContains(aramaMetni)
            }.sorted { $0.ad < $1.ad }
        }
    }
    
    var body: some View {
        Group {
            if viewModel.servisFirmalari.isEmpty {
                // Boş durum
                VStack(spacing: 20) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("Henüz Servis Firması Yok")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Servis firmalarınızı kaydedin")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        yeniFirmaGoster = true
                    } label: {
                        Label("Servis Firması Ekle", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.top)
                }
            } else {
                List {
                    ForEach(filtreliFirmalar) { firma in
                        NavigationLink(destination: ServisFirmaDetayView(firma: firma)) {
                            ServisFirmaSatirView(firma: firma)
                        }
                    }
                    .onDelete(perform: firmaSil)
                }
                .searchable(text: $aramaMetni, prompt: "Firma ara...")
            }
        }
        .navigationTitle("Servis Firmaları")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    yeniFirmaGoster = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
            
            if !viewModel.servisFirmalari.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $yeniFirmaGoster) {
            NavigationView {
                ServisFirmaEkleView()
            }
        }
    }
    
    func firmaSil(at offsets: IndexSet) {
        for index in offsets {
            let firma = filtreliFirmalar[index]
            viewModel.servisFirmaSil(firma)
        }
    }
}
