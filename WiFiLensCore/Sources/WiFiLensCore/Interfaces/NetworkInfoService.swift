import Foundation
import CoreWLAN
import SystemConfiguration

public struct NetworkInterfaceInfo: Sendable {
    enum InterfaceType: String, Sendable {
        case wifi
        case ethernet
        case virtual
    }

    public let interfaceName: String
    public let interfaceIndex: UInt32?
    public let hardwareMAC: String?
    public let isWiFiInterface: Bool
    public let wifiLinkEvidence: WiFiLinkRawEvidence?
    public let ipv4Addresses: [String]
    public let subnetMasks: [String]
    public let router: String?
    public let dnsServers: [String]

    // Wi-Fi specific (nil if not a Wi-Fi interface)
    public let ssid: String?
    public let bssid: String?
    public let channel: Int?
    public let band: ChannelBand?
    public let rssi: Int?
    public let txRate: Double?
    public let phyMode: String?
    public let security: String

    public init(
        interfaceName: String,
        interfaceIndex: UInt32? = nil,
        hardwareMAC: String? = nil,
        isWiFiInterface: Bool = false,
        wifiLinkEvidence: WiFiLinkRawEvidence? = nil,
        ipv4Addresses: [String] = [],
        subnetMasks: [String] = [],
        router: String? = nil,
        dnsServers: [String] = [],
        ssid: String? = nil,
        bssid: String? = nil,
        channel: Int? = nil,
        band: ChannelBand? = nil,
        rssi: Int? = nil,
        txRate: Double? = nil,
        phyMode: String? = nil,
        security: String = "—"
    ) {
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex ?? (if_nametoindex(interfaceName) == 0 ? nil : if_nametoindex(interfaceName))
        self.hardwareMAC = hardwareMAC
        self.isWiFiInterface = isWiFiInterface
        self.wifiLinkEvidence = wifiLinkEvidence
        self.ipv4Addresses = ipv4Addresses
        self.subnetMasks = subnetMasks
        self.router = router
        self.dnsServers = dnsServers
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.band = band
        self.rssi = rssi
        self.txRate = txRate
        self.phyMode = phyMode
        self.security = security
    }

    var interfaceType: InterfaceType {
        if isWiFiInterface { return .wifi }
        if hardwareMAC != nil { return .ethernet }
        return .virtual
    }

    var displayMAC: String { hardwareMAC ?? String(localized: "common.label.unknown", comment: "Generic unknown value label") }
    public var displaySSID: String { ssid ?? "n/a" }
    public var displayBSSID: String { bssid ?? String(localized: "common.label.unknown", comment: "Generic unknown value label") }
    public var displayChannel: String { channel.map { "\($0)" } ?? "—" }
    public var displayRSSI: String { rssi.map { "\($0) dBm" } ?? "—" }
    var displayTxRate: String { txRate.map { "\(Int($0)) Mbps" } ?? "—" }
    var displaySecurity: String { security }
    var displayPhyMode: String { phyMode ?? "—" }
    var displayIP: String { ipv4Addresses.first ?? "—" }
    var displaySubnet: String { subnetMasks.first ?? "—" }
    var displayRouter: String { router ?? "—" }
    var displayDNS: String { dnsServers.isEmpty ? "—" : dnsServers.joined(separator: ", ") }


    var hasNetworkInfo: Bool { !ipv4Addresses.isEmpty || router != nil || !dnsServers.isEmpty }
}

public struct NetworkInterfaceSnapshot: Sendable {
    public let cycleID: UUID
    public let capturedAt: Date
    public let interfaces: [NetworkInterfaceInfo]
    public let interfaceEnumerationSucceeded: Bool
    public let wifiInterfaceDiscoverySucceeded: Bool

