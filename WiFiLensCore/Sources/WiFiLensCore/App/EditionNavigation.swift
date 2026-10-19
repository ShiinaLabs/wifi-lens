import SwiftUI

/// Routes shared by the OSS and Pro application shells.
public enum SidebarPage: String, CaseIterable, Sendable {
    case overview
    case spectrum
    case channels
    case interfaces
    case networkDiagnostics
    case wifiCallingTest
    case roaming
    case bleScanner
    case apRadar
    case timeline
    case networkExperience
    case problemHistory
    case statistics
    case insights
    case settings

    public var requiresLocationAuthorization: Bool {
        switch self {
        case .overview, .settings, .bleScanner, .timeline, .networkExperience, .problemHistory, .statistics, .insights, .networkDiagnostics, .wifiCallingTest:
            false
        case .spectrum, .channels, .interfaces, .roaming, .apRadar:
            true
        }
    }

    public var requiresWiFi: Bool {
        switch self {
        case .overview, .settings, .bleScanner, .timeline, .networkExperience, .problemHistory, .statistics, .insights, .networkDiagnostics, .wifiCallingTest:
            false
        case .spectrum, .channels, .interfaces, .roaming, .apRadar:
            true
        }
    }

    public var label: String {
        switch self {
        case .overview: String(localized: "nav.overview", comment: "Overview sidebar navigation item")
        case .spectrum: String(localized: "nav.spectrum", comment: "Spectrum sidebar navigation item")
        case .channels: String(localized: "nav.channels", comment: "Channels sidebar navigation item")
        case .interfaces: String(localized: "nav.interfaces", comment: "Interfaces sidebar navigation item")
        case .networkDiagnostics: String(localized: "nav.network_diagnostics", comment: "Network Self-Check sidebar navigation item")
        case .wifiCallingTest: String(localized: "nav.wifi_calling_test", comment: "Wi-Fi Calling Test sidebar navigation item")
        case .roaming: String(localized: "nav.roaming_test", comment: "Roaming Test sidebar navigation item")
        case .bleScanner: String(localized: "nav.ble_scanner", comment: "BLE Scanner sidebar navigation item")
        case .apRadar: String(localized: "nav.apRadar", comment: "AP Radar sidebar navigation item")
        case .timeline: String(localized: "nav.timeline", comment: "Timeline sidebar navigation item")
        case .networkExperience: String(localized: "nav.network_experience", comment: "Network Experience sidebar navigation item")
        case .problemHistory: String(localized: "nav.problem_history", comment: "Problem history sidebar navigation item")
        case .statistics: String(localized: "nav.statistics", comment: "Statistics sidebar navigation item")
        case .insights: String(localized: "nav.insights", comment: "Insights sidebar navigation item")
        case .settings: String(localized: "common.action.settings", comment: "Settings button or menu item")
        }
    }

    public var icon: String {
        switch self {
        case .overview: "house"
        case .spectrum: "antenna.radiowaves.left.and.right"
        case .channels: "chart.bar.fill"
        case .interfaces: "cable.connector"
        case .networkDiagnostics: "stethoscope"
        case .wifiCallingTest: "wifi"
        case .roaming: "arrow.triangle.swap"
        case .bleScanner: "personalhotspot"
        case .apRadar: "dot.radiowaves.left.and.right"
        case .timeline: "clock.arrow.circlepath"
        case .networkExperience: "chart.xyaxis.line"
        case .problemHistory: "list.bullet.rectangle"
        case .statistics: "chart.bar.xaxis"
        case .insights: "lightbulb"
        case .settings: "gearshape"
        }
    }

    /// Default Analysis destinations. An edition that does not implement them
    /// presents each one as an invitation to the edition that does.
    static let analysisPages: [SidebarPage] = [.networkExperience, .problemHistory]
}

public enum SecondaryToolbarItemID: String, Hashable, Sendable {
    case channelsSimple = "channels-simple"
    case channelsTable = "channels-table"
    case interfacesSimple = "interfaces-simple"
    case interfacesDetails = "interfaces-details"
    case interfacesMonitor = "interfaces-monitor"
    case spectrumLive = "spectrum-live"
    case spectrumRecording = "spectrum-recording"
    case networkExperienceReliability = "network-experience-reliability"
    case networkExperienceBaseline = "network-experience-baseline"
    case timelineAll = "timeline-all"
    case timelineToday = "timeline-today"
    case timelineYesterday = "timeline-yesterday"
    case timelineThisWeek = "timeline-this-week"
    case timelineCustom = "timeline-custom"
}

struct SecondaryToolbarItem: Identifiable, Equatable, Sendable {
    public let id: SecondaryToolbarItemID
    public let title: String
    var isLocked: Bool

    public init(id: SecondaryToolbarItemID, title: String, isLocked: Bool = false) {
        self.id = id
        self.title = title
        self.isLocked = isLocked
    }
}

public struct SecondaryToolbarDescriptor: Equatable, Sendable {
    let items: [SecondaryToolbarItem]
    public let defaultSelection: SecondaryToolbarItemID

