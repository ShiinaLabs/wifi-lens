import Foundation

public struct WiFiEnvironmentSnapshot: Equatable, Sendable {
    public init(timestamp: Date, interfaceName: String? = nil, networks: [WiFiNetworkObservation] = [], scanDurationMs: Double? = nil, error: WiFiObservationError? = nil) {
        self.timestamp = timestamp; self.interfaceName = interfaceName; self.networks = networks; self.scanDurationMs = scanDurationMs; self.error = error
    }
    public var timestamp: Date
    public var interfaceName: String?
    public var networks: [WiFiNetworkObservation]
    public var scanDurationMs: Double?
    public var error: WiFiObservationError?
}
