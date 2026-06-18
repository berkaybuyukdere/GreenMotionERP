import FirebaseFirestore
import SwiftUI

/// Keeps checkout/return customer email sends alive when the user leaves the detail screen or backgrounds the app.
@MainActor
final class CustomerEmailSendCoordinator: ObservableObject {
    static let shared = CustomerEmailSendCoordinator()

    @Published private(set) var isActive = false
    @Published var showsFullscreenOverlay = false
    @Published var progressMessage = ""
    @Published var progress: Double = 0
    @Published var photoSummary = ""

    private var emailListener: ListenerRegistration?
    private var timeoutWorkItem: DispatchWorkItem?
    private var pollWorkItem: DispatchWorkItem?
    private var observeDidComplete = false
    /// User dismissed the overlay or left the screen — completion should notify in background.
    private var continuingInBackground = false

    private init() {}

    func beginSending(photoSummary: String) {
        isActive = true
        showsFullscreenOverlay = true
        continuingInBackground = false
        progress = 0.05
        progressMessage = "Checking email settings…".localized
        self.photoSummary = photoSummary
    }

    func updateProgress(_ value: Double, message: String, animated: Bool = true) {
        let apply = {
            self.progress = value
            self.progressMessage = message
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.25), apply)
        } else {
            apply()
        }
    }

    /// Hides the full-screen overlay; SMTP/PDF work continues.
    func hideOverlayContinueInBackground() {
        guard isActive, showsFullscreenOverlay else { return }
        continuingInBackground = true
        showsFullscreenOverlay = false
        ToastManager.shared.show("email.pipeline.background".localized, type: .info, duration: 3.0)
    }

    func completeSending(
        success: Bool,
        message: String,
        failureToast: String? = nil,
        emailKind: CustomerEmailPipelineKind = .returnConfirmation,
        vehiclePlate: String? = nil,
        recipient: String? = nil
    ) {
        let deliverInBackground = continuingInBackground

        if deliverInBackground {
            let toastText = success ? message : (failureToast ?? message)
            if success {
                HapticManager.shared.success()
                ToastManager.shared.show(toastText, type: .success, duration: 4.0)
            } else {
                HapticManager.shared.error()
                ToastManager.shared.show(toastText, type: .error, duration: 4.0)
            }
            NotificationManager.shared.postCustomerEmailDeliveryResult(
                success: success,
                kind: emailKind,
                vehiclePlate: vehiclePlate,
                recipient: recipient,
                failureDetail: success ? nil : toastText
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.reset()
            }
            return
        }

        if success {
            withAnimation(.easeInOut(duration: 0.25)) {
                progress = 1
                progressMessage = message
            }
            HapticManager.shared.success()
        } else {
            progressMessage = message
            HapticManager.shared.error()
            let toastText = failureToast ?? message
            ToastManager.shared.show(toastText, type: .error, duration: 3.5)
        }

        let delay = success ? 2.0 : 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reset()
        }
    }

    func reset() {
        tearDownObserver()
        isActive = false
        showsFullscreenOverlay = false
        continuingInBackground = false
        progress = 0
        progressMessage = "Preparing PDF...".localized
        photoSummary = ""
    }

    func observeQueuedEmailStatus(
        documentPath: String,
        timeout: TimeInterval,
        usePolling: Bool,
        completion: @escaping (String) -> Void
    ) {
        tearDownObserver()
        observeDidComplete = false

        let ref = Firestore.firestore().document(documentPath)
        let terminalStatuses: Set<String> = ["sent", "failed", "duplicate_skipped"]

        func finish(_ status: String) {
            guard !observeDidComplete else { return }
            observeDidComplete = true
            tearDownObserver()
            completion(status)
        }

        func schedulePoll() {
            guard usePolling, !observeDidComplete else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, !self.observeDidComplete else { return }
                ref.getDocument { snapshot, error in
                    if let error {
                        print("⚠️ Email poll error: \(error.localizedDescription)")
                    } else if
                        let data = snapshot?.data(),
                        let status = data["status"] as? String,
                        terminalStatuses.contains(status)
                    {
                        finish(status)
                        return
                    }
                    if !self.observeDidComplete {
                        schedulePoll()
                    }
                }
            }
            pollWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        }

        emailListener = ref.addSnapshotListener { snapshot, error in
            if let error {
                print("❌ Email listener error: \(error.localizedDescription)")
                if !usePolling {
                    finish("listener_error")
                }
                return
            }
            guard let data = snapshot?.data() else { return }
            let status = String(describing: data["status"] ?? "unknown")
            if terminalStatuses.contains(status) {
                finish(status)
            }
        }

        let timeoutItem = DispatchWorkItem {
            print("⏱️ Email status observation timeout for path: \(documentPath)")
            finish("timeout")
        }
        timeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        if usePolling {
            schedulePoll()
        }
    }

    private func tearDownObserver() {
        emailListener?.remove()
        emailListener = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        pollWorkItem?.cancel()
        pollWorkItem = nil
        observeDidComplete = false
    }
}
