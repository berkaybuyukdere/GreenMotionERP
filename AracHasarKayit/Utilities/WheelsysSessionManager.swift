import Foundation
import WebKit

/// Manages Wheelsys session persistence using cookies and WKWebsiteDataStore
class WheelsysSessionManager: ObservableObject {
    static let shared = WheelsysSessionManager()
    
    private let domain = "ch.wheelsys.greenmotion.com"
    private let cookieStorageKey = "wheelsys_cookies"
    private let sessionDataKey = "wheelsys_session_data"
    
    private init() {
        // Restore cookies on initialization
        restoreCookies()
    }
    
    // MARK: - Cookie Management
    
    /// Save cookies from HTTPCookieStorage to UserDefaults and WKWebsiteDataStore
    func saveCookies() {
        guard let url = URL(string: "https://\(domain)") else { return }
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return
        }
        
        // Filter cookies for Wheelsys domain
        let wheelsysCookies = cookies.filter { cookie in
            cookie.domain.contains(domain) || cookie.domain == domain
        }
        
        guard !wheelsysCookies.isEmpty else {
            return
        }
        
        // Convert cookies to dictionary array
        let cookieData = wheelsysCookies.compactMap { cookie -> [String: Any]? in
            var properties: [String: Any] = [:]
            properties[HTTPCookiePropertyKey.name.rawValue] = cookie.name
            properties[HTTPCookiePropertyKey.value.rawValue] = cookie.value
            properties[HTTPCookiePropertyKey.domain.rawValue] = cookie.domain
            properties[HTTPCookiePropertyKey.path.rawValue] = cookie.path
            properties[HTTPCookiePropertyKey.secure.rawValue] = cookie.isSecure
            if let expiresDate = cookie.expiresDate {
                properties[HTTPCookiePropertyKey.expires.rawValue] = expiresDate
            }
            properties[HTTPCookiePropertyKey.version.rawValue] = cookie.version
            return properties
        }
        
        // Save to UserDefaults
        UserDefaults.standard.set(cookieData, forKey: cookieStorageKey)
        UserDefaults.standard.synchronize()
        
        // Also save to WKWebsiteDataStore for WKWebView
        let dataStore = WKWebsiteDataStore.default()
        let httpCookieStore = dataStore.httpCookieStore
        
        // Set cookies in WKWebView's cookie store
        for cookie in wheelsysCookies {
            httpCookieStore.setCookie(cookie) {
                // Cookie saved successfully
            }
        }
        
        print("✅ Saved \(wheelsysCookies.count) cookies for Wheelsys")
    }
    
    /// Restore cookies from UserDefaults to HTTPCookieStorage and WKWebsiteDataStore
    func restoreCookies() {
        guard let cookieData = UserDefaults.standard.array(forKey: cookieStorageKey) as? [[String: Any]] else {
            print("ℹ️ No saved cookies found for Wheelsys")
            return
        }
        
        let cookieStorage = HTTPCookieStorage.shared
        let dataStore = WKWebsiteDataStore.default()
        let httpCookieStore = dataStore.httpCookieStore
        
        var restoredCount = 0
        
        for cookieProperties in cookieData {
            // Convert [String: Any] to [HTTPCookiePropertyKey: Any]
            var properties: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in cookieProperties {
                // Map known cookie property keys
                let propertyKey: HTTPCookiePropertyKey
                switch key {
                case HTTPCookiePropertyKey.name.rawValue:
                    propertyKey = .name
                case HTTPCookiePropertyKey.value.rawValue:
                    propertyKey = .value
                case HTTPCookiePropertyKey.domain.rawValue:
                    propertyKey = .domain
                case HTTPCookiePropertyKey.path.rawValue:
                    propertyKey = .path
                case HTTPCookiePropertyKey.secure.rawValue:
                    propertyKey = .secure
                case HTTPCookiePropertyKey.expires.rawValue:
                    propertyKey = .expires
                case HTTPCookiePropertyKey.version.rawValue:
                    propertyKey = .version
                default:
                    continue
                }
                properties[propertyKey] = value
            }
            
            if let cookie = HTTPCookie(properties: properties) {
                // Restore to HTTPCookieStorage
                cookieStorage.setCookie(cookie)
                
                // Also restore to WKWebView's cookie store
                httpCookieStore.setCookie(cookie) {
                    // Cookie restored successfully
                }
                
                restoredCount += 1
            }
        }
        
        print("✅ Restored \(restoredCount) cookies for Wheelsys")
    }
    
    /// Clear all Wheelsys cookies
    func clearCookies() {
        // Clear from HTTPCookieStorage
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://\(domain)")!) {
            for cookie in cookies {
                if cookie.domain.contains(domain) || cookie.domain == domain {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
        
        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: cookieStorageKey)
        UserDefaults.standard.removeObject(forKey: sessionDataKey)
        UserDefaults.standard.synchronize()
        
        // Clear WKWebsiteDataStore
        let dataStore = WKWebsiteDataStore.default()
        let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: websiteDataTypes) { [self] records in
            let wheelsysRecords = records.filter { record in
                record.displayName.contains(self.domain)
            }
            dataStore.removeData(ofTypes: websiteDataTypes, for: wheelsysRecords) {
                print("✅ Cleared WKWebsiteDataStore for Wheelsys")
            }
        }
        
        print("✅ Cleared all Wheelsys cookies and session data")
    }
    
    // MARK: - Session State
    
    /// Check if user is logged in (has valid session cookies)
    func isLoggedIn() -> Bool {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://\(domain)")!) else {
            return false
        }
        
        let wheelsysCookies = cookies.filter { cookie in
            cookie.domain.contains(domain) || cookie.domain == domain
        }
        
        // Check for authentication-related cookies
        let hasAuthCookie = wheelsysCookies.contains { cookie in
            let name = cookie.name.lowercased()
            return name.contains("auth") || 
                   name.contains("session") || 
                   name.contains("token") || 
                   name.contains("login")
        }
        
        return hasAuthCookie && !wheelsysCookies.isEmpty
    }
    
    /// Get session information
    func getSessionInfo() -> [String: String] {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://\(domain)")!) else {
            return [:]
        }
        
        let wheelsysCookies = cookies.filter { cookie in
            cookie.domain.contains(domain) || cookie.domain == domain
        }
        
        var sessionInfo: [String: String] = [:]
        for cookie in wheelsysCookies {
            sessionInfo[cookie.name] = cookie.value
        }
        
        return sessionInfo
    }
}

