import Foundation

public protocol RoamingProbeProviding: Sendable {
    func fetchCurrentProbe() async -> WiFiCurrentStatus
}

public struct RoamingProbeProvider: RoamingProbeProviding {
    private let snapshotSource: any NetworkInterfaceSnapshotSourcing

    public init(snapshotSource: (any NetworkInterfaceSnapshotSourcing)? = nil) {
        self.snapshotSource = snapshotSource ?? SystemNetworkInterfaceSnapshotSource()
    }

    public func fetchCurrentProbe() async -> WiFiCurrentStatus {
        let cycleID = UUID()
        let snapshot = await snapshotSource.capture(cycleID: cycleID)
        return await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
    }
}
