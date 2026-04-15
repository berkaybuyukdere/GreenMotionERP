import XCTest
@testable import AracHasarKayit

#if canImport(ViewInspector)
import ViewInspector

extension ErrorView: Inspectable {}

final class ErrorViewInspectorTests: XCTestCase {
    func testErrorViewRendersErrorMessage() throws {
        let view = ErrorView(error: "Network unavailable")

        let inspection = try view.inspect()
        XCTAssertEqual(try inspection.find(text: "Network unavailable").string(), "Network unavailable")
    }

    func testRetryButtonInvokesRetryAction() throws {
        var retryCalled = false
        let view = ErrorView(error: "Temporary failure") {
            retryCalled = true
        }

        let inspection = try view.inspect()
        try inspection.find(ViewType.Button.self).tap()

        XCTAssertTrue(retryCalled)
    }

    func testNoRetryButtonWhenRetryActionIsNil() throws {
        let view = ErrorView(error: "No retry path")

        let inspection = try view.inspect()
        XCTAssertThrowsError(try inspection.find(ViewType.Button.self))
    }
}
#endif

