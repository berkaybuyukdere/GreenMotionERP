import Foundation
import UIKit

/// Provides validation utilities for user inputs
struct Validators {
    
    // MARK: - RES Code Validation
    
    /// Validates RES code format
    /// - Parameter code: RES code to validate (can be with or without RES- prefix, e.g., "12345" or "RES-12345")
    /// - Returns: True if valid, false otherwise
    static func validateResCode(_ code: String) -> Bool {
        // Remove whitespace
        var trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove RES- prefix if present
        if trimmedCode.hasPrefix("RES-") {
            trimmedCode = String(trimmedCode.dropFirst(4))
        }
        
        // Check if number part exists and is valid
        guard !trimmedCode.isEmpty,
              let number = Int(trimmedCode),
              number > 0 else {
            return false
        }
        
        // RES code must be exactly 5 digits
        return trimmedCode.count == 5
    }
    
    /// Cleans and formats RES code
    /// - Parameter code: RES code to clean
    /// - Returns: Cleaned RES code
    static func cleanResCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If already has RES- prefix, clean duplicates
        if trimmed.hasPrefix("RES-") {
            let withoutPrefix = trimmed.replacingOccurrences(of: "RES-", with: "")
            return "RES-\(withoutPrefix)"
        }
        
        // If doesn't have prefix and starts with numbers, add prefix
        if let firstChar = trimmed.first, firstChar.isNumber {
            return "RES-\(trimmed)"
        }
        
        return trimmed
    }
    
    // MARK: - KM Validation
    
    /// Validates kilometers input
    /// - Parameter km: KM string to validate
    /// - Returns: True if valid, false otherwise
    static func validateKM(_ km: String) -> Bool {
        let trimmed = km.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if not empty
        guard !trimmed.isEmpty else {
            return false
        }
        
        // Check if it's a valid integer
        guard let value = Int(trimmed) else {
            return false
        }
        
        // Check if value is within reasonable range
        return value >= 0 && value <= 999_999
    }
    
    /// Gets the integer value from KM string
    /// - Parameter km: KM string
    /// - Returns: Integer value or nil
    static func getKMValue(_ km: String) -> Int? {
        let trimmed = km.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }
    
    // MARK: - Photo Validation
    
    /// Validates photo array
    /// - Parameter photos: Array of photos
    /// - Returns: True if valid, false otherwise and error message
    static func validatePhotos(_ photos: [UIImage]) -> (isValid: Bool, errorMessage: String?) {
        // Check count limit
        if photos.count > 10 {
            return (false, "Maximum 10 photos allowed")
        }
        
        // Check individual photo sizes
        for (index, photo) in photos.enumerated() {
            let sizeInMB = ImageManager.shared.getImageSizeInMB(photo)
            
            if sizeInMB > 10 {
                return (false, "Photo \(index + 1) is too large (max 10MB)")
            }
            
            if !ImageManager.shared.validateImage(photo) {
                return (false, "Photo \(index + 1) has invalid format")
            }
        }
        
        return (true, nil)
    }
    
    // MARK: - Plate Validation
    
    /// Validates Swiss license plate format
    /// - Parameter plate: Plate to validate
    /// - Returns: True if valid Swiss plate format
    static func validateSwissPlate(_ plate: String) -> Bool {
        let trimmed = plate.replacingOccurrences(of: " ", with: "").uppercased()
        
        // Swiss plate format: 1-2 letters + 1-6 numbers
        let pattern = "^[A-Z]{1,2}[0-9]{1,6}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        
        return regex?.firstMatch(in: trimmed, range: range) != nil
    }
}

