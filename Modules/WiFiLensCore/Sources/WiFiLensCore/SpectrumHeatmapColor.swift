import SwiftUI
import Foundation

/// Fixed thermal-imaging colormap for the heatmap field.
/// The ramp stays in purple → magenta → red → orange → yellow; it avoids a
/// broad white region so the hottest core remains visually localized.
public enum SpectrumHeatmapColor {
    private static let stops: [(t: Double, r: Double, g: Double, b: Double)] = [
        (0.00, 0.005, 0.008, 0.020),
        (0.16, 0.035, 0.005, 0.120),
        (0.34, 0.220, 0.005, 0.390),
        (0.52, 0.650, 0.015, 0.230),
        (0.70, 0.960, 0.080, 0.025),
        (0.86, 1.000, 0.430, 0.015),
        (1.00, 1.000, 0.960, 0.120)
    ]

    public static func color(forIntensity intensity: Float) -> Color {
        color(forIntensity: Double(intensity))
    }

    public static func color(forIntensity intensity: Double) -> Color {
        let rgb = components(forIntensity: intensity)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    public static func components(forIntensity intensity: Double) -> SpectrumHeatmapRGB {
        let value = min(1, max(0, intensity))
        var lower = stops[0]
        var upper = stops[stops.count - 1]
        for index in 0..<(stops.count - 1) {
            if value >= stops[index].t && value <= stops[index + 1].t {
                lower = stops[index]
                upper = stops[index + 1]
                break
            }
        }
        let fraction = (value - lower.t) / max(upper.t - lower.t, .ulpOfOne)
        return SpectrumHeatmapRGB(
            red: lower.r + (upper.r - lower.r) * fraction,
            green: lower.g + (upper.g - lower.g) * fraction,
            blue: lower.b + (upper.b - lower.b) * fraction
        )
    }
}
