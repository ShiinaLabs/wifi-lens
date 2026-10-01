import SwiftUI

/// Liquid glass background available on macOS 26+, falling back to Material on older systems.
public enum GlassStyle {
    case regular
    case clear
}

public extension View {
    /// Apply a glass background that uses `glassEffect` on macOS 26+ and falls back to
    /// the given Material on older systems.
    ///
    /// - Parameters:
    ///   - style: `.regular` (maps to `.regularMaterial`) or `.clear` (maps to `.thinMaterial`)
    ///   - shape: The shape to clip the background to
    @ViewBuilder
    func glassBackground(_ style: GlassStyle = .regular, in shape: some Shape = Rectangle()) -> some View {
        if #available(macOS 26, *) {
            let glass: Glass = switch style {
            case .regular: .regular
            case .clear:   .clear
            }
            glassEffect(glass, in: shape)
        } else {
            let material: Material = switch style {
            case .regular: .regularMaterial
            case .clear:   .thinMaterial
            }
            background(material, in: shape)
        }
    }
}
