import XCTest
@testable import AracHasarKayit

class ErrorManagerTests: XCTestCase {
    
    func testErrorManagerExists() {
        XCTAssertNotNil(ErrorManager.shared, "ErrorManager singleton should exist")
    }
    
    func testErrorHandling() {
        let testError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        // Test that error handling doesn't crash
        ErrorManager.shared.showError(testError, context: "Test Context")
        
        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }
    
    func testErrorMessageHandling() {
        // Test that error message handling doesn't crash
        ErrorManager.shared.showError(message: "Test error message")
        
        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }
}

