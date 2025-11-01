import Foundation
import SwiftUI

/// Centralized error management for user-facing error messages
class ErrorManager: ObservableObject {
    static let shared = ErrorManager()
    
    @Published var currentError: AppError?
    @Published var errorMessage: String?
    
    private init() {}
    
    /// Show error to user
    func showError(_ error: Error, context: String = "") {
        let appError: AppError
        
        // Convert to AppError
        if let appErr = error as? AppError {
            appError = appErr
        } else if let nsError = error as NSError? {
            // Check for network errors
            if nsError.domain == NSURLErrorDomain {
                appError = .networkError(error)
            } else if nsError.domain.contains("Firebase") || nsError.domain.contains("Firestore") {
                appError = .firebaseError(error)
            } else {
                appError = .unknownError
            }
        } else {
            appError = .unknownError
        }
        
        DispatchQueue.main.async {
            self.currentError = appError
            
            // Also show toast notification
            ToastManager.shared.show(
                appError.userFacingMessage,
                type: .error,
                duration: 4.0
            )
            
            // Haptic feedback
            HapticManager.shared.error()
            
            print("❌ Error shown to user: \(appError.userFacingMessage)")
        }
    }
    
    /// Show error with custom message
    func showError(message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.currentError = .validationError(message)
            
            ToastManager.shared.show(message, type: .error)
            HapticManager.shared.error()
        }
    }
    
    /// Show success message
    func showSuccess(_ message: String) {
        DispatchQueue.main.async {
            ToastManager.shared.show(message, type: .success)
            HapticManager.shared.success()
        }
    }
    
    /// Clear current error
    func clearError() {
        DispatchQueue.main.async {
            self.currentError = nil
            self.errorMessage = nil
        }
    }
}

// MARK: - AppError Extensions

extension AppError {
    /// User-friendly error message
    var userFacingMessage: String {
        switch self {
        case .networkError(let error):
            if let nsError = error as NSError?, nsError.code == NSURLErrorNotConnectedToInternet {
                return "No internet connection. Please check your network and try again."
            } else if let nsError = error as NSError?, nsError.code == NSURLErrorTimedOut {
                return "Request timed out. Please try again."
            } else {
                return "Network error. Please check your connection and try again."
            }
        case .validationError(let message):
            return message
        case .unauthorized:
            return "You are not authorized to perform this action. Please log in again."
        case .notFound:
            return "The requested item was not found."
        case .unknownError:
            return "An unexpected error occurred. Please try again."
        case .firebaseError(let error):
            let errorString = error.localizedDescription
            if errorString.contains("permission") || errorString.contains("permission-denied") {
                return "Permission denied. Please contact your administrator."
            } else if errorString.contains("network") || errorString.contains("unavailable") {
                return "Network error. Please check your connection and try again."
            } else {
                return "Unable to complete the operation. Please try again."
            }
        }
    }
}

