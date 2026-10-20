import AppKit
import SwiftUI
import Testing

@testable import WiFi_Lens

/// The main window must not shrink to the point where the detail column disappears and only the
/// sidebar is left. Enforcing that needs both halves of `MainWindowSizing`: SwiftUI's hosting
/// controller rewrites `NSWindow.minSize` from the hosted content on every layout pass, so the
/// AppKit assignment alone does not survive. See `.agents/references/project/WINDOWING.md`.
@MainActor
struct MainWindowMinimumSizeTests {
    /// Windows are built the way `WindowGroup` builds them — an `NSHostingController` as the content
    /// view controller — because that is what overwrites `minSize`. An `NSHostingView` assigned
    /// straight to `contentView` leaves an already-assigned `minSize` alone and hides the defect.
    ///
    /// The detail column mirrors the shipping container: pages stay mounted inside a
    /// `GeometryReader`, which severs their layout minimums from the window and leaves the window
    /// with no floor of its own unless `mainWindowMinimumSize()` supplies one.
    private func makeWindow(applyingSwiftUIMinimum: Bool) -> NSWindow {
        let root = NavigationSplitView {
            Color.clear
        } detail: {
            GeometryReader { _ in Color.clear }
        }

        let rootView =
            applyingSwiftUIMinimum
            ? AnyView(root.mainWindowMinimumSize())
            : AnyView(root)

        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.styleMask = [.titled, .resizable]
        window.setContentSize(MainWindowSizing.defaultSize)
        MainWindowSizing.applyMinimumSize(to: window)
        window.layoutIfNeeded()
        return window
    }

    /// `setFrame` and `setContentSize` ignore `minSize`; only interactive resizing is clamped. The
    /// accessibility frame setter is the one in-process API that goes through that clamp, so it is
    /// what a user dragging the window edge looks like from a test.
    private func attemptResize(_ window: NSWindow, to size: CGSize) {
        window.setAccessibilityFrame(NSRect(origin: window.frame.origin, size: size))
    }

    @Test("The main window cannot be resized below the minimum size")
    func windowCannotBeResizedBelowMinimumSize() {
        let window = makeWindow(applyingSwiftUIMinimum: true)

        attemptResize(window, to: CGSize(width: 320, height: 200))

        #expect(window.frame.width >= MainWindowSizing.minSize.width)
        #expect(window.frame.height >= MainWindowSizing.minSize.height)
    }

    @Test("The minimum holds for a resize attempt that is only slightly too small")
    func windowCannotBeResizedJustBelowMinimumSize() {
        let window = makeWindow(applyingSwiftUIMinimum: true)

        attemptResize(
            window,
            to: CGSize(
                width: MainWindowSizing.minSize.width - 1,
                height: MainWindowSizing.minSize.height - 1
            )
        )

        #expect(window.frame.width >= MainWindowSizing.minSize.width)
        #expect(window.frame.height >= MainWindowSizing.minSize.height)
    }

    @Test("SwiftUI layout leaves the window minimum at the policy size")
    func swiftUILayoutPreservesTheWindowMinimum() {
        let window = makeWindow(applyingSwiftUIMinimum: true)

        #expect(window.minSize.width >= MainWindowSizing.minSize.width)
        #expect(window.minSize.height >= MainWindowSizing.minSize.height)
    }

    /// Guards the reason `mainWindowMinimumSize()` exists. If this starts failing, SwiftUI stopped
    /// lowering the window minimum and the SwiftUI half of the policy can be reconsidered.
    @Test("Without the SwiftUI minimum, SwiftUI lowers the window minimum")
    func swiftUIOverwritesTheAppKitMinimumWhenContentDeclaresNone() {
        let window = makeWindow(applyingSwiftUIMinimum: false)

        #expect(window.minSize.width < MainWindowSizing.minSize.width)

        attemptResize(window, to: CGSize(width: 320, height: 200))

        #expect(window.frame.width < MainWindowSizing.minSize.width)
    }
}
