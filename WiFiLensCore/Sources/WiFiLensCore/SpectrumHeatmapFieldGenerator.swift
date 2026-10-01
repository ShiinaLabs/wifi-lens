import CoreGraphics
import Foundation

protocol SpectrumHeatmapFieldGenerating: Sendable {
    func generate(
        envelopes: [SpectrumHeatmapEnvelope],
        domain: SpectrumHeatmapChannelDomain,
        rssiRange: ClosedRange<Double>,
        resolution: SpectrumHeatmapResolution
    ) -> SpectrumHeatmapRaster
}

struct CPUHeatmapFieldGenerator: SpectrumHeatmapFieldGenerating, Sendable {
    init() {}

    func generate(
        envelopes: [SpectrumHeatmapEnvelope],
        domain: SpectrumHeatmapChannelDomain,
        rssiRange: ClosedRange<Double>,
        resolution: SpectrumHeatmapResolution
    ) -> SpectrumHeatmapRaster {
        let storageCount = resolution.storageCount
        guard storageCount > 0,
              domain.span > 0,
              rssiRange.lowerBound.isFinite,
              rssiRange.upperBound.isFinite,
              rssiRange.lowerBound <= rssiRange.upperBound else {
            return SpectrumHeatmapRaster(
                width: resolution.width,
                height: resolution.height,
                values: Array(repeating: 0, count: storageCount)
            )
        }

        let rect = CGRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        var values = Array(repeating: Float(0), count: storageCount)
        let parameters = SpectrumHeatmapFieldParameters.current

        for y in 0..<resolution.height {
            guard let rssi = SpectrumHeatmapLayout.rssi(
                forY: CGFloat(y) + 0.5,
                in: rect,
                rssiRange: rssiRange
            ) else { continue }

            for x in 0..<resolution.width {
                guard let channel = SpectrumHeatmapLayout.channelCoordinate(
                    forX: CGFloat(x) + 0.5,
                    domain: domain,
                    in: rect
                ) else { continue }

                var density = 0.0
                for envelope in envelopes {
                    guard channel >= envelope.leftX, channel <= envelope.rightX else { continue }
                    let gaussian = envelope.gaussian
                    let curve = gaussian.value(atX: channel)
                    let amplitude = max(0, gaussian.peakY - gaussian.baselineY)
                    guard amplitude > 0 else { continue }

                    // Keep the body tied to the same Gaussian support as the
                    // spectrum curve. This makes the filled field taper at
                    // both frequency edges instead of creating a rectangle.
                    let horizontalSupport = min(
                        1,
                        max(0, (curve - gaussian.baselineY) / amplitude)
                    )
                    guard horizontalSupport > 0 else { continue }

                    let depthDB = curve - rssi
                    if depthDB >= 0 {
                        let decay = exp(-depthDB / parameters.verticalDecayTauDB)
                        let profile = parameters.verticalBodyFloor
                            + (1 - parameters.verticalBodyFloor) * decay
                        density += horizontalSupport * profile
                    } else if depthDB >= -parameters.edgeFadeDB {
                        let edge = (depthDB + parameters.edgeFadeDB) / parameters.edgeFadeDB
                        density += horizontalSupport * smoothstep(edge)
                    }
                }

                let normalized = sqrt(max(0, min(density / parameters.normalizationDivisor, 1.0)))
                values[y * resolution.width + x] = Float(min(1, max(0, normalized)))
            }
        }

        return SpectrumHeatmapRaster(
            width: resolution.width,
            height: resolution.height,
            values: values
        )
    }

    private func smoothstep(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        return clamped * clamped * (3 - 2 * clamped)
    }

}
