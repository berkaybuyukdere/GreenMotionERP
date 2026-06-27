import Foundation
import SwiftUI

/// Owns the shared WheelSys session lifecycle for the hub and the return check-in
/// flow: cold-start status check, capturing a freshly logged-in cookie, and
/// broadcasting validity to dependent tabs. Extracted from `WheelSysHubView` so
/// the same session logic can be reused by the return (iade) check-in.
@MainActor
final class WheelSysSessionCoordinator: ObservableObject {
    @Published var sessionValid = false
    @Published var serverSessionValid = false
    @Published var webViewSessionValid = false
    @Published var fleetChartValid = false
    @Published var checkingSession = false
    @Published var loginSaving = false
    @Published var sessionSuccessNote: String?
    @Published var errorMessage: String?

    /// Bumped to ask dependent tabs to reload after a fresh login.
    @Published var reloadToken = 0

    /// After sign-out / cookie clear, login WebView must not auto-capture an existing WK session.
    @Published var requiresFreshLogin = false

    private var lastStatusRefreshAt: Date?
    private static let statusRefreshCooldown: TimeInterval = 90

    private var franchiseId: String {
        FirebaseService.shared.currentFranchiseId.uppercased()
    }

    private var wheelSysSessionAllowed: Bool {
        FranchiseCapabilityMatrix.wheelSysEnabledForActiveFranchise(franchiseId)
    }

    /// Cold-start: restore Keychain cookie, verify with backend, hydrate validity flags.
    func refreshSessionStatus(force: Bool = false) async {
        let cid = WheelSysDebug.newCorrelationId()
        guard wheelSysSessionAllowed else {
            sessionValid = false
            serverSessionValid = false
            webViewSessionValid = false
            fleetChartValid = false
            WheelSysCookieCache.markServerSessionValid(false)
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "Session",
                "refresh skipped — WheelSys not enabled for franchise=\(franchiseId)",
                cid: cid
            )
            return
        }

        if !force {
            if checkingSession { return }
            if sessionValid,
               let last = lastStatusRefreshAt,
               Date().timeIntervalSince(last) < Self.statusRefreshCooldown {
                WheelSysDebug.logCH(
                    franchiseId: franchiseId,
                    "Session",
                    "refresh skipped — cooldown active valid=\(sessionValid)",
                    cid: cid
                )
                return
            }
        }

        let showCheckingUI = !sessionValid
        if showCheckingUI {
            checkingSession = true
        }
        defer {
            if showCheckingUI {
                checkingSession = false
            }
            lastStatusRefreshAt = Date()
        }

