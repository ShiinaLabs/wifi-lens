import WiFiLensCoreRust

/// Swift-facing API for the portable Rust channel span calculation.
public enum ChannelSpanCalculator {

    /// Convert MHz width into a half-span measured in channel-number steps.
    public static func channelHalfSpan(for widthMHz: Int) -> Int {
        Int(wifi_lens_channel_half_span(Int64(widthMHz)))
    }

    /// Calculate the channel block for a primary channel, width, and band.
    public static func channelBlock(
        primaryChannel: Int,
        widthMHz: Int,
        band: ChannelBand
    ) -> (left: Int, right: Int) {
        channelBlock(
            primaryChannel: primaryChannel,
            widthMHz: widthMHz,
            band: band,
            spanDirection: nil
        )
    }

    static func channelBlock(
        primaryChannel: Int,
        widthMHz: Int,
        band: ChannelBand,
        spanDirection: SpanDirection?
    ) -> (left: Int, right: Int) {
        let directionCode: Int32
        switch spanDirection {
        case .upper: directionCode = 1
        case .lower: directionCode = 2
        case nil: directionCode = 0
        }

        let result = wifi_lens_channel_block(
            Int64(primaryChannel),
            Int64(widthMHz),
            Int32(band.rawValue),
            directionCode
        )
        if result.status == 0 {
            return (Int(result.left), Int(result.right))
        }

        if result.status != 3 {
            assertionFailure("Rust channel span returned status \(result.status)")
        }

        // The legacy Swift API is nonthrowing. Keep narrow 6 GHz input
        // deterministic when Rust reports its explicit invalid-width error.
        let half = channelHalfSpan(for: widthMHz)
        return (primaryChannel - half, primaryChannel + half)
    }
}
