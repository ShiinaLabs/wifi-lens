import Foundation

extension ChannelBand {
    static func from(channelNumber: Int) -> ChannelBand? {
        switch channelNumber {
        case 1...16: .band24GHz
        case 17...170: .band5GHz
        case 171...233: .band6GHz
        default: nil
        }
    }
}

protocol WiFiCurrentConnectionProviding: Sendable {
    func fetchCurrentStatus(from snapshot: NetworkInterfaceSnapshot) async -> WiFiCurrentStatus
}

struct WiFiCurrentConnectionProvider: WiFiCurrentConnectionProviding {
    public init() {}
    func fetchCurrentStatus(from snapshot: NetworkInterfaceSnapshot) async -> WiFiCurrentStatus {
        guard let wifi = snapshot.interfaces.first(where: \.isWiFiInterface) else {
            let reason: WiFiLinkEvidenceReason = if !snapshot.interfaceEnumerationSucceeded {
                .interfaceEnumerationFailed
            } else if !snapshot.wifiInterfaceDiscoverySucceeded {
                .interfaceDiscoveryUnavailable
            } else {
                .interfaceUnavailable
            }
            return WiFiCurrentStatus(
                timestamp: snapshot.capturedAt,
                interfaceSnapshotCycleID: snapshot.cycleID,
                isConnected: false,
                isWiFiPowerOn: true,
                error: .noWiFiConnection,
                linkAssessment: WiFiLinkAssessment(state: .unknown, reason: reason)
            )
        }
        return Self.makeStatus(from: wifi, snapshot: snapshot)
    }

    static func makeStatus(
        from wifi: NetworkInterfaceInfo,
        snapshot: NetworkInterfaceSnapshot
    ) -> WiFiCurrentStatus {
        let interpreted = WiFiLinkInterpreter.evaluate(
            wifi.wifiLinkEvidence,
            expectedCycleID: snapshot.cycleID,
            expectedCapturedAt: snapshot.capturedAt
        )
        let provisional = WiFiCurrentStatus(
            timestamp: snapshot.capturedAt,
            interfaceSnapshotCycleID: snapshot.cycleID,
            interfaceName: wifi.interfaceName,
            interfaceIndex: wifi.interfaceIndex,
            ssid: wifi.ssid,
            bssid: wifi.bssid,
            channel: wifi.channel,
            band: wifi.band,
            rssi: wifi.rssi,
            txRate: wifi.txRate,
            phyMode: wifi.phyMode,
            security: wifi.security,
            routerIP: wifi.router,
            isConnected: false,
            isWiFiPowerOn: wifi.wifiLinkEvidence?.radio == .reportedOn,
            linkEvidence: wifi.wifiLinkEvidence,
            linkAssessment: interpreted
        )
        let verified = WiFiLinkEvidenceValidator.assessment(for: provisional)
        var status = provisional
        let finalAssessment: WiFiLinkAssessment = verified ?? (wifi.wifiLinkEvidence == nil
            ? interpreted
            : WiFiLinkAssessment(state: VerifiedWiFiLinkState.unknown, reason: WiFiLinkEvidenceReason.conflictingLinkEvidence))
        status.linkAssessment = finalAssessment
        status.isConnected = status.linkAssessment?.state == .associated
        return status
    }
}
