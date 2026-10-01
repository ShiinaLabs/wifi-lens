import Foundation
import Testing
@testable import WiFiLensCore

@Suite @MainActor struct SpectrumHeatmapRenderCoordinatorTests {
    @Test func newerRequestReplacesOldResultWithoutPublishingLateWork() async throws {
        let backend = DelayedHeatmapBackend(delayNanoseconds: 20_000_000)
        let worker = SpectrumHeatmapRenderWorker(
            factory: SpectrumHeatmapComputeBackendFactory { backend }
        )
        let coordinator = SpectrumHeatmapRenderCoordinator(worker: worker)
        let first = makeKey(marker: 1)
        let second = makeKey(marker: 2)

        coordinator.request(first)
        try await waitUntil { coordinator.result?.key == first }
        coordinator.request(second)

        #expect(coordinator.isRendering)
        #expect(coordinator.result?.key == first)

        try await waitUntil { coordinator.result?.key == second }
        #expect(coordinator.result?.raster.values.first == 2)
    }

    private func makeKey(marker: Int) -> SpectrumHeatmapRenderKey {
        SpectrumHeatmapRenderKey(
            model: SpectrumHeatmapModel(
                band: .band24GHz,
                channels: [marker],
                envelopes: [SpectrumHeatmapEnvelope(
                    leftX: Double(marker),
                    rightX: Double(marker + 1),
                    peakRSSI: -50,
                    baselineRSSI: -100
                )]
            ),
            domain: SpectrumHeatmapChannelDomain(minChannelCoordinate: 1, maxChannelCoordinate: 16),
            rssiRange: -100...(-30),
            resolution: SpectrumHeatmapResolution(width: 4, height: 4)
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        Issue.record("Timed out waiting for heatmap render")
    }
}

private struct DelayedHeatmapBackend: SpectrumHeatmapComputeBackend, Sendable {
    let kind: SpectrumHeatmapBackendKind = .cpu
    let delayNanoseconds: UInt64

    func compute(_ input: SpectrumHeatmapComputeInput) async throws -> SpectrumHeatmapRaster {
        // Deliberately ignore cancellation so the coordinator must reject the
        // late first result by key rather than relying only on task timing.
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        let marker = Float(input.modelMarker)
        return SpectrumHeatmapRaster(
            width: input.resolution.width,
            height: input.resolution.height,
            values: Array(repeating: marker, count: input.resolution.storageCount)
        )
    }
}

private extension SpectrumHeatmapComputeInput {
    var modelMarker: Int {
        Int(envelopes.first?.leftX ?? 0)
    }
}
