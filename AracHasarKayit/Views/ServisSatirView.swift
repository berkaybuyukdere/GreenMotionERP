import SwiftUI

struct ServisSatirView: View {
    let servis: Servis
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: servis.durum.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(statusColor)
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
                            .font(.system(size: 13, weight: .medium))
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
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                            let reasonText = servis.servisNedenleri.count == 1 ? "reason" : "reasons"
                            Text("\(servis.servisNedenleri.count) \(reasonText)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4).opacity(0.5), lineWidth: colorScheme == .dark ? 1 : 0.5)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.05), radius: 6, x: 0, y: 2)
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
