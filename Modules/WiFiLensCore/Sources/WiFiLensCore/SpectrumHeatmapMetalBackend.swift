@preconcurrency import Metal
import Foundation

enum SpectrumHeatmapMetalBackendError: Error, Equatable, Sendable {
    case bufferAllocationFailed
    case commandEncoderUnavailable
    case commandBufferFailed(String)
    case invalidOutput
}

actor MetalHeatmapComputeBackend: SpectrumHeatmapComputeBackend {
    nonisolated let kind: SpectrumHeatmapBackendKind = .metal

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let fieldPipeline: MTLComputePipelineState
    private let smoothPipeline: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let fieldFunction = library.makeFunction(name: "heatmapFieldKernel"),
              let smoothFunction = library.makeFunction(name: "heatmapSmoothKernel"),
              let fieldPipeline = try? device.makeComputePipelineState(function: fieldFunction),
              let smoothPipeline = try? device.makeComputePipelineState(function: smoothFunction) else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.fieldPipeline = fieldPipeline
        self.smoothPipeline = smoothPipeline
    }

    func compute(
        _ input: SpectrumHeatmapComputeInput
    ) async throws -> SpectrumHeatmapRaster {
        guard input.isValid else {
            return SpectrumHeatmapRaster(
                width: input.resolution.width,
                height: input.resolution.height,
                values: []
            )
        }

        let storageCount = input.resolution.storageCount
        let envelopeStride = MemoryLayout<SpectrumHeatmapMetalEnvelope>.stride
        let parameterStride = MemoryLayout<SpectrumHeatmapMetalParameters>.stride
        let outputStride = MemoryLayout<Float>.stride
        let envelopeByteCount = input.envelopes.count
            .multipliedReportingOverflow(by: envelopeStride)
        let outputByteCount = storageCount
            .multipliedReportingOverflow(by: outputStride)
        guard !envelopeByteCount.overflow,
              !outputByteCount.overflow,
              let envelopeBuffer = device.makeBuffer(
                  length: max(envelopeStride, envelopeByteCount.partialValue),
                  options: .storageModeShared
              ),
              let parameterBuffer = device.makeBuffer(
                  length: parameterStride,
                  options: .storageModeShared
              ),
              let rawBuffer = device.makeBuffer(length: outputByteCount.partialValue, options: .storageModeShared),
              let smoothedBuffer = device.makeBuffer(length: outputByteCount.partialValue, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw SpectrumHeatmapMetalBackendError.bufferAllocationFailed
        }

        let packedEnvelopes = input.envelopes.map(SpectrumHeatmapMetalEnvelope.init(envelope:))
        packedEnvelopes.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress, source.count > 0 else { return }
            envelopeBuffer.contents().copyMemory(
                from: baseAddress,
                byteCount: source.count * envelopeStride
            )
        }

        var parameters = SpectrumHeatmapMetalParameters(input: input)
        withUnsafeBytes(of: &parameters) { source in
            parameterBuffer.contents().copyMemory(
                from: source.baseAddress!,
                byteCount: parameterStride
            )
        }

        guard let fieldEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw SpectrumHeatmapMetalBackendError.commandEncoderUnavailable
        }
        fieldEncoder.setBuffer(envelopeBuffer, offset: 0, index: 0)
        fieldEncoder.setBuffer(rawBuffer, offset: 0, index: 1)
        fieldEncoder.setBuffer(parameterBuffer, offset: 0, index: 2)
        encode(
            fieldEncoder,
            pipeline: fieldPipeline,
            width: input.resolution.width,
            height: input.resolution.height
        )
        fieldEncoder.endEncoding()

        guard let smoothEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw SpectrumHeatmapMetalBackendError.commandEncoderUnavailable
        }
        smoothEncoder.setBuffer(rawBuffer, offset: 0, index: 0)
        smoothEncoder.setBuffer(smoothedBuffer, offset: 0, index: 1)
        smoothEncoder.setBuffer(parameterBuffer, offset: 0, index: 2)
        encode(
            smoothEncoder,
            pipeline: smoothPipeline,
            width: input.resolution.width,
            height: input.resolution.height
        )
        smoothEncoder.endEncoding()

        try Task.checkCancellation()
        try await complete(commandBuffer)

        try Task.checkCancellation()
        let values = smoothedBuffer.contents()
            .bindMemory(to: Float.self, capacity: storageCount)
        let copiedValues = Array(UnsafeBufferPointer(start: values, count: storageCount))
        guard copiedValues.count == storageCount else {
            throw SpectrumHeatmapMetalBackendError.invalidOutput
        }

        return SpectrumHeatmapRaster(
            width: input.resolution.width,
            height: input.resolution.height,
            values: copiedValues
        )
    }

    private func encode(
        _ encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        width: Int,
        height: Int
    ) {
        encoder.setComputePipelineState(pipeline)
        let threads = MTLSize(width: width, height: height, depth: 1)
        let executionWidth = max(1, pipeline.threadExecutionWidth)
        let maxThreads = max(executionWidth, pipeline.maxTotalThreadsPerThreadgroup)
        let threadsPerGroup = MTLSize(
            width: min(executionWidth, width),
            height: min(max(1, maxThreads / executionWidth), height),
            depth: 1
        )
        encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
    }

    private func complete(_ commandBuffer: MTLCommandBuffer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(
                        throwing: SpectrumHeatmapMetalBackendError.commandBufferFailed(error.localizedDescription)
                    )
                } else if buffer.status != .completed {
                    continuation.resume(
                        throwing: SpectrumHeatmapMetalBackendError.commandBufferFailed(
                            "Command buffer completed with status \(buffer.status.rawValue)."
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
            commandBuffer.commit()
        }
    }
}
