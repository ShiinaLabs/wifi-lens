import CoreWLAN

struct WiFiChannel: Sendable {
    let band: ChannelBand
    let channelNumber: Int
    let channelWidthMHz: Int
    let spanDirection: SpanDirection?

    init(from cwChannel: CWChannel) {
        band = ChannelBand(rawValue: cwChannel.channelBand.rawValue) ?? .band24GHz
        channelNumber = cwChannel.channelNumber
        channelWidthMHz = cwChannel.widthMHz
        spanDirection = cwChannel.spanDirection
    }

    init(band: ChannelBand, channelNumber: Int, channelWidthMHz: Int = 20, spanDirection: SpanDirection? = nil) {
        self.band = band
        self.channelNumber = channelNumber
        self.channelWidthMHz = channelWidthMHz
        self.spanDirection = spanDirection
    }
}
