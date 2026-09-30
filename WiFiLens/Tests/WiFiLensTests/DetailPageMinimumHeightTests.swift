import AppKit
import SwiftUI
import Testing
import WiFiLensCore
@testable import WiFi_Lens

/// Detail pages stay mounted while hidden so their page-local state survives navigation.
/// SwiftUI therefore raises the tallest mounted page's minimum height into an
/// `NSHostingView.minHeight` constraint on the split-view column and applies it to the
/// `NSWindow` itself, so a single page can make the app window taller than the screen.
/// See `.agents/references/project/WINDOWING.md`.
@MainActor
struct DetailPageMinimumHeightTests {
    /// Deliberately narrower than the detail column ever gets. Text that refuses vertical
    /// truncation wraps into a very tall column at small widths, which is where the
    /// minimum height escapes.
    private static let probeWidth: CGFloat = 320

    /// No page may demand more than the default launch height of the window.
    private static let maximumMinimumHeight: CGFloat = 700

    /// Returns the largest `NSHostingView.minHeight` constraint SwiftUI installs for the page.
    /// The page must be measured inside a real `NavigationSplitView` in a window: SwiftUI only
    /// emits that constraint for split-view columns, so `sizeThatFits` on the bare page reports
    /// a small height and misses the defect entirely.
    private func minimumHeight(of view: some View) -> CGFloat {
        let host = NSHostingView(rootView: NavigationSplitView { Color.clear } detail: { view })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.probeWidth, height: 200),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.layoutIfNeeded()

        var highest: CGFloat = 0
        func walk(_ subject: NSView) {
            for constraint in subject.constraints
            where constraint.identifier == "NSHostingView.minHeight" {
                highest = max(highest, constraint.constant)
            }
            subject.subviews.forEach(walk)
        }
        walk(host)
        return highest
    }

    @Test("BLE page does not impose a tall minimum height when the feature is off")
    func bleDisabledStateMinimumHeightIsBounded() {
        let height = minimumHeight(of: BLEScannerView(viewModel: nil, bleEnabled: false))
        #expect(height <= Self.maximumMinimumHeight)
    }

    @Test("Channels page minimum height stays within the default window height")
    func channelsMinimumHeightIsBounded() {
        let height = minimumHeight(of: ChannelQualityView(channels: [], mode: .simple))
        #expect(height <= Self.maximumMinimumHeight)
    }

    @Test("Network self-check page minimum height stays within the default window height")
    func networkDiagnosticsMinimumHeightIsBounded() {
        let height = minimumHeight(of: NetworkDiagnosticsView(viewModel: NetworkDiagnosticsViewModel()))
        #expect(height <= Self.maximumMinimumHeight)
    }

    @Test("Roaming page minimum height stays within the default window height")
    func roamingMinimumHeightIsBounded() {
        let height = minimumHeight(of: RoamingTestView(viewModel: RoamingTestViewModel()))
        #expect(height <= Self.maximumMinimumHeight)
    }
}
