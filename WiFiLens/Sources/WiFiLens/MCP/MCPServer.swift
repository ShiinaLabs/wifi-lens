import Foundation
import Network
import MCP

struct MCPSnapshot: Sendable {
    enum PowerState: String, Sendable, Equatable {
        case poweredOn
        case poweredOff
        case interfaceUnavailable
    }

    enum AccessState: String, Sendable, Equatable {
        case waitingForAuthorization
        case denied
        case scanning
        case grantedButSSIDUnavailable
        case scanFailed
    }

    var networks: [WiFiNetwork] = []
    var capturedAt: Date?
    var interfaceName: String?
    var isScanning = false
    var powerState: PowerState = .poweredOn
    var accessState: AccessState = .waitingForAuthorization
    var supportedBands: [String] = []
    var scanIntervalSeconds: Int?

    static let empty = MCPSnapshot()
}

/// MCP Streamable HTTP server on localhost.
/// Only accessible from this machine — no external network exposure.
final class MCPServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: NWListener?
    private(set) var isRunning = false
    var port: UInt16 = 19840

    var snapshotProvider: (@MainActor @Sendable () -> MCPSnapshot)? {
        get { lock.withLock { _snapshotProvider } }
        set { lock.withLock { _snapshotProvider = newValue } }
    }
    private var _snapshotProvider: (@MainActor @Sendable () -> MCPSnapshot)?

    private var transport: StatelessHTTPServerTransport?
    private var mcpServer: Server?
    private var serverTask: Task<Void, Never>?

    func start() async throws {
        guard !isRunning else { return }

        let transport = StatelessHTTPServerTransport()
        self.transport = transport

        let server = Server(
            name: "WiFi Lens",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: true))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.tools)
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(
                    content: [.text(text: "Server unavailable", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            let snapshot = await MainActor.run { [weak self] () -> MCPSnapshot in
                guard let self else { return .empty }
                return self.snapshotProvider?() ?? .empty
            }
            return Self.handleCallTool(name: params.name, arguments: params.arguments, snapshot: snapshot)
        }

        // Start the server — this registers the default Initialize/Ping handlers
        try await server.start(transport: transport)

        // Replace the default Initialize handler with one that allows re-initialization.
        // Default handler rejects initialize after the first one, but in stateless HTTP
        // every connection is independent so repeated initialize is valid.
        let info = Server.Info(name: server.name, version: server.version)
        let inst = server.instructions
        await server.withMethodHandler(Initialize.self) { _ in
            Initialize.Result(
                protocolVersion: Version.latest,
                capabilities: .init(tools: .init(listChanged: true)),
                serverInfo: info,
                instructions: inst
            )
        }

        mcpServer = server

        let params = NWParameters.tcp
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            AppLogger.mcp.error("Invalid MCP port: \(port)")
            return
        }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: endpointPort)
        listener = try NWListener(using: params)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(conn, transport: transport)
        }
        listener?.start(queue: .global(qos: .utility))
        isRunning = true
        AppLogger.mcp.info("MCP server started on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        serverTask?.cancel()
        serverTask = nil
        let server = mcpServer
        let t = transport
        mcpServer = nil
        transport = nil
        isRunning = false
        Task {
            await server?.stop()
            await t?.disconnect()
        }
    }

    // MARK: - Tool definitions

#if DEBUG
    static var toolNamesForTesting: [String] {
        tools.map(\.name)
    }
