import Foundation
import UIKit

/// Checkout vs return photo comparison removed (CH). Pair builder kept for potential future non-LLM use.
struct HandoverReturnPair: Identifiable {
    let id: Int
    var handoverImage: UIImage?
    var returnImage: UIImage?
}

enum HandoverReturnVisionAnalyzer {
    static func buildPairs(exit: ExitIslemi, iade: IadeIslemi) -> [HandoverReturnPair] {
        let maxCount = max(exit.fotograflar.count, iade.fotograflar.count)
        return (0..<maxCount).map { HandoverReturnPair(id: $0, handoverImage: nil, returnImage: nil) }
    }

    static func resolveCheckout(for iade: IadeIslemi, exits: [ExitIslemi]) -> ExitIslemi? {
        if let lid = iade.linkedExitId,
           let match = exits.first(where: { $0.id == lid }) {
            return match
        }
        return exits
            .filter { $0.aracId == iade.aracId }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }
}
