import AVFoundation
import Foundation
import Observation

/// Errors surfaced when the bundled pulse sound cannot be prepared.
enum APRadarAudioError: LocalizedError {
    case resourceNotFound
    case unavailable(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            "AP Radar pulse sound resource is missing."
        case .unavailable(let underlying):
            "AP Radar audio could not be initialized: \(underlying.localizedDescription)"
        }
    }
}

/// Sound presets for AP Radar pulses. Every preset is synthesized once at
/// `prepare` time and played back from memory, so pulses never re-read or
/// re-decode an asset.
///
/// `geiger` is a hidden easter-egg preset: it is only listed in Settings
/// after the user unlocks it with a secret gesture on the radar page.
enum APRadarSoundPreset: String, CaseIterable, Sendable {
    /// Soft, rounded sine pulse — the default tone.
    case softPulse
    /// Short mechanical tick.
    case tick
    /// Falling radar chirp.
    case blip
    /// Geiger-counter click (easter egg).
    case geiger

    /// Resolves a stored raw value, falling back to the default preset.
    static func fromStoredValue(_ value: String?) -> APRadarSoundPreset {
        guard let value, let preset = APRadarSoundPreset(rawValue: value) else {
            return .softPulse
        }
        return preset
    }
}

/// Pure, testable generator for the short WAV pulses used by AP Radar.
///
/// All presets are 16-bit mono PCM at 44.1 kHz and stay well under 100 ms so
/// rapid pulses never overlap into a sustained tone. Each preset uses a short
/// attack ramp and an exponential decay to stay soft and click-free.
enum APRadarSoundSynthesizer {
    static let sampleRate = 44_100
    static let bitsPerSample = 16
    static let channelCount = 1

    /// Renders the preset as a complete WAV file in memory.
    static func makeWAVData(preset: APRadarSoundPreset, sampleRate: Int = sampleRate) -> Data {
        let samples = makeSamples(preset: preset, sampleRate: sampleRate)
        return makeWAVData(samples: samples, sampleRate: sampleRate)
    }

    /// Renders the preset as normalized samples in `-1...1`.
    static func makeSamples(preset: APRadarSoundPreset, sampleRate: Int = sampleRate) -> [Double] {
        switch preset {
        case .softPulse:
            return tone(
                frequency: 880,
                duration: 0.08,
                attack: 0.003,
                decay: 0.02,
                amplitude: 0.5,
                sampleRate: sampleRate
            )
        case .tick:
            return tone(
                frequency: 2_500,
                duration: 0.025,
                attack: 0.001,
                decay: 0.006,
                amplitude: 0.4,
                sampleRate: sampleRate
            )
        case .blip:
            return chirp(
                startFrequency: 1_300,
                endFrequency: 720,
                duration: 0.07,
                attack: 0.002,
                decay: 0.024,
                amplitude: 0.45,
                sampleRate: sampleRate
            )
        case .geiger:
            return geigerClick(sampleRate: sampleRate)
        }
    }

    /// A single sine tone with a linear attack and exponential decay.
    private static func tone(
        frequency: Double,
        duration: Double,
        attack: Double,
        decay: Double,
        amplitude: Double,
        sampleRate: Int
    ) -> [Double] {
        let count = Int(duration * Double(sampleRate))
        let attackSamples = max(1, Int(attack * Double(sampleRate)))
        let decayRate = 1.0 / decay
        return (0..<count).map { index in
            let t = Double(index) / Double(sampleRate)
            let attackGain = index < attackSamples ? Double(index) / Double(attackSamples) : 1.0
            let decayGain = exp(-t * decayRate)
            return sin(2 * .pi * frequency * t) * amplitude * attackGain * decayGain
        }
    }

    /// A sine tone gliding from `startFrequency` down to `endFrequency`.
    private static func chirp(
        startFrequency: Double,
        endFrequency: Double,
        duration: Double,
        attack: Double,
        decay: Double,
        amplitude: Double,
        sampleRate: Int
    ) -> [Double] {
        let count = Int(duration * Double(sampleRate))
        let attackSamples = max(1, Int(attack * Double(sampleRate)))
        let decayRate = 1.0 / decay
        let phaseStep = 2 * .pi / Double(sampleRate)
        var phase = 0.0
        var samples: [Double] = []
        samples.reserveCapacity(count)
        for index in 0..<count {
            let progress = Double(index) / Double(count)
            let frequency = startFrequency + (endFrequency - startFrequency) * (1 - exp(-4 * progress))
            phase += phaseStep * frequency
            let attackGain = index < attackSamples ? Double(index) / Double(attackSamples) : 1.0
            let decayGain = exp(-(Double(index) / Double(sampleRate)) * decayRate)
            samples.append(sin(phase) * amplitude * attackGain * decayGain)
        }
        return samples
    }

