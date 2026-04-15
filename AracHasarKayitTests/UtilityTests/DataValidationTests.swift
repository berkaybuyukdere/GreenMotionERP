import XCTest
@testable import AracHasarKayit

class DataValidationTests: XCTestCase {
    
    // MARK: - String Validation Tests
    
    func testSwissPlateValidation() {
        // Valid Swiss plates
        XCTAssertTrue("ZH12345".isValidSwissPlate, "ZH12345 should be valid")
        XCTAssertTrue("BE 12345".isValidSwissPlate, "BE 12345 should be valid")
        XCTAssertTrue("AG 1".isValidSwissPlate, "AG 1 should be valid")
        
        // Invalid Swiss plates
        XCTAssertFalse("12345".isValidSwissPlate, "Numbers only should be invalid")
        XCTAssertFalse("ABCDEF".isValidSwissPlate, "Letters only should be invalid")
        XCTAssertFalse("".isValidSwissPlate, "Empty string should be invalid")
    }
    
    func testEmailValidation() {
        // Valid emails
        XCTAssertTrue("test@example.com".isValidEmail, "Valid email should pass")
        XCTAssertTrue("user.name@domain.co.uk".isValidEmail, "Valid email with subdomain should pass")
        
        // Invalid emails
        XCTAssertFalse("invalid".isValidEmail, "Invalid email should fail")
        XCTAssertFalse("test@".isValidEmail, "Email without domain should fail")
        XCTAssertFalse("@example.com".isValidEmail, "Email without local part should fail")
    }
    
    func testPhoneNumberValidation() {
        // Valid phone numbers
        XCTAssertTrue("+41 79 123 45 67".isValidPhoneNumber, "Swiss phone number should be valid")
        XCTAssertTrue("0791234567".isValidPhoneNumber, "Swiss phone number without formatting should be valid")
        
        // Invalid phone numbers
        XCTAssertFalse("123".isValidPhoneNumber, "Too short phone number should fail")
        XCTAssertFalse("abc".isValidPhoneNumber, "Non-numeric phone number should fail")
    }
    
    func testStringFieldValidation() {
        // Test empty field validation
        XCTAssertThrowsError(try "".validate(fieldName: "Test", minLength: 1)) { error in
            if let validationError = error as? ValidationError,
               case .emptyField(let field) = validationError {
                XCTAssertEqual(field, "Test")
            } else {
                XCTFail("Expected emptyField error")
            }
        }
        
        // Test too short validation
        XCTAssertThrowsError(try "ab".validate(fieldName: "Test", minLength: 5)) { error in
            if let validationError = error as? ValidationError,
               case .tooShort(let field, let minLength) = validationError {
                XCTAssertEqual(field, "Test")
                XCTAssertEqual(minLength, 5)
            } else {
                XCTFail("Expected tooShort error")
            }
        }
        
        // Test too long validation
        let longString = String(repeating: "a", count: 101)
        XCTAssertThrowsError(try longString.validate(fieldName: "Test", maxLength: 100)) { error in
            if let validationError = error as? ValidationError,
               case .tooLong(let field, let maxLength) = validationError {
                XCTAssertEqual(field, "Test")
                XCTAssertEqual(maxLength, 100)
            } else {
                XCTFail("Expected tooLong error")
            }
        }
        
        // Test valid string
        XCTAssertNoThrow(try "Valid String".validate(fieldName: "Test", minLength: 1, maxLength: 100))
    }
    
    // MARK: - Arac Validation Tests
    
    func testAracValidation() {
        // Valid vehicle
        let validArac = Arac(
            plaka: "ZH12345",
            marka: "BMW",
            model: "X5",
            kategori: "A"
        )
        XCTAssertNoThrow(try validArac.validate(), "Valid vehicle should pass validation")
        
        // Invalid plate
        let invalidPlateArac = Arac(
            plaka: "12345", // Invalid Swiss plate
            marka: "BMW",
            model: "X5",
            kategori: "A"
        )
        XCTAssertThrowsError(try invalidPlateArac.validate()) { error in
            if let validationError = error as? ValidationError,
               case .invalidFormat(let field) = validationError {
                XCTAssertEqual(field, "License Plate")
            } else {
                XCTFail("Expected invalidFormat(License Plate) error")
            }
        }
        
        // Empty plate
        let emptyPlateArac = Arac(
            plaka: "",
            marka: "BMW",
            model: "X5",
            kategori: "A"
        )
        XCTAssertThrowsError(try emptyPlateArac.validate())
        
        // Empty brand
        let emptyBrandArac = Arac(
            plaka: "ZH12345",
            marka: "",
            model: "X5",
            kategori: "A"
        )
        XCTAssertThrowsError(try emptyBrandArac.validate())
    }
    
    // MARK: - HasarKaydi Validation Tests
    
    func testHasarKaydiValidation() {
        let vehicleId = UUID()
        let validHasar = HasarKaydi(
            aracId: vehicleId,
            aracPlaka: "ZH12345",
            tarih: Date(),
            handoverTarihi: Date(),
            resKodu: "RES-12345",
            km: 50000,
            fotograflar: ["photo1.jpg"],
            durum: .inProgress
        )
        XCTAssertNoThrow(try validHasar.validate(), "Valid damage record should pass validation")
        
        // RES code without prefix should also be accepted (numeric only)
        let invalidResHasar = HasarKaydi(
            aracId: vehicleId,
            aracPlaka: "ZH12345",
            tarih: Date(),
            handoverTarihi: Date(),
            resKodu: "12345", // Missing RES- prefix
            km: 50000,
            fotograflar: ["photo1.jpg"],
            durum: .inProgress
        )
        XCTAssertNoThrow(try invalidResHasar.validate(), "Numeric-only RES code should be accepted")
        
        // No photos
        let noPhotosHasar = HasarKaydi(
            aracId: vehicleId,
            aracPlaka: "ZH12345",
            tarih: Date(),
            handoverTarihi: Date(),
            resKodu: "RES-12345",
            km: 50000,
            fotograflar: [],
            durum: .inProgress
        )
        XCTAssertThrowsError(try noPhotosHasar.validate())
        
        // Invalid kilometers (negative)
        let invalidKmHasar = HasarKaydi(
            aracId: vehicleId,
            aracPlaka: "ZH12345",
            tarih: Date(),
            handoverTarihi: Date(),
            resKodu: "RES-12345",
            km: -100,
            fotograflar: ["photo1.jpg"],
            durum: .inProgress
        )
        XCTAssertThrowsError(try invalidKmHasar.validate())
    }
}

