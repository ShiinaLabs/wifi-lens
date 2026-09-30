import Foundation

public struct GatewayLatencyResult: Equatable, Sendable {
    public init(timestamp: Date, routerIP: String? = nil, latencyMs: Double? = nil, packetLoss: Double? = nil, error: WiFiObservationError? = nil) {
        self.timestamp = timestamp; self.routerIP = routerIP; self.latencyMs = latencyMs; self.packetLoss = packetLoss; self.error = error
    }
    public var timestamp: Date
    public var routerIP: String?
    public var latencyMs: Double?
    public var packetLoss: Double?
    public var error: WiFiObservationError?
}
