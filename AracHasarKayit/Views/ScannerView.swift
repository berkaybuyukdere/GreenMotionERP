import SwiftUI

struct ScannerView: View {
    @State private var isActive = false
    
    var body: some View {
        NavigationView {
            PlakaScannerView(isActive: $isActive)
                .navigationTitle("Plaka Tarama")
                .onAppear {
                    isActive = true
                }
                .onDisappear {
                    isActive = false
                }
        }
    }
}
