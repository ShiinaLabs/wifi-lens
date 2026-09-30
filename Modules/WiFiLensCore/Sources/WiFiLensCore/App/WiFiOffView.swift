import SwiftUI

public struct WiFiOffView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "wifi.off.title", comment: "Title when Wi-Fi is turned off"))
                .font(.title3)
                .multilineTextAlignment(.center)
            Text(String(localized: "wifi.off.description", comment: "Description prompting user to turn on Wi-Fi"))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityIdentifier("wifi-off-view")
    }
}
