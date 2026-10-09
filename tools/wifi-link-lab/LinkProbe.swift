import AppKit
import CoreWLAN
import Foundation
import Network
import SystemConfiguration
import Darwin

private let schemaVersion = 1
private let maximumRuntime: TimeInterval = 900
private let sampleInterval: TimeInterval = 0.5

private func utcTimestamp(_ date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

private func monotonicNanoseconds() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

private func optionalBool(_ value: Bool?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

private final class JSONLWriter {
    private let directory: URL
    private let lock = NSLock()
    private var handles: [String: FileHandle] = [:]

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["observations.jsonl", "events.jsonl", "markers.jsonl"] {
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handles[name] = try FileHandle(forWritingTo: url)
            try handles[name]?.seekToEnd()
        }
    }

    func append(_ record: [String: Any], to filename: String, synchronize: Bool = true) {
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .fragmentsAllowed]) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let handle = handles[filename] else { return }
        do {
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            if synchronize { try handle.synchronize() }
        } catch {
            fputs("Unable to append evidence.\n", stderr)
        }
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        for handle in handles.values { try? handle.synchronize() }
    }

    func close() {
        flush()
        lock.lock()
        defer { lock.unlock() }
        for handle in handles.values { try? handle.close() }
        handles.removeAll()
    }
}

private final class Tagger {
    private var ssidTags: [String: String] = [:]
    private var bssidTags: [String: String] = [:]

    func ssid(_ value: String?) -> (readable: Any, tag: Any) {
        guard let value else { return (false, NSNull()) }
        if value.isEmpty { return (true, NSNull()) }
        let tag = ssidTags[value] ?? "SSID-\(ssidTags.count + 1)"
        ssidTags[value] = tag
        return (true, tag)
    }

    func bssid(_ value: String?) -> (readable: Any, tag: Any) {
        guard let value else { return (false, NSNull()) }
        if value.isEmpty { return (true, NSNull()) }
        let tag = bssidTags[value] ?? "AP-\(bssidTags.count + 1)"
        bssidTags[value] = tag
        return (true, tag)
    }
}

private struct PathState {
    var status: String?
    var usesWiFi: Bool?
    var interfaceNames: [String]?
}

private struct InterfaceState {
    let enumerated: Bool?
    let up: Bool?
    let running: Bool?
    let ipv4: Bool?
    let ipv6: Bool?
    let conflict: Bool?
}

private struct EventObservation {
    let date: Date
    let monotonicNanoseconds: UInt64

