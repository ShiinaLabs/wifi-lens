import Foundation

public enum ExternalDestination {
    case privacyPolicy
    case appStore
    case appStoreWriteReview
    case appStoreCampaignWelcome
    case appStoreCampaignDiagnosis
    case appStoreCampaignExport
    case appStoreCampaignPreviewLock
    case appStoreCampaignPreviewTimeline
    case appStoreCampaignPreviewStatistics
    case appStoreCampaignPreviewInsights
    case appStoreCampaignSettingsAbout
    case website
    case github
    case githubIssues
    case githubWiFiCallingIssue
    case xAccount
    case developerProfile
    case chartLensRepository
    case mcpSwiftSDKRepository
    case sparkleRepository
    case discord
}

public enum ExternalLinks {
    public static func url(for destination: ExternalDestination) -> URL? {
        let value = switch destination {
        case .privacyPolicy:
            "https://wifi-lens.shiinalabs.com/privacy"
        case .appStore:
            "https://apps.apple.com/app/wifi-lens-pro/id6776590746"
        case .appStoreWriteReview:
            "https://apps.apple.com/app/wifi-lens-pro/id6776590746?action=write-review"
        // Each entry point uses a distinct App Store Connect campaign so
        // conversion attribution can identify the source surface. Regenerate
        // from App Analytics -> Campaigns when campaigns change; never
        // handcraft the pt parameter.
        case .appStoreCampaignWelcome:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_welcome&mt=8"
        case .appStoreCampaignDiagnosis:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_diagnosis&mt=8"
        case .appStoreCampaignExport:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_export&mt=8"
        case .appStoreCampaignPreviewLock:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_preview_lock&mt=8"
        case .appStoreCampaignPreviewTimeline:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_preview_timeline&mt=8"
        case .appStoreCampaignPreviewStatistics:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_preview_statistics&mt=8"
        case .appStoreCampaignPreviewInsights:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_preview_insights&mt=8"
        case .appStoreCampaignSettingsAbout:
            "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_settings_about&mt=8"
        case .website:
            "https://wifi-lens.shiinalabs.com"
        case .github:
            "https://github.com/SHIINASAMA/wifi-lens"
        case .githubIssues:
            "https://github.com/SHIINASAMA/wifi-lens/issues"
        case .githubWiFiCallingIssue:
            "https://github.com/SHIINASAMA/wifi-lens/issues/new?template=wifi-calling.yml&labels=wifi-calling"
        case .xAccount:
            "https://x.com/WiFiLens"
        case .developerProfile:
            "https://x.com/KAORU11843779"
        case .chartLensRepository:
            "https://github.com/SHIINASAMA/chart-lens"
        case .mcpSwiftSDKRepository:
            "https://github.com/modelcontextprotocol/swift-sdk"
        case .sparkleRepository:
            "https://github.com/sparkle-project/Sparkle"
        case .discord:
            "https://discord.gg/gH6sTCYaJ7"
        }

        return URL(string: value)
    }
}
