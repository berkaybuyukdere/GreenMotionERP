import XCTest
@testable import AracHasarKayit

#if canImport(ViewInspector)
import ViewInspector

extension EmptyStateView: Inspectable {}

final class EmptyStateViewInspectorTests: XCTestCase {
    func testEmptyStateRendersTitleAndMessage() throws {
        let view = EmptyStateView(
            icon: "tray",
            title: "No Data",
            message: "Nothing to show"
        )

        let inspection = try view.inspect()
        XCTAssertEqual(try inspection.find(text: "No Data").string(), "No Data")
        XCTAssertEqual(try inspection.find(text: "Nothing to show").string(), "Nothing to show")
    }
}
#endif

