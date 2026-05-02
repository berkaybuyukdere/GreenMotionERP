import SwiftUI

struct ServisSatirView: View {
    let servis: Servis
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Status: colour only on the right badge; left icon uses neutral frame + blue ring.
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 48, height: 48)
                Circle()
                    .stroke(Color.blue.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 48, height: 48)
                Image(systemName: servis.durum.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(.systemGray))
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(servis.aracPlaka)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(servis.servisFirmaAdi)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Status Badge
                    statusBadge
                }
                
                // Metadata
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(servis.gonderilmeTarihi.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    if !servis.servisNedenleri.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            let reasonText = servis.servisNedenleri.count == 1 ? "reason" : "reasons"
                            Text("\(servis.servisNedenleri.count) \(reasonText)")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 4, x: 0, y: 1)
    }
    
    private var statusColor: Color {
        Color(uiColor: servis.durum.renk)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(servis.durum.displayTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.15))
        )
    }
}
