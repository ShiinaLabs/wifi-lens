import CoreWLAN

public struct WiFiChannel: Sendable {
    public let band: ChannelBand
    public let channelNumber: Int
    public let channelWidthMHz: Int
    public let spanDirection: SpanDirection?

    public init(from cwChannel: CWChannel) {
        band = ChannelBand(rawValue: cwChannel.channelBand.rawValue) ?? .band24GHz
        channelNumber = cwChannel.channelNumber
        channelWidthMHz = cwChannel.widthMHz
        spanDirection = cwChannel.spanDirection
    }

    public init(band: ChannelBand, channelNumber: Int, channelWidthMHz: Int = 20, spanDirection: SpanDirection? = nil) {
        self.band = band
        self.channelNumber = channelNumber
        self.channelWidthMHz = channelWidthMHz
        self.spanDirection = spanDirection
    }
}
