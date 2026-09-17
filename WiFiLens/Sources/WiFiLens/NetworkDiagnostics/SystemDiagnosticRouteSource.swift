import Darwin
import Foundation

enum DiagnosticRouteParser {
    private static let recognizedFields = ["destination", "gateway", "interface", "flags", "mask"]
    private static let unsupportedInterfacePrefixes = [
        "lo", "utun", "ipsec", "ppp", "tun", "tap", "bridge", "gif", "stf"
    ]

    static func parse(
        output: String,
        interfaceIndices: [String: UInt32]
    ) -> DiagnosticRouteSelection {
        var fields: [String: String] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard recognizedFields.contains(key) else { continue }
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard fields[key] == nil else { return .ambiguous }
            fields[key] = value
        }

        guard let destination = fields["destination"], destination == "default",
              let interfaceName = fields["interface"], !interfaceName.isEmpty,
              let flags = fields["flags"], !flags.isEmpty else {
            return .unavailable
        }

        guard hasUpFlag(flags),
              let interfaceIndex = interfaceIndices[interfaceName], interfaceIndex != 0 else {
            return .unavailable
        }

        if DiagnosticRouteInterface.isTunnel(interfaceName) {
            return .tunneled(.init(
                interfaceName: interfaceName,
                interfaceIndex: interfaceIndex
            ))
        }

        guard let gateway = fields["gateway"], !gateway.isEmpty,
              hasRequiredFlags(flags) else {
            return .unavailable
        }
        if isLinkLayerAddress(gateway) {
            return .unsupported
        }
        guard isUnicastIPv4(gateway) else { return .unavailable }
        if unsupportedInterfacePrefixes.contains(where: { interfaceName.hasPrefix($0) }) {
            return .unsupported
        }

        return .selected(.init(
            interfaceName: interfaceName,
            interfaceIndex: interfaceIndex,
            address: gateway
        ))
    }

    private static func hasRequiredFlags(_ flags: String) -> Bool {
        let normalized = flags
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let flagSet = Set(normalized)
        return flagSet.contains("UP") && flagSet.contains("GATEWAY")
    }

    private static func hasUpFlag(_ flags: String) -> Bool {
        let normalized = flags
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Set(normalized).contains("UP")
    }

    private static func isLinkLayerAddress(_ address: String) -> Bool {
        address.lowercased().hasPrefix("link#") || address.contains("#")
    }

    private static func isUnicastIPv4(_ address: String) -> Bool {
        var value = in_addr()
        let result = address.withCString { pointer in
            inet_pton(AF_INET, pointer, &value)
        }
        guard result == 1 else { return false }

        let bytes = withUnsafeBytes(of: value.s_addr) { Array($0) }
        guard bytes.count == 4 else { return false }
        let first = bytes[0]
        let isUnspecified = bytes.allSatisfy { $0 == 0 }
        let isLoopback = first == 127
        let isMulticast = (224...239).contains(first)
        let isBroadcast = bytes.allSatisfy { $0 == 255 }
        return !isUnspecified && !isLoopback && !isMulticast && !isBroadcast
    }
}

enum DiagnosticIPv6RouteParser {
    private static let recognizedFields = ["destination", "interface", "flags", "mask"]

    static func parse(
        output: String,
        interfaceIndices: [String: UInt32]
    ) -> DiagnosticIPv6RouteTarget? {
        var fields: [String: String] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard recognizedFields.contains(key) else { continue }
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard fields[key] == nil else { return nil }
            fields[key] = value
        }

        guard fields["destination"] == "::",
              fields["mask"] == "default",
              let interfaceName = fields["interface"],
              !interfaceName.isEmpty,
              let flags = fields["flags"],
              hasUpFlag(flags),
              let interfaceIndex = interfaceIndices[interfaceName],
              interfaceIndex != 0 else {
            return nil
        }

        return DiagnosticIPv6RouteTarget(
            interfaceName: interfaceName,
            interfaceIndex: interfaceIndex
        )
    }

    private static func hasUpFlag(_ flags: String) -> Bool {
        let normalized = flags
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Set(normalized).contains("UP")
    }
}

struct SystemDiagnosticRouteSource: DiagnosticRouteSourcing {
    private static let executablePath = "/sbin/route"
    private static let arguments = ["-n", "get", "-inet", "default"]
    private static let outputLimit = 16 * 1024

    func currentRoute(timeout: Duration) async -> DiagnosticRouteSelection {
        let interfaceIndices = await interfaceIndices()
        let execution = DiagnosticRouteProcessExecution(
            executablePath: Self.executablePath,
            arguments: Self.arguments,
            environment: ["LC_ALL": "C"],
            outputLimit: Self.outputLimit
        )
        let result = await withTaskCancellationHandler {
            await execution.run(timeout: timeout)
        } onCancel: {
            execution.cancel()
        }

        guard result.exitCode == 0, !result.timedOut, !result.cancelled else {
            return .unavailable
        }
        return DiagnosticRouteParser.parse(
            output: result.stdout,
            interfaceIndices: interfaceIndices
        )
    }

    private func interfaceIndices() async -> [String: UInt32] {
        await Task.detached(priority: .utility) {
            Dictionary(
                uniqueKeysWithValues: NetworkInfoService.fetchAll().compactMap { interface in
                    let index = if_nametoindex(interface.interfaceName)
                    guard index != 0 else { return nil }
                    return (interface.interfaceName, index)
                }
            )
        }.value
    }
}

