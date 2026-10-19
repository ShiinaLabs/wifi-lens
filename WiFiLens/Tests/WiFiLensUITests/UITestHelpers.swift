import XCTest

/// Shared helpers for WiFiLens UI tests.
/// Each page-specific test file's `XCTestCase` subclass can call these free functions
/// to avoid duplicating setup boilerplate.
extension XCTestCase {

    @discardableResult
    func waitForElement(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        message: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("\(message)\n\(app.debugDescription)", file: file, line: line)
            return false
        }
        return true
    }

    @discardableResult
    func waitForValue(
        _ expectedValue: Int,
        of element: XCUIElement,
        timeout: TimeInterval = 3,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElement)?.value as? Int == expectedValue
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        guard result == .completed else {
            XCTFail(message, file: file, line: line)
            return false
        }
        return true
    }

    @discardableResult
    func waitForEither(
        _ first: XCUIElement,
        _ second: XCUIElement,
        timeout: TimeInterval = 5,
        message: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate { _, _ in first.exists || second.exists }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        guard result == .completed else {
            XCTFail("\(message)\n\(app.debugDescription)", file: file, line: line)
            return false
        }
        return true
    }

    /// Standard UI test launch: purge saved state, set launch arguments, and launch.
    /// Call from `setUpWithError`.
    func launchAppForUITest(
        _ app: XCUIApplication,
        bundleID: String = "io.github.kaoru.wifi-lens"
    ) {
        let savedState = NSHomeDirectory() + "/Library/Saved Application State/\(bundleID).savedState"
        try? FileManager.default.removeItem(atPath: savedState)

        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-UITest",
        ]
        app.launch()

        let dismissButton = app.dialogs.firstMatch.buttons["Ignore"]
        if dismissButton.exists {
            dismissButton.click()
        }
    }

    /// Click a sidebar item by its accessibility identifier.
    @discardableResult
    func selectSidebar(
        _ sidebarID: String, app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) -> Bool {
        let sidebar = app.descendants(matching: .any)[sidebarID]
        guard
            waitForElement(
                sidebar,
                message: "Sidebar item '\(sidebarID)' not found",
                app: app,
                file: file,
                line: line
            )
        else { return false }
        sidebar.click()
        return true
    }

    /// Click a sidebar item by its accessibility identifier and verify its exact target page.
    @discardableResult
    func navigateToPage(
        _ sidebarID: String, pageID: String, app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) -> Bool {
        guard selectSidebar(sidebarID, app: app, file: file, line: line) else { return false }

        let page = app.descendants(matching: .any)[pageID]
        return waitForElement(
            page,
            timeout: 5,
            message: "\(sidebarID) did not navigate to \(pageID)",
            app: app,
            file: file,
            line: line
        )
    }

    /// Click the Settings sidebar item and wait for the settings page to appear.
    @discardableResult
    func navigateToSettings(
        _ app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) -> Bool {
        navigateToPage("sidebar-settings", pageID: "page-settings", app: app, file: file, line: line)
    }
}
