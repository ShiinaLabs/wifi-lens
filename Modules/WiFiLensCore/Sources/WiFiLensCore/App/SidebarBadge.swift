import Foundation
import SwiftUI

/// Compact metadata displayed at the trailing edge of a sidebar destination.
struct SidebarBadge: View {
    public enum Presentation: Hashable, Sendable {
        case full
        case compact

        static let adaptiveOrder: [Self] = [.full, .compact]

        var showsText: Bool {
            self == .full
        }
    }

    struct Swatch: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        init(hex: Int) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        func contrastRatio(to other: Swatch) -> Double {
            let lighter = max(relativeLuminance, other.relativeLuminance)
            let darker = min(relativeLuminance, other.relativeLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }

        private var relativeLuminance: Double {
            0.2126 * Self.linearized(red)
                + 0.7152 * Self.linearized(green)
                + 0.0722 * Self.linearized(blue)
        }

        private static func linearized(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
    }

    struct ColorSet: Equatable {
        let foreground: Swatch
        let background: Swatch
        let border: Swatch
    }

    struct Palette: Equatable {
        let light: ColorSet
        let dark: ColorSet
    }

    enum Metrics {
        static let textSize: CGFloat = 10
        static let iconSize: CGFloat = 9
        static let horizontalPadding: CGFloat = 7
        static let verticalPadding: CGFloat = 3
        static let borderWidth: CGFloat = 1
    }

    enum Style: Equatable {
        case pro
        case preview
        case experimental

        var icon: String {
            switch self {
            case .pro: "crown.fill"
            case .preview: "sparkles"
            case .experimental: "flask"
            }
        }

        var localizationKey: String {
            switch self {
            case .pro: "common.badge.pro"
            case .preview: "common.badge.preview"
            case .experimental: "common.badge.experimental"
            }
        }

        var palette: Palette {
            switch self {
            case .pro:
                Palette(
                    light: ColorSet(
                        foreground: Swatch(hex: 0x6E4700),
                        background: Swatch(hex: 0xFFF1C7),
                        border: Swatch(hex: 0xC78A10)
                    ),
                    dark: ColorSet(
                        foreground: Swatch(hex: 0xFFE6A3),
                        background: Swatch(hex: 0x604918),
                        border: Swatch(hex: 0xA67C22)
                    )
                )
            case .preview:
                Palette(
                    light: ColorSet(
                        foreground: Swatch(hex: 0x4B2A99),
                        background: Swatch(hex: 0xE9E3FF),
                        border: Swatch(hex: 0x8066C6)
                    ),
                    dark: ColorSet(
                        foreground: Swatch(hex: 0xE2DEFF),
                        background: Swatch(hex: 0x403675),
                        border: Swatch(hex: 0x7063C8)
                    )
                )
            case .experimental:
                Palette(
                    light: ColorSet(
                        foreground: Swatch(hex: 0x005F56),
                        background: Swatch(hex: 0xE0F5F1),
                        border: Swatch(hex: 0x4FB3A6)
                    ),
                    dark: ColorSet(
                        foreground: Swatch(hex: 0xA7F0E6),
                        background: Swatch(hex: 0x1F4E49),
                        border: Swatch(hex: 0x53C6B7)
                    )
                )
            }
        }

        var text: String {
            String(
                localized: String.LocalizationValue(localizationKey),
                comment: "Sidebar metadata badge text"
            )
        }
    }

    let icon: String
    let text: String
    private let presentation: Presentation
    private let palette: Palette?
    private let tint: Color?

    @Environment(\.colorScheme) private var colorScheme

    public init(icon: String, text: String, tint: Color, presentation: Presentation = .full) {
        self.icon = icon
        self.text = text
        self.presentation = presentation
        palette = nil
        self.tint = tint
    }

    init(icon: String, text: String, palette: Palette, presentation: Presentation = .full) {
        self.icon = icon
        self.text = text
        self.presentation = presentation
        self.palette = palette
        tint = nil
    }

    public init(style: Style, presentation: Presentation = .full) {
        self.init(
            icon: style.icon,
            text: style.text,
            palette: style.palette,
            presentation: presentation
        )
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: Metrics.iconSize, weight: .semibold))
                .accessibilityHidden(true)

            if presentation.showsText {
                Text(text)
                    .font(.system(size: Metrics.textSize, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: badgeShape)
        .overlay {
            badgeShape
                .stroke(borderColor, lineWidth: Metrics.borderWidth)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .help(text)
        .allowsHitTesting(false)
    }

    private var badgeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
    }

    private var activeColorSet: ColorSet? {
        guard let palette else { return nil }
        return colorScheme == .dark ? palette.dark : palette.light
    }

    private var foregroundColor: Color {
        if let activeColorSet {
            return activeColorSet.foreground.color
        }
        return colorScheme == .dark ? .white : .black
    }

    private var backgroundColor: Color {
        if let activeColorSet {
            return activeColorSet.background.color
        }
        return tint?.opacity(colorScheme == .dark ? 0.48 : 0.18) ?? .clear
    }

    private var borderColor: Color {
        if let activeColorSet {
            return activeColorSet.border.color
        }
        return tint?.opacity(colorScheme == .dark ? 0.85 : 0.50) ?? .clear
    }
}

#Preview("Sidebar badges") {
    VStack(alignment: .leading, spacing: 8) {
        SidebarBadge(style: .pro)
        SidebarBadge(style: .preview)
        SidebarBadge(icon: "star.fill", text: "Custom", tint: .teal)
    }
    .padding()
    .preferredColorScheme(.dark)
}
