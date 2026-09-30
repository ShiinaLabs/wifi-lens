import SwiftUI
import WiFiLensCore

#if DEBUG

struct DebugThroughputView: View {
    @State private var samples: [ThroughputSample] = []
    @State private var timer: Timer?
    @State private var phase: Double = 0

    // Adjustable parameters
    @State private var baseRate: Double = 500_000     // ~500 KB/s
    @State private var amplitude: Double = 400_000    // ±400 KB/s swing
    @State private var speed: Double = 1.0
    @State private var isRunning: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            ThroughputChartView(samples: samples, interfaceName: "en0 (sim)")
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: isRunning) { _, running in
            if running { startTimer() } else { stopTimer() }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                isRunning.toggle()
            } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
            .help(isRunning ? "Pause" : "Resume")

            paramSlider(label: "Base", value: $baseRate, range: 0...2_000_000, format: "%.0f K", scale: 1_000)
            paramSlider(label: "Amplitude", value: $amplitude, range: 0...1_500_000, format: "%.0f K", scale: 1_000)
            paramSlider(label: "Speed", value: $speed, range: 0.1...5.0, format: "%.1f×", scale: 1)
        }
        .font(.system(size: 10))
    }

    private func paramSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        scale: Double = 1_000
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(String(format: format, value.wrappedValue / scale))")
                .foregroundColor(.secondary)
            Slider(value: value, in: range) { Text(label) }
                .controlSize(.mini)
                .frame(width: 120)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        phase += 0.05 * speed
        let now = Date()
        // Download and upload oscillate out of phase
        let down = max(0, baseRate + amplitude * sin(phase))
        let up   = max(0, baseRate * 0.4 + amplitude * 0.35 * cos(phase * 1.7))
        let sample = ThroughputSample(
            timestamp: now,
            bytesIn: UInt64(down),
            bytesOut: UInt64(up),
            rateIn: down,
            rateOut: up
        )
        samples.append(sample)
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
    }
}

#endif
