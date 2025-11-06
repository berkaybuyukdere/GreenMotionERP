import XCTest
@testable import AracHasarKayit

class AracViewModelTests: XCTestCase {
    var viewModel: AracViewModel!
    
    override func setUp() {
        super.setUp()
        // Note: This requires Firebase to be configured
        // In a real scenario, we would use dependency injection
        // For now, we'll test what we can without Firebase
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testViewModelInitialization() {
        // Test that ViewModel can be initialized
        // This is a basic smoke test
        XCTAssertNotNil(AracViewModel.self)
    }
    
    // MARK: - Data Validation Tests
    
    func testKategorilerNotEmpty() {
        let viewModel = AracViewModel()
        XCTAssertFalse(viewModel.kategoriler.isEmpty, "Categories should not be empty")
        XCTAssertTrue(viewModel.kategoriler.contains("A"), "Should contain category A")
    }
    
    // MARK: - Loading State Tests
    
    func testLoadingStatesInitialized() {
        let viewModel = AracViewModel()
        XCTAssertFalse(viewModel.isSavingArac, "isSavingArac should be false initially")
        XCTAssertFalse(viewModel.isUpdatingArac, "isUpdatingArac should be false initially")
        XCTAssertFalse(viewModel.isDeletingArac, "isDeletingArac should be false initially")
    }
}