    init(items: [SecondaryToolbarItem], defaultSelection: SecondaryToolbarItemID) {
        self.items = items
        self.defaultSelection = defaultSelection
    }

    func selectionIndex(for id: SecondaryToolbarItemID) -> Int {
        items.firstIndex { $0.id == id } ?? items.firstIndex { $0.id == defaultSelection } ?? 0
    }

    public static func forPage(
        _ page: SidebarPage,
        spectrum: SecondaryToolbarDescriptor = .spectrum(recordingLocked: true),
        timeline: SecondaryToolbarDescriptor? = nil,
        networkExperience: SecondaryToolbarDescriptor? = nil
    ) -> Self? {
        switch page {
        case .channels:
            Self(
                items: [
                    SecondaryToolbarItem(id: .channelsSimple, title: String(localized: "channels.mode.simple", comment: "Simple view mode for channel quality")),
                    SecondaryToolbarItem(id: .channelsTable, title: String(localized: "channels.mode.professional", comment: "Professional view mode for channel quality")),
                ],
                defaultSelection: .channelsSimple
            )
        case .interfaces:
            Self(
                items: [
                    SecondaryToolbarItem(id: .interfacesSimple, title: String(localized: "channels.mode.simple", comment: "Simple view mode for interfaces")),
                    SecondaryToolbarItem(id: .interfacesDetails, title: String(localized: "common.label.details", comment: "Details view mode label")),
                    SecondaryToolbarItem(id: .interfacesMonitor, title: String(localized: "interfaces.mode.monitor", comment: "Throughput monitor view mode")),
                ],
                defaultSelection: .interfacesSimple
            )
        case .spectrum:
            spectrum
        case .networkExperience:
            networkExperience
        case .timeline:
            timeline
        default:
            nil
        }
    }

    /// Subview switcher for a page whose subview titles are owned by the
    /// edition that provides the page. The caller supplies already-localized
    /// titles so this shared type stays free of edition-specific content.
    public static func subviews(
        _ firstID: SecondaryToolbarItemID,
        firstTitle: String,
        _ secondID: SecondaryToolbarItemID,
        secondTitle: String
    ) -> Self {
        Self(
            items: [
                SecondaryToolbarItem(id: firstID, title: firstTitle),
                SecondaryToolbarItem(id: secondID, title: secondTitle),
            ],
            defaultSelection: firstID
        )
    }

    public static func spectrum(recordingLocked: Bool) -> Self {
        Self(
            items: [
                SecondaryToolbarItem(id: .spectrumLive, title: String(localized: "spectrum.mode.live", comment: "Live spectrum mode")),
                SecondaryToolbarItem(id: .spectrumRecording, title: String(localized: "spectrum.mode.recording_page", comment: "Recording page mode"), isLocked: recordingLocked),
            ],
            defaultSelection: .spectrumLive
        )
    }

    public static func timeline(defaultSelection: SecondaryToolbarItemID) -> Self {
        Self(
            items: [
                SecondaryToolbarItem(id: .timelineAll, title: String(localized: "timeline.filter.all", comment: "Timeline all-time range filter")),
                SecondaryToolbarItem(id: .timelineToday, title: String(localized: "timeline.filter.today", comment: "Timeline today range filter")),
                SecondaryToolbarItem(id: .timelineThisWeek, title: String(localized: "timeline.filter.this_week", comment: "Timeline this-week range filter")),
                SecondaryToolbarItem(id: .timelineCustom, title: String(localized: "timeline.filter.custom", comment: "Timeline custom range filter")),
            ],
            defaultSelection: defaultSelection
        )
    }
}

public struct SecondaryToolbarSelections: Equatable, Sendable {
    public var channels: SecondaryToolbarItemID
    public var interfaces: SecondaryToolbarItemID
    public var spectrum: SecondaryToolbarItemID
    public var networkExperience: SecondaryToolbarItemID
    public var timeline: SecondaryToolbarItemID

    public init(
        channels: SecondaryToolbarItemID = .channelsSimple,
        interfaces: SecondaryToolbarItemID = .interfacesSimple,
        spectrum: SecondaryToolbarItemID = .spectrumLive,
        networkExperience: SecondaryToolbarItemID = .networkExperienceReliability,
        timeline: SecondaryToolbarItemID = .timelineToday
    ) {
        self.channels = channels
        self.interfaces = interfaces
        self.spectrum = spectrum
        self.networkExperience = networkExperience
        self.timeline = timeline
    }

    public func selection(for page: SidebarPage) -> SecondaryToolbarItemID? {
        switch page {
        case .channels: channels
        case .interfaces: interfaces
        case .spectrum: spectrum
        case .networkExperience: networkExperience
        case .timeline: timeline
        default: nil
        }
    }

    public mutating func setSelection(_ selection: SecondaryToolbarItemID, for page: SidebarPage) {
        switch page {
        case .channels: channels = selection
        case .interfaces: interfaces = selection
        case .spectrum: spectrum = selection
        case .networkExperience: networkExperience = selection
        case .timeline: timeline = selection
        default: break
        }
    }
}
