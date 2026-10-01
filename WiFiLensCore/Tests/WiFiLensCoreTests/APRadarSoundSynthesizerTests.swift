import Foundation
import Testing
@testable import WiFiLensCore

@Suite("APRadarSoundSynthesizer")
struct APRadarSoundSynthesizerTests {

    /// Reads a 16-bit little-endian value at `offset` in the WAV payload.
    private func int16(_ data: Data, at offset: Int) -> Int16 {
        let lower = Int16(data[data.startIndex + offset]) & 0x00FF
        let upper = Int16(data[data.startIndex + offset + 1]) << 8
        return lower | upper
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[data.startIndex + offset + index]) << (8 * index)
        }
        return value
    }

    @Test("WAV header describes 16-bit mono PCM at 44.1 kHz")
    func wavHeader() throws {
        let data = APRadarSoundSynthesizer.makeWAVData(preset: .softPulse)
        #expect(data.count > 44)
        #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        #expect(String(data: data[12..<16], encoding: .ascii) == "fmt ")
        #expect(uint32(data, at: 16) == 16) // fmt chunk size
        #expect(int16(data, at: 20) == 1) // PCM
        #expect(int16(data, at: 22) == 1) // channels
        #expect(uint32(data, at: 24) == 44_100) // sample rate
        #expect(uint32(data, at: 28) == 88_200) // byte rate
        #expect(int16(data, at: 32) == 2) // block align
        #expect(int16(data, at: 34) == 16) // bits per sample
        #expect(String(data: data[36..<40], encoding: .ascii) == "data")
    }

    @Test("every preset renders a short non-empty, non-silent clip")
    func presetsRenderAudibleClips() {
        for preset in APRadarSoundPreset.allCases {
            let data = APRadarSoundSynthesizer.makeWAVData(preset: preset)
            #expect(data.count > 44, "preset \(preset) produced no payload")
            let sampleCount = (data.count - 44) / 2
            #expect(sampleCount > 0)
            #expect(sampleCount < 44_100 / 10, "preset \(preset) exceeds 100 ms")

            var peak = 0.0
            var offset = 44
            while offset + 1 < data.count {
                let sample = Double(int16(data, at: offset)) / Double(Int16.max)
                peak = max(peak, abs(sample))
                offset += 2
            }
            #expect(peak > 0.05, "preset \(preset) is effectively silent")
            #expect(peak <= 1.0, "preset \(preset) clipped")
        }
    }

    @Test("presets are distinct tones")
    func presetsDiffer() {
        let clips = Dictionary(uniqueKeysWithValues: APRadarSoundPreset.allCases.map {
            ($0, APRadarSoundSynthesizer.makeWAVData(preset: $0))
        })
        for lhs in APRadarSoundPreset.allCases {
            for rhs in APRadarSoundPreset.allCases where rhs != lhs {
                #expect(clips[lhs] != clips[rhs], "\(lhs) and \(rhs) produced identical audio")
            }
        }
    }

    @Test("soft pulse starts near silence and returns to silence")
    func softPulseEnvelopeIsClickFree() {
        let samples = APRadarSoundSynthesizer.makeSamples(preset: .softPulse)
        #expect(!samples.isEmpty)
        #expect(abs(samples[0]) < 0.02, "soft pulse should ramp in instead of clicking")
        let tail = samples.suffix(64)
        #expect(tail.allSatisfy { abs($0) < 0.02 }, "soft pulse should decay to near silence")
    }

    @Test("geiger click is short and percussive")
    func geigerClickIsShort() {
        let samples = APRadarSoundSynthesizer.makeSamples(preset: .geiger)
        #expect(!samples.isEmpty)
        #expect(samples.count < 44_100 / 10)
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.05)
    }

    @Test("stored value resolves to a preset with a safe fallback")
    func storedValueResolution() {
        #expect(APRadarSoundPreset.fromStoredValue("softPulse") == .softPulse)
        #expect(APRadarSoundPreset.fromStoredValue("tick") == .tick)
        #expect(APRadarSoundPreset.fromStoredValue("blip") == .blip)
        #expect(APRadarSoundPreset.fromStoredValue("geiger") == .geiger)
        #expect(APRadarSoundPreset.fromStoredValue(nil) == .softPulse)
        #expect(APRadarSoundPreset.fromStoredValue("nonsense") == .softPulse)
    }
}

    // MARK: - Geiger hiss

    @Test("geiger hiss renders a seamless, non-silent noise loop")
    func geigerHissIsSeamlessNoise() {
        let samples = APRadarSoundSynthesizer.makeHissSamples()
        #expect(!samples.isEmpty)
        #expect(samples.count == Int(0.5 * Double(APRadarSoundSynthesizer.sampleRate)))

        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 1.0 })

        let rms = sqrt(samples.reduce(0.0) { $0 + $1 * $1 } / Double(samples.count))
        #expect(rms > 0.05, "hiss loop is effectively silent")

        // The loop point must not click: the first and last samples are the
        // boundary of the infinite loop, so they should be close together.
        let boundaryJump = abs(samples[0] - samples[samples.count - 1])
        #expect(boundaryJump < 0.8)
    }

    @Test("geiger hiss WAV is a valid mono PCM clip of the expected length")
    func geigerHissWAVIsValid() {
        let data = APRadarSoundSynthesizer.makeHissWAVData()
        #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        let expectedPayload = Int(0.5 * Double(APRadarSoundSynthesizer.sampleRate)) * 2
        #expect(data.count == 44 + expectedPayload)
    }
