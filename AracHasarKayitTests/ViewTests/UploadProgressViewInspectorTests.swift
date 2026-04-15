import XCTest
@testable import AracHasarKayit

#if canImport(ViewInspector)
import ViewInspector

extension UploadProgressView: Inspectable {}

final class UploadProgressViewInspectorTests: XCTestCase {
    func testUploadProgressRendersMessageAndPercentage() throws {
        let view = UploadProgressView(
            progress: 0.42,
            currentItem: 2,
            totalItems: 5,
            message: "Uploading Photos"
        )

        let inspection = try view.inspect()
        XCTAssertEqual(try inspection.find(text: "Uploading Photos").string(), "Uploading Photos")
        XCTAssertEqual(try inspection.find(text: "42%").string(), "42%")
    }
}
#endif

