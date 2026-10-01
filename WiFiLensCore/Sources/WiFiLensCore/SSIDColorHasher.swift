import SwiftUI
import CryptoKit

/// Deterministic color assignment for SSIDs using SHA-1 hash,
/// matching the JavaScript `getColorForSSID()` behavior.
public struct SSIDColorHasher {
    private let palette: [Color]

    public init() {
        self.palette = Constants.palette
    }

    init(palette: [Color]) {
        self.palette = palette
    }

    public func color(for ssid: String?, bssid: String) -> Color {
        guard let ssid, !ssid.isEmpty, ssid.lowercased() != "n/a" else {
            return Constants.graySSIDColor
        }
        let data = Data(bssid.utf8)
        let hash = Insecure.SHA1.hash(data: data)
        let firstElement = hash.withUnsafeBytes { $0[0] }
        let index = Int(firstElement) % palette.count
        return palette[index]
    }
}
