import AppKit
import SwiftUI
import WiFiLensCore

enum OSSEditionAssembly {
    @MainActor
    static let configuration = WiFiLensEditionConfiguration(
        identity: .openSource,
        capabilities: [.ble],
        shouldStartObservationRuntime: true,
        requiresLiveWiFiAuthorization: true,
        isTimelineLockedPreview: true,
        initialMainWindowRoute: .overview,
        timelineToolbarDescriptor: nil,
        spectrumToolbarDescriptor: .spectrum(recordingLocked: true),
        exportSuccessPresentation: .banner,
        onboardingConfiguration: onboardingConfiguration,
        guidanceConfiguration: guidanceConfiguration,
        guidanceCoordinator: guidanceCoordinator,
        shellHooks: WiFiLensEditionShellHooks(
            markdownExportCommandContribution: .lockedPreview,
            makeMainWindowState: makeMainWindowState,
            makeObservationRuntime: makeObservationRuntime,
            makeRoamingViewModel: makeRoamingViewModel,
            makeOnboardingExistingInstallationDetector: makeOnboardingExistingInstallationDetector,
            configureMainWindow: configureMainWindow,
            mainWindowDidFinishStartup: mainWindowDidFinishStartup,
            registerMainWindowState: registerMainWindowState,
            unregisterMainWindowState: unregisterMainWindowState,
            startLifecycle: startLifecycle,
            prepareForTermination: prepareForTermination,
            mainWindowDidBecomeActive: mainWindowDidBecomeActive,
            mainWindowWillClose: mainWindowWillClose,
            detailContribution: { AnyView(detailContribution(context: $0)) },
            settingsContribution: { AnyView(settingsContribution()) }
        ),
        menuBarWindowManagementEnabled: false
    )

    @ViewBuilder
    @MainActor
    static func roamingPageContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
    }

    @ViewBuilder
    @MainActor
    static func apRadarPageContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
    }

    @ViewBuilder
    @MainActor
    static func channelsPageContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
    }

    static var isControlledDemoSession: Bool { false }
    static var shouldStartObservationRuntime: Bool { true }
    static var requiresLiveWiFiAuthorization: Bool { true }

    @MainActor
    static let guidanceCoordinator = GuidanceCoordinator(
        configuration: guidanceConfiguration,
        stateStore: UserDefaultsGuidanceStateStore(),
        isProAppInstalled: {
#if DEBUG
            switch GuidanceDebugOverrides.proInstallationOverride {
            case .useRealDetection: break
            case .treatAsNotInstalled: return false
            case .treatAsInstalled: return true
            }
#endif
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.kaoru.wifi-lens-pro") != nil
        },
        campaignURL: { moment in
            switch moment {
            case .diagnosticsCompleted, .analysisLoaded, .roamingCompleted:
                ExternalLinks.url(for: .appStoreCampaignDiagnosis)
            case .exportSucceeded:
                ExternalLinks.url(for: .appStoreCampaignExport)
            }
        }
    )

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
    static func makeRoamingViewModel(scannerViewModel: ScannerViewModel) -> RoamingTestViewModel {
        RoamingTestViewModel {
            OSSEditionAssembly.guidanceCoordinator.record(.roamingCompleted)
        }
    }

    @MainActor
    static func makeObservationRuntime(store: WiFiObservationStore) -> WiFiObservationRuntime {
        WiFiObservationRuntime(store: store)
    }

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
                    EditionAssemblyProvider.onboardingCoordinator.debugReset()
                }
                Button("Show Welcome Now") {
                    guard OSSEditionAssembly.onboardingConfiguration.welcomeEnabled else { return }
                    EditionAssemblyProvider.onboardingCoordinator.debugRequestShowWelcome()
                    NSApp.activate(ignoringOtherApps: true)
                    if let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        mainWindow.makeKeyAndOrderFront(nil)
                    } else {
                        showMainWindow(.overview)
                    }
                }
                Button("Log Onboarding State") {
                    EditionAssemblyProvider.onboardingCoordinator.debugLogState(edition: "OSS")
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
                    OSSEditionAssembly.guidanceCoordinator.debugResetState()
                }
                Button("Prepare OSS Invitation Eligibility") {
                    OSSEditionAssembly.guidanceCoordinator.debugPrepareInvitationEligibility()
                }
                Button("Trigger Diagnostics Invitation") {
                    OSSEditionAssembly.guidanceCoordinator.debugScheduleInvitation(for: .diagnosticsCompleted)
                    GuidanceDebugOverrides.requestDiagnosticsStaging()
                    showMainWindow(.networkDiagnostics)
                }
                Button("Trigger Export Invitation Banner") {
                    OSSEditionAssembly.guidanceCoordinator.debugScheduleInvitation(for: .exportSucceeded)
                    OSSEditionAssembly.guidanceCoordinator.debugPublishExportFeedback()
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
                    OSSEditionAssembly.guidanceCoordinator.debugLogState(edition: "OSS")
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


enum EditionAssemblyProvider {
    @MainActor static let configuration = OSSEditionAssembly.configuration
    @MainActor static let onboardingCoordinator = OnboardingCoordinator(
        store: UserDefaultsOnboardingStateStore(),
        existingInstallationDetector: configuration.shellHooks.makeOnboardingExistingInstallationDetector(),
        welcomeEnabled: configuration.onboardingConfiguration.welcomeEnabled
    )
}

enum EditionAppShell {
    static var isControlledDemoSession: Bool { false }
    static var opensMainWindowAtLaunch: Bool { false }

    @MainActor
    static func startProductDiagnostics() -> String? {
        CrashReporter.register()
        MetricKitManager.start()
        return CrashReporter.consumeCrashLog()
    }

    @ViewBuilder @MainActor
    static func roamingPageContent<Content: View>(@ViewBuilder content: () -> Content) -> some View { content() }

    @ViewBuilder @MainActor
    static func apRadarPageContent<Content: View>(@ViewBuilder content: () -> Content) -> some View { content() }

    @ViewBuilder @MainActor
    static func channelsPageContent<Content: View>(@ViewBuilder content: () -> Content) -> some View { content() }

#if DEBUG
    @MainActor
    @ViewBuilder
    static func debugTimelinePage() -> some View {
        EmptyView()
    }

    @MainActor
    static func debugCommands(showMainWindow: @escaping (SidebarPage) -> Void) -> some Commands {
        OSSEditionAssembly.debugCommands(showMainWindow: showMainWindow)
    }
#endif

    @SceneBuilder @MainActor
    static func menuBarScene(openMainWindow: @escaping (SidebarPage?) -> Void, terminate: @escaping () -> Void) -> some Scene {}
}
