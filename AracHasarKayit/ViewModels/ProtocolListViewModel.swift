import Foundation
import Combine

@MainActor
class ProtocolListViewModel: ObservableObject {
    @Published var protocols: [Protocol] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    
    deinit {
        firebaseService.removeProtocolListener()
    }
    
    init() {
        setupRealtimeListener()
        loadProtocols()
    }
    
    private func setupRealtimeListener() {
        firebaseService.observeProtocols { [weak self] protocols in
            DispatchQueue.main.async {
                self?.protocols = protocols
                self?.isLoading = false
                self?.errorMessage = nil
            }
        }
    }
    
    func loadProtocols() {
        isLoading = true
        errorMessage = nil
        
        firebaseService.loadProtocols { [weak self] protocols, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.protocols = protocols ?? []
                }
                self?.isLoading = false
            }
        }
    }
    
    func refreshProtocols() {
        loadProtocols()
    }
    
    var totalProtocols: Int { protocols.count }
    
    var paidCount: Int {
        protocols.filter { $0.effectivePaymentStatus == "paid" }.count
    }
    
    var pendingPaymentCount: Int {
        protocols.filter { $0.effectivePaymentStatus == "pending" }.count
    }
    
    var unpaidCount: Int {
        protocols.filter { $0.effectivePaymentStatus == "unpaid" }.count
    }
    
    var totalOutstanding: Double {
        protocols.reduce(0) { $0 + $1.financialOutstanding }
    }
    
    var draftCount: Int {
        protocols.filter { $0.status.uppercased() == "DRAFT" }.count
    }
    
    var pendingCount: Int {
        protocols.filter { $0.status.uppercased() == "PENDING" }.count
    }
    
    var completedCount: Int {
        protocols.filter { $0.status.uppercased() == "COMPLETE" }.count
    }
    
    var overdueCount: Int {
        protocols.filter { $0.status.uppercased() == "OVERDUE" }.count
    }
    
    var cancelledCount: Int {
        protocols.filter { $0.status.uppercased() == "CANCELLED" }.count
    }
    
    var totalBaseCost: Double {
        protocols.compactMap { $0.baseCostDouble }.reduce(0, +)
    }
    
    var averageBaseCost: Double {
        let costs = protocols.compactMap { $0.baseCostDouble }
        return costs.isEmpty ? 0 : totalBaseCost / Double(costs.count)
    }
}
