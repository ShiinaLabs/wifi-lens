import AppKit
import SwiftUI

enum EditionComposition {
    static var guidanceConfiguration: GuidanceConfiguration {
        var config = GuidanceConfiguration()
        config.invitationEnabled = true
        return config
    }

    static var exportSuccessPresentation: ExportSuccessPresentation { .banner }

    static func makeOnboardingExistingInstallationDetector() -> any ExistingInstallationDetecting {
        SparkleAutomaticCheckExistingInstallationDetector()
    }

    static var onboardingConfiguration: OnboardingConfiguration {
        OnboardingConfiguration(
            welcomeEnabled: true,
            showsProLink: true,
            proURL: ExternalLinks.url(for: .appStoreCampaignWelcome),
            startRoute: .overview,
            startToolbarSelection: nil,
            primaryActionKey: "onboarding.welcome.start",
            highlights: [
                OnboardingHighlight(icon: "wifi", titleKey: "onboarding.welcome.highlight.live"),
                OnboardingHighlight(icon: "waveform.path.ecg", titleKey: "onboarding.welcome.highlight.diagnostics"),
                OnboardingHighlight(icon: "square.and.arrow.up", titleKey: "onboarding.welcome.highlight.export")
            ]
        )
    }

    @MainActor
    static var markdownExportCommandContribution: MarkdownExportCommandContribution {
        .lockedPreview
    }

    @MainActor
    static func makeMainWindowState() -> AnyObject { NSObject() }

    @MainActor
    static func makeRoamingViewModel() -> RoamingTestViewModel { RoamingTestViewModel() }

    static var initialMainWindowRoute: SidebarPage { .overview }

    @MainActor
    static func configureMainWindow(_ window: NSWindow) {}

    @MainActor
    static func mainWindowDidFinishStartup(_ windowID: UUID) {}

    @MainActor
    static func registerMainWindowState(_ state: AnyObject, for windowID: UUID) -> Bool { true }

    @MainActor
    static func unregisterMainWindowState(_ state: AnyObject, for windowID: UUID) {}

    static let isTimelineLockedPreview = true

    static var timelineToolbarDescriptor: SecondaryToolbarDescriptor? { nil }

    static var spectrumToolbarDescriptor: SecondaryToolbarDescriptor {
        .spectrum(recordingLocked: true)
    }

    @ViewBuilder
    @MainActor
    static func settingsContribution() -> some View {
        Section {
            BLEFeatureSettingsRow()
            MenuBarFeaturePreviewRow()
        } header: {
            Text(String(localized: "settings.section.features", comment: "Features subsection header in settings"))
        }
    }

