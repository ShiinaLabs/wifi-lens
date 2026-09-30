import Foundation
import Observation
import SplitView
import WiFiLensCore

struct SpectrumPanelID: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: String { rawValue }

    static let primary = SpectrumPanelID(rawValue: "primary")
    static let secondary = SpectrumPanelID(rawValue: "secondary")
    static let tertiary = SpectrumPanelID(rawValue: "tertiary")
}

enum SpectrumPanelViewType: String, CaseIterable, Identifiable, Codable, Sendable {
    case spectrum = "spectrum"
    case trend = "trend"
    case table = "table"
    case heatmap = "heatmap"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spectrum: return String(localized: "nav.spectrum", comment: "Spectrum chart label in the spectrum panel")
        case .trend: return String(localized: "spectrum.panel.trend", comment: "Trend chart label in spectrum panel")
        case .table: return String(localized: "spectrum.panel.table", comment: "Table view label in spectrum panel")
        case .heatmap: return String(localized: "spectrum.panel.heatmap", comment: "Heatmap label in spectrum panel")
        }
    }

    var icon: String {
        switch self {
        case .spectrum: return "wave.3.left"
        case .trend: return "chart.line.uptrend.xyaxis"
        case .table: return "tablecells"
        case .heatmap: return "square.grid.3x3.fill"
        }
    }
}

struct SpectrumPanelDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: SpectrumPanelID
    var viewType: SpectrumPanelViewType
    var band: ChannelBand

    private enum CodingKeys: String, CodingKey {
        case id
        case viewType
        case band
    }

    init(id: SpectrumPanelID, viewType: SpectrumPanelViewType, band: ChannelBand) {
        self.id = id
        self.viewType = viewType
        self.band = band
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SpectrumPanelID.self, forKey: .id)
        viewType = try container.decode(SpectrumPanelViewType.self, forKey: .viewType)

        let bandID = try container.decode(String.self, forKey: .band)
        guard let band = ChannelBand(id: bandID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .band,
                in: container,
                debugDescription: "Unsupported channel band identifier: \(bandID)"
            )
        }
        self.band = band
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(viewType, forKey: .viewType)
        try container.encode(band.id, forKey: .band)
    }
}

@MainActor @Observable final class SpectrumDashboardState {
    nonisolated static let minimumPanelCount = 1
    nonisolated static let maximumPanelCount = 6
    nonisolated static let persistenceKey = "spectrum.dashboard.panels"

    static let defaultPanels = [
        SpectrumPanelDescriptor(id: .primary, viewType: .spectrum, band: .band24GHz),
        SpectrumPanelDescriptor(id: .secondary, viewType: .spectrum, band: .band5GHz),
        SpectrumPanelDescriptor(id: .tertiary, viewType: .table, band: .band24GHz)
    ]

    private static let persistenceVersion = 1

    private struct PersistedPayload: Codable {
        let version: Int
        let panels: [SpectrumPanelDescriptor]
    }

    private(set) var panels: [SpectrumPanelDescriptor]

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let persistenceEnabled: Bool
    @ObservationIgnored private var splitFractionHolders: [String: FractionHolder] = [:]

    init(
        userDefaults: UserDefaults = .standard,
        initialPanels: [SpectrumPanelDescriptor]? = nil,
        persistenceEnabled: Bool = true
    ) {
        let loadedPanels = persistenceEnabled ? Self.loadPanels(from: userDefaults) : nil
        self.userDefaults = userDefaults
        self.persistenceEnabled = persistenceEnabled
        self.panels = loadedPanels ?? initialPanels ?? Self.defaultPanels
        reconcileFractionHolders()

        if persistenceEnabled && loadedPanels == nil {
            persist()
        }
    }

