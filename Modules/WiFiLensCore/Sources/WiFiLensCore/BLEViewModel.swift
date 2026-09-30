import CoreBluetooth
import Logging
import SwiftUI

@MainActor
@Observable
public final class BLEViewModel {
    private static let logger = Logger(label: "ble")
    private enum BluetoothStateChangeSource: String {
        case monitor = "monitor callback"
        case scanner = "scanner stream"
    }

    private let scanner: any BLEScanning
    let deviceTracker = BLEDeviceTracker()
    public let bluetoothPermission = BluetoothPermissionManager()
    let bluetoothPowerMonitor = BLEPowerMonitor()

    public private(set) var isScanning = false
    private(set) var bluetoothState: BLEBluetoothState = .unknown
    private(set) var devices: [BLEDeviceSnapshot] = []
    var selectedDeviceID: String?
    public private(set) var errorMessage: String?

    private var scanTask: Task<Void, Never>?
    private var bluetoothMonitoringTask: Task<Void, Never>?
    private var shouldResumeScanningAfterPowerRestore = false
    private var scanGeneration: UInt64 = 0
    private var scanSession: BLEScanSession?
    private let authorizationOverride: Bool?
    private let monitorsBluetoothPower: Bool

    var displayedDevices: [BLEDeviceSnapshot] {
        devices.sorted { $0.rssi > $1.rssi }
    }

    var selectedDevice: BLEDeviceSnapshot? {
        guard let id = selectedDeviceID else { return nil }
        return devices.first { $0.id == id }
    }

    var selectedDeviceHistory: [BLERSSISample]? {
        guard let id = selectedDeviceID,
              let uuid = UUID(uuidString: id) else { return nil }
        return deviceTracker.rssiHistory(for: uuid)
    }

    // MARK: - Actions

    public init(
        scanner: any BLEScanning = BLEScanner(),
        authorizationOverride: Bool? = nil,
        monitorsBluetoothPower: Bool = true
    ) {
        self.scanner = scanner
        self.authorizationOverride = authorizationOverride
        self.monitorsBluetoothPower = monitorsBluetoothPower
        bluetoothState = bluetoothPowerMonitor.currentState
        if monitorsBluetoothPower {
            startBluetoothMonitoring()
            bluetoothPowerMonitor.startMonitoring()
        }
    }

    func requestPermission() {
        bluetoothPermission.requestPermissionIfNeeded()
    }

    public func startScanning() async {
        guard !isScanning else { return }

        if monitorsBluetoothPower { bluetoothPowerMonitor.startMonitoring() }
        if authorizationOverride == nil { bluetoothPermission.refreshStatus() }
        guard authorizationOverride ?? bluetoothPermission.isAuthorized else {
            shouldResumeScanningAfterPowerRestore = false
            if bluetoothPermission.authorizationStatus == .notDetermined {
                bluetoothPermission.requestPermissionIfNeeded()
            }
            errorMessage = bluetoothPermission.authorizationStatus == .denied
                ? String(localized: "ble.permission.denied_message", comment: "Bluetooth permission denied error message")
                : String(localized: "ble.permission.required_message", comment: "Bluetooth permission required explanation")
            return
        }

        shouldResumeScanningAfterPowerRestore = true
        isScanning = true
        errorMessage = nil
        scanGeneration &+= 1
        let generation = scanGeneration

        let session = await scanner.startScanning()
        guard generation == scanGeneration, isScanning, !Task.isCancelled else {
            await session.stop()
            return
        }
        scanSession = session
        scanTask = Task { [weak self] in
            for await event in session.events {
                guard let self, generation == self.scanGeneration, !Task.isCancelled else { break }
                switch event {
                case .deviceBatch(let eventsByDevice):
                    devices = deviceTracker.processBatch(eventsByDevice)

                case .bluetoothStateChanged(let state):
                    await handleBluetoothStateChange(state, fromScanner: true)

                case .failure(let message):
                    errorMessage = message
                    Self.logger.error("scan failure: \(message)")
                }
            }
            guard let self, generation == self.scanGeneration else { return }
            self.scanTask = nil
            self.scanSession = nil
            self.isScanning = false
        }
    }

