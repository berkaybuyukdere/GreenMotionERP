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
                .foregroundColor(secili ? .white : .primary.opacity(0.72))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if secili {
                            Capsule().fill(renk)
                        } else {
                            Capsule()
                                .fill(Color(.systemGray6))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.blue.opacity(0.45), lineWidth: 1)
                                )
                        }
                    }
                )
        }
    }
}
