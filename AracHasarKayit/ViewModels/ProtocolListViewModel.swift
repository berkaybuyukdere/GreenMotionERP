import Foundation
import Combine

@MainActor
class ProtocolListViewModel: ObservableObject {
    @Published var protocols: [Protocol] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Start real-time listening for protocol updates
        setupRealtimeListener()
        // Load protocols once on init
        loadProtocols()
    }
    
    private func setupRealtimeListener() {
        firebaseService.observeProtocols { [weak self] protocols in
            DispatchQueue.main.async {
                self?.protocols = protocols
                self?.isLoading = false
                self?.errorMessage = nil
                print("✅ Real-time update: Loaded \(protocols.count) protocols")
            }
        }
    }
    
    func loadProtocols() {
        print("🔄 Manual refresh triggered...")
        isLoading = true
        errorMessage = nil
        
        firebaseService.loadProtocols { [weak self] protocols, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    print("❌ Error loading protocols: \(error)")
                } else {
                    self?.protocols = protocols ?? []
                    print("✅ Loaded \(protocols?.count ?? 0) protocols")
                }
                self?.isLoading = false
            }
        }
    }
    
    func refreshProtocols() {
        loadProtocols()
    }
    
    func searchProtocols(query: String, completion: @escaping ([Protocol]?, Error?) -> Void) {
        // For now, filter locally. Can be enhanced with Firestore queries later
        let filtered = protocols.filter { `protocol` in
            `protocol`.protocolName.localizedCaseInsensitiveContains(query) ||
            `protocol`.customerName.localizedCaseInsensitiveContains(query) ||
            `protocol`.vehiclePlate.localizedCaseInsensitiveContains(query)
        }
        completion(filtered, nil)
    }
    
    func filterProtocolsByStatus(_ status: String, completion: @escaping ([Protocol]?, Error?) -> Void) {
        // For now, filter locally. Can be enhanced with Firestore queries later
        let filtered = protocols.filter { $0.status.uppercased() == status.uppercased() }
        completion(filtered, nil)
    }
    
    func filterProtocolsByDateRange(startDate: Date, endDate: Date, completion: @escaping ([Protocol]?, Error?) -> Void) {
        // For now, filter locally. Can be enhanced with Firestore queries later
        let filtered = protocols.filter { `protocol` in
            guard let createdAt = `protocol`.createdAtFormatted else { return false }
            return createdAt >= startDate && createdAt <= endDate
        }
        completion(filtered, nil)
    }
    
    func updateProtocolStatus(_ protocolId: String, status: String) {
        guard let protocolIndex = protocols.firstIndex(where: { $0.id == protocolId }) else {
            errorMessage = "Protocol not found"
            return
        }
        
        var protocolToUpdate = protocols[protocolIndex]
        protocolToUpdate.status = status
        protocolToUpdate.updatedAt = ISO8601DateFormatter().string(from: Date())
        
        firebaseService.updateProtocol(protocolToUpdate) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    print("❌ Error updating protocol status: \(error)")
                } else {
                    // Update local array
                    self?.protocols[protocolIndex] = protocolToUpdate
                    print("✅ Protocol status updated successfully")
                }
            }
        }
    }
    
    func deleteProtocol(_ protocolId: String) {
        firebaseService.deleteProtocol(id: protocolId) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    print("❌ Error deleting protocol: \(error)")
                } else {
                    // Remove from local array
                    self?.protocols.removeAll { $0.id == protocolId }
                    print("✅ Protocol deleted successfully")
                }
            }
        }
    }
    
    func getProtocolStatistics(completion: @escaping (ProtocolStatistics?, Error?) -> Void) {
        // Use local data for statistics
        let statistics = ProtocolStatistics(protocols: protocols)
        completion(statistics, nil)
    }
    
    
    // MARK: - Computed Properties
    
    var totalProtocols: Int {
        protocols.count
    }
    
    var draftCount: Int {
        let count = protocols.filter { $0.status.uppercased() == "DRAFT" }.count
        print("🔍 Draft count: \(count) (looking for 'DRAFT')")
        protocols.forEach { protocolItem in
            print("🔍 Protocol status: '\(protocolItem.status)' -> uppercased: '\(protocolItem.status.uppercased())'")
        }
        return count
    }
    
    var pendingCount: Int {
        let count = protocols.filter { $0.status.uppercased() == "PENDING" }.count
        print("🔍 Pending count: \(count) (looking for 'PENDING')")
        protocols.forEach { protocolItem in
            print("🔍 Protocol status: '\(protocolItem.status)' -> uppercased: '\(protocolItem.status.uppercased())'")
        }
        return count
    }
    
    var completedCount: Int {
        let count = protocols.filter { $0.status.uppercased() == "COMPLETE" }.count
        print("🔍 Completed count: \(count) (looking for 'COMPLETE')")
        protocols.forEach { protocolItem in
            print("🔍 Protocol status: '\(protocolItem.status)' -> uppercased: '\(protocolItem.status.uppercased())'")
        }
        return count
    }
    
    var overdueCount: Int {
        let count = protocols.filter { $0.status.uppercased() == "OVERDUE" }.count
        print("🔍 Overdue count: \(count) (looking for 'OVERDUE')")
        protocols.forEach { protocolItem in
            print("🔍 Protocol status: '\(protocolItem.status)' -> uppercased: '\(protocolItem.status.uppercased())'")
        }
        return count
    }
    
    var cancelledCount: Int {
        let count = protocols.filter { $0.status.uppercased() == "CANCELLED" }.count
        print("🔍 Cancelled count: \(count) (looking for 'CANCELLED')")
        protocols.forEach { protocolItem in
            print("🔍 Protocol status: '\(protocolItem.status)' -> uppercased: '\(protocolItem.status.uppercased())'")
        }
        return count
    }
    
    
    var totalBaseCost: Double {
        protocols.compactMap { $0.baseCostDouble }.reduce(0, +)
    }
    
    var averageBaseCost: Double {
        let costs = protocols.compactMap { $0.baseCostDouble }
        return costs.isEmpty ? 0 : totalBaseCost / Double(costs.count)
    }
    
    var protocolsByType: [String: Int] {
        Dictionary(grouping: protocols, by: { $0.protocolType })
            .mapValues { $0.count }
    }
    
    var protocolsByStatus: [String: Int] {
        Dictionary(grouping: protocols, by: { $0.status.uppercased() })
            .mapValues { $0.count }
    }
}
