import SwiftUI
import Foundation
import ChartLens

/// Shared, identity-free description of the Gaussian envelope used by every
/// spectrum presentation. Callers provide their canonical X coordinate space.
struct SpectrumEnvelopeGeometry: Equatable, Sendable {
    let leftX: Double
    let rightX: Double
    let peakRSSI: Double
    let baselineRSSI: Double

    var sigma: Double { (rightX - leftX) / 8.0 }

    var gaussian: GaussianEnvelope {
        GaussianEnvelope(
            leftX: leftX,
            rightX: rightX,
            peakY: peakRSSI,
            baselineY: baselineRSSI,
            sigma: sigma
        )
    }
}

public struct ChartSeriesDomainData: Identifiable {
    public let id: String
    public let ssid: String
    public let bssid: String
    public let channel: Int
    public let left: Int
    public let apex: Double
    public let right: Int
    public let rssi: Int
    public let phyMode: String
    public let channelWidth: String
    public let supportsK: Bool
    public let supportsR: Bool
    public let supportsV: Bool
    public let supportsWPA3: Bool
    public let isHiddenSSID: Bool
    public let security: String
    public let mcs: String
    public let nss: String
    public let country: String

    public init(id: String, ssid: String, bssid: String, channel: Int, left: Int, apex: Double, right: Int, rssi: Int, phyMode: String, channelWidth: String, supportsK: Bool, supportsR: Bool, supportsV: Bool, supportsWPA3: Bool, isHiddenSSID: Bool, security: String, mcs: String, nss: String, country: String) {
        self.id = id
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.left = left
        self.apex = apex
        self.right = right
        self.rssi = rssi
        self.phyMode = phyMode
        self.channelWidth = channelWidth
        self.supportsK = supportsK
        self.supportsR = supportsR
        self.supportsV = supportsV
        self.supportsWPA3 = supportsWPA3
        self.isHiddenSSID = isHiddenSSID
        self.security = security
        self.mcs = mcs
        self.nss = nss
        self.country = country
    }
}

public struct ChartSeriesRenderState {
    public var displayRSSI: Double = 0.0
    public var color: Color = .gray
    public var isFilteredOut: Bool = false
    public var isVisible: Bool = true
    public var visibilityLocked: Bool = false
    public var qualityScore: Int = 0
    public var trendArrow: String = ""
    public var trendDelta: Int = 0

    public init(displayRSSI: Double = 0.0, color: Color = .gray, isFilteredOut: Bool = false, isVisible: Bool = true, visibilityLocked: Bool = false, qualityScore: Int = 0, trendArrow: String = "", trendDelta: Int = 0) {
        self.displayRSSI = displayRSSI
        self.color = color
        self.isFilteredOut = isFilteredOut
        self.isVisible = isVisible
        self.visibilityLocked = visibilityLocked
        self.qualityScore = qualityScore
        self.trendArrow = trendArrow
        self.trendDelta = trendDelta
    }
}

public struct ChartSeriesData: Identifiable {
    public let domain: ChartSeriesDomainData
    public var render: ChartSeriesRenderState

    public init(domain: ChartSeriesDomainData, render: ChartSeriesRenderState = .init()) {
        self.domain = domain
        self.render = render
    }

    public init(
        id: String,
        ssid: String,
        bssid: String,
        channel: Int,
        left: Int,
        apex: Double,
        right: Int,
        rssi: Int,
        displayRSSI: Double = 0.0,
        color: Color = .gray,
        isFilteredOut: Bool = false,
        phyMode: String = "",
        channelWidth: String = "",
        supportsK: Bool = false,
        supportsR: Bool = false,
        supportsV: Bool = false,
        supportsWPA3: Bool = false,
        isHiddenSSID: Bool = false,
        security: String = "",
        mcs: String = "",
        nss: String = "",
        country: String = "",
        isVisible: Bool = true,
        visibilityLocked: Bool = false,
        qualityScore: Int = 0,
        trendArrow: String = "",
        trendDelta: Int = 0
    ) {
        self.domain = ChartSeriesDomainData(
            id: id,
            ssid: ssid,
            bssid: bssid,
            channel: channel,
            left: left,
            apex: apex,
            right: right,
            rssi: rssi,
            phyMode: phyMode,
            channelWidth: channelWidth,
            supportsK: supportsK,
            supportsR: supportsR,
            supportsV: supportsV,
            supportsWPA3: supportsWPA3,
            isHiddenSSID: isHiddenSSID,
            security: security,
            mcs: mcs,
            nss: nss,
            country: country
        )
        self.render = ChartSeriesRenderState(
            displayRSSI: displayRSSI,
            color: color,
            isFilteredOut: isFilteredOut,
            isVisible: isVisible,
            visibilityLocked: visibilityLocked,
            qualityScore: qualityScore,
            trendArrow: trendArrow,
            trendDelta: trendDelta
        )
    }

    public var id: String { domain.id }
    public var ssid: String { domain.ssid }
    public var bssid: String { domain.bssid }
    public var channel: Int { domain.channel }
    public var left: Int { domain.left }
    public var apex: Double { domain.apex }
    public var right: Int { domain.right }
    public var rssi: Int { domain.rssi }
    public var phyMode: String { domain.phyMode }
    public var channelWidth: String { domain.channelWidth }
    public var supportsK: Bool { domain.supportsK }
    public var supportsR: Bool { domain.supportsR }
    public var supportsV: Bool { domain.supportsV }
    public var supportsWPA3: Bool { domain.supportsWPA3 }
    public var isHiddenSSID: Bool { domain.isHiddenSSID }
    public var security: String { domain.security }
    public var mcs: String { domain.mcs }
    public var nss: String { domain.nss }
    public var country: String { domain.country }

    public var displayRSSI: Double {
        get { render.displayRSSI }
        set { render.displayRSSI = newValue }
    }

    public var color: Color {
        get { render.color }
        set { render.color = newValue }
    }

    public var isFilteredOut: Bool {
        get { render.isFilteredOut }
        set { render.isFilteredOut = newValue }
    }

    public var isVisible: Bool {
        get { render.isVisible }
        set { render.isVisible = newValue }
    }

    public var visibilityLocked: Bool {
        get { render.visibilityLocked }
        set { render.visibilityLocked = newValue }
    }

    public var qualityScore: Int {
        get { render.qualityScore }
        set { render.qualityScore = newValue }
    }

    public var trendArrow: String {
        get { render.trendArrow }
        set { render.trendArrow = newValue }
    }

    public var trendDelta: Int {
        get { render.trendDelta }
        set { render.trendDelta = newValue }
    }

    public var displaySSID: String { ssid.isEmpty ? "n/a" : ssid }

    public var curvePoints: [(x: Double, y: Double)] {
        gaussianEnvelope(peakY: Double(rssi)).sampledPoints(count: 81)
    }

    public var displayCurvePoints: [(x: Double, y: Double)] {
        gaussianEnvelope(peakY: displayRSSI).sampledPoints(count: 81)
    }

    private func gaussianEnvelope(peakY: Double) -> GaussianEnvelope {
        SpectrumEnvelopeGeometry(
            leftX: Double(left),
            rightX: Double(right),
            peakRSSI: peakY,
            baselineRSSI: Double(Constants.rssiNoiseFloor)
        ).gaussian
    }
}
