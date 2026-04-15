import XCTest
import SwiftUI
@testable import AracHasarKayit

#if canImport(SnapshotTesting)
import SnapshotTesting

final class EmptyStateViewSnapshotTests: XCTestCase {
    private func skipIfSnapshotsDisabled() throws {
        guard ProcessInfo.processInfo.environment["ENABLE_SNAPSHOT_TESTS"] == "1" else {
            throw XCTSkip("Set ENABLE_SNAPSHOT_TESTS=1 to run snapshot assertions.")
        }
    }

    func testEmptyStateDefaultAppearance() throws {
        try skipIfSnapshotsDisabled()
        let view = EmptyStateView(
            icon: "tray",
            title: "No Data",
            message: "Nothing to show"
        )
        .frame(width: 390, height: 844)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: .iPhone13)
        )
    }

    func testEmptyStateLightModeAppearance() throws {
        try skipIfSnapshotsDisabled()
        let view = EmptyStateView(
            icon: "tray",
            title: "No Data",
            message: "Nothing to show",
            buttonText: "Retry",
            buttonAction: {}
        )
        .preferredColorScheme(.light)
        .frame(width: 390, height: 844)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: .iPhone13)
        )
    }

    func testEmptyStateDarkModeAppearance() throws {
        try skipIfSnapshotsDisabled()
        let view = EmptyStateView(
            icon: "tray",
            title: "No Data",
            message: "Nothing to show",
            buttonText: "Retry",
            buttonAction: {}
        )
        .preferredColorScheme(.dark)
        .frame(width: 390, height: 844)

        assertSnapshot(
            of: UIHostingController(rootView: view),
            as: .image(on: .iPhone13)
        )
    }
}
#endif

