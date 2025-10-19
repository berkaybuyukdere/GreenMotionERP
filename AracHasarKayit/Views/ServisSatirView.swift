import SwiftUI

struct ServisSatirView: View {
    let servis: Servis
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: servis.durum.renk).opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: servis.durum.icon)
                    .font(.title3)
                    .foregroundColor(Color(uiColor: servis.durum.renk))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(servis.aracPlaka)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(servis.servisFirmaAdi)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Label {
                        Text(servis.gonderilmeTarihi.formatted(date: .abbreviated, time: .omitted))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: servis.durum.icon)
                            .font(.caption2)
                        Text(servis.durum.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: servis.durum.renk))
                    .cornerRadius(8)
                }
                
                if !servis.servisNedenleri.isEmpty {
                    Label("\(servis.servisNedenleri.count) iÅŸlem", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
