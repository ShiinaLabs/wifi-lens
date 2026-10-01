import SwiftUI

public enum Constants {
    static let scanInterval: Duration = .seconds(3)
    static let uiUpdateInterval: Duration = .milliseconds(300)

    /// Visually distinct palette — each color is clearly separable at a glance.
    static let palette: [Color] = [
        Color(hex: "#3366CC"),  // blue
        Color(hex: "#DC3912"),  // red
        Color(hex: "#FF9900"),  // orange
        Color(hex: "#109618"),  // green
        Color(hex: "#990099"),  // purple
        Color(hex: "#0099C6"),  // cyan
        Color(hex: "#DD4477"),  // pink
        Color(hex: "#66AA00"),  // lime
        Color(hex: "#B82E2E"),  // brick
        Color(hex: "#316395"),  // steel
        Color(hex: "#994499"),  // mauve
        Color(hex: "#22AA99"),  // teal
        Color(hex: "#AAAA11"),  // olive
        Color(hex: "#6633CC"),  // indigo
        Color(hex: "#E67300"),  // amber
        Color(hex: "#329262"),  // forest
    ]

    static let graySSIDColor: Color = Color(hex: "#888888")
    static let filteredOutOpacity: Double = 0.15
    static let minZoomRange: Int = 2
    public static let rssiNoiseFloor: Int = -100
}
