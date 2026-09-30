import Foundation

struct SpectrumHeatmapFieldParameters: Equatable, Sendable {
    static let current = SpectrumHeatmapFieldParameters(
        verticalDecayTauDB: 10.0,
        verticalBodyFloor: 0.12,
        edgeFadeDB: 3.0,
        normalizationDivisor: 4.0
    )

    let verticalDecayTauDB: Double
    let verticalBodyFloor: Double
    let edgeFadeDB: Double
    let normalizationDivisor: Double
}

struct SpectrumHeatmapComputeInput: Equatable, Sendable {
    let envelopes: [SpectrumHeatmapEnvelope]
    let domain: SpectrumHeatmapChannelDomain
    let rssiRange: ClosedRange<Double>
    let resolution: SpectrumHeatmapResolution

    var isValid: Bool {
        resolution.storageCount > 0
            && domain.span > 0
            && rssiRange.lowerBound.isFinite
            && rssiRange.upperBound.isFinite
            && rssiRange.lowerBound <= rssiRange.upperBound
    }
}

enum SpectrumHeatmapBackendKind: Equatable, Sendable {
    case cpu
    case metal
}

/// Selects the compute backend once for a render worker lifetime. The factory
/// is injectable so fallback behavior can be tested without depending on the
/// host GPU or Metal library loading.
struct SpectrumHeatmapComputeBackendFactory: Sendable {
    private let metalFactory: @Sendable () -> (any SpectrumHeatmapComputeBackend)?

    init(
        metalFactory: @escaping @Sendable () -> (any SpectrumHeatmapComputeBackend)?
    ) {
        self.metalFactory = metalFactory
    }

    static let live = SpectrumHeatmapComputeBackendFactory {
        MetalHeatmapComputeBackend()
    }

    func makeBackend() -> any SpectrumHeatmapComputeBackend {
        metalFactory() ?? CPUHeatmapComputeBackend()
    }
}

protocol SpectrumHeatmapComputeBackend: Sendable {
    var kind: SpectrumHeatmapBackendKind { get }

    func compute(
        _ input: SpectrumHeatmapComputeInput
    ) async throws -> SpectrumHeatmapRaster
}

struct CPUHeatmapComputeBackend: SpectrumHeatmapComputeBackend, Sendable {
    let kind: SpectrumHeatmapBackendKind = .cpu

    init() {}

    func compute(
        _ input: SpectrumHeatmapComputeInput
    ) async throws -> SpectrumHeatmapRaster {
        let raw = CPUHeatmapFieldGenerator().generate(
            envelopes: input.envelopes,
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )
        return SpectrumHeatmapRasterizer.smooth(raw, domain: input.domain)
    }
}

struct SpectrumHeatmapMetalEnvelope: Equatable, Sendable {
    var geometry: SIMD4<Float>

    init(envelope: SpectrumHeatmapEnvelope) {
        geometry = SIMD4(
            Float(envelope.leftX),
            Float(envelope.rightX),
            Float(envelope.peakRSSI),
            Float(envelope.baselineRSSI)
        )
    }
}

struct SpectrumHeatmapMetalParameters: Equatable, Sendable {
    var domainAndRSSI: SIMD4<Float>
    var raster: SIMD4<UInt32>
    var field: SIMD4<Float>

    init(input: SpectrumHeatmapComputeInput) {
        let parameters = SpectrumHeatmapFieldParameters.current
        domainAndRSSI = SIMD4(
            Float(input.domain.minChannelCoordinate),
            Float(input.domain.maxChannelCoordinate),
            Float(input.rssiRange.lowerBound),
            Float(input.rssiRange.upperBound)
        )
        raster = SIMD4(
            UInt32(clamping: input.resolution.width),
            UInt32(clamping: input.resolution.height),
            UInt32(clamping: input.envelopes.count),
            0
        )
        field = SIMD4(
            Float(parameters.verticalDecayTauDB),
            Float(parameters.verticalBodyFloor),
            Float(parameters.edgeFadeDB),
            Float(parameters.normalizationDivisor)
        )
    }
}
