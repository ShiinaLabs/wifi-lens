import AppKit
import SwiftUI

public enum WiFiLensEditionIdentity: String, Sendable {
    case openSource
    case pro
}

public enum WiFiLensEditionCapability: String, Hashable, Sendable {
    case timeline
    case analysis
    case wifiCalling
    case ble
    case markdownExport
    case menuBar
}

public enum ExportSuccessPresentation: Equatable, Sendable {
    case banner
    case preserveExisting
}

public enum MarkdownExportCommandContribution {
    case available(@MainActor (ScannerViewModel) -> Void)
    case lockedPreview
}

public struct EditionCompositionContext {
    public let mainWindowID: UUID
    public let mainWindowState: AnyObject
    public let scannerViewModel: ScannerViewModel
    public let macVendorDatabaseManager: MACVendorDatabaseManager
    public let isMACVendorDatabaseAvailable: Bool
    public let selectedPage: Binding<SidebarPage>
    public let secondaryToolbarSelections: Binding<SecondaryToolbarSelections>
    public let bleEnabled: Binding<Bool>
    public let openMainWindow: (SidebarPage?) -> Void

    public init(
        mainWindowID: UUID,
        mainWindowState: AnyObject,
        scannerViewModel: ScannerViewModel,
        macVendorDatabaseManager: MACVendorDatabaseManager,
        isMACVendorDatabaseAvailable: Bool,
        selectedPage: Binding<SidebarPage>,
        secondaryToolbarSelections: Binding<SecondaryToolbarSelections>,
        bleEnabled: Binding<Bool>,
        openMainWindow: @escaping (SidebarPage?) -> Void
    ) {
        self.mainWindowID = mainWindowID
        self.mainWindowState = mainWindowState
        self.scannerViewModel = scannerViewModel
        self.macVendorDatabaseManager = macVendorDatabaseManager
        self.isMACVendorDatabaseAvailable = isMACVendorDatabaseAvailable
        self.selectedPage = selectedPage
        self.secondaryToolbarSelections = secondaryToolbarSelections
        self.bleEnabled = bleEnabled
        self.openMainWindow = openMainWindow
    }
}

/// Product assembly supplied by an app shell. AppKit scenes and capture
/// instrumentation remain owned by the outer shell; this value describes the
/// product behavior and feature contributions the shared app host needs.
@MainActor
public struct WiFiLensEditionShellHooks {
    public let markdownExportCommandContribution: MarkdownExportCommandContribution
    public let makeMainWindowState: @MainActor () -> AnyObject
    public let makeObservationRuntime: @MainActor (WiFiObservationStore) -> WiFiObservationRuntime
    public let makeRoamingViewModel: @MainActor (ScannerViewModel) -> RoamingTestViewModel
    public let makeOnboardingExistingInstallationDetector: () -> any ExistingInstallationDetecting
    public let configureMainWindow: @MainActor (NSWindow) -> Void
    public let mainWindowDidFinishStartup: @MainActor (UUID) -> Void
    public let registerMainWindowState: @MainActor (AnyObject, UUID) -> Bool
    public let unregisterMainWindowState: @MainActor (AnyObject, UUID) -> Void
    public let startLifecycle: @MainActor (WiFiObservationRuntime) -> Void
    public let prepareForTermination: @MainActor () async -> Void
    public let mainWindowDidBecomeActive: @MainActor (UUID) -> Void
    public let mainWindowWillClose: @MainActor (UUID) -> Void
    public let detailContribution: @MainActor (EditionCompositionContext) -> AnyView
    public let settingsContribution: @MainActor () -> AnyView

