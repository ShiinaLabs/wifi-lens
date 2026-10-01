import Metal
import Testing
@testable import WiFiLensCore

@Suite struct SpectrumHeatmapMetalBackendTests {
    private static let tolerance = 0.02

    private let input = SpectrumHeatmapComputeInput(
        envelopes: [SpectrumHeatmapEnvelope(
            leftX: 3,
            rightX: 7,
            peakRSSI: -50,
            baselineRSSI: -100
        )],
        domain: SpectrumHeatmapChannelDomain(
            minChannelCoordinate: 1,
            maxChannelCoordinate: 9
        ),
        rssiRange: -100...(-30),
        resolution: SpectrumHeatmapResolution(width: 32, height: 16)
    )

    @Test func metalBackendMatchesCPUReferenceWhenAvailable() async throws {
        guard let backend = MetalHeatmapComputeBackend() else { return }

        try await assertParity(input, backend: backend)
    }

    @Test func emptyInputMatchesCPUReferenceWhenAvailable() async throws {
        guard let backend = MetalHeatmapComputeBackend() else { return }

        let emptyInput = SpectrumHeatmapComputeInput(
            envelopes: [],
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )
        try await assertParity(emptyInput, backend: backend)
    }

    @Test func overlappingEnvelopesMatchCPUReferenceWhenAvailable() async throws {
        guard let backend = MetalHeatmapComputeBackend() else { return }

        let overlappingInput = SpectrumHeatmapComputeInput(
            envelopes: [
                SpectrumHeatmapEnvelope(leftX: 2, rightX: 6, peakRSSI: -55, baselineRSSI: -100),
                SpectrumHeatmapEnvelope(leftX: 4, rightX: 8, peakRSSI: -60, baselineRSSI: -100)
            ],
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )
        try await assertParity(overlappingInput, backend: backend)
    }

    @Test func concurrentMetalComputationsUseIndependentBufferState() async throws {
        guard let backend = MetalHeatmapComputeBackend() else { return }

        let firstInput = SpectrumHeatmapComputeInput(
            envelopes: [
                SpectrumHeatmapEnvelope(leftX: 1, rightX: 3, peakRSSI: -45, baselineRSSI: -100)
            ],
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )
        let secondInput = SpectrumHeatmapComputeInput(
            envelopes: [
                SpectrumHeatmapEnvelope(leftX: 6, rightX: 9, peakRSSI: -80, baselineRSSI: -100)
            ],
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )

        async let first = backend.compute(firstInput)
        async let second = backend.compute(secondInput)
        let (firstRaster, secondRaster) = try await (first, second)

        let firstExpected = try await CPUHeatmapComputeBackend().compute(firstInput)
        let secondExpected = try await CPUHeatmapComputeBackend().compute(secondInput)
        assertRaster(firstRaster, matches: firstExpected)
        assertRaster(secondRaster, matches: secondExpected)
    }

    private func assertParity(
        _ input: SpectrumHeatmapComputeInput,
        backend: MetalHeatmapComputeBackend
    ) async throws {
        let actual = try await backend.compute(input)
        let expected = try await CPUHeatmapComputeBackend().compute(input)
        assertRaster(actual, matches: expected)
    }

    private func assertRaster(
        _ actual: SpectrumHeatmapRaster,
        matches expected: SpectrumHeatmapRaster
    ) {
        #expect(actual.width == expected.width)
        #expect(actual.height == expected.height)
        #expect(actual.values.allSatisfy { $0.isFinite && (0...1).contains($0) })

        // Float32 CPU/Metal parity uses a tolerance instead of byte equality.
        let maximumError = zip(actual.values, expected.values)
            .map { abs(Double($0) - Double($1)) }
            .max() ?? 0
        #expect(maximumError < Self.tolerance)
    }
}
