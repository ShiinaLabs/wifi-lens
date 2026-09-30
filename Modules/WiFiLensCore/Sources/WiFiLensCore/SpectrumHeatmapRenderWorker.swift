import CoreGraphics
import Foundation

/// Completed heatmap work returned to the main-actor presentation boundary.
/// CGImage is immutable after construction, so it is safe to hand off once
/// the worker has finished creating it.
struct SpectrumHeatmapRenderResult: @unchecked Sendable {
    let key: SpectrumHeatmapRenderKey
    let raster: SpectrumHeatmapRaster
    let image: CGImage
}

/// Owns backend selection, computation, caching, and bitmap conversion away
/// from SwiftUI and the main actor. CPU work is additionally wrapped in a
/// detached task so a CPU fallback cannot inherit a caller's main executor.
actor SpectrumHeatmapRenderWorker {
    private let backendFactory: SpectrumHeatmapComputeBackendFactory
    private let cpuBackend = CPUHeatmapComputeBackend()
    private var selectedBackend: (any SpectrumHeatmapComputeBackend)?
    private var metalDisabled = false
    private var cachedResult: SpectrumHeatmapRenderResult?

    init(factory: SpectrumHeatmapComputeBackendFactory = .live) {
        self.backendFactory = factory
    }

    func render(_ key: SpectrumHeatmapRenderKey) async throws -> SpectrumHeatmapRenderResult {
        if let cachedResult, cachedResult.key == key {
            return cachedResult
        }

        try Task.checkCancellation()
        let input = SpectrumHeatmapComputeInput(
            envelopes: key.model.envelopes,
            domain: key.domain,
            rssiRange: key.rssiRange,
            resolution: key.resolution
        )

        let backend = selectBackendIfNeeded()
        let raster: SpectrumHeatmapRaster
        do {
            raster = try await Self.computeOffMainActor(using: backend, input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard backend.kind == .metal else {
                throw error
            }

            // A failed Metal submission disables it for this worker lifetime;
            // later renders go directly to the CPU reference implementation.
            // The request that already selected Metal must still fall back,
            // even if another concurrent request disabled Metal first.
            if !metalDisabled {
                metalDisabled = true
                selectedBackend = cpuBackend
            }
            raster = try await Self.computeOffMainActor(using: cpuBackend, input: input)
        }

        try Task.checkCancellation()
        guard let image = await Self.bitmapOffMainActor(for: raster) else {
            throw SpectrumHeatmapMetalBackendError.invalidOutput
        }

        let result = SpectrumHeatmapRenderResult(key: key, raster: raster, image: image)
        cachedResult = result
        return result
    }

    func selectedBackendKind() async -> SpectrumHeatmapBackendKind {
        selectBackendIfNeeded().kind
    }

    private func selectBackendIfNeeded() -> any SpectrumHeatmapComputeBackend {
        if let selectedBackend {
            return selectedBackend
        }

        let backend = backendFactory.makeBackend()
        selectedBackend = backend
        return backend
    }

    private static func computeOffMainActor(
        using backend: any SpectrumHeatmapComputeBackend,
        input: SpectrumHeatmapComputeInput
    ) async throws -> SpectrumHeatmapRaster {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await backend.compute(input)
        }
        return try await withTaskCancellationHandler(
            operation: {
                try await task.value
            },
            onCancel: {
                task.cancel()
            }
        )
    }

    private static func bitmapOffMainActor(for raster: SpectrumHeatmapRaster) async -> CGImage? {
        let task = Task.detached(priority: .userInitiated) {
            SpectrumHeatmapRasterizer.cgImage(for: raster) {
                SpectrumHeatmapColor.components(forIntensity: Double($0))
            }
        }
        return await task.value
    }
}
