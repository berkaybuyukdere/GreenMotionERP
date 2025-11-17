import SwiftUI

struct ServisDetayView: View {
    @EnvironmentObject var viewModel: AracViewModel
    @State var servis: Servis
    @State private var duzenlemeGoster = false
    @State private var silmeOnayiGoster = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var guncelServis: Servis {
        viewModel.servisler.first(where: { $0.id == servis.id }) ?? servis
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Card
                statusCard
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Vehicle Information
                informationCard(title: "Vehicle Information", icon: "car.fill") {
                    informationRow(label: "Plate", value: guncelServis.aracPlaka, icon: "number.square.fill")
                    
                    if let arac = viewModel.araclar.first(where: { $0.id == guncelServis.aracId }) {
                        Divider()
                            .padding(.vertical, 4)
                        informationRow(label: "Brand/Model", value: "\(arac.marka) \(arac.model)", icon: "car.fill")
                    }
                }
                .padding(.horizontal)
                
                // Service Information
                informationCard(title: "Service Information", icon: "wrench.and.screwdriver.fill") {
                    informationRow(label: "Service Company", value: guncelServis.servisFirmaAdi, icon: "building.2.fill")
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    informationRow(label: "Send Date", value: guncelServis.gonderilmeTarihi.formatted(date: .abbreviated, time: .omitted), icon: "calendar")
                    
                    if let teslimTarihi = guncelServis.teslimTarihi {
                        Divider()
                            .padding(.vertical, 4)
                        informationRow(label: "Delivery Date", value: teslimTarihi.formatted(date: .abbreviated, time: .omitted), icon: "calendar.badge.checkmark")
                    }
                }
                .padding(.horizontal)
                
                // Service Reasons
                if !guncelServis.servisNedenleri.isEmpty {
                    informationCard(title: "Service Reasons", icon: "checkmark.circle.fill") {
                        ForEach(Array(guncelServis.servisNedenleri.enumerated()), id: \.element) { index, neden in
                            HStack(spacing: 12) {
                                Image(systemName: neden.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                Text(neden.rawValue)
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            
                            if index < guncelServis.servisNedenleri.count - 1 {
                                Divider()
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Description
                if !guncelServis.aciklama.isEmpty {
                    informationCard(title: "Description", icon: "text.alignleft") {
                        Text(guncelServis.aciklama)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }
                
                // Delete Button
                Button(role: .destructive) {
                    silmeOnayiGoster = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Delete Service Record")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Service Details")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    duzenlemeGoster = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $duzenlemeGoster) {
            NavigationView {
                ServisEkleView(duzenlenecekServis: guncelServis)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(false)
            .presentationBackgroundInteraction(.enabled(upThrough: .large))
        }
        .alert("Delete Service Record", isPresented: $silmeOnayiGoster) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.servisSil(guncelServis)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this service record? This action cannot be undone.")
        }
        .onAppear {
            servis = guncelServis
        }
    }
    
    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: guncelServis.durum.icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            
            Text(guncelServis.durum.displayTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(statusColor)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(statusColor.opacity(colorScheme == .dark ? 0.5 : 0.3), lineWidth: colorScheme == .dark ? 2.5 : 2)
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.1), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Information Card
    private func informationCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Divider()
                .background(colorScheme == .dark ? Color(.systemGray3) : Color(.systemGray4))
            
            content()
        }
        .padding(20)
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
    
    // MARK: - Information Row
    private func informationRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
    
    private var statusColor: Color {
        Color(uiColor: guncelServis.durum.renk)
    }
}
