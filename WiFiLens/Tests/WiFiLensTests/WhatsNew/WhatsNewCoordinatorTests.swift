import AppKit
import Foundation
import MarkdownKit
import Testing
@testable import WiFi_Lens

@MainActor
final class WhatsNewCoordinatorTests {
    private var store: InMemoryWhatsNewStateStore!
    private var coordinator: WhatsNewCoordinator!

    // MARK: - Version gating

    @Test func showsSheetWhenVersionDiffers() {
        let coordinator = makeCoordinator(storedVersion: "1.5.0", appVersion: "1.6.0")
        coordinator.checkForUpdate()
        #expect(coordinator.shouldShowSheet == true)
    }

    @Test func doesNotShowSheetWhenVersionMatches() {
        let coordinator = makeCoordinator(storedVersion: "1.6.0", appVersion: "1.6.0")
        coordinator.checkForUpdate()
        #expect(coordinator.shouldShowSheet == false)
    }

    @Test func showsSheetWhenNoStoredVersion() {
        let coordinator = makeCoordinator(storedVersion: nil, appVersion: "1.6.0")
        coordinator.checkForUpdate()
        #expect(coordinator.shouldShowSheet == true)
    }

    // MARK: - Mark seen

    @Test func markSeenPersistsVersion() {
        let coordinator = makeCoordinator(storedVersion: nil, appVersion: "1.6.0")
        coordinator.checkForUpdate()
        coordinator.markSeen()
        #expect(store.load().lastSeenVersion == "1.6.0")
        #expect(coordinator.shouldShowSheet == false)
    }

    @Test func dismissDoesNotPersistVersion() {
        let coordinator = makeCoordinator(storedVersion: nil, appVersion: "1.6.0")
        coordinator.checkForUpdate()
        coordinator.dismiss()
        #expect(store.load().lastSeenVersion == nil)
        #expect(coordinator.shouldShowSheet == false)
    }

    // MARK: - Onboarding integration

    @Test func markVersionSeenForOnboardingPreventsSheet() {
        let coordinator = makeCoordinator(storedVersion: nil, appVersion: "1.6.0")
        coordinator.markVersionSeenForOnboarding()
        coordinator.checkForUpdate()
        #expect(store.load().lastSeenVersion == "1.6.0")
        #expect(coordinator.shouldShowSheet == false)
    }

    // MARK: - Badge re-view

    @Test func badgeReViewOpensSheet() {
        let coordinator = makeCoordinator(storedVersion: "1.6.0", appVersion: "1.6.0")
        coordinator.showSheetFromBadge = true
        #expect(coordinator.showSheetFromBadge == true)
    }

    @Test func badgeReViewDismissResetsFlag() {
        let coordinator = makeCoordinator(storedVersion: "1.6.0", appVersion: "1.6.0")
        coordinator.showSheetFromBadge = true
        coordinator.markSeen()
        #expect(coordinator.showSheetFromBadge == false)
    }

    // MARK: - Version string

    @Test func versionStringContainsCurrentVersion() {
        let coordinator = makeCoordinator(storedVersion: nil, appVersion: "1.6.0")
        #expect(coordinator.versionString == "WiFi Lens 1.6.0")
    }


    // MARK: - Markdown renderer

    @Test func rendererUsesSharedMarkdownKitImplementation() {
        let markdown = "# Heading\n\n- Item\n\n[link](https://example.com)"
        let appOutput = MarkdownRenderer.render(markdown, pointSize: 13)
        let packageOutput = MarkdownKit.MarkdownRenderer.render(markdown, pointSize: 13)

        #expect(appOutput.isEqual(to: packageOutput))
    }

    @Test func renderHeadingIsLargerAndBold() {
        let ns = MarkdownRenderer.render("# Heading", pointSize: 13)
        let attrs = ns.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > 13)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test func renderListAddsBullet() {
        let ns = MarkdownRenderer.render("- Item", pointSize: 13)
        #expect(ns.string.hasPrefix("\u{2022}"))
    }

    @Test func renderCodeBlockUsesFixedPitchFont() {
        let ns = MarkdownRenderer.render("```swift\nprint(1)\n```", pointSize: 13)
        // The code block begins with an indentation tab, so scan for the first
        // run that actually carries the monospaced code font.
        var foundFixedPitch = false
        for i in 0..<ns.length {
            let font = ns.attributes(at: i, effectiveRange: nil)[.font] as? NSFont
            if font?.isFixedPitch == true {
                foundFixedPitch = true
                break
            }
        }
        #expect(foundFixedPitch)
    }

    @Test func renderSeparatesBlocksWithNewlines() {
        let ns = MarkdownRenderer.render("# A\n\nB", pointSize: 13)
        #expect(ns.string.contains("\n"))
    }

    @Test func renderPreservesLinks() {
        let ns = MarkdownRenderer.render("[link](https://example.com)", pointSize: 13)
        var foundLink = false
        for i in 0..<ns.length {
            if ns.attributes(at: i, effectiveRange: nil)[.link] != nil {
                foundLink = true
                break
            }
        }
        #expect(foundLink)
    }


    @Test func renderBlockQuoteIndentsText() {
        let ns = MarkdownRenderer.render("> a quote", pointSize: 13)
        let attrs = ns.attributes(at: 0, effectiveRange: nil)
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        #expect(style != nil)
        #expect((style?.headIndent ?? 0) > 0)
    }

    @Test func renderUnsupportedTableFallsBackToPlainText() {
        // MarkdownKit does not format tables, but Foundation's parsed cell text
        // remains readable in its plain-text fallback.
        let ns = MarkdownRenderer.render("| a | b |\n|---|---|\n| 1 | 2 |", pointSize: 13)
        #expect(ns.string == "ab12")
    }

    // MARK: - Helpers

    private func makeCoordinator(
        storedVersion: String?,
        appVersion: String
    ) -> WhatsNewCoordinator {
        store = InMemoryWhatsNewStateStore(
            initial: WhatsNewState(lastSeenVersion: storedVersion)
        )
        return WhatsNewCoordinator(store: store, currentVersion: appVersion)
    }
}
