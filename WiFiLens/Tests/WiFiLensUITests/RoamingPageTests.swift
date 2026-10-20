import XCTest

/// Roaming test page tests.
@MainActor
final class RoamingPageTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        launchAppForUITest(app)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Navigation

    func testNavigateToRoamingPage() throws {
        continueAfterFailure = true
        navigateToPage("sidebar-roaming", pageID: "page-roaming", app: app)
    }

    // MARK: - Controls

    func testRoamingControlsPresent() throws {
        guard navigateToPage("sidebar-roaming", pageID: "page-roaming", app: app) else { return }

        let idleState = app.descendants(matching: .any)["roaming-idle-state"]
        let activeState = app.descendants(matching: .any)["roaming-active-state"]
        guard
            waitForEither(
                idleState,
                activeState,
                message: "Roaming page should expose either idle or active state",
                app: app
            )
        else { return }
        XCTAssertNotEqual(
            idleState.exists, activeState.exists,
            "Roaming page should expose exactly one state")
    }
}
