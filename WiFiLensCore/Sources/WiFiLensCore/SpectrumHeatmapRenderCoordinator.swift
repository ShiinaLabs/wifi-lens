import Observation

/// Main-actor boundary for asynchronous heatmap presentation. It owns only
/// task lifecycle and publication of completed worker results; all compute,
/// fallback, caching, and bitmap conversion belong to the worker actor.
@MainActor @Observable
final class SpectrumHeatmapRenderCoordinator {
    private let worker: SpectrumHeatmapRenderWorker
    private var renderTask: Task<Void, Never>?
    private var currentKey: SpectrumHeatmapRenderKey?

    private(set) var result: SpectrumHeatmapRenderResult?
    private(set) var isRendering = false

    init() {
        self.worker = SpectrumHeatmapRenderWorker()
    }

    init(worker: SpectrumHeatmapRenderWorker) {
        self.worker = worker
    }

    func request(_ key: SpectrumHeatmapRenderKey) {
        guard !key.model.envelopes.isEmpty else {
            renderTask?.cancel()
            renderTask = nil
            currentKey = key
            result = nil
            isRendering = false
            return
        }

        if (currentKey == key && isRendering) || result?.key == key {
            return
        }

        renderTask?.cancel()
        currentKey = key
        isRendering = true

        let worker = worker
        renderTask = Task { [weak self] in
            do {
                let completed = try await worker.render(key)
                guard !Task.isCancelled else { return }
                guard let self, self.currentKey == key else { return }
                self.result = completed
                self.isRendering = false
            } catch is CancellationError {
                // A newer key owns the presentation now.
            } catch {
                guard let self, self.currentKey == key else { return }
                self.isRendering = false
            }
        }
    }

    func cancel() {
        renderTask?.cancel()
        renderTask = nil
        isRendering = false
    }

    func selectedBackendKind() async -> SpectrumHeatmapBackendKind {
        await worker.selectedBackendKind()
    }
}
