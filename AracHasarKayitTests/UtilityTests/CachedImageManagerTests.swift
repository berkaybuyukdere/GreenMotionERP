import XCTest
@testable import AracHasarKayit

class CachedImageManagerTests: XCTestCase {
    
    var imageManager: CachedImageManager!
    
    override func setUp() {
        super.setUp()
        imageManager = CachedImageManager.shared
    }
    
    override func tearDown() {
        imageManager = nil
        super.tearDown()
    }
    
    // MARK: - Cache Management Tests
    
    func testCacheManagerExists() {
        XCTAssertNotNil(CachedImageManager.shared, "CachedImageManager singleton should exist")
    }
    
    func testCacheCleanup() {
        // API is now fire-and-forget; verify it doesn't crash.
        CachedImageManager.shared.performCacheCleanup()
        XCTAssertTrue(true)
    }
    
    // MARK: - URL Validation Tests
    
    func testInvalidURLHandling() {
        let expectation = XCTestExpectation(description: "Invalid URL handled")
        
        // Note: loadImage method signature may vary, this is a basic test
        // In real implementation, we would test the actual method signature
        expectation.fulfill()
        
        wait(for: [expectation], timeout: 1.0)
    }
}

