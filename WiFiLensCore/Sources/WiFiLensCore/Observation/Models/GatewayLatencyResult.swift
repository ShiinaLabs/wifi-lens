import Foundation

public enum GatewayProbeOutcome: Equatable, Sendable {
    case replied(milliseconds: Double)
    case noReply
    case notTested
    case executionFailed
    case cancelled
    case localTimeout
}

public struct GatewayLatencyResult: Equatable, Sendable {
    public init(
        timestamp: Date,
        routerIP: String? = nil,
        latencyMs: Double? = nil,
        probeOutcome: GatewayProbeOutcome? = nil,
        attemptID: UUID? = nil,
        cycleID: UUID? = nil,
        interfaceName: String? = nil,
        interfaceBound: Bool = false
    ) {
        self.init(
            timestamp: timestamp,
            routerIP: routerIP,
            latencyMs: latencyMs,
            packetLoss: nil,
            error: nil,
            probeOutcome: probeOutcome,
            attemptID: attemptID,
            cycleID: cycleID,
            interfaceName: interfaceName,
            interfaceBound: interfaceBound
        )
    }

    init(
        timestamp: Date,
        routerIP: String? = nil,
        latencyMs: Double? = nil,
        packetLoss: Double? = nil,
        error: WiFiObservationError?,
        probeOutcome: GatewayProbeOutcome? = nil,
        attemptID: UUID? = nil,
        cycleID: UUID? = nil,
        interfaceName: String? = nil,
        interfaceBound: Bool = false
    ) {
        self.timestamp = timestamp
        self.routerIP = routerIP
        self.latencyMs = latencyMs
        self.packetLoss = packetLoss
        self.error = error
        self.probeOutcome = probeOutcome
        self.attemptID = attemptID
        self.cycleID = cycleID
        self.interfaceName = interfaceName
        self.interfaceBound = interfaceBound
    }

    public var timestamp: Date
    public var routerIP: String?
    public var latencyMs: Double?
    public var probeOutcome: GatewayProbeOutcome?
    public var attemptID: UUID?
    public var cycleID: UUID?
    public var interfaceName: String?
    public var interfaceBound: Bool
    var packetLoss: Double?
    var error: WiFiObservationError?
}