    public init(
        markdownExportCommandContribution: MarkdownExportCommandContribution,
        makeMainWindowState: @escaping @MainActor () -> AnyObject,
        makeObservationRuntime: @escaping @MainActor (WiFiObservationStore) -> WiFiObservationRuntime,
        makeRoamingViewModel: @escaping @MainActor (ScannerViewModel) -> RoamingTestViewModel,
        makeOnboardingExistingInstallationDetector: @escaping () -> any ExistingInstallationDetecting,
        configureMainWindow: @escaping @MainActor (NSWindow) -> Void,
        mainWindowDidFinishStartup: @escaping @MainActor (UUID) -> Void,
        registerMainWindowState: @escaping @MainActor (AnyObject, UUID) -> Bool,
        unregisterMainWindowState: @escaping @MainActor (AnyObject, UUID) -> Void,
        startLifecycle: @escaping @MainActor (WiFiObservationRuntime) -> Void,
        prepareForTermination: @escaping @MainActor () async -> Void,
        mainWindowDidBecomeActive: @escaping @MainActor (UUID) -> Void,
        mainWindowWillClose: @escaping @MainActor (UUID) -> Void,
        detailContribution: @escaping @MainActor (EditionCompositionContext) -> AnyView,
        settingsContribution: @escaping @MainActor () -> AnyView
    ) {
        self.markdownExportCommandContribution = markdownExportCommandContribution
        self.makeMainWindowState = makeMainWindowState
        self.makeObservationRuntime = makeObservationRuntime
        self.makeRoamingViewModel = makeRoamingViewModel
        self.makeOnboardingExistingInstallationDetector = makeOnboardingExistingInstallationDetector
        self.configureMainWindow = configureMainWindow
        self.mainWindowDidFinishStartup = mainWindowDidFinishStartup
        self.registerMainWindowState = registerMainWindowState
        self.unregisterMainWindowState = unregisterMainWindowState
        self.startLifecycle = startLifecycle
        self.prepareForTermination = prepareForTermination
        self.mainWindowDidBecomeActive = mainWindowDidBecomeActive
        self.mainWindowWillClose = mainWindowWillClose
        self.detailContribution = detailContribution
        self.settingsContribution = settingsContribution
    }
}

@MainActor
public struct WiFiLensEditionConfiguration {
    public let identity: WiFiLensEditionIdentity
    public let capabilities: Set<WiFiLensEditionCapability>
    public let shouldStartObservationRuntime: Bool
    public let requiresLiveWiFiAuthorization: Bool
    public let isTimelineLockedPreview: Bool
    public let initialMainWindowRoute: SidebarPage
    public let timelineToolbarDescriptor: SecondaryToolbarDescriptor?
    public let spectrumToolbarDescriptor: SecondaryToolbarDescriptor
    public let exportSuccessPresentation: ExportSuccessPresentation
    public let onboardingConfiguration: OnboardingConfiguration
    public let guidanceConfiguration: GuidanceConfiguration
    public let guidanceCoordinator: GuidanceCoordinator
    public let shellHooks: WiFiLensEditionShellHooks
    public var markdownExportCommandContribution: MarkdownExportCommandContribution {
        shellHooks.markdownExportCommandContribution
    }
    public var detailContribution: @MainActor (EditionCompositionContext) -> AnyView {
        shellHooks.detailContribution
    }
    public var settingsContribution: @MainActor () -> AnyView {
        shellHooks.settingsContribution
    }
    public let menuBarWindowManagementEnabled: Bool

    func sidebarBadgeStyle(for page: SidebarPage) -> SidebarBadge.Style? {
        switch page {
        case .apRadar:
            .preview
        case .wifiCallingTest:
            capabilities.contains(.wifiCalling) ? .preview : .pro
        default:
            nil
        }
    }

    var analysisSidebarBadgeStyle: SidebarBadge.Style {
        capabilities.contains(.analysis) ? .preview : .pro
    }

    public init(
        identity: WiFiLensEditionIdentity,
        capabilities: Set<WiFiLensEditionCapability>,
        shouldStartObservationRuntime: Bool,
        requiresLiveWiFiAuthorization: Bool,
        isTimelineLockedPreview: Bool,
        initialMainWindowRoute: SidebarPage,
        timelineToolbarDescriptor: SecondaryToolbarDescriptor?,
        spectrumToolbarDescriptor: SecondaryToolbarDescriptor,
        exportSuccessPresentation: ExportSuccessPresentation,
        onboardingConfiguration: OnboardingConfiguration,
        guidanceConfiguration: GuidanceConfiguration,
        guidanceCoordinator: GuidanceCoordinator,
        shellHooks: WiFiLensEditionShellHooks,
        menuBarWindowManagementEnabled: Bool
    ) {
        self.identity = identity
        self.capabilities = capabilities
        self.shouldStartObservationRuntime = shouldStartObservationRuntime
        self.requiresLiveWiFiAuthorization = requiresLiveWiFiAuthorization
        self.isTimelineLockedPreview = isTimelineLockedPreview
        self.initialMainWindowRoute = initialMainWindowRoute
        self.timelineToolbarDescriptor = timelineToolbarDescriptor
        self.spectrumToolbarDescriptor = spectrumToolbarDescriptor
        self.exportSuccessPresentation = exportSuccessPresentation
        self.onboardingConfiguration = onboardingConfiguration
        self.guidanceConfiguration = guidanceConfiguration
        self.guidanceCoordinator = guidanceCoordinator
        self.shellHooks = shellHooks
        self.menuBarWindowManagementEnabled = menuBarWindowManagementEnabled
    }
}
