import XCTest

/// Settings page tests — theme, scan interval, region, feature toggles,
/// permission badges, and diagnostics buttons.
@MainActor
final class SettingsPageTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        launchAppForUITest(app)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// Scroll the settings scroll view to make lower sections visible.
    private func scrollSettings(byDeltaY deltaY: CGFloat) {
        let scrollView = app.scrollViews["settings-scroll-view"]
        if scrollView.exists {
            scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
        }
    }

    // MARK: - Navigation

    func testNavigateToSettingsPage() throws {
        continueAfterFailure = true
        navigateToSettings(app)
    }

    // MARK: - Appearance & Scan

    func testSettingsThemeAndScanControls() throws {
        guard navigateToSettings(app) else { return }

        // Theme picker — radio group with 3 options (system/light/dark).
        let themeGroup = app.radioGroups["settings-theme-picker"]
        guard themeGroup.waitForExistence(timeout: 3) else {
            XCTFail("Theme picker not found.\n\(app.debugDescription)")
            return
        }
        let themeButtons = themeGroup.radioButtons
        XCTAssertEqual(themeButtons.count, 3, "Expected 3 theme options (system/light/dark)")

        let originalThemeIndex = (0..<themeButtons.count).first {
            themeButtons.element(boundBy: $0).value as? Int == 1
        }
        let selectedThemeIndex = try XCTUnwrap(originalThemeIndex, "No selected theme option")
        let alternateThemeIndex = (selectedThemeIndex + 1) % themeButtons.count
        themeButtons.element(boundBy: alternateThemeIndex).click()
        waitForValue(
            1,
            of: themeButtons.element(boundBy: alternateThemeIndex),
            message: "Alternate theme did not become selected")
        themeButtons.element(boundBy: selectedThemeIndex).click()
        waitForValue(
            1,
            of: themeButtons.element(boundBy: selectedThemeIndex),
            message: "Original theme was not restored")

        // Scan interval picker — pop-up button with menu items.
        let intervalPicker = app.popUpButtons["settings-scan-interval-picker"]
        XCTAssertTrue(
            intervalPicker.waitForExistence(timeout: 3),
            "Scan interval picker not found")
        intervalPicker.click()
        let intervalItem = intervalPicker.menuItems.firstMatch
        XCTAssertTrue(
            intervalItem.waitForExistence(timeout: 2),
            "Scan interval menu did not open")
        XCTAssertEqual(intervalPicker.menuItems.count, 5, "Expected 5 scan interval options")
        app.typeKey(.escape, modifierFlags: [])

        // Region picker.
        let regionPicker = app.popUpButtons["settings-region-picker"]
        XCTAssertTrue(
            regionPicker.waitForExistence(timeout: 3),
            "Region picker not found")
        regionPicker.click()
        let regionItem = regionPicker.menuItems.firstMatch
        XCTAssertTrue(
            regionItem.waitForExistence(timeout: 2),
            "Region menu did not open")
        XCTAssertEqual(regionPicker.menuItems.count, 5, "Expected 5 region options")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Feature Toggles

    func testSettingsFeatureToggles() throws {
        guard navigateToSettings(app) else { return }

        // BLE toggle — renders as CheckBox on macOS.
        let bleToggle = app.checkBoxes["settings-ble-toggle"]
        guard bleToggle.waitForExistence(timeout: 3) else {
            XCTFail("BLE toggle not found")
            return
        }
        let bleWasOn = (bleToggle.value as? Int) == 1
        bleToggle.click()
        waitForValue(bleWasOn ? 0 : 1, of: bleToggle, message: "BLE toggle did not change state")
        bleToggle.click()
        waitForValue(bleWasOn ? 1 : 0, of: bleToggle, message: "BLE toggle state was not restored")

        // MCP toggle and port field.
        let mcpToggle = app.switches["settings-mcp-toggle"]
        XCTAssertTrue(
            mcpToggle.waitForExistence(timeout: 3),
            "MCP toggle not found")
        let portField = app.textFields["settings-mcp-port-field"]
        XCTAssertTrue(portField.exists, "MCP port field not found")
    }

    // MARK: - Diagnostics & Permissions

    func testSettingsDiagnosticsAndPermissions() throws {
        guard navigateToSettings(app) else { return }
        scrollSettings(byDeltaY: 600)

        // Permission badges.
        let locationBadge = app.descendants(matching: .any)["permission-location-badge"]
        XCTAssertTrue(
            locationBadge.waitForExistence(timeout: 3),
            "Location permission badge not found")

        let bluetoothBadge = app.descendants(matching: .any)["permission-bluetooth-badge"]
        XCTAssertTrue(
            bluetoothBadge.waitForExistence(timeout: 3),
            "Bluetooth permission badge not found")

        // Reveal logs button.
        let revealLogs = app.buttons["settings-reveal-logs-button"]
        XCTAssertTrue(
            revealLogs.waitForExistence(timeout: 3),
            "Reveal logs button not found")

        // Privacy policy button.
        let privacyBtn = app.buttons["settings-privacy-policy-button"]
        XCTAssertTrue(
            privacyBtn.waitForExistence(timeout: 3),
            "Privacy policy button not found")

        #if OSS
            // Auto-update toggle and check-now button (OSS only).
            scrollSettings(byDeltaY: 200)
            let autoCheckToggle = app.switches["settings-auto-check-toggle"]
            XCTAssertTrue(
                autoCheckToggle.waitForExistence(timeout: 3),
                "Auto-check toggle not found")

            let checkNowBtn = app.buttons["settings-check-now-button"]
            XCTAssertTrue(
                checkNowBtn.waitForExistence(timeout: 3),
                "Check now button not found")
        #endif
    }
}
