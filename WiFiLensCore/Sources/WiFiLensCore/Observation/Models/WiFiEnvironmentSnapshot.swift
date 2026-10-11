import Foundation

public struct WiFiEnvironmentSnapshot: Equatable, Sendable {
    public init(timestamp: Date, interfaceName: String? = nil, networks: [WiFiNetworkObservation] = [], scanDurationMs: Double? = nil, error: WiFiObservationError? = nil, sourceCycleID: UUID? = nil) {
        self.timestamp = timestamp; self.interfaceName = interfaceName; self.networks = networks; self.scanDurationMs = scanDurationMs; self.error = error; self.sourceCycleID = sourceCycleID
    }
    public var timestamp: Date
    public var interfaceName: String?
    public var networks: [WiFiNetworkObservation]
    public var scanDurationMs: Double?
    public var error: WiFiObservationError?
    /// Identifies the complete interface snapshot paired with this scan result.
    /// A failed scan still has a cycle identity, but its network array is not valid data.
    public var sourceCycleID: UUID?
}
