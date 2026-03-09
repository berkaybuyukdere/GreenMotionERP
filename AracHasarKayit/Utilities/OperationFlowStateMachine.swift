import Foundation

enum OperationFlowState: String {
    case draft
    case processing
    case uploadingMedia
    case completed
    case failed
    
    func canTransition(to newState: OperationFlowState) -> Bool {
        switch (self, newState) {
        case (.draft, .processing),
             (.draft, .uploadingMedia),
             (.processing, .uploadingMedia),
             (.processing, .failed),
             (.uploadingMedia, .completed),
             (.uploadingMedia, .failed),
             (.failed, .processing),
             (.failed, .uploadingMedia),
             (.completed, .processing),
             (_, .draft):
            return true
        case let (current, target):
            return current == target
        }
    }
}