#endif

    private static let tools: [Tool] = [
        Tool(
            name: "scan_networks",
            description: "Scan nearby Wi-Fi networks. Returns SSID, BSSID, RSSI, channel, band, PHY mode, channel width, security, MCS/NSS, and country code for each visible network.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "band": .object([
                        "type": .string("string"),
                        "enum": .array(["24", "5", "6"].map { .string($0) }),
                        "description": .string("Filter by band: 24 = 2.4 GHz, 5 = 5 GHz, 6 = 6 GHz.")
                    ])
                ]),
                "required": .array([])
            ])
        ),
        Tool(
            name: "get_network_detail",
            description: "Get detailed information about a specific Wi-Fi network by BSSID.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bssid": .object([
                        "type": .string("string"),
                        "description": .string("The BSSID (MAC address) of the target network, e.g. 'aa:bb:cc:dd:ee:ff'.")
                    ])
                ]),
                "required": .array([.string("bssid")])
            ])
        ),
        Tool(
            name: "get_channel_occupancy",
            description: "Get per-channel network count for each band. Useful for finding the least congested channel.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        ),
        Tool(
            name: "get_scan_metadata",
            description: "Return read-only context for the most recent Wi-Fi scan snapshot. It does not trigger a new scan.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        ),
    ]

    // MARK: - Client setup

    static func setupPrompt(port: UInt16) -> String {
        let url = "http://127.0.0.1:\(port)/"

        return """
        Add or update an MCP server entry named "wifi-lens" with these properties:
        - Transport: Streamable HTTP
        - URL: \(url)
        - Purpose: Read-only access to local Wi-Fi scan data exposed by the WiFi Lens macOS app.

        Use this client's native configuration format. Preserve every other setting and MCP server.
        Do not expose this server through LAN, tunneling, or public networking. It must stay bound to 127.0.0.1.
        Do not install dependencies or modify unrelated settings.
        After applying the configuration, verify that the wifi-lens MCP server is available and list its tools.
        If you cannot modify the client configuration directly, return the exact minimal configuration snippet and the manual step required.
        """
    }

    // MARK: - HTTP adapter (NWListener → StatelessHTTPServerTransport)

    private func handle(_ conn: NWConnection, transport: StatelessHTTPServerTransport) {
        conn.start(queue: .global(qos: .utility))
        receiveRequest(conn, transport: transport, accumulated: Data())
    }

    private func receiveRequest(
        _ conn: NWConnection, transport: StatelessHTTPServerTransport, accumulated: Data
    ) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else { conn.cancel(); return }
            var buf = accumulated
            buf.append(data)

            guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if buf.count < 65536 {
                    self.receiveRequest(conn, transport: transport, accumulated: buf)
                } else {
                    conn.cancel()
                }
                return
            }

            let headerData = buf[..<headerEnd.lowerBound]
            let afterHeaders = buf[headerEnd.upperBound...]

            guard let headerStr = String(data: headerData, encoding: .utf8) else { conn.cancel(); return }
            let lines = headerStr.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else { conn.cancel(); return }
            let parts = requestLine.components(separatedBy: " ")
            guard parts.count >= 2 else { conn.cancel(); return }
            let method = parts[0]
            let path = parts[1]

            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let colonIdx = line.firstIndex(of: ":") ?? line.startIndex
                let key = String(line[..<colonIdx]).lowercased()
                let valStart = line.index(colonIdx, offsetBy: 1)
                let value = valStart < line.endIndex
                    ? String(line[line.index(after: valStart)...]).trimmingCharacters(in: .whitespaces)
                    : ""
                headers[key] = value
            }

            let contentLength = Int(headers["content-length"] ?? "") ?? 0
            let bodySoFar = Data(afterHeaders)

            if bodySoFar.count >= contentLength {
                let body = bodySoFar.prefix(contentLength)
                self.processRequest(conn, transport: transport, method: method, path: path, headers: headers, body: body)
            } else {
                self.receiveBody(conn, transport: transport, method: method, path: path,
                                 headers: headers, bodySoFar: bodySoFar, contentLength: contentLength)
            }
        }
    }

    private func receiveBody(
        _ conn: NWConnection, transport: StatelessHTTPServerTransport,
        method: String, path: String, headers: [String: String],
        bodySoFar: Data, contentLength: Int
    ) {
        let remaining = contentLength - bodySoFar.count
        guard remaining > 0 else {
            processRequest(conn, transport: transport, method: method, path: path,
                           headers: headers, body: bodySoFar)
            return
        }
        conn.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { [weak self] data, _, _, error in
            guard let self else { conn.cancel(); return }
            if error != nil { conn.cancel(); return }
            var full = bodySoFar
            if let data { full.append(data) }
            self.processRequest(conn, transport: transport, method: method, path: path,
                                headers: headers, body: full.prefix(contentLength))
        }
    }

    private func processRequest(
        _ conn: NWConnection, transport: StatelessHTTPServerTransport,
        method: String, path: String, headers: [String: String], body: Data
    ) {
        let request = HTTPRequest(method: method, headers: headers,
                                   body: body.isEmpty ? nil : body, path: path)
        Task {
            let response = await transport.handleRequest(request)
            let raw = Self.serialize(response)
            conn.send(content: raw, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    // MARK: - HTTP response serialization

    private static func serialize(_ response: HTTPResponse) -> Data {
        let statusLine: String
        switch response.statusCode {
        case 200: statusLine = "HTTP/1.1 200 OK\r\n"
        case 202: statusLine = "HTTP/1.1 202 Accepted\r\n"
        case 400: statusLine = "HTTP/1.1 400 Bad Request\r\n"
        case 404: statusLine = "HTTP/1.1 404 Not Found\r\n"
        case 405: statusLine = "HTTP/1.1 405 Method Not Allowed\r\n"
        case 406: statusLine = "HTTP/1.1 406 Not Acceptable\r\n"
        case 415: statusLine = "HTTP/1.1 415 Unsupported Media Type\r\n"
        default:  statusLine = "HTTP/1.1 \(response.statusCode) Error\r\n"
        }

        let bodyData = response.bodyData ?? Data()
        var headerStr = statusLine
        for (key, value) in response.headers {
            headerStr += "\(key): \(value)\r\n"
        }
        headerStr += "Content-Length: \(bodyData.count)\r\n"
        headerStr += "\r\n"

        guard let headerData = headerStr.data(using: .ascii) else { return Data() }
        return headerData + bodyData
    }

    // MARK: - Tool dispatch

    static func handleCallTool(
        name: String, arguments: [String: Value]?, networks: [WiFiNetwork]
    ) -> CallTool.Result {
        handleCallTool(
            name: name,
            arguments: arguments,
            snapshot: MCPSnapshot(networks: networks)
        )
    }

    static func handleCallTool(
        name: String, arguments: [String: Value]?, snapshot: MCPSnapshot
    ) -> CallTool.Result {
        let networks = snapshot.networks
        switch name {
        case "scan_networks":
            var nets = networks
            if let bandArg = arguments?["band"]?.stringValue {
                nets = nets.filter { $0.channel.band.id == bandArg }
            }
            return .init(content: [.text(text: serializeNetworks(nets), annotations: nil, _meta: nil)])

        case "get_network_detail":
            guard let bssid = arguments?["bssid"]?.stringValue else {
                return .init(
                    content: [.text(text: #"{"error":"missing required parameter: bssid"}"#, annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            guard let nw = networks.first(where: { $0.bssid.caseInsensitiveCompare(bssid) == .orderedSame }) else {
                return .init(
                    content: [.text(text: #"{"error":"network not found"}"#, annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            return .init(content: [.text(text: serializeNetwork(nw, detail: true), annotations: nil, _meta: nil)])

        case "get_channel_occupancy":
            var bands: [String: [Int: Int]] = [:]
            for nw in networks {
                bands[nw.channel.band.id, default: [:]][nw.channel.channelNumber, default: 0] += 1
            }
            let dict = bands.mapValues { band in
                band.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value }
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
               let json = String(data: data, encoding: .utf8) {
                return .init(content: [.text(text: json, annotations: nil, _meta: nil)])
            }
            return .init(content: [.text(text: "{}", annotations: nil, _meta: nil)], isError: true)

        case "get_scan_metadata":
            return serializeMetadata(snapshot)

        default:
            return .init(
                content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    // MARK: - JSON helpers

    private static func serializeNetworks(_ nets: [WiFiNetwork]) -> String {
        let entries = nets.map { entryDict($0, detail: false) }
        guard JSONSerialization.isValidJSONObject(entries),
              let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func serializeNetwork(_ nw: WiFiNetwork, detail: Bool) -> String {
        let dict = entryDict(nw, detail: detail)
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func entryDict(_ nw: WiFiNetwork, detail: Bool) -> [String: Any] {
        let ie = nw.ieData.map { IEParser.parse(data: $0) }
        var dict: [String: Any] = [
            "ssid": nw.ssid ?? "n/a",
            "bssid": nw.bssid,
            "rssi": nw.rssi,
            "channel": nw.channel.channelNumber,
            "band": nw.channel.band.id,
            "channelWidthMHz": nw.channel.channelWidthMHz,
            "phyMode": ie.map { phyLabel($0) } ?? "",
            "channelWidth": ie.map { widthLabel($0) } ?? "",
            "supports80211k": ie?.supports80211k ?? false,
            "supports80211r": ie?.supports80211r ?? false,
            "supports80211v": ie?.supports80211v ?? false,
            "supports80211w": ie?.supports80211w ?? false,
            "supportsWPA3": ie?.supportsWPA3 ?? false,
            "isHiddenSSID": ie?.isHiddenSSID ?? false,
            "security": ie?.securitySummary ?? "",
            "mcs": ie?.mcsSummary ?? "",
            "nss": ie?.nssSummary ?? "",
            "country": ie?.countryCode ?? "",
        ]
        if detail {
            dict["isIBSS"] = nw.isIBSS
        }
        return dict
    }

    private static func phyLabel(_ ie: IEData) -> String {
        if ie.heSupported { return "ax" }
        if ie.vhtSupported { return "ac" }
        if ie.htSupported { return "n" }
        return ""
    }

    private static func widthLabel(_ ie: IEData) -> String {
        if ie.supports160MHz { return "160" }
        if ie.supports80MHz { return "80" }
        if ie.operating40MHz { return "40" }
        return ""
    }

    private static func serializeMetadata(_ snapshot: MCPSnapshot) -> CallTool.Result {
        var dict: [String: Any] = [
            "isScanning": snapshot.isScanning,
            "powerState": snapshot.powerState.rawValue,
            "accessState": snapshot.accessState.rawValue,
        ]

        if let capturedAt = snapshot.capturedAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            dict["capturedAt"] = formatter.string(from: capturedAt)
        }
        if let interfaceName = snapshot.interfaceName {
            dict["interfaceName"] = interfaceName
        }
        if !snapshot.supportedBands.isEmpty {
            dict["supportedBands"] = snapshot.supportedBands
        }
        if let scanIntervalSeconds = snapshot.scanIntervalSeconds {
            dict["scanIntervalSeconds"] = scanIntervalSeconds
        }

        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return .init(
                content: [.text(text: #"{"error":"metadata serialization failed"}"#, annotations: nil, _meta: nil)],
                isError: true
            )
        }
        return .init(content: [.text(text: json, annotations: nil, _meta: nil)])
    }
}
