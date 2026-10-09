import SwiftUI
import CoreWLAN

private let headerHeight: CGFloat = 28

public enum InterfaceViewMode: String, CaseIterable {
    case simple
    case details
    case monitor

    public var displayName: String {
        switch self {
        case .simple:  String(localized: "channels.mode.simple", comment: "Simple view mode for channel quality")
        case .details: String(localized: "common.label.details", comment: "Details view mode label")
        case .monitor: String(localized: "interfaces.mode.monitor", comment: "Throughput monitor view mode")
        }
    }
}

public struct InterfacesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let interfaces: [NetworkInterfaceInfo]
    let scannerViewModel: ScannerViewModel
    @ObservedObject private var store: WiFiObservationStore
    let throughputMonitor: ThroughputMonitor
    let mode: InterfaceViewMode
    @State private var gatewayLatency: Double?

    public init(
        interfaces: [NetworkInterfaceInfo],
        scannerViewModel: ScannerViewModel,
        throughputMonitor: ThroughputMonitor,
        mode: InterfaceViewMode
    ) {
        self.interfaces = interfaces
        self.scannerViewModel = scannerViewModel
        _store = ObservedObject(wrappedValue: scannerViewModel.store)
        self.throughputMonitor = throughputMonitor
        self.mode = mode
    }

    private var wifiInterface: NetworkInterfaceInfo? {
        if verifiedLinkState == .associated,
           let interfaceName = store.currentStatus?.interfaceName {
            return interfaces.first {
                $0.isWiFiInterface && $0.interfaceName == interfaceName
            }
        }
        return interfaces.first(where: \.isWiFiInterface)
    }

    private var verifiedLinkState: VerifiedWiFiLinkState {
        guard let status = store.currentStatus,
              status.error == nil,
              store.validity(at: Date())?.currentStatus == .current else { return .unknown }
        return status.linkAssessment?.state ?? .unknown
    }

    private var linkStateLabel: String {
        switch verifiedLinkState {
        case .associated:
            String(localized: "common.label.connected", comment: "Connected state indicator")
        case .disconnected:
            String(localized: "overview.status.not_connected", comment: "Empty state when not connected to any Wi-Fi network")
        case .unknown:
            String(localized: "common.label.unknown", comment: "Generic unknown value label")
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if interfaces.isEmpty {
                Spacer()
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(String(localized: "interfaces.empty.no_interfaces", comment: "Empty state when no network interfaces exist"))
                    .foregroundColor(.secondary)
                Spacer()
            } else if mode == .simple {
                dashboardView
            } else if mode == .monitor {
                monitorView
            } else {
                detailsView
            }
        }
    }

    // MARK: - Dashboard (Simple)

    private var dashboardView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let wifi = wifiInterface {
                    connectionHero(wifi)
                    healthIndicators(wifi)
                    linkDetails(wifi)
                }

                let others = interfaces.filter { !$0.isWiFiInterface && $0.ipv4Addresses.first != nil }
                if !others.isEmpty {
                    otherInterfaces(others)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: 640)
        }
        .frame(maxWidth: .infinity)
        .scrollClipDisabled()
    }

    // MARK: - Hero

    private func connectionHero(_ wifi: NetworkInterfaceInfo) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verifiedLinkState == .associated ? wifi.displaySSID : String(localized: "common.label.unknown", comment: "Generic unknown value label"))
                        .font(.title3)
                        .fontWeight(.semibold)
                        // Same guardrail as OverviewView.connectionCard: a long SSID
                        // is one unbreakable token that would widen the hero past the
                        // detail column at the minimum window size.
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(verifiedLinkState == .associated ? wifi.displaySSID : String(localized: "common.label.unknown", comment: "Generic unknown value label"))
                    HStack(spacing: 6) {
                        Circle().fill(verifiedLinkState == .associated ? Color.green : Color.secondary).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(linkStateLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("· \(wifi.interfaceName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(bandLabel(wifi))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(channelLabel(wifi))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let latency = gatewayLatency {
                        Text(String(format: String(localized: "interfaces.field.gateway_latency_fmt", comment: "Gateway latency value with milliseconds"), latency))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(latencyColor(latency))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
        .task(id: "\(wifi.router ?? "")-\(verifiedLinkState.rawValue)") {
            gatewayLatency = nil
            guard verifiedLinkState == .associated, let router = wifi.router else { return }
            let pinger = GatewayPinger()
            while !Task.isCancelled {
                gatewayLatency = await pinger.ping(host: router)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Health Indicators

    private func healthIndicators(_ wifi: NetworkInterfaceInfo) -> some View {
        HStack(spacing: 12) {
            // RSSI
            indicatorPill(
                title: String(localized: "channels.table.col.rssi", comment: "RSSI column header"),
                value: wifi.displayRSSI,
                subtitle: nil,
                color: rssiColor(wifi.rssi ?? -100),
                bar: rssiBar(wifi.rssi ?? -100)
            )
            .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))

            // PHY Mode
            indicatorPill(
                title: String(localized: "interfaces.field.phy_mode", comment: "PHY mode field label"),
                value: wifi.displayPhyMode,
                subtitle: wifiModelabel(wifi),
                color: .accentColor,
                bar: nil
            )
            .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))

            // Stability
            let stab = stability(wifi)
            indicatorPill(
                title: String(localized: "interfaces.field.stability", comment: "Connection stability field label"),
                value: stab.label,
                subtitle: String(format: String(localized: "format.score_fraction", comment: "Score value out of 100"), stab.score),
                color: stab.color,
                bar: scoreBar(stab.score, color: stab.color)
            )
            .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func indicatorPill(title: String, value: String, subtitle: String?, color: Color, bar: AnyView?) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(title).font(.caption2).foregroundColor(.secondary)
            Spacer().frame(height: 6)
            Text(value).font(.title3.weight(.semibold)).foregroundColor(color)
            Spacer().frame(height: 4)
            if let sub = subtitle {
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
            Spacer().frame(height: 4)
            if let bar = bar {
                bar.padding(.horizontal, 12)
            } else {
                Rectangle().fill(.clear).frame(height: 4)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            if let sub = subtitle {
                return String(format: String(localized: "common.accessibility.metric_sub_fmt", comment: "Label: value, subtitle format for VoiceOver metric"), title, value, sub)
            }
            return String(format: String(localized: "common.accessibility.metric_fmt", comment: "Label: value format for VoiceOver metric"), title, value)
        }())
    }

    // MARK: - Link Details

    private func linkDetails(_ wifi: NetworkInterfaceInfo) -> some View {
        HStack(alignment: .top, spacing: 24) {
            kvTable([
                (String(localized: "interfaces.field.bssid", comment: "BSSID field label"), wifi.displayBSSID),
                (String(localized: "overview.health.security_label", comment: "Security health indicator label"), wifi.displaySecurity),
                (String(localized: "interfaces.field.mcs_nss", comment: "MCS/NSS field label"), mcsNssLabel(wifi)),
                (String(localized: "interfaces.field.tx_rate", comment: "Transmit rate field label"), wifi.displayTxRate),
                (String(localized: "interfaces.field.krv", comment: "802.11 k/r/v roaming support field label"), kvrLabel(wifi)),
            ])
            kvTable([
                (String(localized: "interfaces.field.ipv4_address", comment: "IPv4 address field label"), wifi.displayIP),
                (String(localized: "interfaces.field.subnet_mask", comment: "Subnet mask field label (full)"), wifi.displaySubnet),
                (String(localized: "interfaces.field.router", comment: "Router/gateway address field label"), wifi.displayRouter),
                (String(localized: "interfaces.field.dns", comment: "DNS server field label"), wifi.displayDNS),
                (String(localized: "interfaces.field.hardware_mac", comment: "Hardware MAC address field label"), wifi.displayMAC),
            ])
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Other Interfaces

    private func otherInterfaces(_ others: [NetworkInterfaceInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "interfaces.label.other", comment: "Other interfaces section header"))
                .font(.headline)
                .foregroundColor(.secondary)
            VStack(spacing: 4) {
                ForEach(others, id: \.interfaceName) { iface in
                    HStack(spacing: 8) {
                        Image(systemName: "cable.connector")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(iface.interfaceName)
                            .font(.callout)
                        Spacer()
                        Text(iface.displayIP)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Monitor

    @State private var selectedMonitorInterface: String?
    @State private var isMonitorChartCollapsed = false
    @State private var isMonitorTableCollapsed = false

    private var monitorInterfaces: [String] {
        var seen = Set(throughputMonitor.activeInterfaces)
        for info in interfaces where !info.interfaceName.isEmpty {
            seen.insert(info.interfaceName)
        }
        return seen.sorted { a, b in
            let aWifi = a.hasPrefix("en") ? 0 : 1
            let bWifi = b.hasPrefix("en") ? 0 : 1
            if aWifi != bWifi { return aWifi < bWifi }
            return a < b
        }
    }

    private var monitorSamples: [ThroughputSample] {
        guard let name = selectedMonitorInterface else { return [] }
        return throughputMonitor.samples(for: name)
    }

    private var selectedMonitorRate: String {
        guard let name = selectedMonitorInterface,
              let last = throughputMonitor.samples(for: name).last else { return "" }
        let down = rateDown(last.rateIn)
        let up = rateUp(last.rateOut)
        return "\(down)  \(up)"
    }

    private var monitorView: some View {
        GeometryReader { geometry in
            let totalH = geometry.size.height
            let sections = 2
            let allHeaders = CGFloat(sections) * headerHeight
            let contentPool = max(0, totalH - allHeaders)
            let chartExpanded = !isMonitorChartCollapsed
            let tableExpanded = !isMonitorTableCollapsed

            let chartWeight: CGFloat = 1.0
            let tableWeight: CGFloat = 1.5
            let activeWeight = (chartExpanded ? chartWeight : 0) + (tableExpanded ? tableWeight : 0)
            let totalWeight = max(1, activeWeight)

            let chartContentH: CGFloat = chartExpanded
                ? max(60, contentPool * chartWeight / totalWeight)
                : 0
            let tableContentH: CGFloat = tableExpanded
                ? max(60, contentPool * tableWeight / totalWeight)
                : 0

            VStack(spacing: 0) {
                // Chart section
                monitorChartHeader
                if chartExpanded {
                    monitorChartContent(height: chartContentH)
                }

                Divider()

                // Interface table section
                monitorTableHeader
                if tableExpanded {
                    monitorTableContent(height: tableContentH)
                }
            }
            .clipped()
        }
    }

    private var monitorChartHeader: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { isMonitorChartCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isMonitorChartCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .frame(width: 12)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                Text(String(localized: "interfaces.field.throughput", comment: "Throughput section header"))
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(selectedMonitorRate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var monitorTableHeader: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { isMonitorTableCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isMonitorTableCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .frame(width: 12)
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption)
                Text(String(localized: "nav.interfaces", comment: "Interfaces sidebar navigation item"))
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(String(format: String(localized: "interfaces.count_format", comment: "Interface count with number"), monitorInterfaces.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func monitorChartContent(height: CGFloat) -> some View {
        Group {
            if monitorSamples.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "interfaces.empty.select_to_monitor", comment: "Prompt to select interface for throughput monitoring"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: height)
            } else {
                ThroughputChartView(samples: monitorSamples, interfaceName: selectedMonitorInterface ?? "")
                    .frame(height: height)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func monitorTableContent(height: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(monitorInterfaces, id: \.self) { name in
                    let isSelected = selectedMonitorInterface == name
                    let lastSample = throughputMonitor.samples(for: name).last
                    Button {
                        selectedMonitorInterface = name
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: name.hasPrefix("en") ? "wifi" : "cable.connector")
                                .font(.callout)
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                                .frame(width: 20)

                            Text(name)
                                .font(isSelected ? .subheadline.weight(.semibold) : .subheadline)
                                .foregroundColor(.primary)
                                .frame(width: 60, alignment: .leading)

                            Spacer()

                            if let s = lastSample {
                                Text(rateDown(s.rateIn))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(s.rateIn == 0 ? .secondary.opacity(0.5) : .green)
                                    .frame(width: 72, alignment: .trailing)
                                    .lineLimit(1)
                                Text(rateUp(s.rateOut))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(s.rateOut == 0 ? .secondary.opacity(0.5) : .blue)
                                    .frame(width: 72, alignment: .trailing)
                                    .lineLimit(1)
                            } else {
                                Text("—").font(.callout).foregroundColor(.secondary).frame(width: 72)
                                Text("—").font(.callout).foregroundColor(.secondary).frame(width: 72)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)

                    if name != monitorInterfaces.last {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: height)
    }

    private func rateDown(_ bytesPerSec: Double) -> String {
        "↓  " + rateVal(bytesPerSec)
    }
    private func rateUp(_ bytesPerSec: Double) -> String {
        "↑  " + rateVal(bytesPerSec)
    }
    private func rateVal(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1_024 { return String(format: "%4.0f B", bytesPerSec) }
        if bytesPerSec < 1_048_576 { return String(format: "%4.0f K", bytesPerSec / 1_024) }
        if bytesPerSec < 1_073_741_824 { return String(format: "%4.1f M", bytesPerSec / 1_048_576) }
        return String(format: "%4.1f G", bytesPerSec / 1_073_741_824)
    }

    // MARK: - Details (Professional)

    private var detailsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(interfaces, id: \.interfaceName) { iface in
                    InterfaceCard(info: iface)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func kvTable(_ pairs: [(String, String)]) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(pairs, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(value)
                        .font(.callout)
                        .textSelection(.enabled)
                        .gridColumnAlignment(.leading)
                }
            }
        }
    }

    private func bandLabel(_ wifi: NetworkInterfaceInfo) -> String {
        guard let ch = wifi.channel else { return "—" }
        if ch <= 14 { return String(localized: "wifi.band.24ghz", comment: "2.4 GHz Wi-Fi band name") }
        if ch <= 170 { return String(localized: "wifi.band.5ghz", comment: "5 GHz Wi-Fi band name") }
        return String(localized: "wifi.band.6ghz", comment: "6 GHz Wi-Fi band name")
    }

    private func channelLabel(_ wifi: NetworkInterfaceInfo) -> String {
        guard let ch = wifi.channel else { return "—" }
        return String(format: String(localized: "interfaces.field.channel_fmt", comment: "Formatted channel label with number"), String(ch))
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -50 { return .green }
        if rssi >= -70 { return .yellow }
        if rssi >= -85 { return .orange }
        return .red
    }

    private func rssiBar(_ rssi: Int) -> AnyView {
        let pct = max(0.0, min(1.0, Double(rssi + 100) / 70.0))
        return AnyView(
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.quaternary).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(rssiColor(rssi))
                        .frame(width: geo.size.width * pct, height: 4)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        )
    }

    private func scoreBar(_ score: Int, color: Color) -> AnyView {
        AnyView(
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.quaternary).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 4)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        )
    }

    private func stability(_ wifi: NetworkInterfaceInfo) -> (score: Int, label: String, color: Color) {
        let rssi = wifi.rssi ?? -100
        var score = 0
        if rssi >= -50 { score += 40 }
        else if rssi >= -70 { score += 30 }
        else if rssi >= -85 { score += 15 }

        // Trend bonus from signal history
        let bssid = wifi.bssid ?? ""
        if let trend = scannerViewModel.signalHistory.trend(for: bssid) {
            switch trend.direction {
            case .up:   score += 15
            case .down: score += 0
            case .stable:
                if abs(trend.delta) <= 2 { score += 15 }
                else { score += 5 }
            }
        }

        // Protocol bonus
        let ie = scannerViewModel.lastNetworks
            .first(where: { $0.bssid == bssid })
            .flatMap { $0.ieData.map { IEParser.parse(data: $0) } }
        let k = ie?.supports80211k ?? false
        let r = ie?.supports80211r ?? false
        let v = ie?.supports80211v ?? false
        let protoCount = [k, r, v].filter { $0 }.count
        score += [0, 7, 14, 20][protoCount]

        // Width bonus
        if let iface = CWWiFiClient.shared().interface() {
            let width = iface.wlanChannel()?.channelWidth.rawValue ?? 20
            if width >= 80 { score += 15 }
            else if width >= 40 { score += 10 }
        }

        score = min(100, score)
        let label: String = switch score {
        case 85...:  String(localized: "channels.quality.excellent", comment: "Excellent channel quality tier")
        case 70...:  String(localized: "overview.signal.good", comment: "Good signal level label")
        case 50...:  String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier")
        default:     String(localized: "overview.signal.weak", comment: "Weak signal level label")
        }
        let color: Color = switch score {
        case 85...: .green
        case 70...: .mint
        case 50...: .orange
        default:    .red
        }
        return (score, label, color)
    }

    private func wifiModelabel(_ wifi: NetworkInterfaceInfo) -> String {
        switch wifi.displayPhyMode {
        case "802.11be": return String(localized: "wifi.generation.wifi_7", comment: "Wi-Fi 7 (802.11be) generation name")
        case "802.11ax": return String(localized: "wifi.generation.wifi_6", comment: "Wi-Fi 6 (802.11ax) generation name")
        case "802.11ac": return String(localized: "wifi.generation.wifi_5", comment: "Wi-Fi 5 (802.11ac) generation name")
        case "802.11n":  return String(localized: "wifi.generation.wifi_4", comment: "Wi-Fi 4 (802.11n) generation name")
        default: return wifi.displayPhyMode
        }
    }

    private func mcsNssLabel(_ wifi: NetworkInterfaceInfo) -> String {
        let bssid = wifi.bssid ?? ""
        let ie = scannerViewModel.lastNetworks
            .first(where: { $0.bssid == bssid })
            .flatMap { $0.ieData.map { IEParser.parse(data: $0) } }
        let mcs = ie?.mcsSummary ?? ""
        let nss = ie?.nssSummary ?? ""
        if mcs.isEmpty && nss.isEmpty { return String(localized: "symbol.em_dash", comment: "Em dash symbol used as placeholder") }
        return String(format: String(localized: "interfaces.field.mcs_nss_fmt", comment: "MCS/NSS formatted value"), mcs, nss)
    }

    private func kvrLabel(_ wifi: NetworkInterfaceInfo) -> String {
        let bssid = wifi.bssid ?? ""
        let ie = scannerViewModel.lastNetworks
            .first(where: { $0.bssid == bssid })
            .flatMap { $0.ieData.map { IEParser.parse(data: $0) } }
        guard let ie else { return "—" }
        var parts: [String] = []
        if ie.supports80211k { parts.append("k") }
        if ie.supports80211r { parts.append("r") }
        if ie.supports80211v { parts.append("v") }
        return parts.isEmpty ? "—" : parts.joined(separator: " / ")
    }
}

// MARK: - Interface Card (Details mode)

private struct InterfaceCard: View {
    let info: NetworkInterfaceInfo

    /// A compact row that only renders if a value is meaningful.
    private func compactRow(label: String, value: String) -> some View {
        let isEmpty = value.isEmpty || value == "—"
        return HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text(isEmpty ? "—" : value)
                .font(isEmpty ? .callout : .callout.monospacedDigit())
                .foregroundColor(isEmpty ? .secondary.opacity(0.6) : .primary)
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// Non‑monospaced row for labels like security.
    private func labelRow(label: String, value: String) -> some View {
        let isEmpty = value.isEmpty || value == "—"
        return HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text(isEmpty ? "—" : value)
                .font(.callout)
                .foregroundColor(isEmpty ? .secondary.opacity(0.6) : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func typeBadge(_ t: NetworkInterfaceInfo.InterfaceType) -> some View {
        let (label, color): (String, Color) = switch t {
        case .wifi:     (String(localized: "interfaces.label.wifi", comment: "Wi-Fi interface type label"), .accentColor)
        case .ethernet: (String(localized: "interfaces.label.ethernet", comment: "Ethernet interface type label"), .secondary)
        case .virtual:  (String(localized: "interfaces.label.virtual", comment: "Virtual interface type label"), .secondary.opacity(0.8))
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    var body: some View {
        let t = info.interfaceType

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                typeBadge(t)
                Text(t == .wifi ? (info.ssid ?? info.interfaceName) : info.interfaceName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if t == .wifi, !info.displayRSSI.isEmpty, info.displayRSSI != "—" {
                    Text(info.displayRSSI)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(rssiColor(info.rssi ?? -100))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(rssiColor(info.rssi ?? -100).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                if t != .virtual {
                    Text(info.interfaceName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            // Body — two‑column compact rows
            VStack(spacing: 2) {
                if t == .wifi {
                    compactRow(label: String(localized: "interfaces.field.bssid", comment: "BSSID field label"), value: info.displayBSSID)
                    compactRow(label: String(localized: "overview.health.channel_label", comment: "Channel quality health indicator label"), value: info.displayChannel)
                    compactRow(label: String(localized: "interfaces.field.phy", comment: "PHY mode field label (short)"), value: info.displayPhyMode)
                    compactRow(label: String(localized: "interfaces.field.tx_rate", comment: "Transmit rate field label"), value: info.displayTxRate)
                    labelRow(label: String(localized: "overview.health.security_label", comment: "Security health indicator label"), value: info.displaySecurity)
                }

                // Network section — shown for Wi‑Fi and any interface that has network data
                if info.hasNetworkInfo || t == .wifi {
                    if t == .wifi {
                        Divider().padding(.horizontal, 8).padding(.vertical, 2)
                    }
                    compactRow(label: String(localized: "interfaces.field.ipv4", comment: "IPv4 section header"), value: info.displayIP)
                    compactRow(label: String(localized: "interfaces.field.subnet", comment: "Subnet mask field label (short)"), value: info.displaySubnet)
                    compactRow(label: String(localized: "interfaces.field.router", comment: "Router/gateway address field label"), value: info.displayRouter)
                    compactRow(label: String(localized: "interfaces.field.dns", comment: "DNS server field label"), value: info.displayDNS)
                }

                // MAC — only for Wi‑Fi and Ethernet (not virtual)
                if t != .virtual {
                    compactRow(label: String(localized: "interfaces.field.mac", comment: "MAC address field label (short)"), value: info.displayMAC)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 7))
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -50 { return .green }
        if rssi >= -70 { return .yellow }
        if rssi >= -85 { return .orange }
        return .red
    }

}

private func latencyColor(_ ms: Double) -> Color {
    if ms < 5 { return .green }
    if ms < 20 { return .yellow }
    return .red
}
