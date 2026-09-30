import SwiftUI
import WiFiLensCore

extension SidebarPage {
    var badgeStyle: SidebarBadge.Style? {
        switch self {
        case .apRadar:
            .preview
        case .wifiCallingTest:
            Self.wifiCallingBadgeStyle(for: .current)
        default:
            nil
        }
    }

    static func wifiCallingBadgeStyle(for config: BuildConfig) -> SidebarBadge.Style? {
        switch config {
        case .oss: .pro
        case .pro: .preview
        }
    }

    static func timelineBadgeStyle(for config: BuildConfig) -> SidebarBadge.Style {
        analysisBadgeStyle(for: config)
    }

    static func analysisBadgeStyle(for config: BuildConfig) -> SidebarBadge.Style {
        switch config {
        case .oss: .pro
        case .pro: .preview
        }
    }
}

enum SidebarSection {
    case overview
    case tools
    case analysis
    case debug
    case settings

    var localizationKey: String {
        switch self {
        case .overview:
            "sidebar.section.overview"
        case .tools:
            "sidebar.section.tools"
        case .analysis:
            "sidebar.section.analysis"
        case .debug:
            "sidebar.section.debug"
        case .settings:
            "sidebar.section.settings"
        }
    }

    var title: String {
        String(localized: String.LocalizationValue(localizationKey), comment: "Sidebar section title")
    }

    /// Edition badge shown on the group title. The Analysis group carries one
    /// badge for all of its routes instead of repeating it on every row.
    var badgeStyle: SidebarBadge.Style? {
        switch self {
        case .analysis:
            SidebarPage.analysisBadgeStyle(for: .current)
        default:
            nil
        }
    }
}

private struct BluetoothIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        // Main vertical spine: M128 36V220
        path.move(to: CGPoint(x: w * 0.5, y: h * 36.0 / 256.0))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 220.0 / 256.0))

        // Upper right diamond: M128 128L190 74L128 36
        path.move(to: CGPoint(x: w * 0.5, y: h * 128.0 / 256.0))
        path.addLine(to: CGPoint(x: w * 190.0 / 256.0, y: h * 74.0 / 256.0))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 36.0 / 256.0))

        // Lower right diamond: M128 128L190 182L128 220
        path.move(to: CGPoint(x: w * 0.5, y: h * 128.0 / 256.0))
        path.addLine(to: CGPoint(x: w * 190.0 / 256.0, y: h * 182.0 / 256.0))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 220.0 / 256.0))

        // Left crossing arms: M66 74L128 128L66 182
        path.move(to: CGPoint(x: w * 66.0 / 256.0, y: h * 74.0 / 256.0))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 128.0 / 256.0))
        path.addLine(to: CGPoint(x: w * 66.0 / 256.0, y: h * 182.0 / 256.0))

        return path
    }
}

struct SidebarView: View {
    @Binding var selectedPage: SidebarPage
    var locationManager: LocationPermissionManager
    var isWiFiAvailable: Bool
    var bleEnabled: Bool

