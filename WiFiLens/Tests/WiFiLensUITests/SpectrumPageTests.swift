import XCTest

/// Spectrum dashboard page tests (OSS-only features).
/// Pro-specific recording mode tests live in the ProUITests target.
@MainActor
final class SpectrumPageTests: XCTestCase {
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

    func testNavigateToSpectrumPage() throws {
        continueAfterFailure = true
        navigateToPage("sidebar-spectrum", pageID: "page-spectrum", app: app)
    }

    // MARK: - Content

    func testSpectrumDashboardSectionsVisible() throws {
        guard navigateToPage("sidebar-spectrum", pageID: "page-spectrum", app: app) else { return }

        let dashboard = app.descendants(matching: .any)["spectrum-dashboard"]
        waitForElement(dashboard, message: "Spectrum dashboard content not found", app: app)

        let liveMode = app.radioButtons["secondary-toolbar-spectrum-live"]
        waitForElement(liveMode, message: "Live spectrum toolbar mode not found", app: app)
        XCTAssertEqual(liveMode.value as? Int, 1, "Live spectrum mode should be selected")
    }
}
