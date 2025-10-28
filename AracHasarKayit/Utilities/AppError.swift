import SwiftUI

/// Standardized error handling for the app
enum AppError: LocalizedError {
    case networkError(Error)
    case validationError(String)
    case unauthorized
    case notFound
    case unknownError
    case firebaseError(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .unauthorized:
            return "You are not authorized to perform this action"
        case .notFound:
            return "The requested item was not found"
        case .unknownError:
            return "An unknown error occurred"
        case .firebaseError(let error):
            return "Firebase error: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Please check your internet connection and try again"
        case .validationError:
            return "Please check your input and try again"
        case .unauthorized:
            return "Please log in to continue"
        case .notFound:
            return "Please try refreshing the data"
        case .unknownError:
            return "Please try again or contact support"
        case .firebaseError:
            return "Please try again or contact support"
        }
    }
}

/// Error handler for displaying errors to users
class ErrorHandler {
    static let shared = ErrorHandler()
    private init() {}
    
    /// Handle and display error
    func handle(_ error: Error, in context: String = "") {
        let appError: AppError
        
        if let appErr = error as? AppError {
            appError = appErr
        } else {
            appError = .unknownError
        }
        
        // Log error
        print("❌ Error in \(context): \(appError.errorDescription ?? "Unknown")")
        
        // Show toast notification
        ToastManager.shared.show(
            appError.errorDescription ?? "An error occurred",
            type: .error
        )
        
        // Send haptic feedback
        HapticManager.shared.error()
    }
    
    /// Show validation error
    func showValidationError(_ message: String) {
        let error = AppError.validationError(message)
        handle(error, in: "Validation")
    }
    
    /// Show network error
    func showNetworkError(_ error: Error) {
        let appError = AppError.networkError(error)
        handle(appError, in: "Network")
    }
}

