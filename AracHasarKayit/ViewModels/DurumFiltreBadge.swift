import SwiftUI

struct DurumFiltreBadge: View {
    let baslik: String
    let secili: Bool
    var renk: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(baslik)
                .font(.subheadline)
                .fontWeight(secili ? .semibold : .regular)
                .foregroundColor(secili ? .white : renk)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(secili ? renk : renk.opacity(0.1))
                .cornerRadius(20)
        }
    }
}