    static func capture() -> EventObservation {
        EventObservation(date: Date(), monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
}

private final class Collector: NSObject, CWEventDelegate {
    private let writer: JSONLWriter
    private let outputURL: URL
    private let workQueue = DispatchQueue(label: "wifi-link-lab.collector")
    private let pathQueue = DispatchQueue(label: "wifi-link-lab.path")
    private let client = CWWiFiClient.shared()
    private let tagger = Tagger()
    private var timer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private var store: SCDynamicStore?
    private var registeredEvents: [CWEventType] = []
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var currentInterfaceName: String?
    private var hasReportedInterfaceState = false
    private var pathState = PathState(status: nil, usesWiFi: nil, interfaceNames: nil)
    private let pathLock = NSLock()
    private let lifecycleLock = NSLock()
    private var stopRequested = false
    private var finalized = false
    private var notificationSamplePending = false
    private var startedAt = Date()
    private var previousSampleStart: UInt64?
    private var signalSources: [DispatchSourceSignal] = []

    init(outputDirectory: URL) throws {
        outputURL = outputDirectory
        writer = try JSONLWriter(directory: outputDirectory)
        super.init()
    }

    func run() {
        client.delegate = self
        registerCoreWLANEvents()
        setupDynamicStore()
        setupPathMonitor()
        setupPowerNotifications()
        writeEnvironment()

        let source = DispatchSource.makeTimerSource(queue: workQueue)
        source.schedule(deadline: .now(), repeating: sampleInterval, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            guard let self, !self.isStopRequested else { return }
            self.sample(trigger: self.previousSampleStart == nil ? "startup" : "timer")
            if Date().timeIntervalSince(self.startedAt) >= maximumRuntime { self.stop() }
        }
        timer = source
        source.resume()

        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let signalSource = DispatchSource.makeSignalSource(signal: signalNumber, queue: DispatchQueue.global(qos: .utility))
            signalSource.setEventHandler { [weak self] in self?.stop() }
            signalSources.append(signalSource)
            signalSource.resume()
        }
        while !isFinalized {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private var isStopRequested: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return stopRequested
    }

    private var isFinalized: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return finalized
    }

    private func writeEnvironment() {
        let record: [String: Any] = [
            "schemaVersion": schemaVersion,
            "tool": "WiFiLens-LinkProbe",
            "runtime": "macOS",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "swiftVersion": "Swift",
            "sampleIntervalMilliseconds": Int(sampleInterval * 1000),
            "maximumRuntimeSeconds": Int(maximumRuntime),
            "startedAt": utcTimestamp(startedAt),
            "monotonicNanoseconds": monotonicNanoseconds()
        ]
        let url = writerDirectory().appendingPathComponent("environment.json")
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func writerDirectory() -> URL { outputURL }

    private func registerCoreWLANEvents() {
        let events: [(CWEventType, String)] = [
            (.powerDidChange, "powerDidChange"),
            (.ssidDidChange, "ssidDidChange"),
            (.bssidDidChange, "bssidDidChange"),
            (.linkDidChange, "linkDidChange"),
            (.modeDidChange, "modeDidChange")
        ]
        for (type, name) in events {
            var success = false
            var errorDomain: Any = NSNull()
            var errorCode: Any = NSNull()
            var errorDescription: Any = NSNull()
            do {
                try client.startMonitoringEvent(with: type)
                success = true
            } catch let failure as NSError {
                errorDomain = failure.domain
                errorCode = failure.code
                errorDescription = failure.localizedDescription
            } catch {
                errorDomain = "unknown"
                errorDescription = error.localizedDescription
            }
            if success { registeredEvents.append(type) }
            logEvent(source: "coreWLAN", eventType: "registration", interfaceName: nil,
                     fields: ["registeredEvent": name, "success": success,
                              "registrationStatus": success ? "registered" : "registrationDeniedOrUnavailable",
                              "errorDomain": errorDomain,
                              "errorCode": errorCode,
                              "errorDescription": errorDescription])
        }
    }

    private func setupDynamicStore() {
        var context = SCDynamicStoreContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, changedKeys, info in
            let observation = EventObservation.capture()
            guard let info else { return }
            let collector = Unmanaged<Collector>.fromOpaque(info).takeUnretainedValue()
            let keys = (changedKeys as? [String]) ?? []
            collector.enqueueEvent(source: "systemConfiguration", eventType: "dynamicStoreChanged",
                                   interfaceName: collector.activeInterfaceName(changedKeys: keys),
                                   fields: ["changedKeys": keys], observation: observation)
            collector.enqueueSample(trigger: "notification")
        }
        guard let createdStore = SCDynamicStoreCreate(nil, "WiFiLens-LinkProbe" as CFString, callback, &context) else {
            let code = SCError()
            logEvent(source: "systemConfiguration", eventType: "registration", interfaceName: nil,
                     fields: ["registeredEvent": "Link-IPv4-IPv6", "success": false,
                              "errorCode": code, "errorDescription": String(cString: SCErrorString(code))])
            return
        }
        store = createdStore
        let patterns = ["State:/Network/Interface/.*/Link", "State:/Network/Interface/.*/IPv4", "State:/Network/Interface/.*/IPv6"] as CFArray
        guard SCDynamicStoreSetNotificationKeys(createdStore, nil, patterns) else {
            let code = SCError()
            logEvent(source: "systemConfiguration", eventType: "registration", interfaceName: nil,
                     fields: ["registeredEvent": "Link-IPv4-IPv6", "success": false,
                              "errorCode": code, "errorDescription": String(cString: SCErrorString(code))])
            store = nil
            return
        }
        guard SCDynamicStoreSetDispatchQueue(createdStore, workQueue) else {
            let code = SCError()
            logEvent(source: "systemConfiguration", eventType: "registration", interfaceName: nil,
                     fields: ["registeredEvent": "Link-IPv4-IPv6", "success": false,
                              "errorCode": code, "errorDescription": String(cString: SCErrorString(code))])
            store = nil
            return
        }
        logEvent(source: "systemConfiguration", eventType: "registration", interfaceName: nil,
                 fields: ["registeredEvent": "Link-IPv4-IPv6", "success": true,
                          "errorCode": NSNull(), "errorDescription": NSNull()])
    }

    private func interfaceName(from key: String) -> String? {
        let parts = key.split(separator: "/")
        guard parts.count >= 4, parts[0] == "State:", parts[1] == "Network", parts[2] == "Interface" else { return nil }
        return String(parts[3])
    }

    private func activeInterfaceName(changedKeys: [String]) -> String? {
        guard let activeInterfaceName = currentInterfaceName else { return nil }
        return changedKeys.contains { interfaceName(from: $0) == activeInterfaceName } ? activeInterfaceName : nil
    }

    private func setupPathMonitor() {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { [weak self] path in
            let observation = EventObservation.capture()
            guard let self else { return }
            let interfaces = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map(\.name).sorted()
            let names = interfaces.isEmpty ? nil : interfaces
            let state = PathState(status: self.pathStatus(path.status), usesWiFi: path.usesInterfaceType(.wifi), interfaceNames: names)
            self.pathLock.lock()
            self.pathState = state
            self.pathLock.unlock()
            let uniqueInterfaceName = names?.count == 1 ? names?.first : nil
            self.enqueueEvent(source: "networkPath", eventType: "pathUpdate", interfaceName: uniqueInterfaceName,
                              fields: ["nwPathStatus": state.status as Any? ?? NSNull(),
                                       "nwPathUsesWiFi": state.usesWiFi.map { $0 as Any } ?? NSNull(),
                                       "nwPathInterfaceNames": names as Any? ?? NSNull(),
                                       "nwPathInterfaceNameAmbiguous": (names?.count ?? 0) > 1], observation: observation)
        }
        pathMonitor = monitor
        monitor.start(queue: pathQueue)
        logEvent(source: "networkPath", eventType: "registration", interfaceName: nil,
                 fields: ["registeredEvent": "requiredInterfaceType.wifi", "success": true])
    }

    private func pathStatus(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requiresConnection"
        @unknown default: return "unknown"
        }
    }

