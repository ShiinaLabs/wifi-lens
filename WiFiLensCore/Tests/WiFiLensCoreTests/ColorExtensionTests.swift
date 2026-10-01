import Testing
import SwiftUI
@testable import WiFiLensCore

struct ColorExtensionTests {

    @Test func hexWithoutHash() {
        let color = Color(hex: "3366CC")
        #expect(!color.isClear)
    }

    @Test func hexWithHash() {
        let color = Color(hex: "#3366CC")
        #expect(!color.isClear)
    }

    @Test func knownColor() {
        // #FF9900 → orange
        let color = Color(hex: "FF9900")
        #expect(!color.isClear)
    }

    @Test func black() {
        let color = Color(hex: "000000")
        #expect(!color.isClear)
    }

    @Test func white() {
        let color = Color(hex: "FFFFFF")
        #expect(!color.isClear)
    }

    @Test func red() {
        let color = Color(hex: "FF0000")
        #expect(!color.isClear)
    }

    @Test func paletteColorsAllProduceNonClear() {
        for c in Constants.palette {
            #expect(!c.isClear)
        }
    }
}

extension Color {
    fileprivate var isClear: Bool {
        guard let components = self.cgColor?.components else { return true }
        return components.allSatisfy { $0 == 0 }
    }
}
