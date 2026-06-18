import Foundation
import SwiftUI

/// Owns the shared WheelSys session lifecycle for the hub and the return check-in
/// flow: cold-start status check, capturing a freshly logged-in cookie, and
/// broadcasting validity to dependent tabs. Extracted from `WheelSysHubView` so
/// the same session logic can be reused by the return (iade) check-in.
@MainActor
final class WheelSysSessionCoordinator: ObservableObject {
    @Published var sessionValid = false
    @Published var fleetChartValid = false
    @Published var checkingSession = false
    @Published var loginSaving = false
    @Published var sessionSuccessNote: String?
    @Published var errorMessage: String?

    /// Bumped to ask dependent tabs to reload after a fresh login.
    @Published var reloadToken = 0

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    /// Cold-start: trust the in-memory cookie first, then verify with backend.
    func refreshSessionStatus() async {
        checkingSession = true
        defer { checkingSession = false }

        sessionValid = WheelSysCookieCache.isValid
        if sessionValid {
            WheelSysDebug.log("Session", "cold-start cookie valid")
            return
        }

        do {
            let status = try await WheelSysCheckinService.sessionStatus(franchiseId: franchiseId)
            fleetChartValid = status.fleetChartValid
            sessionValid = WheelSysCookieCache.isValid
            WheelSysDebug.log("Session", "status check valid=\(sessionValid) fleetChart=\(fleetChartValid)")
        } catch {
            sessionValid = WheelSysCookieCache.isValid
            WheelSysDebug.error("Session", "status check failed: \(error.localizedDescription)")
        }
    }

    /// Persist a freshly captured WKWebView cookie and mark the session live.
    func saveCapturedSession(_ cookie: String) async {
        loginSaving = true
        defer { loginSaving = false }
        do {
            try await WheelSysCheckinService.saveSessionCookie(
                franchiseId: franchiseId,
                sessionCookie: cookie
            )
            sessionValid = WheelSysCookieCache.isValid
            fleetChartValid = true
            reloadToken += 1
            sessionSuccessNote = "wheelsys_checkin.session_saved".localized
            WheelSysDebug.log("Session", "captured session saved valid=\(sessionValid)")
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { self.sessionSuccessNote = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
            WheelSysDebug.error("Session", "save failed: \(error.localizedDescription)")
        }
    }

    func markExpired() {
        sessionValid = false
        WheelSysDebug.log("Session", "marked expired by dependent view")
    }
}