    public init(
        cycleID: UUID,
        capturedAt: Date,
        interfaces: [NetworkInterfaceInfo],
        interfaceEnumerationSucceeded: Bool = true,
        wifiInterfaceDiscoverySucceeded: Bool = true
    ) {
        self.cycleID = cycleID
        self.capturedAt = capturedAt
        self.interfaces = interfaces
        self.interfaceEnumerationSucceeded = interfaceEnumerationSucceeded
        self.wifiInterfaceDiscoverySucceeded = wifiInterfaceDiscoverySucceeded
    }
}

public protocol NetworkInterfaceSnapshotSourcing: Sendable {
    func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot
}

struct SystemNetworkInterfaceSnapshotSource: NetworkInterfaceSnapshotSourcing {
    public init() {}
    @concurrent
    public func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot {
        let capturedAt = Date()
        return NetworkInfoService.captureSnapshot(cycleID: cycleID, capturedAt: capturedAt)
    }
}

public enum NetworkInfoService {
    private struct InterfaceCaptureResult {
        let interfaces: [NetworkInterfaceInfo]
        let interfaceEnumerationSucceeded: Bool
        let wifiInterfaceDiscoverySucceeded: Bool
    }

    static func captureSnapshot(cycleID: UUID, capturedAt: Date) -> NetworkInterfaceSnapshot {
        let capture = fetchAll(cycleID: cycleID, capturedAt: capturedAt)
        return NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: capture.interfaces,
            interfaceEnumerationSucceeded: capture.interfaceEnumerationSucceeded,
            wifiInterfaceDiscoverySucceeded: capture.wifiInterfaceDiscoverySucceeded
        )
    }

    /// Captures only the fields required by the process-wide link state center.
    /// This intentionally avoids interface, DNS, and gateway enumeration.
    static func captureWiFiLinkEvidence(
        cycleID: UUID,
        capturedAt: Date,
        interfaceName preferredName: String? = nil,
        interface preferredInterface: CWInterface? = nil,
        store preferredStore: SCDynamicStore? = nil
    ) -> WiFiLinkRawEvidence? {
        let captureStartedAt = capturedAt
        let client = CWWiFiClient.shared()
        let names = preferredName.map { [$0] } ?? client.interfaceNames() ?? []
        guard !names.isEmpty else { return nil }
        let name = preferredName ?? client.interface()?.interfaceName.flatMap { names.contains($0) ? $0 : nil } ?? names.sorted().first!
        let interface = preferredInterface ?? client.interface(withName: name)
        var failures: [WiFiLinkEvidenceField: WiFiLinkEvidenceReadFailure] = [:]
        guard let interface else {
            failures[.mode] = .interfaceNotFound
            failures[.radio] = .interfaceNotFound
            return WiFiLinkRawEvidence(
                snapshotCycleID: cycleID,
                capturedAt: capturedAt,
                interfaceName: name,
                mode: .unavailable,
                radio: .unavailable,
                interfaceIndex: interfaceIndex(name),
                captureStartedAt: captureStartedAt,
                captureEndedAt: Date(),
                readFailures: failures
            )
        }

        let coreWLANModeRawValue = interface.interfaceMode().rawValue
        let mode: WiFiModeEvidence
        switch coreWLANModeRawValue {
        case 0:
            mode = .noneOrReadFailure
        case 1: mode = .station
        case let rawValue: mode = .other(rawValue: rawValue)
        }
        let reportedPower = interface.powerOn()
        let radio: WiFiRadioEvidence = reportedPower ? .reportedOn : .reportedOffOrReadFailure
        let store = preferredStore ?? SCDynamicStoreCreate(nil, "WiFiLens.LinkEvidence" as CFString, nil, nil)
        let linkKey = "State:/Network/Interface/\(name)/Link"
        let linkDictionary = store.flatMap {
            SCDynamicStoreCopyValue($0, linkKey as CFString) as? [String: Any]
        }
        let linkActive = linkDictionary?[kSCPropNetLinkActive as String] as? Bool
        let linkDetaching = linkDictionary?["Detaching"] as? Bool
        if linkDictionary == nil { failures[.linkActive] = .missingValue }
        else if linkActive == nil { failures[.linkActive] = .missingValue }
        if linkDetaching == nil { failures[.linkDetaching] = .missingValue }

        let serviceActive = interface.serviceActive()
        let flags = interfaceFlags(name)
        if flags == nil { failures[.interfaceFlags] = .enumerationFailed }
        let ssid = interface.ssid()
        let bssid = interface.bssid()
        if ssid == nil { failures[.ssid] = .apiReturnedNoValue }
        if bssid == nil { failures[.bssid] = .apiReturnedNoValue }

        return WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: capturedAt,
            interfaceName: name,
            mode: mode,
            coreWLANModeRawValue: coreWLANModeRawValue,
            radio: radio,
            linkActive: linkActive,
            ssid: ssid,
            bssid: bssid,
            modeSource: .coreWLAN,
            radioSource: .coreWLAN,
            linkSource: linkDictionary == nil ? nil : .systemConfiguration,
            serviceActiveSource: .coreWLAN,
            linkDetachingSource: linkDictionary == nil ? nil : .systemConfiguration,
            interfaceFlagsSource: flags == nil ? nil : .getifaddrs,
            interfaceIndex: interfaceIndex(name),
            radioPowerOnRaw: reportedPower,
            serviceActive: serviceActive,
            linkDetaching: linkDetaching,
            interfaceFlagsUp: flags?.up,
            interfaceFlagsRunning: flags?.running,
            captureStartedAt: captureStartedAt,
            captureEndedAt: Date(),
            readFailures: failures
        )
    }

    /// All available network interfaces, including virtual ones.
    /// Uses `getifaddrs()` for discovery so VPN / VM / bridge adapters
    /// are visible even when they have no SystemConfiguration state.
    static func fetchAll() -> [NetworkInterfaceInfo] {
        fetchAll(cycleID: nil, capturedAt: Date()).interfaces
    }

    private static func fetchAll(cycleID: UUID?, capturedAt: Date) -> InterfaceCaptureResult {
        let store = SCDynamicStoreCreate(nil, "WiFiLens" as CFString, nil, nil)
        let dns = fetchDNS(store)
        let wifiClient = CWWiFiClient.shared()
        let discoveredWiFiNames = wifiClient.interfaceNames()
        let wifiNames = Set(discoveredWiFiNames ?? [])

        // Discover all interfaces via getifaddrs (includes virtual ones)
        var ifaces: [String: (ips: [String], subnets: [String], mac: String?)] = [:]
        var addrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrPtr) == 0, let first = addrPtr else {
            return InterfaceCaptureResult(
                interfaces: [],
                interfaceEnumerationSucceeded: false,
                wifiInterfaceDiscoverySucceeded: discoveredWiFiNames != nil
            )
        }
        defer { freeifaddrs(first) }

        for name in wifiNames {
            ifaces[name] = ifaces[name] ?? (ips: [], subnets: [], mac: nil)
        }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let namePtr = ptr.pointee.ifa_name,
                  let addr = ptr.pointee.ifa_addr else { continue }
            let name = String(cString: namePtr)
            if name == "lo0" { continue }  // skip loopback

            var entry = ifaces[name] ?? (ips: [], subnets: [], mac: nil)

            if addr.pointee.sa_family == sa_family_t(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buffer, socklen_t(buffer.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    entry.ips.append(String(decoding: buffer.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self))
                }
                // Subnet mask
                if let netmask = ptr.pointee.ifa_netmask, netmask.pointee.sa_family == sa_family_t(AF_INET) {
                    var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(netmask, socklen_t(netmask.pointee.sa_len), &maskBuf, socklen_t(maskBuf.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        entry.subnets.append(String(decoding: maskBuf.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self))
                    }
                }
            }

            // MAC from AF_LINK
            if addr.pointee.sa_family == sa_family_t(AF_LINK) {
                let link = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                if link.sdl_alen > 0 {
                    let macBase = UnsafeRawPointer(ptr.pointee.ifa_addr)
                        .advanced(by: MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)! + Int(link.sdl_nlen))
                    let bytes = macBase.bindMemory(to: UInt8.self, capacity: Int(link.sdl_alen))
                    entry.mac = (0..<Int(link.sdl_alen)).map {
                        String(format: "%02x", bytes[$0])
                    }.joined(separator: ":")
                }
            }

            ifaces[name] = entry
        }

        // Read each SystemConfiguration collection once per capture. The maps
        // below are reused while enriching every discovered interface.
        var interfaceIPv4ByName: [String: [String: Any]] = [:]
        if let store,
           let ipv4Keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Interface/.*/IPv4" as CFString) as? [String] {
            for key in ipv4Keys {
                let name = key.components(separatedBy: "/").dropLast().last ?? key
                guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else { continue }
                interfaceIPv4ByName[name] = dict
                if ifaces[name] == nil {
                    ifaces[name] = (ips: [], subnets: [], mac: nil)
                }
                if ifaces[name]?.ips.isEmpty ?? true {
                    ifaces[name]?.ips = dict["Addresses"] as? [String] ?? []
                }
                if ifaces[name]?.subnets.isEmpty ?? true {
                    ifaces[name]?.subnets = dict["SubnetMasks"] as? [String] ?? []
                }
            }
        }

        var serviceIPv4ByInterface: [String: [String: Any]] = [:]
        if let store,
           let serviceKeys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String] {
            for key in serviceKeys {
                guard let dictionary = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                      let interfaceName = dictionary["InterfaceName"] as? String else { continue }
                if serviceIPv4ByInterface[interfaceName] == nil {
                    serviceIPv4ByInterface[interfaceName] = dictionary
                }
            }
        }

        // Build result, enriching each Wi-Fi interface independently of SSID visibility.
        var result: [NetworkInterfaceInfo] = []
        for (name, entry) in ifaces {
            let isWiFi = wifiNames.contains(name)
            let wifiInterface = isWiFi ? wifiClient.interface(withName: name) : nil
            let wiFiInfo = wifiInterface.flatMap(fetchWiFiDetails)
            let linkEvidence = cycleID.flatMap { id in
                isWiFi ? captureWiFiLinkEvidence(
                    cycleID: id,
                    capturedAt: capturedAt,
                    interfaceName: name,
                    interface: wifiInterface,
                    store: store
                ) : nil
            }

            // Router lookup from SystemConfiguration (Interface path)
            var router: String?
            if let ipv4Dict = interfaceIPv4ByName[name] {
                if let r = ipv4Dict["Router"] as? String { router = r }
                else if let arr = ipv4Dict["Router"] as? [String], let first = arr.first { router = first }
            }

            if router == nil, let serviceIPv4 = serviceIPv4ByInterface[name] {
                if let value = serviceIPv4["Router"] as? String {
                    router = value
                } else if let values = serviceIPv4["Router"] as? [String] {
                    router = values.first
                }
            }

            result.append(NetworkInterfaceInfo(
                interfaceName: name,
                hardwareMAC: isWiFi ? (wiFiInfo?.hardwareMAC ?? entry.mac) : entry.mac,
                isWiFiInterface: isWiFi,
                wifiLinkEvidence: linkEvidence,
                ipv4Addresses: entry.ips,
                subnetMasks: entry.subnets,
                router: router,
                dnsServers: dns,
                ssid: wiFiInfo?.ssid,
                bssid: wiFiInfo?.bssid,
                channel: wiFiInfo?.channel,
                band: wiFiInfo?.band,
                rssi: wiFiInfo?.rssi,
                txRate: wiFiInfo?.txRate,
                phyMode: wiFiInfo?.phyMode,
                security: wiFiInfo?.security ?? "—"
            ))
        }
        return InterfaceCaptureResult(
            interfaces: result.sorted { a, b in
                if a.isWiFiInterface != b.isWiFiInterface { return a.isWiFiInterface }
                return a.interfaceName < b.interfaceName
            },
            interfaceEnumerationSucceeded: true,
            wifiInterfaceDiscoverySucceeded: discoveredWiFiNames != nil
        )
    }

    private static func interfaceIndex(_ name: String) -> UInt32? {
        let index = if_nametoindex(name)
        return index == 0 ? nil : index
    }

    private static func interfaceFlags(_ name: String) -> (up: Bool, running: Bool)? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return nil }
        defer { freeifaddrs(first) }
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let rawName = item.pointee.ifa_name, String(cString: rawName) == name else { continue }
            let flags = Int32(item.pointee.ifa_flags)
            return (flags & IFF_UP != 0, flags & IFF_RUNNING != 0)
        }
        return nil
    }


    static func fetch() -> NetworkInterfaceInfo? {
        let client = CWWiFiClient.shared()
        guard let iface = client.interface(),
              let name = iface.interfaceName else { return nil }

        // Wi-Fi specifics from CoreWLAN
        let ssid = iface.ssid()
        let bssid = iface.bssid()
        let wlanChannel = iface.wlanChannel()
        let channel = wlanChannel?.channelNumber
        let band = wlanChannel.flatMap {
            channelBand(coreWLANRawValue: $0.channelBand.rawValue)
        }
        let rssi = iface.rssiValue()
        let txRate = iface.transmitRate()
        let security: String = securityLabel(iface)
        let phyMode: String? = phyModeLabel(iface)
        let hwMAC = iface.hardwareAddress()

        // IPv4 / Router from SystemConfiguration
        var ipv4s: [String] = []
        var subnets: [String] = []
        var router: String?

        let store = SCDynamicStoreCreate(nil, "WiFiLens" as CFString, nil, nil)
        if let store,
           let ipv4Dict = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(name)/IPv4" as CFString) as? [String: Any] {
            ipv4s = ipv4Dict["Addresses"] as? [String] ?? []
            subnets = ipv4Dict["SubnetMasks"] as? [String] ?? []
            // Router may be a String or [String]; try both
            if let r = ipv4Dict["Router"] as? String {
                router = r
            } else if let rArr = ipv4Dict["Router"] as? [String], let first = rArr.first {
                router = first
            }
        }

        // Fallback: try Service-based path for router
        if router == nil, let store {
            let servicePattern = "State:/Network/Service/.*/IPv4"
            if let serviceKeys = SCDynamicStoreCopyKeyList(store, servicePattern as CFString) as? [String] {
                for key in serviceKeys {
                    if let svcDict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                        if let svcInterface = svcDict["InterfaceName"] as? String, svcInterface == name {
                            if ipv4s.isEmpty {
                                ipv4s = svcDict["Addresses"] as? [String] ?? []
                            }
                            if subnets.isEmpty {
                                subnets = svcDict["SubnetMasks"] as? [String] ?? []
                            }
                            if router == nil {
                                if let r = svcDict["Router"] as? String {
                                    router = r
                                } else if let rArr = svcDict["Router"] as? [String], let first = rArr.first {
                                    router = first
                                }
                            }
                            break
                        }
                    }
                }
            }
        }

        // DNS servers
        var dnsServers: [String] = []
        if let store,
           let dnsDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = dnsDict["ServerAddresses"] as? [String] {
            dnsServers = servers
        }

        return NetworkInterfaceInfo(
            interfaceName: name,
            hardwareMAC: hwMAC,
            isWiFiInterface: true,
            ipv4Addresses: ipv4s,
            subnetMasks: subnets,
            router: router,
            dnsServers: dnsServers,
            ssid: ssid,
            bssid: bssid,
            channel: channel,
            band: band,
            rssi: rssi,
            txRate: txRate,
            phyMode: phyMode,
            security: security
        )
    }

    // MARK: - Helpers for fetchAll

    private static func fetchDNS(_ store: SCDynamicStore?) -> [String] {
        guard let store,
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = dict["ServerAddresses"] as? [String] else { return [] }
        return servers
    }

    static func channelBand(coreWLANRawValue: Int) -> ChannelBand? {
        ChannelBand(rawValue: coreWLANRawValue)
    }

    private static func securityLabel(_ iface: CWInterface) -> String {
        switch iface.security().rawValue {
        case 0: return String(localized: "common.label.none", comment: "Generic none/empty value label")
        case 1: return String(localized: "wifi.security.wep", comment: "WEP security type")
        case 2: return String(localized: "wifi.security.wpa_personal", comment: "WPA Personal security type")
        case 3: return String(localized: "wifi.security.wpa_wpa2_personal", comment: "WPA/WPA2 Personal mixed mode")
        case 4: return String(localized: "wifi.security.wpa2_personal", comment: "WPA2 Personal security type")
        case 5: return String(localized: "wifi.security.personal", comment: "Generic Personal security type label")
        case 6: return String(localized: "wifi.security.dynamic_wep", comment: "Dynamic WEP security type")
        case 7: return String(localized: "wifi.security.wpa_enterprise", comment: "WPA Enterprise security type")
        case 8: return String(localized: "wifi.security.wpa_wpa2_enterprise", comment: "WPA/WPA2 Enterprise mixed mode")
        case 9: return String(localized: "wifi.security.wpa2_enterprise", comment: "WPA2 Enterprise security type")
        case 10: return String(localized: "wifi.security.enterprise", comment: "Generic Enterprise security type label")
        case 13: return String(localized: "wifi.security.wpa3_personal", comment: "WPA3 Personal security type")
        case 14: return String(localized: "wifi.security.wpa3_enterprise", comment: "WPA3 Enterprise security type")
        case 15: return String(localized: "wifi.security.wpa3_transition", comment: "WPA3 Transition mode security type")
        default: return "—"
        }
    }

    /// Maps CWPHYMode raw values to PHY labels (kCWPHYModeNone=0, 11a=1, 11b=2,
    /// 11g=3, 11n=4, 11ac=5, 11ax=6, 11be=7). Raw 0 (None) returns nil.
    private static func phyModeLabel(_ iface: CWInterface) -> String? {
        switch iface.activePHYMode().rawValue {
        case 1: return String(localized: "wifi.phy_mode.802_11a", comment: "802.11a PHY mode label")
        case 2: return String(localized: "wifi.phy_mode.802_11b", comment: "802.11b PHY mode label")
        case 3: return String(localized: "wifi.phy_mode.802_11g", comment: "802.11g PHY mode label")
        case 4: return String(localized: "wifi.phy_mode.802_11n", comment: "802.11n PHY mode label")
        case 5: return String(localized: "wifi.phy_mode.802_11ac", comment: "802.11ac PHY mode label")
        case 6: return String(localized: "wifi.phy_mode.802_11ax", comment: "802.11ax PHY mode label")
        case 7: return String(localized: "wifi.phy_mode.802_11be", comment: "802.11be PHY mode label")
        default: return nil
        }
    }

    private static func fetchWiFiDetails(_ iface: CWInterface) -> (hardwareMAC: String?, ssid: String?, bssid: String?, channel: Int?, band: ChannelBand?, rssi: Int?, txRate: Double?, phyMode: String?, security: String)? {
        let wlanChannel = iface.wlanChannel()
        return (
            iface.hardwareAddress(),
            iface.ssid(),
            iface.bssid(),
            wlanChannel?.channelNumber,
            wlanChannel.flatMap { channelBand(coreWLANRawValue: $0.channelBand.rawValue) },
            iface.rssiValue(),
            iface.transmitRate(),
            phyModeLabel(iface),
            securityLabel(iface)
        )
    }

}
