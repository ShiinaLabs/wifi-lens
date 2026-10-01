import Foundation

/// One short first-run highlight shown in the welcome sheet.
public struct OnboardingHighlight: Equatable, Sendable {
    public var icon: String
    public var titleKey: String

    public init(icon: String, titleKey: String) {
        self.icon = icon
        self.titleKey = titleKey
    }
}

/// Edition-provided onboarding tuning read by the shared welcome flow.
public struct OnboardingConfiguration: Equatable, Sendable {
    public var welcomeEnabled: Bool
    public var showsProLink: Bool
    public var proURL: URL?
    public var startRoute: SidebarPage?
    public var startToolbarSelection: SecondaryToolbarItemID?
    public var primaryActionKey: String
    public var highlights: [OnboardingHighlight]

    public init(
        welcomeEnabled: Bool,
        showsProLink: Bool,
        proURL: URL?,
        startRoute: SidebarPage?,
        startToolbarSelection: SecondaryToolbarItemID?,
        primaryActionKey: String,
        highlights: [OnboardingHighlight]
    ) {
        self.welcomeEnabled = welcomeEnabled
        self.showsProLink = showsProLink
        self.proURL = proURL
        self.startRoute = startRoute
        self.startToolbarSelection = startToolbarSelection
        self.primaryActionKey = primaryActionKey
        self.highlights = highlights
    }

    public static let disabled = OnboardingConfiguration(
        welcomeEnabled: false,
        showsProLink: false,
        proURL: nil,
        startRoute: nil,
        startToolbarSelection: nil,
        primaryActionKey: "onboarding.welcome.start",
        highlights: []
    )
}

public protocol ExistingInstallationDetecting {
    func hasExistingInstallationEvidence() -> Bool
}

public struct NoExistingInstallationDetector: ExistingInstallationDetecting {
    public init() {}

    public func hasExistingInstallationEvidence() -> Bool { false }
}