struct SystemDiagnosticIPv6RouteSource: DiagnosticIPv6RouteSourcing {
    private static let executablePath = "/sbin/route"
    private static let arguments = ["-n", "get", "-inet6", "default"]
    private static let outputLimit = 16 * 1024

    func currentIPv6Route(timeout: Duration) async -> DiagnosticIPv6RouteTarget? {
        let interfaceIndices = await interfaceIndices()
        let execution = DiagnosticRouteProcessExecution(
            executablePath: Self.executablePath,
            arguments: Self.arguments,
            environment: ["LC_ALL": "C"],
            outputLimit: Self.outputLimit
        )
        let result = await withTaskCancellationHandler {
            await execution.run(timeout: timeout)
        } onCancel: {
            execution.cancel()
        }

        guard result.exitCode == 0, !result.timedOut, !result.cancelled else {
            return nil
        }
        return DiagnosticIPv6RouteParser.parse(
            output: result.stdout,
            interfaceIndices: interfaceIndices
        )
    }

    private func interfaceIndices() async -> [String: UInt32] {
        await Task.detached(priority: .utility) {
            Dictionary(
                uniqueKeysWithValues: NetworkInfoService.fetchAll().compactMap { interface in
                    let index = if_nametoindex(interface.interfaceName)
                    guard index != 0 else { return nil }
                    return (interface.interfaceName, index)
                }
            )
        }.value
    }
}

struct DiagnosticRouteProcessResult: Sendable {
    let exitCode: Int32?
    let stdout: String
    let stderr: String
    let timedOut: Bool
    let cancelled: Bool
}

final class DiagnosticRouteProcessExecution: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let outputLimit: Int
    private let timeoutQueue = DispatchQueue(
        label: "com.shiinalabs.wifi-lens.diagnostic-route-timeout",
        qos: .utility
    )
    private var continuation: CheckedContinuation<DiagnosticRouteProcessResult, Never>?
    private var timeoutSource: DispatchSourceTimer?
    private var didFinish = false

    init(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        outputLimit: Int
    ) {
        process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        var inheritedEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { inheritedEnvironment[$0.key] = $0.value }
        process.environment = inheritedEnvironment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.outputLimit = outputLimit
    }

    func run(timeout: Duration) async -> DiagnosticRouteProcessResult {
        let result = await withCheckedContinuation { continuation in
            lock.lock()
            if didFinish {
                lock.unlock()
                continuation.resume(returning: DiagnosticRouteProcessResult(
                    exitCode: nil,
                    stdout: "",
                    stderr: "",
                    timedOut: false,
                    cancelled: true
                ))
            } else {
                self.continuation = continuation
                let timeoutSource = DispatchSource.makeTimerSource(queue: timeoutQueue)
                timeoutSource.schedule(
                    deadline: .now() + Self.dispatchInterval(for: timeout),
                    leeway: .milliseconds(1)
                )
                timeoutSource.setEventHandler { [weak self] in
                    self?.finish(timedOut: true, cancelled: false)
                }
                timeoutSource.resume()
                self.timeoutSource = timeoutSource
                lock.unlock()
                DispatchQueue.global(qos: .utility).async { [self] in
                    execute()
                }
            }
        }
        return result
    }

    func cancel() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        let continuation = self.continuation
        self.continuation = nil
        let timeoutSource = self.timeoutSource
        self.timeoutSource = nil
        didFinish = true
        lock.unlock()

        timeoutSource?.setEventHandler {}
        timeoutSource?.cancel()

        if process.isRunning {
            process.terminate()
        }

        continuation?.resume(returning: .init(
            exitCode: nil,
            stdout: "",
            stderr: "",
            timedOut: false,
            cancelled: true
        ))
    }

    private func execute() {
        guard !isFinished() else { return }
        do {
            try process.run()
        } catch {
            finish(timedOut: false, cancelled: false)
            return
        }

        if isFinished(), process.isRunning {
            process.terminate()
        }

        process.waitUntilExit()
        finish(timedOut: false, cancelled: false)
    }

    private func finish(timedOut: Bool, cancelled: Bool) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = self.continuation
        self.continuation = nil
        let timeoutSource = self.timeoutSource
        self.timeoutSource = nil
        lock.unlock()

        timeoutSource?.setEventHandler {}
        timeoutSource?.cancel()

        let shouldStop = timedOut || cancelled
        if shouldStop, process.isRunning {
            process.terminate()
        }

        let exitCode = shouldStop || process.isRunning ? nil : process.terminationStatus
        let stdout = shouldStop ? "" : read(pipe: stdoutPipe.fileHandleForReading)
        let stderr = shouldStop ? "" : read(pipe: stderrPipe.fileHandleForReading)

        continuation?.resume(returning: .init(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut,
            cancelled: cancelled
        ))
    }

    private func isFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFinish
    }

    private func read(pipe: FileHandle) -> String {
        let data = pipe.readDataToEndOfFile()
        let limited = data.prefix(outputLimit)
        return String(data: limited, encoding: .utf8) ?? ""
    }

    private static func dispatchInterval(for duration: Duration) -> DispatchTimeInterval {
        let components = duration.components
        let nanoseconds = Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000
        let clamped = min(max(nanoseconds, 0), Double(Int.max))
        return .nanoseconds(Int(clamped))
    }
}
