import Testing
import SwiftUI
@testable import WiFiLensCore
struct SSIDColorHasherTests {

    let hasher = SSIDColorHasher()

    @Test func sameBSSIDReturnsSameColor() {
        let color1 = hasher.color(for: "MyNetwork", bssid: "aa:bb:cc:dd:ee:ff")
        let color2 = hasher.color(for: "MyNetwork", bssid: "aa:bb:cc:dd:ee:ff")
        #expect(color1 == color2)
    }

    @Test func sameSSIDDifferentBSSIDReturnsDifferentColors() {
        let color1 = hasher.color(for: "MyNetwork", bssid: "aa:bb:cc:dd:ee:01")
        let color2 = hasher.color(for: "MyNetwork", bssid: "aa:bb:cc:dd:ee:02")
        #expect(color1 != color2)
    }

    @Test func nilSSIDReturnsGray() {
        let color = hasher.color(for: nil, bssid: "aa:bb:cc:dd:ee:ff")
        #expect(color == Constants.graySSIDColor)
    }

    @Test func naSSIDReturnsGray() {
        let color = hasher.color(for: "n/a", bssid: "aa:bb:cc:dd:ee:ff")
        #expect(color == Constants.graySSIDColor)
    }

    @Test func naSSIDCaseInsensitiveReturnsGray() {
        let color = hasher.color(for: "N/A", bssid: "aa:bb:cc:dd:ee:ff")
        #expect(color == Constants.graySSIDColor)
    }

    @Test func emptySSIDReturnsGray() {
        let color = hasher.color(for: "", bssid: "aa:bb:cc:dd:ee:ff")
        #expect(color == Constants.graySSIDColor)
    }

    @Test func colorIsFromPalette() {
        let color = hasher.color(for: "test", bssid: "aa:bb:cc:dd:ee:ff")
        #expect(color != Constants.graySSIDColor)
    }
}
