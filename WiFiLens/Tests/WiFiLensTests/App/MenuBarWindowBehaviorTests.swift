import AppKit
import SwiftUI
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@Suite("MenuBar Main Window Behavior")
struct MenuBarWindowBehaviorTests {
    @Test("debug console does not duplicate OSLog levels")
    func debugConsoleDoesNotDuplicateOSLogLevels() {
        #expect(DebugConsoleLogPolicy.shouldWrite(.trace))
        #expect(DebugConsoleLogPolicy.shouldWrite(.debug))
        #expect(!DebugConsoleLogPolicy.shouldWrite(.info))
        #expect(!DebugConsoleLogPolicy.shouldWrite(.notice))
        #expect(DebugConsoleLogPolicy.shouldWrite(.warning))
        #expect(DebugConsoleLogPolicy.shouldWrite(.error))
        #expect(DebugConsoleLogPolicy.shouldWrite(.critical))
    }

    @Test("network diagnostics route is shared and permission independent")
    @MainActor
    func networkDiagnosticsRouteRequirements() {
        #expect(SidebarPage.networkDiagnostics.requiresLocationAuthorization == false)
        #expect(SidebarPage.networkDiagnostics.requiresWiFi == false)
        #expect(SidebarPage.networkDiagnostics.icon == "stethoscope")
        #expect(EditionAssemblyProvider.configuration.sidebarBadgeStyle(for: .networkDiagnostics) == nil)
    }

    @Test("Pro sidebar badge uses paid-feature semantics")
    @MainActor
    func proSidebarBadgeStyle() {
        #expect(SidebarBadge.Style.pro.icon == "crown.fill")
        #expect(SidebarBadge.Style.pro.localizationKey == "common.badge.pro")
        #expect(EditionAssemblyProvider.configuration.sidebarBadgeStyle(for: .wifiCallingTest) == .pro)
    }

    @Test("Preview sidebar badge uses preview-feature semantics")
    func previewSidebarBadgeStyle() {
        #expect(SidebarBadge.Style.preview.icon == "sparkles")
        #expect(SidebarBadge.Style.preview.localizationKey == "common.badge.preview")
    }

    @Test("Semantic sidebar badge palettes keep small text readable")
    func semanticSidebarBadgePalettesMeetContrastTarget() {
        for style in [SidebarBadge.Style.pro, .preview] {
            #expect(style.palette.light.foreground.contrastRatio(to: style.palette.light.background) >= 4.5)
            #expect(style.palette.dark.foreground.contrastRatio(to: style.palette.dark.background) >= 4.5)
        }
    }

    @Test("Sidebar badge metrics remain legible beside navigation labels")
    func sidebarBadgeMetrics() {
        #expect(SidebarBadge.Metrics.textSize == 10)
        #expect(SidebarBadge.Metrics.iconSize == 9)
        #expect(SidebarBadge.Metrics.verticalPadding == 3)
        #expect(SidebarBadge.Metrics.borderWidth == 1)
    }

    @Test("Sidebar badges prefer full content before compact icon fallback")
    func sidebarBadgeAdaptivePresentationOrder() {
        #expect(SidebarBadge.Presentation.adaptiveOrder == [.full, .compact])
        #expect(SidebarBadge.Presentation.full.showsText)
        #expect(!SidebarBadge.Presentation.compact.showsText)
    }

    @MainActor
    @Test("Sidebar badge row reserves one minimum gap between label and badge")
    func sidebarBadgeRowUsesSingleMinimumGap() {
        let label = NSHostingView(
            rootView: Label("Network Check", systemImage: "stethoscope")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        )
        let badge = NSHostingView(rootView: SidebarBadge(style: .preview))
        let row = NSHostingView(
            rootView: SidebarBadgeRowContent(
                title: "Network Check",
                icon: "stethoscope",
                style: .preview,
                presentation: .full
            )
        )
        let expectedWidth = label.fittingSize.width
            + SidebarBadgeRowContent.minimumGap
            + badge.fittingSize.width

        #expect(row.fittingSize.width <= expectedWidth + 1)
    }