        let wasConnected = sessionValid

        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "Session",
            "refresh start franchise=\(franchiseId)",
            cid: cid
        )
        WheelSysCookieCache.restorePersistedSession(franchiseId: franchiseId)
        WheelSysCookieCache.restoreWheelSysOperator(franchiseId: franchiseId)
        webViewSessionValid = WheelSysCookieCache.isValid

        // Server session must match this Firebase user — never reuse another user's stored cookie.
        guard WheelSysCookieCache.currentUserId() != nil else {
            sessionValid = false
            serverSessionValid = false
            fleetChartValid = false
            WheelSysCookieCache.markServerSessionValid(false)
            return
        }

        do {
            let status = try await WheelSysCheckinService.sessionStatus(franchiseId: franchiseId)
            fleetChartValid = status.fleetChartValid
            serverSessionValid = status.hasSession && status.isValid
            WheelSysCookieCache.markServerSessionValid(serverSessionValid)

            if serverSessionValid {
                if !webViewSessionValid {
                    WheelSysDebug.logCH(
                        franchiseId: franchiseId,
                        "Session",
                        "server valid — attempting WKWebView cookie hydrate",
                        cid: cid
                    )
                    if let fromWebView = await WheelSysCheckinService.getWheelSysCookieString(),
                       WheelSysCheckinService.isValidWheelSysCookie(fromWebView) {
                        WheelSysCookieCache.set(fromWebView, franchiseId: franchiseId)
                        webViewSessionValid = true
                        WheelSysDebug.logCH(
                            franchiseId: franchiseId,
                            "Session",
                            "WKWebView cookie hydrated",
                            cid: cid
                        )
                    }
                }
                sessionValid = webViewSessionValid || serverSessionValid
                WheelSysDebug.logCH(
                    franchiseId: franchiseId,
                    "Session",
                    "verified webView=\(webViewSessionValid) server=\(serverSessionValid) fleetChart=\(fleetChartValid)",
                    cid: cid
                )
                return
            }

            if webViewSessionValid {
                if wasConnected && WheelSysCookieCache.isValid {
                    WheelSysDebug.warnCH(
                        franchiseId: franchiseId,
                        "Session",
                        "server probe invalid while connected — keeping active session (no auto re-login)",
                        cid: cid
                    )
                    sessionValid = true
                    return
                }
                WheelSysDebug.warnCH(
                    franchiseId: franchiseId,
                    "Session",
                    "keychain cookie present but server session invalid — clearing stale cookie",
                    cid: cid
                )
                WheelSysCookieCache.clear(franchiseId: franchiseId)
                webViewSessionValid = false
                requiresFreshLogin = true
            }
            sessionValid = false
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "Session",
                "session invalid — login required",
                cid: cid
            )
        } catch {
            if wasConnected && WheelSysCookieCache.hasUsableSession {
                WheelSysDebug.warnCH(
                    franchiseId: franchiseId,
                    "Session",
                    "status probe error while connected — keeping session",
                    cid: cid
                )
                sessionValid = true
                return
            }
            serverSessionValid = false
            WheelSysCookieCache.markServerSessionValid(false)
            webViewSessionValid = WheelSysCookieCache.isValid
            sessionValid = webViewSessionValid
            WheelSysDebug.errorCH(
                franchiseId: franchiseId,
                "Session",
                "status check failed: \(error.localizedDescription)",
                cid: cid
            )
        }
    }

    /// Drop Keychain / in-memory WheelSys cookies without navigating away from connected tabs.
    func clearCachedSessionCookie() {
        let cid = WheelSysDebug.newCorrelationId()
        WheelSysCookieCache.clear(franchiseId: franchiseId)
        WheelSysLoginWebView.clearWebsiteData()
        webViewSessionValid = false
        serverSessionValid = false
        fleetChartValid = false
        sessionValid = false
        sessionSuccessNote = nil
        reloadToken += 1
        requiresFreshLogin = true
        lastStatusRefreshAt = nil
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "Session",
            "cached cookie cleared — re-login required",
            cid: cid
        )
    }

    /// Clear local + persisted WheelSys cookies and return to inline login.
    func signOut() {
        let cid = WheelSysDebug.newCorrelationId()
        WheelSysCookieCache.clear(franchiseId: franchiseId)
        WheelSysLoginWebView.clearWebsiteData()
        sessionValid = false
        serverSessionValid = false
        webViewSessionValid = false
        fleetChartValid = false
        sessionSuccessNote = nil
        errorMessage = nil
        reloadToken += 1
        requiresFreshLogin = true
        lastStatusRefreshAt = nil
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "Session",
            "signed out — showing login",
            cid: cid
        )
    }

    /// Persist a freshly captured WKWebView cookie and mark the session live.
    func saveCapturedSession(_ cookie: String) async {
        let cid = WheelSysDebug.newCorrelationId()
        guard wheelSysSessionAllowed else {
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "Session",
                "save skipped — WheelSys not enabled",
                cid: cid
            )
            return
        }
        guard !loginSaving else {
            WheelSysDebug.logCH(franchiseId: franchiseId, "Session", "save skipped — already saving", cid: cid)
            return
        }
        if sessionValid, WheelSysCookieCache.isValid {
            WheelSysDebug.logCH(franchiseId: franchiseId, "Session", "save skipped — session already valid", cid: cid)
            return
        }

        loginSaving = true
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "Session",
            "save start hasCookie=\(WheelSysCheckinService.isValidWheelSysCookie(cookie))",
            cid: cid
        )
        defer { loginSaving = false }
        do {
            try await WheelSysCheckinService.saveSessionCookie(
                franchiseId: franchiseId,
                sessionCookie: cookie
            )
            webViewSessionValid = WheelSysCookieCache.isValid
            serverSessionValid = true
            sessionValid = true
            fleetChartValid = true
            WheelSysCookieCache.markServerSessionValid(true)
            WheelSysSessionPromptCenter.resetSnooze()
            reloadToken += 1
            sessionSuccessNote = "wheelsys_checkin.session_saved".localized
            requiresFreshLogin = false
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "Session",
                "captured session saved valid=\(sessionValid) reloadToken=\(reloadToken)",
                cid: cid
            )
            NotificationCenter.default.post(name: .wheelSysSessionRestored, object: nil)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { self.sessionSuccessNote = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
            requiresFreshLogin = true
            WheelSysDebug.errorCH(
                franchiseId: franchiseId,
                "Session",
                "save failed: \(error.localizedDescription)",
                cid: cid
            )
        }
    }

    func markExpired() {
        serverSessionValid = false
        WheelSysCookieCache.markServerSessionValid(false)
        // Never kick the user back to the login WebView while client cookies remain valid.
        // Journal/fleet operational failures must not look like a sign-out.
        guard !WheelSysCookieCache.isValid else {
            WheelSysDebug.logCH(
                franchiseId: franchiseId,
                "Session",
                "markExpired ignored — client cookie still valid"
            )
            return
        }
        sessionValid = false
        webViewSessionValid = false
        requiresFreshLogin = true
        WheelSysDebug.logCH(
            franchiseId: franchiseId,
            "Session",
            "marked expired — fresh login required before auto-capture"
        )
    }
}
