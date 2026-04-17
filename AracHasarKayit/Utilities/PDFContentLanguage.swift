import Foundation

enum PDFContentLanguage {
    case automatic
    case turkish
    case english

    func resolved(forTurkeyFranchise: Bool) -> PDFContentLanguage {
        switch self {
        case .automatic:
            return forTurkeyFranchise ? .turkish : .english
        default:
            return self
        }
    }
}