    var body: some View {
        List(selection: $selectedPage) {
            Section {
                Label(SidebarPage.overview.label, systemImage: SidebarPage.overview.icon)
                    .tag(SidebarPage.overview)
                    .accessibilityIdentifier("sidebar-overview")
            }
            Section {
                sidebarGroupTitle(.tools)
                ForEach([SidebarPage.spectrum, .channels, .interfaces, .networkDiagnostics, .wifiCallingTest, .roaming, .bleScanner, .apRadar], id: \.self) { page in
                    if page == .bleScanner {
                        Label(title: { Text(page.label) }, icon: {
                            BluetoothIconShape()
                                .stroke(.foreground, style: .init(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                        })
                            .tag(page)
                            .disabled(!UITestMode.isActive && page.requiresWiFi && !isWiFiAvailable)
                            .opacity(!UITestMode.isActive && page.requiresWiFi && !isWiFiAvailable ? 0.4 : 1.0)
                            .accessibilityHint(!UITestMode.isActive && page.requiresWiFi && !isWiFiAvailable
                                ? String(localized: "sidebar.hint.requires_wifi", comment: "Accessibility hint when sidebar item is disabled due to no Wi‑Fi")
                                : "")
                            .accessibilityIdentifier("sidebar-bleScanner")
                    } else {
                        sidebarRow(for: page)
                            .tag(page)
                            .disabled(!UITestMode.isActive && page.requiresWiFi && !isWiFiAvailable)
                            .opacity(!UITestMode.isActive && page.requiresWiFi && !isWiFiAvailable ? 0.4 : 1.0)
                            .accessibilityHint(!UITestMode.isActive && page.requiresWiFi && !isWiFiAvailable
                                ? String(localized: "sidebar.hint.requires_wifi", comment: "Accessibility hint when sidebar item is disabled due to no Wi‑Fi")
                                : "")
                            .accessibilityIdentifier("sidebar-\(page.rawValue)")
                    }
                }
            }
            Section {
                sidebarGroupTitle(.analysis)
                ForEach(SidebarPage.analysisPages, id: \.self) { page in
                    sidebarRow(for: page)
                        .tag(page)
                        .accessibilityIdentifier("sidebar-\(page.rawValue)")
                }
            }
#if DEBUG
            Section {
                sidebarGroupTitle(.debug)
                Label(SidebarPage.spectrumDebugChart.label, systemImage: SidebarPage.spectrumDebugChart.icon)
                    .tag(SidebarPage.spectrumDebugChart)
                    .accessibilityIdentifier("sidebar-spectrumDebugChart")

                Label(SidebarPage.debugChart.label, systemImage: SidebarPage.debugChart.icon)
                    .tag(SidebarPage.debugChart)
                    .accessibilityIdentifier("sidebar-debugChart")

#if DEBUG && PRO
                Label(SidebarPage.debugTimeline.label, systemImage: SidebarPage.debugTimeline.icon)
                    .tag(SidebarPage.debugTimeline)
                    .accessibilityIdentifier("sidebar-debugTimeline")
#endif
            }
#endif
            Section {
                sidebarGroupTitle(.settings)
                Label(SidebarPage.settings.label, systemImage: SidebarPage.settings.icon)
                    .tag(SidebarPage.settings)
                    .accessibilityIdentifier("sidebar-settings")
            }
        }
        .id(selectedPage)
        .background(.ultraThinMaterial)
        .listStyle(.sidebar)
        .safeAreaPadding(.top, 12)
        .frame(minWidth: 160, idealWidth: 180)
    }

    @ViewBuilder
    private func sidebarRow(for page: SidebarPage) -> some View {
        sidebarLabel(for: page)
    }

    @ViewBuilder
    private func sidebarLabel(for page: SidebarPage) -> some View {
        if let badgeStyle = page.badgeStyle {
            ViewThatFits(in: .horizontal) {
                SidebarBadgeRowContent(
                    title: page.label,
                    icon: page.icon,
                    style: badgeStyle,
                    presentation: .full
                )
                SidebarBadgeRowContent(
                    title: page.label,
                    icon: page.icon,
                    style: badgeStyle,
                    presentation: .compact
                )
            }
        } else {
            Label(page.label, systemImage: page.icon)
        }
    }

    private func sidebarGroupTitle(_ section: SidebarSection) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)

            Spacer(minLength: 4)

            if let badgeStyle = section.badgeStyle {
                SidebarBadge(style: badgeStyle)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

struct SidebarBadgeRowContent: View {
    static let minimumGap: CGFloat = 8

    let title: String
    let icon: String
    let style: SidebarBadge.Style
    let presentation: SidebarBadge.Presentation

    var body: some View {
        HStack(spacing: 0) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .fixedSize(horizontal: presentation == .full, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: Self.minimumGap)
            SidebarBadge(style: style, presentation: presentation)
        }
    }
}