    @discardableResult
    func addPanel(defaultBand: ChannelBand = .band24GHz) -> SpectrumPanelID? {
        guard panels.count < Self.maximumPanelCount else { return nil }

        let id = SpectrumPanelID(rawValue: "panel-\(UUID().uuidString)")
        panels.append(SpectrumPanelDescriptor(id: id, viewType: .spectrum, band: defaultBand))
        reconcileFractionHolders()
        persist()
        return id
    }

    @discardableResult
    func removePanel(id: SpectrumPanelID) -> Bool {
        guard panels.count > Self.minimumPanelCount,
              let index = panels.firstIndex(where: { $0.id == id }) else {
            return false
        }

        panels.remove(at: index)
        reconcileFractionHolders()
        persist()
        return true
    }

    func updatePanel(_ descriptor: SpectrumPanelDescriptor) {
        guard let index = panels.firstIndex(where: { $0.id == descriptor.id }) else { return }
        panels[index] = descriptor
        persist()
    }

    func fractionHolder(
        topID: SpectrumPanelID,
        bottomID: SpectrumPanelID,
        defaultFraction: CGFloat
    ) -> FractionHolder {
        let key = Self.boundaryKey(topID: topID, bottomID: bottomID)
        return splitFractionHolders[key] ?? FractionHolder(defaultFraction)
    }

    nonisolated static func boundaryKey(topID: SpectrumPanelID, bottomID: SpectrumPanelID) -> String {
        "\(topID.rawValue)->\(bottomID.rawValue)"
    }

    private func reconcileFractionHolders() {
        let previous = splitFractionHolders
        var reconciled: [String: FractionHolder] = [:]

        for pair in zip(panels, panels.dropFirst()) {
            let key = Self.boundaryKey(topID: pair.0.id, bottomID: pair.1.id)
            if let holder = previous[key] {
                reconciled[key] = holder
                continue
            }

            let defaultFraction = 1.0 / CGFloat(max(panels.count, Self.minimumPanelCount))
            let defaults = userDefaults
            let fractionKey = Self.fractionPersistenceKey(for: key)
            let shouldPersist = persistenceEnabled
            let initialFraction = shouldPersist
                ? Self.storedFraction(from: defaults, key: fractionKey, fallback: defaultFraction)
                : defaultFraction
            let holder = FractionHolder(
                initialFraction,
                getter: {
                    guard shouldPersist else { return defaultFraction }
                    return Self.storedFraction(from: defaults, key: fractionKey, fallback: defaultFraction)
                },
                setter: { fraction in
                    guard shouldPersist else { return }
                    let clampedFraction = min(max(fraction, 0.05), 0.95)
                    defaults.set(Double(clampedFraction), forKey: fractionKey)
                }
            )
            reconciled[key] = holder
        }

        splitFractionHolders = reconciled
    }

    private func persist() {
        guard persistenceEnabled else { return }
        let payload = PersistedPayload(version: Self.persistenceVersion, panels: panels)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: Self.persistenceKey)
    }

    private static func loadPanels(from userDefaults: UserDefaults) -> [SpectrumPanelDescriptor]? {
        guard let data = userDefaults.data(forKey: persistenceKey),
              let payload = try? JSONDecoder().decode(PersistedPayload.self, from: data),
              payload.version == persistenceVersion,
              payload.panels.count >= minimumPanelCount,
              payload.panels.count <= maximumPanelCount else {
            return nil
        }

        let ids = payload.panels.map(\.id)
        guard ids.allSatisfy({ !$0.rawValue.isEmpty }), Set(ids).count == ids.count else {
            return nil
        }
        return payload.panels
    }

    private static func fractionPersistenceKey(for boundaryKey: String) -> String {
        "spectrum.dashboard.fraction.\(boundaryKey)"
    }

    private static func storedFraction(from defaults: UserDefaults, key: String, fallback: CGFloat) -> CGFloat {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return fallback }
        let value = CGFloat(number.doubleValue)
        guard value.isFinite else { return fallback }
        return min(max(value, 0.05), 0.95)
    }
}
