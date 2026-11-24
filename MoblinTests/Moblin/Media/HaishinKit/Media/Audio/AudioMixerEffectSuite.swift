import AudioToolbox
@testable import Moblin
import Testing

struct AudioMixerEffectSuite {
    @Test
    func retiringAChainReleasesItsStagesOnTheEffectsQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let chain = AudioMixerEffectChain([RetirementProbe {
                dispatchPrecondition(condition: .onQueue(AudioMixerMaintenance.shared.queue))
                continuation.resume()
            }])
            withExtendedLifetime(chain) {}
        }
    }

    @Test
    func equalizerAttenuatesItsCenterFrequency() throws {
        let equalizer = try #require(AudioMixerEffectSettings.equalizer(.init(gain: -12)).makeStage())
        #expect(equalizer.latency == 0)
        var samples = createBlock(0) { createSine(0, $0) }
        try #require(equalizer.process(&samples))
        samples = createBlock(1) { createSine(0, $0) }
        #expect(equalizer.process(&samples))
        #expect(abs(peak(samples.suffix(256)) - 0.5 * pow(10, -12.0 / 20)) < 0.005)
    }

    @Test
    func failedEqualizerPassesDryAudioAndResets() throws {
        let equalizer = try #require(AudioMixerEffectSettings.equalizer(.init(gain: -12))
            .makeStage() as? AudioMixerEffect)
        let dry = createBlock(0) { createSine(0, $0) }
        var samples = dry
        AudioUnitUninitialize(equalizer.audioUnit)
        #expect(equalizer.process(&samples))
        #expect(samples == dry)
        try #require(AudioUnitInitialize(equalizer.audioUnit) == noErr)
        equalizer.reset()
        #expect(equalizer.process(&samples))
        #expect(peak(samples.suffix(256)) < 0.2)
    }

    @Test
    func compressorAttenuatesOnlyTheLouderSignal() throws {
        let compressor = try #require(AudioMixerEffectSettings.compressor(.init()).makeStage())
        let quiet = try #require(AudioMixerEffectSettings.compressor(.init()).makeStage())
        var loudPeak: Float = 0
        var quietPeak: Float = 0
        for block in 0 ..< 20 {
            var loud = createBlock(block) { createSine(0, $0) }
            var quietSamples = loud.map { $0 * 0.04 }
            try #require(compressor.process(&loud))
            try #require(quiet.process(&quietSamples))
            loudPeak = peak(loud.suffix(256))
            quietPeak = peak(quietSamples.suffix(256))
        }
        #expect(loudPeak > 0.04 && loudPeak < 0.25)
        #expect(abs(quietPeak - 0.02) < 0.001)
    }

    @Test
    func failedCompressorRetainsDrySignalTiming() throws {
        let compressor = try #require(AudioMixerEffectSettings.compressor(.init())
            .makeStage() as? AudioMixerEffect)
        let latency = Int(compressor.latency)
        try #require(latency > 0 && latency < audioMixerFramesPerBlock)
        let previous = createBlock(0) { createNoise(0, $0) }
        var samples = previous
        try #require(compressor.process(&samples))
        let lastWet = try #require(samples.last)
        AudioUnitUninitialize(compressor.audioUnit)
        let next = createBlock(1) { createNoise(0, $0) }
        samples = next
        #expect(compressor.process(&samples))
        let dry = Array(previous.suffix(latency)) + Array(next.dropLast(latency))
        #expect(abs(samples[0] - lastWet) < 1e-6)
        #expect(samples.dropFirst(256) == dry.dropFirst(256))
        let following = createBlock(2) { createNoise(0, $0) }
        samples = following
        #expect(compressor.process(&samples))
        #expect(samples == Array(next.suffix(latency)) + Array(following.dropLast(latency)))
    }

    @Test
    func expanderReducesLowLevelSoundAndPreservesSpeechLevelSound() throws {
        let expander = try #require(AudioMixerEffectSettings.expander(.init()).makeStage())
        let loud = try #require(AudioMixerEffectSettings.expander(.init()).makeStage())
        var quietPeak: Float = 0
        var loudPeak: Float = 0
        for block in 0 ..< 30 {
            var quietSamples = createBlock(block) { 0.01 * createSine(0, $0) }
            var loudSamples = quietSamples.map { $0 * 60 }
            try #require(expander.process(&quietSamples))
            try #require(loud.process(&loudSamples))
            quietPeak = peak(quietSamples.suffix(256))
            loudPeak = peak(loudSamples.suffix(256))
        }
        #expect(quietPeak < 0.0025)
        #expect(abs(loudPeak - 0.3) < 0.001)
    }

    @Test
    func deEsserReducesSibilance() throws {
        let deEsser = try #require(AudioMixerEffectSettings.deEsser(.init()).makeStage())
        let speech = try #require(AudioMixerEffectSettings.deEsser(.init()).makeStage())
        #expect(deEsser.latency == 0)
        var sibilancePeak: Float = 0
        var speechPeak: Float = 0
        for block in 0 ..< 10 {
            var sibilance = createBlock(block) { 0.4 * sin(Float($0 % 8) * .pi / 4) }
            var speechSamples = createBlock(block) { createSine(0, $0) }
            try #require(deEsser.process(&sibilance))
            try #require(speech.process(&speechSamples))
            sibilancePeak = peak(sibilance.suffix(256))
            speechPeak = peak(speechSamples.suffix(256))
        }
        #expect(sibilancePeak > 0.1 && sibilancePeak < 0.2)
        #expect(abs(speechPeak - 0.5) < 0.01)
    }
}

private final class RetirementProbe: AudioMixerEffectStage {
    let latency: Int64 = 0
    private let onRelease: () -> Void

    init(_ onRelease: @escaping () -> Void) {
        self.onRelease = onRelease
    }

    deinit {
        onRelease()
    }

    func reset() {}

    func process(_: UnsafeMutablePointer<Float>) -> Bool {
        true
    }
}

private func peak(_ samples: ArraySlice<Float>) -> Float {
    samples.map { abs($0) }.max() ?? 0
}

private func createBlock(_ index: Int, _ value: (Int) -> Float) -> [Float] {
    (0 ..< audioMixerFramesPerBlock).map { value(index * audioMixerFramesPerBlock + $0) }
}
