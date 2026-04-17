import SwiftUI

struct USaveMiniLogoView: View {
    var size: CGSize = CGSize(width: 112, height: 40)

    var body: some View {
        Image("usave_logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .shadow(color: Color.yellow.opacity(0.28), radius: 8, x: 0, y: 2)
    }
}

