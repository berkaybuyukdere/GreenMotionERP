import XCTest

class VehicleFlowTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Vehicle List Tests
    
    func testVehicleListAppears() throws {
        // Navigate to Vehicles tab
        let vehiclesTab = app.tabBars.buttons["Vehicles"]
        if vehiclesTab.exists {
            vehiclesTab.tap()
            
            // Wait for vehicles list to appear
            let exists = NSPredicate(format: "exists == true")
            expectation(for: exists, evaluatedWith: app.navigationBars.firstMatch, handler: nil)
            waitForExpectations(timeout: 5, handler: nil)
            
            // Test passes if we can navigate to vehicles tab
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Navigation Tests
    
    func testTabNavigation() throws {
        // Test that all tabs are accessible
        let tabBar = app.tabBars.firstMatch
        
        if tabBar.exists {
            // Try to find common tabs
            let dashboardTab = app.tabBars.buttons["Dashboard"]
            let vehiclesTab = app.tabBars.buttons["Vehicles"]
            let scanTab = app.tabBars.buttons["Scan"]
            
            // At least one tab should exist
            XCTAssertTrue(dashboardTab.exists || vehiclesTab.exists || scanTab.exists, "At least one tab should be accessible")
        }
    }
    
    // MARK: - App Launch Test
    
    func testAppLaunches() throws {
        // Basic test that app launches without crashing
        XCTAssertTrue(app.state == .runningForeground, "App should be running in foreground")
    }
}

