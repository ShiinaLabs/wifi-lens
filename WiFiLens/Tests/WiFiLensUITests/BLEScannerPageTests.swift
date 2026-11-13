import XCTest

/// BLE scanner page tests.
@MainActor
final class BLEScannerPageTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        launchAppForUITest(app)
    }

    override func tearDown() async throws {
        app.terminate()
    }

    // MARK: - Navigation

    func testNavigateToBLEScannerPage() throws {
        guard navigateToPage("sidebar-bleScanner", pageID: "page-bleScanner", app: app) else { return }

        let disabledState = app.descendants(matching: .any)["ble-disabled-state"]
        waitForElement(
            disabledState,
            message: "UI test mode should expose the deterministic BLE disabled state",
            app: app)
    }
}
