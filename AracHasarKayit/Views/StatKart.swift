import SwiftUI

struct StatKart: View {
    let baslik: String
    let deger: String
    let ikon: String
    let renk: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: ikon)
                    .foregroundColor(renk)
                Text(baslik)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(deger)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(renk)
        }
        .frame(minWidth: 120)
        .padding()
        .background(renk.opacity(0.1))
        .cornerRadius(12)
    }
}
