import CoreWLAN

extension CWChannel {
    var widthMHz: Int {
        switch channelWidth {
        case .width20MHz: 20
        case .width40MHz: 40
        case .width80MHz: 80
        case .width160MHz: 160
        case .widthUnknown: 20
        @unknown default: 20
        }
    }

    /// Parse span direction (HT40+/HT40-) from the channel description string.
    /// The format is: `...channelWidth={NNNMHz(optional(+/-)1)?}...`
    var spanDirection: SpanDirection? {
        // Regex matches the channelWidth segment and captures the optional direction indicator
        guard let match = try? /channelWidth=\{\d+MHz(?:\(([+-])1\))?\}/
            .firstMatch(in: description) else { return nil }
        let direction = match.output.1
        switch direction {
        case "+": return .upper
        case "-": return .lower
        default: return nil
        }
    }
}
