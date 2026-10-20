import XCTest

/// Channel analysis page tests.
@MainActor
final class ChannelsPageTests: XCTestCase {
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

    func testNavigateToChannelsPage() throws {
        continueAfterFailure = true
        navigateToPage("sidebar-channels", pageID: "page-channels", app: app)
    }

    // MARK: - Content

    func testChannelsToolbarChangesMode() throws {
        guard navigateToPage("sidebar-channels", pageID: "page-channels", app: app) else { return }

        let simple = app.radioButtons["secondary-toolbar-channels-simple"]
        let table = app.radioButtons["secondary-toolbar-channels-table"]
        guard waitForElement(simple, message: "Simple channel mode not found", app: app),
            waitForElement(table, message: "Table channel mode not found", app: app)
        else { return }

        XCTAssertEqual(simple.value as? Int, 1, "Simple mode should be selected by default")
        table.click()
        waitForValue(1, of: table, message: "Table mode did not become selected")
        simple.click()
        waitForValue(1, of: simple, message: "Simple mode was not restored")
    }
}
