import Foundation

public struct RoamingSessionRecord: Codable {
    public let version: Int
    public let savedAt: Date
    public let ssid: String
    public let bssid: String?
    public let phyMode: String?
    public let channel: Int
    public let duration: TimeInterval
    public let segments: [RoamingSegment]
    public let transitions: [APTransitionEvent]

    public init(
        version: Int,
        savedAt: Date,
        ssid: String,
        bssid: String?,
        phyMode: String?,
        channel: Int,
        duration: TimeInterval,
        segments: [RoamingSegment],
        transitions: [APTransitionEvent]
    ) {
        self.version = version
        self.savedAt = savedAt
        self.ssid = ssid
        self.bssid = bssid
        self.phyMode = phyMode
        self.channel = channel
        self.duration = duration
        self.segments = segments
        self.transitions = transitions
    }

    public static let currentVersion = 1
}
