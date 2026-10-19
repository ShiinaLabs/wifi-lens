import XCTest

/// Network interfaces page tests.
@MainActor
final class InterfacesPageTests: XCTestCase {
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

    func testNavigateToInterfacesPage() throws {
        continueAfterFailure = true
        navigateToPage("sidebar-interfaces", pageID: "page-interfaces", app: app)
    }

    // MARK: - Content

    func testInterfacesToolbarChangesMode() throws {
        guard navigateToPage("sidebar-interfaces", pageID: "page-interfaces", app: app) else { return }

        let simple = app.radioButtons["secondary-toolbar-interfaces-simple"]
        let details = app.radioButtons["secondary-toolbar-interfaces-details"]
        let monitor = app.radioButtons["secondary-toolbar-interfaces-monitor"]
        guard waitForElement(simple, message: "Simple interfaces mode not found", app: app),
            waitForElement(details, message: "Details interfaces mode not found", app: app),
            waitForElement(monitor, message: "Monitor interfaces mode not found", app: app)
        else { return }

        XCTAssertEqual(simple.value as? Int, 1, "Simple mode should be selected by default")
        details.click()
        waitForValue(1, of: details, message: "Details mode did not become selected")
        monitor.click()
        waitForValue(1, of: monitor, message: "Monitor mode did not become selected")
        simple.click()
        waitForValue(1, of: simple, message: "Simple mode was not restored")
    }
}