    @Test("route intent preserves current page when route is nil")
    func routeIntentPreservesCurrentPage() {
        #expect(routeIntent(for: nil) == .preserveCurrentPage)
    }

    @Test("route intent navigates when route is provided")
    func routeIntentNavigatesToSettings() {
        #expect(routeIntent(for: .settings) == .navigate(.settings))
    }

    @Test("route intent navigates to timeline when route is provided")
    func routeIntentNavigatesToTimeline() {
        #expect(routeIntent(for: .timeline) == .navigate(.timeline))
    }

    @Test("timeline page remains browse-only")
    func timelinePageDoesNotRequireLiveWiFiOrLocation() {
        #expect(SidebarPage.timeline.icon == "clock.arrow.circlepath")
        #expect(!SidebarPage.timeline.requiresLocationAuthorization)
        #expect(!SidebarPage.timeline.requiresWiFi)
    }

    @Test("Analysis routes have stable identities and order")
    func analysisRoutesHaveStableIdentitiesAndOrder() {
        #expect(SidebarPage.statistics.rawValue == "statistics")
        #expect(SidebarPage.insights.rawValue == "insights")
        #expect(SidebarPage.analysisPages == [.timeline, .statistics, .insights])
        #expect(SidebarPage.timeline.rawValue == "timeline")
        #expect(!SidebarPage.statistics.requiresLocationAuthorization)
        #expect(!SidebarPage.statistics.requiresWiFi)
        #expect(!SidebarPage.insights.requiresLocationAuthorization)
        #expect(!SidebarPage.insights.requiresWiFi)
    }

    @Test("Timeline badge reflects edition semantics")
    @MainActor
    func timelineBadgeReflectsEdition() {
        #expect(EditionAssemblyProvider.configuration.sidebarBadgeStyle(for: .timeline) == nil)
        #expect(EditionAssemblyProvider.configuration.analysisSidebarBadgeStyle == .pro)
    }

    @Test("Analysis group badge reflects Timeline preview semantics")
    @MainActor
    func analysisBadgesReflectTimelinePreviewSemantics() {
        for page in [SidebarPage.timeline, .statistics, .insights] {
            #expect(EditionAssemblyProvider.configuration.sidebarBadgeStyle(for: page) == nil)
        }
        #expect(EditionAssemblyProvider.configuration.analysisSidebarBadgeStyle == .pro)
    }

    @Test("sidebar section titles use localized keys")
    func sidebarSectionTitlesUseLocalizedKeys() {
        #expect(SidebarSection.overview.localizationKey == "sidebar.section.overview")
        #expect(SidebarSection.tools.localizationKey == "sidebar.section.tools")
        #expect(SidebarSection.analysis.localizationKey == "sidebar.section.analysis")
        #expect(SidebarSection.debug.localizationKey == "sidebar.section.debug")
        #expect(SidebarSection.settings.localizationKey == "sidebar.section.settings")
    }

    @Test("close action switches to accessory only when menu bar is enabled")
    func closeActionDependsOnMenuBarFlag() {
        #expect(closeAction(menuBarEnabled: true) == .switchToAccessory)
        #expect(closeAction(menuBarEnabled: false) == .keepCurrentPolicy)
    }

    @Test("reopen action switches to regular only from accessory mode with menu bar enabled")
    func reopenActionDependsOnCurrentPolicy() {
        #expect(reopenAction(menuBarEnabled: true, currentPolicy: .accessory) == .switchToRegular)
        #expect(reopenAction(menuBarEnabled: true, currentPolicy: .regular) == .keepCurrentPolicy)
        #expect(reopenAction(menuBarEnabled: false, currentPolicy: .accessory) == .keepCurrentPolicy)
    }

    @Test("resolved window is focused only when reopening requires window creation")
    func resolvedWindowFocusIntentDependsOnExistingWindow() {
        #expect(resolvedWindowFocusIntent(hasExistingMainWindow: true) == .noFollowUpFocus)
        #expect(resolvedWindowFocusIntent(hasExistingMainWindow: false) == .focusResolvedWindow)
    }
}
