import XCTest
@testable import AracHasarKayit

#if canImport(ViewInspector)
import ViewInspector

extension DemoBannerView: Inspectable {}

final class DemoBannerViewInspectorTests: XCTestCase {
    func testBannerRendersDaysRemainingText() throws {
        let view = DemoBannerView(daysRemaining: 5, onDismiss: {})

        let texts = try view.inspect().findAll(ViewType.Text.self).map { try $0.string() }
        XCTAssertTrue(texts.contains { $0.contains("5") })
    }

    func testDismissButtonCallsOnDismiss() throws {
        var dismissCalled = false
        let view = DemoBannerView(daysRemaining: 5) {
            dismissCalled = true
        }

        let inspection = try view.inspect()
        try inspection.find(ViewType.Button.self).tap()

        XCTAssertTrue(dismissCalled)
    }
}
#endif

