import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class VehicleServiceFlagStore: ObservableObject {
    static let shared = VehicleServiceFlagStore()

    @Published private(set) var flags: [VehicleServiceFlag] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var listeningClientCount = 0

    deinit { listener?.remove() }

    func startListening() {
        guard Auth.auth().currentUser != nil else { return }
        listeningClientCount += 1
        guard listeningClientCount == 1 else { return }

        listener?.remove()
        listener = FirebaseService.shared
            .getFilteredQuery("vehicleServiceFlags")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.flags = (snapshot?.documents ?? [])
                        .compactMap { VehicleServiceFlag(document: $0) }
                        .sorted { $0.updatedAt > $1.updatedAt }
                }
            }
    }

    func stopListening() {
        listeningClientCount = max(0, listeningClientCount - 1)
        guard listeningClientCount == 0 else { return }
        listener?.remove()
        listener = nil
        flags = []
    }

    func activeFlags() -> [VehicleServiceFlag] {
        flags.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .needsService
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func flag(forVehicleId vehicleId: UUID) -> VehicleServiceFlag? {
        flags.first { $0.vehicleId == vehicleId.uuidString }
    }

    func save(
        vehicleId: UUID,
        plate: String,
        kind: VehicleServiceFlagKind,
        note: String,
        userId: String,
        userName: String
    ) async throws {
        let flag = VehicleServiceFlag(
            vehicleId: vehicleId.uuidString,
            plate: plate,
            kind: kind,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedByUid: userId,
            updatedByName: userName,
            franchiseId: FirebaseService.shared.currentFranchiseId
        )
        try await FirebaseService.shared
            .getCollectionReference("vehicleServiceFlags")
            .document(flag.vehicleId)
            .setData(flag.firestorePayload, merge: true)
    }

    func clear(vehicleId: UUID) async throws {
        try await FirebaseService.shared
            .getCollectionReference("vehicleServiceFlags")
            .document(vehicleId.uuidString)
            .delete()
    }
}