    @ViewBuilder
    @MainActor
    static func detailContribution(context: EditionCompositionContext) -> some View {
        switch context.selectedPage.wrappedValue {
        case .spectrum:
            OSSSpectrumCompositionView(
                scannerViewModel: context.scannerViewModel,
                isVendorColumnAvailable: context.isMACVendorDatabaseAvailable,
                selection: context.secondaryToolbarSelections.wrappedValue.spectrum
            )
            .accessibilityIdentifier("page-spectrum")
            .accessibilityElement(children: .contain)
        case .timeline:
            ProFeaturePlaceholderView(
                featureName: String(localized: "pro.timeline.title", comment: "Pro timeline feature title"),
                featureDescription: String(localized: "pro.timeline.description", comment: "Pro timeline feature description"),
                featureIcon: SidebarPage.timeline.icon,
                campaign: .appStoreCampaignPreviewTimeline,
                customSkeleton: { TimelineSkeletonView() }
            )
            .accessibilityIdentifier("page-timeline")
        case .statistics:
            ProFeaturePlaceholderView(
                featureName: String(localized: "pro.statistics.title", comment: "Pro Statistics feature title"),
                featureDescription: String(localized: "pro.statistics.description", comment: "Pro Statistics feature description"),
                featureIcon: SidebarPage.statistics.icon,
                campaign: .appStoreCampaignPreviewStatistics,
                customSkeleton: { StatisticsSkeletonView() }
            )
            .accessibilityIdentifier("page-statistics")
        case .insights:
            ProFeaturePlaceholderView(
                featureName: String(localized: "pro.insights.title", comment: "Pro Insights feature title"),
                featureDescription: String(localized: "pro.insights.description", comment: "Pro Insights feature description"),
                featureIcon: SidebarPage.insights.icon,
                campaign: .appStoreCampaignPreviewInsights,
                customSkeleton: { InsightsSkeletonView() }
            )
            .accessibilityIdentifier("page-insights")
        case .wifiCallingTest:
            ProFeaturePlaceholderView(
                featureName: String(localized: "pro.wifi_calling_test.title", comment: "Pro Wi-Fi Calling Test feature title"),
                featureDescription: String(localized: "pro.wifi_calling_test.description", comment: "Pro Wi-Fi Calling Test feature description"),
                featureIcon: "wifi",
                campaign: .appStoreCampaignPreviewLock,
                customSkeleton: { WiFiCallingSkeletonView() }
            )
            .accessibilityIdentifier("page-wifiCallingTest")
        default:
            EmptyView()
        }
    }

#if DEBUG
    /// Debug-only manual testing controls for the OSS invitation flow. The
    /// whole menu is compiled out of Release builds.
    @MainActor
    static func debugCommands(
        showMainWindow: @escaping (SidebarPage) -> Void
    ) -> some Commands {
        CommandMenu("Debug") {
            Menu("Onboarding") {
                Button("Reset Welcome State") {
                    OnboardingCoordinator.shared.debugReset()
                }
                Button("Show Welcome Now") {
                    guard EditionComposition.onboardingConfiguration.welcomeEnabled else { return }
                    OnboardingCoordinator.shared.debugRequestShowWelcome()
                    NSApp.activate(ignoringOtherApps: true)
                    if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        mainWindow.makeKeyAndOrderFront(nil)
                    } else {
                        showMainWindow(.overview)
                    }
                }
                Button("Log Onboarding State") {
                    OnboardingCoordinator.shared.debugLogState(edition: "OSS")
                }
            }
            Menu("What's New") {
                Button("Reset What's New State") {
                    WhatsNewCoordinator.shared.debugReset()
                }
                Button("Show What's New Now") {
                    WhatsNewCoordinator.shared.debugRequestShow()
                }
            }
            Divider()
            Menu("Lifecycle Guidance") {
                Button("Reset Lifecycle Guidance State") {
                    GuidanceCoordinator.shared.debugResetState()
                }
                Button("Prepare OSS Invitation Eligibility") {
                    GuidanceCoordinator.shared.debugPrepareInvitationEligibility()
                }
                Button("Trigger Diagnostics Invitation") {
                    GuidanceCoordinator.shared.debugScheduleInvitation(for: .diagnosticsCompleted)
                    GuidanceDebugOverrides.requestDiagnosticsStaging()
                    showMainWindow(.networkDiagnostics)
                }
                Button("Trigger Export Invitation Banner") {
                    GuidanceCoordinator.shared.debugScheduleInvitation(for: .exportSucceeded)
                    GuidanceCoordinator.shared.debugPublishExportFeedback()
                    NSApp.activate(ignoringOtherApps: true)
                    if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        mainWindow.makeKeyAndOrderFront(nil)
                    } else {
                        showMainWindow(.overview)
                    }
                }
                Picker("Pro Installation Override", selection: Binding(
                    get: { GuidanceDebugOverrides.proInstallationOverride },
                    set: { GuidanceDebugOverrides.setProInstallationOverride($0) }
                )) {
                    Text("Use Real Detection").tag(ProInstallationOverride.useRealDetection)
                    Text("Treat Pro as Not Installed").tag(ProInstallationOverride.treatAsNotInstalled)
                    Text("Treat Pro as Installed").tag(ProInstallationOverride.treatAsInstalled)
                }
                Button("Log Lifecycle Guidance State") {
                    GuidanceCoordinator.shared.debugLogState(edition: "OSS")
                }
            }
        }
    }
#endif

    static func startLifecycle(observationRuntime: WiFiObservationRuntime) {}

    @MainActor
    static func prepareForTermination() async {}

    @MainActor
    static func mainWindowDidBecomeActive(_ windowID: UUID) {}

    @MainActor
    static func mainWindowWillClose(_ windowID: UUID) {}

    @SceneBuilder
    @MainActor
    static func menuBarScene(
        openMainWindow: @escaping (SidebarPage?) -> Void,
        terminate: @escaping () -> Void
    ) -> some Scene {}

    static let menuBarWindowManagementEnabled = false
}

private struct OSSSpectrumCompositionView: View {
    @Bindable var scannerViewModel: ScannerViewModel
    let isVendorColumnAvailable: Bool
    let selection: SecondaryToolbarItemID

    var body: some View {
        if selection == .spectrumRecording {
            ProFeaturePlaceholderView(
                featureName: String(localized: "pro.recording.title", comment: "Pro recording feature title"),
                featureDescription: String(localized: "pro.recording.description", comment: "Pro recording feature description"),
                featureIcon: "record.circle",
                customSkeleton: { RecordingSkeletonView() }
            )
        } else {
            ContentView(
                viewModel: scannerViewModel,
                isVendorColumnAvailable: isVendorColumnAvailable
            )
        }
    }
}
