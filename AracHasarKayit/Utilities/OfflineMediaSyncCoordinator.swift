import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore

/// Persists return / check-out / damage photos (and return signatures) locally when Storage uploads cannot complete,
/// then uploads and patches Firestore when the device is online again.
final class OfflineMediaSyncCoordinator: ObservableObject {
    static let shared = OfflineMediaSyncCoordinator()

    @Published private(set) var pendingJobCount: Int = 0

    private struct Job: Codable, Equatable {
        enum Entity: String, Codable {
            case iade
            case exit
            case hasar
        }

        let id: UUID
        let documentId: UUID
        let entity: Entity
        let createdAt: Date
        let photoRelativeNames: [String]
        let pendingSignature: Bool
        /// Per-photo Storage layout for damage: "handover", "return", or "flat" (legacy flat path).
        var hasarSlotTypes: [String]?
    }

    private let ioQueue = DispatchQueue(label: "OfflineMediaSyncCoordinator.io", qos: .utility)
    private var jobs: [Job] = []
    private var isDraining = false

    private let storageRoot: URL
    private let jobsURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("AracHasarKayit", isDirectory: true)
        storageRoot = root.appendingPathComponent("offline_media_jobs", isDirectory: true)
        jobsURL = root.appendingPathComponent("offline_media_queue.json")
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        loadJobsFromDisk()
        publishCount()
    }

    // MARK: - Public API

    func enqueueIadeMedia(
        documentId: UUID,
        images: [UIImage],
        signaturePNG: Data?,
        completion: @escaping (Bool) -> Void
    ) {
        enqueue(entity: .iade, documentId: documentId, images: images, signaturePNG: signaturePNG, hasarSlotTypes: nil, completion: completion)
    }

    func enqueueExitMedia(documentId: UUID, images: [UIImage], completion: @escaping (Bool) -> Void) {
        enqueue(entity: .exit, documentId: documentId, images: images, signaturePNG: nil, hasarSlotTypes: nil, completion: completion)
    }

    /// `slotTypes` must align with `images`: "handover" (index 0), "return", or "flat" (detail-view adds).
    func enqueueHasarMedia(documentId: UUID, images: [UIImage], slotTypes: [String], completion: @escaping (Bool) -> Void) {
        guard images.count == slotTypes.count else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        enqueue(entity: .hasar, documentId: documentId, images: images, signaturePNG: nil, hasarSlotTypes: slotTypes, completion: completion)
    }

    private func enqueue(
        entity: Job.Entity,
        documentId: UUID,
        images: [UIImage],
        signaturePNG: Data?,
        hasarSlotTypes: [String]?,
        completion: @escaping (Bool) -> Void
    ) {
        ioQueue.async {
            guard !images.isEmpty || signaturePNG != nil else {
                DispatchQueue.main.async { completion(true) }
                return
            }

            let jobId = UUID()
            let jobDir = self.storageRoot.appendingPathComponent(jobId.uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)
            } catch {
                DispatchQueue.main.async { completion(false) }
                return
            }

            var photoNames: [String] = []
            for (index, image) in images.enumerated() {
                let name = String(format: "photo_%05d.jpg", index)
                let fileURL = jobDir.appendingPathComponent(name)
                guard let data = ImageOptimizationManager.shared.getOptimizedJPEGData(from: image, model: .highQuality) else {
                    try? FileManager.default.removeItem(at: jobDir)
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                do {
                    try data.write(to: fileURL, options: .atomic)
                    photoNames.append(name)
                } catch {
                    try? FileManager.default.removeItem(at: jobDir)
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            }

            let hasSig = signaturePNG != nil
            if let signaturePNG {
                let sigURL = jobDir.appendingPathComponent("signature.png")
                do {
                    try signaturePNG.write(to: sigURL, options: .atomic)
                } catch {
                    try? FileManager.default.removeItem(at: jobDir)
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            }

            let job = Job(
                id: jobId,
                documentId: documentId,
                entity: entity,
                createdAt: Date(),
                photoRelativeNames: photoNames,
                pendingSignature: hasSig,
                hasarSlotTypes: entity == .hasar ? hasarSlotTypes : nil
            )
            self.jobs.append(job)
            self.persistJobsToDisk()
            self.publishCount()
            DispatchQueue.main.async { completion(true) }
        }
    }

    func processQueueIfNeeded() {
        ioQueue.async { self.drainIfNeeded() }
    }

    // MARK: - Persistence

    private func loadJobsFromDisk() {
        guard let data = try? Data(contentsOf: jobsURL),
              let decoded = try? JSONDecoder().decode([Job].self, from: data) else {
            jobs = []
            return
        }
        jobs = decoded.sorted { $0.createdAt < $1.createdAt }
    }

    private func persistJobsToDisk() {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: jobsURL, options: .atomic)
    }

    private func publishCount() {
        DispatchQueue.main.async {
            self.pendingJobCount = self.jobs.count
            OfflineModeManager.shared.syncPendingMediaJobCount(self.jobs.count)
        }
    }

    private func removeJob(_ job: Job) {
        let dir = storageRoot.appendingPathComponent(job.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        jobs.removeAll { $0.id == job.id }
        persistJobsToDisk()
        publishCount()
    }

    // MARK: - Drain

    private func drainIfNeeded() {
        guard !isDraining else { return }
        guard OfflineModeManager.shared.isOnline else { return }
        guard Auth.auth().currentUser != nil else { return }
        guard let job = jobs.first else { return }

        isDraining = true

        DispatchQueue.main.async {
            Firestore.firestore().waitForPendingWrites { [weak self] _ in
                self?.ioQueue.async {
                    self?.process(job) { success in
                        self?.ioQueue.async {
                            guard let self else { return }
                            if success {
                                self.removeJob(job)
                            }
                            self.isDraining = false
                            if success {
                                self.drainIfNeeded()
                            }
                        }
                    }
                }
            }
        }
    }

    private func process(_ job: Job, completion: @escaping (Bool) -> Void) {
        let jobDir = storageRoot.appendingPathComponent(job.id.uuidString, isDirectory: true)
        let fs = FirebaseService.shared

        let photoCount = job.photoRelativeNames.count
        var orderedPhotoURLs = Array<String?>(repeating: nil, count: photoCount)
        let group = DispatchGroup()
        let lock = NSLock()
        var hadFailure = false

        for (index, name) in job.photoRelativeNames.enumerated() {
            group.enter()
            let fileURL = jobDir.appendingPathComponent(name)
            guard let image = UIImage(contentsOfFile: fileURL.path) else {
                lock.lock()
                hadFailure = true
                lock.unlock()
                group.leave()
                continue
            }
            let path: String
            switch job.entity {
            case .iade:
                path = "iade_fotograflari/\(UUID().uuidString).jpg"
            case .exit:
                path = "exit_fotograflari/\(UUID().uuidString).jpg"
            case .hasar:
                path = storagePathForHasarJob(job, photoIndex: index)
            }
            let slot = index
            fs.uploadImage(image, path: path) { remoteURL, error in
                defer { group.leave() }
                if let remoteURL {
                    lock.lock()
                    orderedPhotoURLs[slot] = remoteURL
                    lock.unlock()
                } else if error != nil {
                    lock.lock()
                    hadFailure = true
                    lock.unlock()
                }
            }
        }

        var signatureURL: String?
        if job.pendingSignature, job.entity == .iade {
            group.enter()
            let sigURL = jobDir.appendingPathComponent("signature.png")
            if let sigData = try? Data(contentsOf: sigURL) {
                let path = "iade_signatures/\(UUID().uuidString).png"
                fs.uploadData(sigData, path: path, contentType: "image/png") { url, error in
                    defer { group.leave() }
                    if let url {
                        signatureURL = url
                    } else if error != nil {
                        lock.lock()
                        hadFailure = true
                        lock.unlock()
                    }
                }
            } else {
                lock.lock()
                hadFailure = true
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: ioQueue) {
            if hadFailure {
                completion(false)
                return
            }

            let uploadedPhotoURLs = orderedPhotoURLs.compactMap { $0 }
            if uploadedPhotoURLs.count != photoCount {
                completion(false)
                return
            }

            self.fetchAndMerge(job: job, newPhotoURLs: uploadedPhotoURLs, signatureURL: signatureURL, completion: completion)
        }
    }

    private func fetchAndMerge(
        job: Job,
        newPhotoURLs: [String],
        signatureURL: String?,
        completion: @escaping (Bool) -> Void
    ) {
        let attempts = 5
        let ioQ = ioQueue
        func attempt(_ left: Int) {
            switch job.entity {
            case .iade:
                FirebaseService.shared.fetchIadeIslemi(id: job.documentId) { iade, error in
                    ioQ.async {
                        guard let iade else {
                            if left > 0 {
                                DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                                    ioQ.async { attempt(left - 1) }
                                }
                            } else {
                                LogManager.shared.error("Offline sync: iade document missing after retries", error: error)
                                completion(false)
                            }
                            return
                        }
                        var merged = iade
                        merged.fotograflar = iade.fotograflar + newPhotoURLs
                        if let signatureURL {
                            merged.customerSignatureURL = signatureURL
                        }
                        FirebaseService.shared.saveIadeIslemi(merged) { err in
                            ioQ.async {
                                completion(err == nil)
                            }
                        }
                    }
                }
            case .exit:
                FirebaseService.shared.fetchExitIslemi(id: job.documentId) { exit, error in
                    ioQ.async {
                        guard let exit else {
                            if left > 0 {
                                DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                                    ioQ.async { attempt(left - 1) }
                                }
                            } else {
                                LogManager.shared.error("Offline sync: exit document missing after retries", error: error)
                                completion(false)
                            }
                            return
                        }
                        var merged = exit
                        merged.fotograflar = exit.fotograflar + newPhotoURLs
                        FirebaseService.shared.saveExitIslemi(merged) { err in
                            ioQ.async {
                                completion(err == nil)
                            }
                        }
                    }
                }
            case .hasar:
                FirebaseService.shared.fetchHasarKaydiTopLevel(id: job.documentId) { hasar, error in
                    ioQ.async {
                        guard let hasar else {
                            if left > 0 {
                                DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                                    ioQ.async { attempt(left - 1) }
                                }
                            } else {
                                LogManager.shared.error("Offline sync: hasar document missing after retries", error: error)
                                completion(false)
                            }
                            return
                        }
                        var merged = hasar
                        merged.fotograflar = hasar.fotograflar + newPhotoURLs
                        FirebaseService.shared.saveHasarKaydiTopLevel(merged) { err in
                            ioQ.async {
                                completion(err == nil)
                            }
                        }
                    }
                }
            }
        }
        attempt(attempts)
    }

    private func storagePathForHasarJob(_ job: Job, photoIndex: Int) -> String {
        let slot: String
        if let types = job.hasarSlotTypes, photoIndex < types.count {
            slot = types[photoIndex]
        } else {
            slot = "flat"
        }
        let u = UUID().uuidString
        switch slot {
        case "handover":
            return "hasar_fotograflari/handover/\(u).jpg"
        case "return":
            return "hasar_fotograflari/return/\(u).jpg"
        default:
            return "hasar_fotograflari/\(u).jpg"
        }
    }
}