    /// A short Geiger-counter click: a fast noise burst with an immediate
    /// exponential decay plus a faint tonal body so it reads as a physical
    /// "clack" rather than static.
    private static func geigerClick(sampleRate: Int) -> [Double] {
        let duration = 0.03
        let count = Int(duration * Double(sampleRate))
        let attackSamples = max(1, Int(0.0008 * Double(sampleRate)))
        let decayRate = 1.0 / 0.0045
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { index in
            let t = Double(index) / Double(sampleRate)
            let attackGain = index < attackSamples ? Double(index) / Double(attackSamples) : 1.0
            let decayGain = exp(-t * decayRate)
            let noise = Double.random(in: -1...1, using: &generator)
            let body = sin(2 * .pi * 900 * t)
            return (0.75 * noise + 0.25 * body) * 0.5 * attackGain * decayGain
        }
    }

    /// Renders the low-level background hiss of a Geiger tube as a seamless,
    /// looping clip (~0.5 s). A real counter does not go silent between
    /// clicks: it carries a faint broadband static, so the preset plays this
    /// continuously at a low volume with the percussive clicks on top.
    static func makeHissWAVData(sampleRate: Int = sampleRate) -> Data {
        makeWAVData(samples: makeHissSamples(sampleRate: sampleRate), sampleRate: sampleRate)
    }

    /// Generates one seamless loop of softened white noise (the Geiger hiss).
    /// The noise is lightly low-passed so it reads as airy static rather than
    /// harsh digital crackle, normalized to a fixed RMS, and the loop seam is
    /// overlap-crossfaded so the loop point never clicks.
    static func makeHissSamples(duration: Double = 0.5, sampleRate: Int = sampleRate) -> [Double] {
        let count = Int(duration * Double(sampleRate))
        guard count > 0 else { return [] }
        let fade = max(1, min(count, Int(0.02 * Double(sampleRate))))
        var generator = SystemRandomNumberGenerator()

        func smoothedNoise(length: Int) -> [Double] {
            var samples: [Double] = []
            samples.reserveCapacity(length)
            var previous = 0.0
            for _ in 0..<length {
                let white = Double.random(in: -1...1, using: &generator)
                previous = 0.80 * previous + 0.20 * white
                samples.append(previous)
            }
            return samples
        }

        // Generate `count + fade` so the tail can be blended into the head;
        // the loop boundary then sits between two adjacent smoothed samples.
        var noise = smoothedNoise(length: count + fade)
        for index in 0..<fade {
            let t = Double(index) / Double(fade)
            noise[index] = noise[index] * t + noise[count + index] * (1 - t)
        }
        noise.removeLast(fade)

        let rms = sqrt(noise.reduce(0) { $0 + $1 * $1 } / Double(count))
        if rms > 0 {
            let gain = 0.35 / rms
            noise = noise.map { min(max($0 * gain, -1), 1) }
        }
        return noise
    }

