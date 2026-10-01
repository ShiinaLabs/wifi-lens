import Foundation
import Testing
@testable import WiFiLensCore

@Suite struct SpectrumHeatmapComputeBackendTests {
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

    @Test func cpuBackendMatchesReferenceFieldAndSmoothing() async throws {
        let backend = CPUHeatmapComputeBackend()
        let actual = try await backend.compute(input)
        let raw = CPUHeatmapFieldGenerator().generate(
            envelopes: input.envelopes,
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )
        let expected = SpectrumHeatmapRasterizer.smooth(raw, domain: input.domain)

        #expect(actual == expected)
    }

    @Test func metalBufferContractsAre16ByteAligned() {
        #expect(MemoryLayout<SpectrumHeatmapMetalEnvelope>.alignment == 16)
        #expect(MemoryLayout<SpectrumHeatmapMetalEnvelope>.stride == 16)
        #expect(MemoryLayout<SpectrumHeatmapMetalParameters>.alignment == 16)
        #expect(MemoryLayout<SpectrumHeatmapMetalParameters>.stride == 48)
    }

    @Test func workerSelectsCPUWhenMetalIsUnavailable() async throws {
        let worker = SpectrumHeatmapRenderWorker(
            factory: SpectrumHeatmapComputeBackendFactory { nil }
        )

        let result = try await worker.render(
            SpectrumHeatmapRenderKey(
                model: SpectrumHeatmapModel(band: .band24GHz, channels: [1], envelopes: input.envelopes),
                domain: input.domain,
                rssiRange: input.rssiRange,
                resolution: input.resolution
            )
        )

        #expect(result.raster.width == input.resolution.width)
        let selectedKind = await worker.selectedBackendKind()
        #expect(selectedKind == .cpu)
    }

    @Test func workerPrefersTheInjectedMetalBackend() async {
        let backend = TestHeatmapBackend(kind: .metal)
        let worker = SpectrumHeatmapRenderWorker(
            factory: SpectrumHeatmapComputeBackendFactory { backend }
        )

        let selectedKind = await worker.selectedBackendKind()

        #expect(selectedKind == .metal)
    }

    @Test func workerDisablesFailedMetalAndFallsBackOnlyOnce() async throws {
        let failingBackend = TestHeatmapBackend(kind: .metal, failure: TestHeatmapBackendError.failed)
        let worker = SpectrumHeatmapRenderWorker(
            factory: SpectrumHeatmapComputeBackendFactory { failingBackend }
        )
        let key = SpectrumHeatmapRenderKey(
            model: SpectrumHeatmapModel(band: .band24GHz, channels: [1], envelopes: input.envelopes),
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )

        _ = try await worker.render(key)
        _ = try await worker.render(key)

        let selectedKind = await worker.selectedBackendKind()
        #expect(selectedKind == .cpu)
        #expect(failingBackend.computeCount == 1)
    }

    @Test func concurrentFailedMetalRendersEachFallBackToCPU() async throws {
        let failingBackend = TestHeatmapBackend(kind: .metal, failure: TestHeatmapBackendError.failed)
        let worker = SpectrumHeatmapRenderWorker(
            factory: SpectrumHeatmapComputeBackendFactory { failingBackend }
        )
        let firstKey = makeRenderKey(channel: 1)
        let secondKey = makeRenderKey(channel: 6)

        async let first = worker.render(firstKey)
        async let second = worker.render(secondKey)
        let (firstResult, secondResult) = try await (first, second)

        #expect(firstResult.raster.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        #expect(secondResult.raster.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        #expect(failingBackend.computeCount == 2)

        let selectedKind = await worker.selectedBackendKind()
        #expect(selectedKind == .cpu)
    }

    private func makeRenderKey(channel: Int) -> SpectrumHeatmapRenderKey {
        SpectrumHeatmapRenderKey(
            model: SpectrumHeatmapModel(
                band: .band24GHz,
                channels: [channel],
                envelopes: input.envelopes
            ),
            domain: input.domain,
            rssiRange: input.rssiRange,
            resolution: input.resolution
        )
    }
}

private enum TestHeatmapBackendError: Error {
    case failed
}

private struct TestHeatmapBackend: SpectrumHeatmapComputeBackend, Sendable {
    let kind: SpectrumHeatmapBackendKind
    let failure: TestHeatmapBackendError?
    private let count = LockedCount()

    init(kind: SpectrumHeatmapBackendKind, failure: TestHeatmapBackendError? = nil) {
        self.kind = kind
        self.failure = failure
    }

    var computeCount: Int { count.value }

    func compute(_ input: SpectrumHeatmapComputeInput) async throws -> SpectrumHeatmapRaster {
        count.increment()
        if let failure { throw failure }
        return SpectrumHeatmapRaster(
            width: input.resolution.width,
            height: input.resolution.height,
            values: Array(repeating: 0, count: input.resolution.storageCount)
        )
    }
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
