import Foundation

struct RoamingSessionRecord: Codable {
    let version: Int
    let savedAt: Date
    let ssid: String
    let bssid: String?
    let phyMode: String?
    let channel: Int
    let duration: TimeInterval
    let segments: [RoamingSegment]
    let transitions: [APTransitionEvent]

    init(
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

    static let currentVersion = 1
}
