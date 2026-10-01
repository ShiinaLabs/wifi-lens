import Foundation

public struct GatewayLatencyResult: Equatable, Sendable {
    public init(timestamp: Date, routerIP: String? = nil, latencyMs: Double? = nil) {
        self.init(timestamp: timestamp, routerIP: routerIP, latencyMs: latencyMs, packetLoss: nil, error: nil)
    }

    init(timestamp: Date, routerIP: String? = nil, latencyMs: Double? = nil, packetLoss: Double? = nil, error: WiFiObservationError?) {
        self.timestamp = timestamp; self.routerIP = routerIP; self.latencyMs = latencyMs; self.packetLoss = packetLoss; self.error = error
    }
    public var timestamp: Date
    public var routerIP: String?
    public var latencyMs: Double?
    var packetLoss: Double?
    var error: WiFiObservationError?
}