    /// Packs normalized samples into a 16-bit mono PCM WAV file.
    static func makeWAVData(samples: [Double], sampleRate: Int = sampleRate) -> Data {
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = channelCount * bytesPerSample
        let byteRate = sampleRate * blockAlign
        let dataSize = samples.count * blockAlign

        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(36 + UInt32(dataSize), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16, to: &data) // fmt chunk size
        appendUInt16(1, to: &data) // PCM
        appendUInt16(UInt16(channelCount), to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(byteRate), to: &data)
        appendUInt16(UInt16(blockAlign), to: &data)
        appendUInt16(UInt16(bitsPerSample), to: &data)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(dataSize), to: &data)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * Double(Int16.max))
            withUnsafeBytes(of: intSample.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

/// Preloaded, single-shot audio playback for AP Radar pulses.
///
/// The selected preset is synthesized and decoded once in `prepare(preset:)`;
/// every pulse reuses the same `AVAudioPlayer` instead of re-reading or
/// re-decoding an asset.
@MainActor
final class APRadarAudioPlayer: APRadarAudioPlaying {
    private var player: AVAudioPlayer?
    private var hissPlayer: AVAudioPlayer?
    private var loadedPreset: APRadarSoundPreset?

    /// Volume of the continuous Geiger hiss relative to the click (kept faint).
    private static let geigerHissVolume: Float = 0.06

    func prepare(preset: APRadarSoundPreset) throws {
        if player != nil, loadedPreset == preset { return }
        let wavData = APRadarSoundSynthesizer.makeWAVData(preset: preset)
        do {
            let player = try AVAudioPlayer(data: wavData)
            player.prepareToPlay()
            self.player = player
            self.loadedPreset = preset
            try prepareHissIfNeeded(preset: preset)
        } catch {
            throw APRadarAudioError.unavailable(underlying: error)
        }
    }

    /// Builds (or tears down) the continuous Geiger hiss layer when switching
    /// presets. Hiss preparation failure is non-fatal: the clicks still work
    /// and the preset simply plays without the ambient static.
    private func prepareHissIfNeeded(preset: APRadarSoundPreset) throws {
        if preset != .geiger {
            hissPlayer?.stop()
            hissPlayer = nil
            return
        }
        let hissData = APRadarSoundSynthesizer.makeHissWAVData()
        do {
            let hiss = try AVAudioPlayer(data: hissData)
            hiss.numberOfLoops = -1
            hiss.volume = Self.geigerHissVolume
            hiss.prepareToPlay()
            hissPlayer = hiss
        } catch {
            hissPlayer = nil
        }
    }

    /// Plays one pulse from the start (and starts the Geiger hiss when the
    /// selected preset uses it). Returns false when audio is not ready or the
    /// system refuses playback.
    @discardableResult
    func playPulse() -> Bool {
        guard let player else { return false }
        if let hiss = hissPlayer, !hiss.isPlaying {
            hiss.play()
        }
        player.currentTime = 0
        return player.play()
    }

    /// Stops any in-flight playback and the continuous hiss immediately.
    func stop() {
        player?.stop()
        hissPlayer?.stop()
    }
}

/// Protocol seam used by the view model so tests can substitute a spy.
@MainActor
protocol APRadarAudioPlaying: AnyObject {
    func prepare(preset: APRadarSoundPreset) throws
    @discardableResult
    func playPulse() -> Bool
    func stop()
}

/// Plays a short, self-contained preview of a sound preset from Settings.
///
/// The previewer owns a single audio player and one cancellable task, so a
/// preview never overlaps with itself and stops immediately when the settings
/// page is left or the preset changes. Geiger previews include the continuous
/// hiss plus a short Poisson burst so the easter egg is audible without
/// starting a tracking session.
///
/// `isPlaying` is observable so the Settings row can refresh its icon when a
/// preview ends naturally instead of staying on "stop" forever.
@MainActor
@Observable
final class APRadarSoundPreviewer {
    private let player: any APRadarAudioPlaying
    private var task: Task<Void, Never>?
    /// Incremented on every stop/start so a cancelled preview that wakes after
    /// a replacement cannot stop the new preview's player or state.
    private var generation = 0
    private(set) var isPlaying = false
    /// Test seam: replaces wall-clock sleeps with a deterministic sleeper.
    private let sleep: @MainActor (Duration) async throws -> Void

    /// Number of pulses for the regular (non-Geiger) preview.
    private static let regularPulseCount = 3
    /// Spacing between regular preview pulses.
    private static let regularPulseSpacing: Duration = .milliseconds(300)
    /// Length of the Geiger preview burst.
    private static let geigerPreviewDuration: Duration = .seconds(1.2)
    /// Average click interval for the Geiger preview (fast enough to convey
    /// the irregular cadence without being mistaken for a steady rhythm).
    private static let geigerPreviewMeanInterval: Double = 0.25

    convenience init() {
        self.init(player: APRadarAudioPlayer())
    }

    init(
        player: any APRadarAudioPlaying = APRadarAudioPlayer(),
        sleep: @escaping @MainActor (Duration) async throws -> Void =
            APRadarSoundPreviewer.realSleep
    ) {
        self.player = player
        self.sleep = sleep
    }

    @MainActor
    private static func realSleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    /// Starts a short preview of `preset`, replacing any running preview.
    /// Returns false when the preset cannot be prepared (audio failure is
    /// non-fatal; the settings row simply stays silent).
    @discardableResult
    func start(preset: APRadarSoundPreset) -> Bool {
        stop()
        do {
            try player.prepare(preset: preset)
        } catch {
            return false
        }
        generation &+= 1
        let token = generation
        isPlaying = true
        task = Task { [weak self] in
            await self?.runPreview(preset: preset, token: token)
        }
        return true
    }

    /// Starts a preview, or stops the running one when already playing.
    func toggle(preset: APRadarSoundPreset) {
        if isPlaying {
            stop()
        } else {
            start(preset: preset)
        }
    }

    /// Cancels the preview task and stops all audio immediately.
    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        player.stop()
        isPlaying = false
    }

    private func runPreview(preset: APRadarSoundPreset, token: Int) async {
        if preset == .geiger {
            // Track the remaining burst time instead of an absolute deadline so
            // the loop is fully deterministic under an injected sleeper.
            var remaining = Self.geigerPreviewDuration
            while !Task.isCancelled, remaining > .zero {
                guard generation == token else { return }
                player.playPulse()
                let interval = APRadarPulseInterval.nextExponentialInterval(
                    mean: Self.geigerPreviewMeanInterval
                )
                let step: Duration = .seconds(interval)
                try? await sleep(step)
                remaining -= step
            }
        } else {
            for _ in 0..<Self.regularPulseCount {
                guard !Task.isCancelled, generation == token else { break }
                player.playPulse()
                try? await sleep(Self.regularPulseSpacing)
            }
        }
        // Only the current generation may stop the player and publish the
        // idle state; a cancelled preview that woke after a replacement must
        // leave the new preview's audio and state alone.
        guard generation == token else { return }
        player.stop()
        isPlaying = false
    }
}