    private func setupPowerNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            self?.enqueueEvent(source: "appKit", eventType: "willSleep", interfaceName: nil, fields: [:])
            self?.enqueueSample(trigger: "notification")
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.enqueueEvent(source: "appKit", eventType: "didWake", interfaceName: nil, fields: [:])
            self?.enqueueSample(trigger: "notification")
        }
        logEvent(source: "appKit", eventType: "registration", interfaceName: nil,
                 fields: ["registeredEvent": "sleepWake", "success": true])
    }

    private func recordInterfaceState(_ latest: String?) {
        let previous = currentInterfaceName
        guard !hasReportedInterfaceState || latest != previous else { return }
        hasReportedInterfaceState = true
        currentInterfaceName = latest
        if let latest {
            logEvent(source: "coreWLAN", eventType: "interfaceChanged", interfaceName: latest,
                     fields: ["previousInterfaceName": previous as Any? ?? NSNull()])
        } else {
            logEvent(source: "coreWLAN", eventType: "interfaceUnavailable", interfaceName: nil,
                     fields: ["previousInterfaceName": previous as Any? ?? NSNull()])
        }
    }

    private func enqueueSample(trigger: String) {
        if trigger != "notification" {
            workQueue.async { [weak self] in
                guard let self, !self.isStopRequested else { return }
                self.sample(trigger: trigger)
            }
            return
        }

        lifecycleLock.lock()
        guard !stopRequested, !notificationSamplePending else {
            lifecycleLock.unlock()
            return
        }
        notificationSamplePending = true
        lifecycleLock.unlock()

        workQueue.async { [weak self] in
            guard let self else { return }
            self.lifecycleLock.lock()
            self.notificationSamplePending = false
            let shouldSample = !self.stopRequested
            self.lifecycleLock.unlock()
            guard shouldSample else { return }
            self.sample(trigger: trigger)
        }
    }

    private func enqueueEvent(source: String, eventType: String, interfaceName: String?, fields: [String: Any], observation: EventObservation = .capture()) {
        workQueue.async { [weak self] in
            self?.logEvent(source: source, eventType: eventType, interfaceName: interfaceName, fields: fields, observation: observation)
        }
    }

    private func sample(trigger: String) {
        guard !isStopRequested else { return }
        let startDate = Date()
        let startMonotonic = monotonicNanoseconds()
        let intervalSincePrevious = previousSampleStart.map { Double(startMonotonic - $0) / 1_000_000 }
        previousSampleStart = startMonotonic

        var errors: [String: Any] = [:]
        var durations: [String: Any] = [:]
        var interface: CWInterface?
        measure("interface", durations: &durations, errors: &errors) { interface = client.interface() }
        let name = interface?.interfaceName
        recordInterfaceState(name)

        var mode: Any = NSNull()
        var modeRaw: Any = NSNull()
        var power: Any = NSNull()
        var serviceActive: Any = NSNull()
        var ssidRead: Any = NSNull()
        var ssidTag: Any = NSNull()
        var bssidRead: Any = NSNull()
        var bssidTag: Any = NSNull()
        var channelRead: Any = NSNull()
        var channel: Any = NSNull()

        if let interface {
            measure("interfaceMode", durations: &durations, errors: &errors) {
                let value = interface.interfaceMode()
                modeRaw = value.rawValue
                mode = Self.modeName(value)
            }
            measure("powerOn", durations: &durations, errors: &errors) { power = interface.powerOn() }
            measure("serviceActive", durations: &durations, errors: &errors) { serviceActive = interface.serviceActive() }
            measure("ssid", durations: &durations, errors: &errors) {
                let tagged = tagger.ssid(interface.ssid())
                ssidRead = tagged.readable
                ssidTag = tagged.tag
            }
            measure("bssid", durations: &durations, errors: &errors) {
                let tagged = tagger.bssid(interface.bssid())
                bssidRead = tagged.readable
                bssidTag = tagged.tag
            }
            measure("wlanChannel", durations: &durations, errors: &errors) {
                if let value = interface.wlanChannel() {
                    channelRead = true
                    channel = value.channelNumber
                } else {
                    channelRead = false
                }
            }
        } else {
            errors["interface"] = "unavailable"
        }

        let systemStart = monotonicNanoseconds()
        let system = systemConfigurationState(interfaceName: name, errors: &errors)
        durations["systemConfiguration"] = Double(monotonicNanoseconds() - systemStart) / 1_000_000
        let flagsStart = monotonicNanoseconds()
        let interfaceState = interfaceFlags(interfaceName: name, errors: &errors)
        durations["interfaceFlags"] = Double(monotonicNanoseconds() - flagsStart) / 1_000_000
        pathLock.lock()
        let path = pathState
        pathLock.unlock()
        let endDate = Date()
        let endMonotonic = monotonicNanoseconds()
        let record: [String: Any] = [
            "schemaVersion": schemaVersion,
            "kind": "sample",
            "time": utcTimestamp(endDate),
            "monotonicNanoseconds": endMonotonic,
            "sampleStartedAt": utcTimestamp(startDate),
            "sampleEndedAt": utcTimestamp(endDate),
            "sampleStartMonotonicNanoseconds": startMonotonic,
            "sampleDurationMs": Double(endMonotonic - startMonotonic) / 1_000_000,
            "intervalSincePreviousSampleMs": intervalSincePrevious as Any? ?? NSNull(),
            "trigger": trigger,
            "interfaceName": name as Any? ?? NSNull(),
            "mode": mode,
            "modeRaw": modeRaw,
            "powerOnRaw": power,
            "serviceActiveRaw": serviceActive,
            "ssidReadable": ssidRead,
            "ssidTag": ssidTag,
            "bssidReadable": bssidRead,
            "bssidTag": bssidTag,
            "channelReadable": channelRead,
            "channel": channel,
            "callDurationsMs": durations,
            "scLinkKeyPresent": system.linkPresent,
            "scLinkActive": system.linkActive,
            "scLinkDetaching": system.linkDetaching,
            "scIPv4KeyPresent": system.ipv4Present,
            "scIPv6KeyPresent": system.ipv6Present,
            "interfaceEnumerated": interfaceState.enumerated as Any? ?? NSNull(),
            "interfaceUp": interfaceState.up as Any? ?? NSNull(),
            "interfaceRunning": interfaceState.running as Any? ?? NSNull(),
            "ipv4Present": interfaceState.ipv4 as Any? ?? NSNull(),
            "ipv6Present": interfaceState.ipv6 as Any? ?? NSNull(),
            "flagsConflict": interfaceState.conflict as Any? ?? NSNull(),
            "nwPathStatus": path.status as Any? ?? NSNull(),
            "nwPathUsesWiFi": path.usesWiFi.map { $0 as Any } ?? NSNull(),
            "nwPathInterfaceNames": path.interfaceNames as Any? ?? NSNull(),
            "errorsByField": errors
        ]
        writer.append(record, to: "observations.jsonl", synchronize: true)
    }

    private func measure(_ field: String, durations: inout [String: Any], errors: inout [String: Any], body: () -> Void) {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let end = DispatchTime.now().uptimeNanoseconds
        durations[field] = Double(end - start) / 1_000_000
        _ = errors
    }

    private func systemConfigurationState(interfaceName: String?, errors: inout [String: Any]) -> (linkPresent: Any, linkActive: Any, linkDetaching: Any, ipv4Present: Any, ipv6Present: Any) {
        guard let interfaceName, let store else {
            return (NSNull(), NSNull(), NSNull(), NSNull(), NSNull())
        }
        let base = "State:/Network/Interface/\(interfaceName)"
        func read(_ suffix: String) -> (value: CFPropertyList?, status: Int32) {
            let value = SCDynamicStoreCopyValue(store, "\(base)/\(suffix)" as CFString)
            return (value, value == nil ? SCError() : Int32(kSCStatusOK))
        }
        func presence(_ result: (value: CFPropertyList?, status: Int32), field: String) -> Any {
            if result.value != nil { return true }
            if result.status == Int32(kSCStatusNoKey) { return false }
            errors[field] = ["errorCode": result.status,
                             "errorDescription": String(cString: SCErrorString(result.status))]
            return NSNull()
        }
        let linkResult = read("Link")
        let ipv4Result = read("IPv4")
        let ipv6Result = read("IPv6")
        let link = linkResult.value as? [String: Any]
        let linkPresence = presence(linkResult, field: "systemConfiguration.Link")
        let ipv4Presence = presence(ipv4Result, field: "systemConfiguration.IPv4")
        let ipv6Presence = presence(ipv6Result, field: "systemConfiguration.IPv6")
        if let link {
            return (linkPresence, link["Active"] as? Bool as Any? ?? NSNull(),
                    link["Detaching"] as? Bool as Any? ?? NSNull(), ipv4Presence, ipv6Presence)
        }
        return (linkPresence, NSNull(), NSNull(), ipv4Presence, ipv6Presence)
    }

    private func interfaceFlags(interfaceName: String?, errors: inout [String: Any]) -> InterfaceState {
        guard let interfaceName else { return InterfaceState(enumerated: nil, up: nil, running: nil, ipv4: nil, ipv6: nil, conflict: nil) }
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else {
            errors["getifaddrs"] = "failed"
            return InterfaceState(enumerated: nil, up: nil, running: nil, ipv4: nil, ipv6: nil, conflict: nil)
        }
        defer { freeifaddrs(addressList) }
        var matching = [(up: Bool, running: Bool, ipv4: Bool, ipv6: Bool)]()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let entry = item.pointee
            if let address = entry.ifa_name, String(cString: address) == interfaceName {
                let flags = Int32(entry.ifa_flags)
                let family = entry.ifa_addr.map { Int32($0.pointee.sa_family) }
                matching.append((flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                                 family == AF_INET, family == AF_INET6))
            }
            cursor = entry.ifa_next
        }
        guard !matching.isEmpty else {
            return InterfaceState(enumerated: false, up: nil, running: nil, ipv4: false, ipv6: false, conflict: false)
        }
        func consistent(_ values: [Bool]) -> (value: Bool?, conflict: Bool) {
            let unique = Set(values)
            let conflict = unique.count > 1
            return (conflict ? nil : unique.first, conflict)
        }
        let up = consistent(matching.map(\.up))
        let running = consistent(matching.map(\.running))
        let conflict = up.conflict || running.conflict
        return InterfaceState(enumerated: true, up: up.value, running: running.value,
                              ipv4: matching.contains(where: \.ipv4), ipv6: matching.contains(where: \.ipv6), conflict: conflict)
    }

    private func logEvent(source: String, eventType: String, interfaceName: String?, fields: [String: Any], observation: EventObservation = .capture()) {
        var record: [String: Any] = [
            "schemaVersion": schemaVersion,
            "kind": "event",
            "source": source,
            "eventType": eventType,
            "time": utcTimestamp(observation.date),
            "monotonicNanoseconds": observation.monotonicNanoseconds,
            "interfaceName": interfaceName as Any? ?? NSNull()
        ]
        for (key, value) in fields { record[key] = value }
        writer.append(record, to: "events.jsonl", synchronize: true)
    }

    private func measureEvent(_ eventType: String, interfaceName: String?) {
        enqueueEvent(source: "coreWLAN", eventType: eventType, interfaceName: interfaceName, fields: [:])
        enqueueSample(trigger: "notification")
    }

    private func stop() {
        lifecycleLock.lock()
        guard !stopRequested else {
            lifecycleLock.unlock()
            return
        }
        stopRequested = true
        lifecycleLock.unlock()
        workQueue.async { [weak self] in self?.finalizeStop() }
    }

    private func finalizeStop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        for source in signalSources { source.cancel() }
        signalSources.removeAll()
        pathMonitor?.pathUpdateHandler = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        if let store { SCDynamicStoreSetDispatchQueue(store, nil) }
        store = nil
        client.delegate = nil
        for type in registeredEvents {
            var success = false
            var errorDomain: Any = NSNull()
            var errorCode: Any = NSNull()
            var errorDescription: Any = NSNull()
            do {
                try client.stopMonitoringEvent(with: type)
                success = true
            } catch let failure as NSError {
                errorDomain = failure.domain
                errorCode = failure.code
                errorDescription = failure.localizedDescription
            } catch {
                errorDomain = "unknown"
                errorDescription = error.localizedDescription
            }
            logEvent(source: "coreWLAN", eventType: "unregistration", interfaceName: nil,
                     fields: ["success": success, "eventTypeRaw": type.rawValue,
                              "errorDomain": errorDomain, "errorCode": errorCode,
                              "errorDescription": errorDescription])
        }
        registeredEvents.removeAll()
        let center = NSWorkspace.shared.notificationCenter
        if let sleepObserver { center.removeObserver(sleepObserver); self.sleepObserver = nil }
        if let wakeObserver { center.removeObserver(wakeObserver); self.wakeObserver = nil }
        writer.append(["schemaVersion": schemaVersion, "kind": "event", "source": "collector", "eventType": "stopped",
                       "time": utcTimestamp(), "monotonicNanoseconds": monotonicNanoseconds(), "interfaceName": NSNull()],
                      to: "events.jsonl", synchronize: true)
        writer.close()
        lifecycleLock.lock()
        finalized = true
        lifecycleLock.unlock()
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }


    private static func modeName(_ mode: CWInterfaceMode) -> String {
        switch mode.rawValue {
        case 0: return "none"
        case 1: return "station"
        case 2: return "ibss"
        case 3: return "hostAP"
        default: return "unknown"
        }
    }

    func clientConnectionInterrupted() {
        enqueueEvent(source: "coreWLAN", eventType: "clientConnectionInterrupted", interfaceName: nil, fields: [:])
        enqueueSample(trigger: "notification")
    }

    func clientConnectionInvalidated() {
        enqueueEvent(source: "coreWLAN", eventType: "clientConnectionInvalidated", interfaceName: nil, fields: [:])
        enqueueSample(trigger: "notification")
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { measureEvent("powerDidChange", interfaceName: interfaceName) }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { measureEvent("ssidDidChange", interfaceName: interfaceName) }
    func bssidDidChangeForWiFiInterface(withName interfaceName: String) { measureEvent("bssidDidChange", interfaceName: interfaceName) }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { measureEvent("linkDidChange", interfaceName: interfaceName) }
    func modeDidChangeForWiFiInterface(withName interfaceName: String) { measureEvent("modeDidChange", interfaceName: interfaceName) }
}

let outputPath = CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
do {
    let collector = try Collector(outputDirectory: outputURL)
    collector.run()
} catch {
    fputs("Unable to initialize collector.\n", stderr)
    exit(1)
}