    public func stopScanning() {
        shouldResumeScanningAfterPowerRestore = false
        stopScanning(preserveResumeIntent: false)
    }

    private func stopScanning(preserveResumeIntent: Bool) {
        scanGeneration &+= 1
        isScanning = false
        scanTask?.cancel()
        scanTask = nil
        let session = scanSession
        scanSession = nil
        Task { await session?.stop() }
        if !preserveResumeIntent {
            shouldResumeScanningAfterPowerRestore = false
        }
    }

    private func startBluetoothMonitoring() {
        guard bluetoothMonitoringTask == nil else { return }

        bluetoothMonitoringTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.bluetoothPowerMonitor.events {
                await self.handleBluetoothStateChange(state, fromScanner: false)
            }
        }
    }

    private func handleBluetoothStateChange(_ state: BLEBluetoothState, fromScanner: Bool) async {
        let previousState = bluetoothState
        bluetoothState = state
        bluetoothPermission.refreshStatus()

        if previousState != state {
            let source = fromScanner ? BluetoothStateChangeSource.scanner : BluetoothStateChangeSource.monitor
            Self.logger.info("Bluetooth state changed [\(source.rawValue)]: \(previousState.logLabel) -> \(state.logLabel)")
        }

        switch state {
        case .poweredOn:
            errorMessage = nil
            if shouldResumeScanningAfterPowerRestore, !isScanning {
                Self.logger.info("Bluetooth scan resumed after power restored")
                await startScanning()
            }

        case .poweredOff, .resetting:
            if isScanning {
                Self.logger.warning("Bluetooth scan paused because adapter is \(state.logLabel)")
                stopScanning(preserveResumeIntent: true)
            }

        case .unauthorized:
            shouldResumeScanningAfterPowerRestore = false
            if isScanning {
                Self.logger.warning("Bluetooth scan stopped because authorization is unavailable")
                stopScanning(preserveResumeIntent: false)
            }
            errorMessage = String(localized: "ble.permission.required_with_action", comment: "Bluetooth permission required with action instruction")

        case .unsupported:
            shouldResumeScanningAfterPowerRestore = false
            if isScanning {
                Self.logger.error("Bluetooth scan stopped because hardware is unsupported")
                stopScanning(preserveResumeIntent: false)
            }
            errorMessage = String(localized: "ble.state.unsupported", comment: "BLE state: hardware does not support BLE")

        case .unknown:
            break
        }
    }

    nonisolated deinit {
        MainActor.assumeIsolated {
            // Defensive cleanup (NH-13): cancel in-flight tasks and stop the active
            // scan session so its idle-sleep activity token is released.
            scanTask?.cancel()
            scanTask = nil
            bluetoothMonitoringTask?.cancel()
            bluetoothMonitoringTask = nil
            let session = scanSession
            scanSession = nil
            if let session {
                Task { await session.stop() }
            }
        }
    }
}

final class BLEPowerMonitor: NSObject, CBCentralManagerDelegate {
    private var continuation: AsyncStream<BLEBluetoothState>.Continuation?
    private var centralManager: CBCentralManager?
    private(set) var currentState: BLEBluetoothState = .unknown

    var events: AsyncStream<BLEBluetoothState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(currentState)
        }
    }

    override init() {
        super.init()
    }

    func startMonitoring() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    deinit {
        centralManager?.delegate = nil
        centralManager = nil
    }

    private func updateState(from central: CBCentralManager) {
        let nextState: BLEBluetoothState = switch central.state {
        case .unknown:      .unknown
        case .resetting:    .resetting
        case .unsupported:  .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff:   .poweredOff
        case .poweredOn:    .poweredOn
        @unknown default:   .unknown
        }

        guard nextState != currentState else { return }
        currentState = nextState
        continuation?.yield(nextState)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateState(from: central)
    }
}

private extension BLEBluetoothState {
    var logLabel: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        case .unauthorized: return "unauthorized"
        }
    }
}
