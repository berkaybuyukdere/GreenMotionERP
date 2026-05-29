import Foundation
import Combine

@MainActor
final class FileLibraryViewModel: ObservableObject {
    @Published var items: [FileLibraryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentFolderId: String = ""

    private let firebaseService = FirebaseService.shared

    deinit {
        firebaseService.removeFileLibraryListener()
    }

    init() {
        startListening()
    }

    var fileCount: Int {
        items.filter { $0.type == .file }.count
    }

    var folderCount: Int {
        items.filter { $0.type == .folder }.count
    }

    func startListening() {
        isLoading = true
        firebaseService.observeFileLibrary { [weak self] items in
            Task { @MainActor in
                self?.items = items
                self?.isLoading = false
                self?.errorMessage = nil
            }
        }
    }

    func refresh() {
        isLoading = true
        firebaseService.loadFileLibrary { [weak self] items, error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.items = items ?? []
                    self?.errorMessage = nil
                }
                self?.isLoading = false
            }
        }
    }

    func items(inFolder folderId: String, searchQuery: String) -> [FileLibraryItem] {
        let scoped = items.filter { $0.parentId == folderId }
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return scoped.sorted(by: sortItems)
        }

        let needle = trimmed.lowercased()
        let matches = items.filter { item in
            item.displayTitle.lowercased().contains(needle)
                || item.note.lowercased().contains(needle)
                || item.categoryLabelKey.localized.lowercased().contains(needle)
                || item.uploadedByName.lowercased().contains(needle)
                || item.uploadedByEmail.lowercased().contains(needle)
        }
        return matches.sorted(by: sortItems)
    }

    func folderPath(to folderId: String) -> [(id: String, name: String)] {
        guard !folderId.isEmpty else { return [] }
        var path: [(id: String, name: String)] = []
        var cursor = folderId
        var guardRail = 0
        while !cursor.isEmpty, guardRail < 12 {
            guardRail += 1
            guard let folder = items.first(where: { $0.id == cursor && $0.type == .folder }) else { break }
            path.insert((folder.id, folder.name), at: 0)
            cursor = folder.parentId
        }
        return path
    }

    private func sortItems(_ lhs: FileLibraryItem, _ rhs: FileLibraryItem) -> Bool {
        if lhs.type != rhs.type {
            return lhs.type == .folder
        }
        return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }
}
