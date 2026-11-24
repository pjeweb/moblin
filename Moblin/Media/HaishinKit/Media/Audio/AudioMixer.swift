import Accelerate
import AVFoundation

let audioMixerFramesPerBlock = 1024
let audioMixerMinimumLatency: Int64 = 2400

struct AudioMixerLevels {
    let sources: [String: Float]
    let output: Float
}

struct AudioMixerSourceSettings {
    let id: String
    let bufferedAudio: UUID?
    let channelsMap: [Int: Int]
    let channel: Int?
    let gain: Float
    let delay: Double
    let voice: Bool
    let sends: (stream: Float, recording: Float)
    var effects: [AudioMixerEffectSettings] = []

    func hasSameInput(as other: Self) -> Bool {
        id == other.id && bufferedAudio == other.bufferedAudio && channelsMap == other.channelsMap
            && channel == other.channel && voice == other.voice
    }
}

final class AudioMixerSource {
    let id: String
    private(set) var delay: Int64 = 0
    private var isRemoved = false
    var startIndex: Int64 = .min
    private let channelsMap: [Int: Int]
    private let channel: Int?
    let voice: AudioMixerEffectChain
    private var effectAddress: Unmanaged<AudioMixerEffectChain>
    private var pendingEffectAddress: Unmanaged<AudioMixerEffectChain>?
    private var effectTransitionBlocksRemaining = 0

    private var effects: AudioMixerEffectChain {
        effectAddress.takeUnretainedValue()
    }

    private var pendingEffects: AudioMixerEffectChain? {
        pendingEffectAddress?.takeUnretainedValue()
    }

    var hasPendingEffects: Bool {
        pendingEffectAddress != nil
    }

    private let effectTransition = AudioMixerEffectBuffer()
    private let effectHistory: AudioMixerEffectBuffer?
    private let diagnostics: AudioMixerReport
    private var gain: Float = 0
    private var currentGain: Float = 0
    private var sends: (stream: Float, recording: Float) = (0, 0)
    private var currentSends: (stream: Float, recording: Float) = (0, 0)
    private var currentDelay: Int64 = 0
    private var numberOfInputChannels = -1
    private var readChannel = -1
    private var isSilent = true
    private var peak: Float = 0
    private let samples = makeAudioMixerSamples(count: audioMixerFramesPerBlock)
    private let previousSamples = makeAudioMixerSamples(count: audioMixerFadeFrames)

    init(_ prepared: AudioMixerPreparedSource) {
        let settings = prepared.settings
        id = settings.id
        channelsMap = settings.channelsMap
        channel = settings.channel
        voice = prepared.voice
        effectHistory = prepared.voice.isEmpty ? nil : AudioMixerEffectBuffer()
        effectAddress = .passUnretained(prepared.effects)
        diagnostics = AudioMixerReport { [id = settings.id] reason in
            logger.debug("audio-mixer: Source \(id) \(reason == 0 ? "input overwritten" : "stalled")")
        }
        update(prepared)
        currentDelay = delay
        currentSends = sends
    }

    deinit {
        samples.deallocate()
        previousSamples.deallocate()
    }

    func hasDifferentSends(_ target: (stream: Float, recording: Float)) -> Bool {
        target.stream != target.recording || currentSends.stream != currentSends.recording
    }

    var effectsLatency: Int64 {
        voice.latency + max(effects.latency, pendingEffects?.latency ?? 0)
    }

    func update(_ prepared: AudioMixerPreparedSource) {
        gain = prepared.settings.gain
        delay = prepared.delay
        sends = prepared.settings.sends
        pendingEffectAddress = effects === prepared.effects ? nil : .passUnretained(prepared.effects)
        effectTransitionBlocksRemaining = 4
    }

    func remove() {
        isRemoved = true
    }

    func reset() {
        isSilent = true
    }

    func takePeak() -> Float {
        defer {
            peak = 0
        }
        return peak
    }

    func render(_ input: AudioMixerInput,
                _ blockStart: Int64,
                _ streamBus: AudioMixerBus,
                _ recordingBus: AudioMixerBus?)
    {
        let startGain = currentGain
        let startSends = currentSends
        let previousDelay = currentDelay
        currentGain = isRemoved ? 0 : gain
        currentSends = sends
        if input.numberOfChannels != numberOfInputChannels {
            configure(input.numberOfChannels)
        }
        guard startGain != 0 || currentGain != 0 else {
            isSilent = true
            if let pendingEffects {
                activateEffects(pendingEffects)
            }
            readBlock(input, blockStart - delay + voice.latency + effects.latency)
            return
        }
        let lookahead = requiredFrames(effects)
        var delay = delay
        if !isSilent, input.writeIndex - (blockStart - delay) < Int64(lookahead) {
            delay = previousDelay
        }
        currentDelay = delay
        let index = blockStart - delay
        let end = Int(min(max(input.writeIndex - index, 0), Int64(lookahead)))
        let isOverwritten = index < input.oldestIndex
        if isOverwritten, !isSilent {
            diagnostics.record(0)
            isSilent = true
        }
        if isSilent {
            if let pendingEffects {
                activateEffects(pendingEffects)
            }
            guard input.writeIndex - index >= Int64(requiredFrames(effects)),
                  !isOverwritten, index >= startIndex, start(input, index)
            else {
                return
            }
            if startGain != 0 {
                fadeIn()
            }
            isSilent = false
        } else {
            let latency = voice.latency + effects.latency
            readBlock(input, index + latency)
            if previousDelay != delay {
                seek(input, blockStart - previousDelay + latency)
            }
            let canTransition = end >= lookahead && previousDelay == delay
            processEffects(input, index, canTransition: canTransition)
            if end < lookahead {
                diagnostics.record(1)
                fadeOut(min(end, audioMixerFramesPerBlock))
                isSilent = true
                if let pendingEffects {
                    activateEffects(pendingEffects)
                }
            } else if let pendingEffects {
                effectTransitionBlocksRemaining -= 1
                if effectTransitionBlocksRemaining == 0 {
                    fadeOut(audioMixerFramesPerBlock)
                    activateEffects(pendingEffects)
                    isSilent = true
                }
            }
        }
        send(to: streamBus, startGain * startSends.stream, currentGain * sends.stream)
        if let recordingBus {
            send(to: recordingBus, startGain * startSends.recording, currentGain * sends.recording)
        }
    }

    private func configure(_ numberOfInputChannels: Int) {
        self.numberOfInputChannels = numberOfInputChannels
        if let channel {
            readChannel = channel
        } else if let inputChannel = channelsMap[0], inputChannel < numberOfInputChannels {
            readChannel = inputChannel
        } else {
            readChannel = 0
        }
        isSilent = true
    }

    private func start(_ input: AudioMixerInput, _ index: Int64) -> Bool {
        start(effects, input, index, samples)
    }

    private func start(_ chain: AudioMixerEffectChain,
                       _ input: AudioMixerInput,
                       _ index: Int64,
                       _ samples: UnsafeMutablePointer<Float>,
                       resetChain: Bool = true) -> Bool
    {
        let inputIndex = index + voice.latency + chain.latency
        voice.reset()
        if resetChain {
            chain.reset()
        }
        if !voice.isEmpty || !chain.isEmpty {
            read(input, inputIndex - Int64(audioMixerFramesPerBlock), audioMixerFramesPerBlock, samples)
            voice.process(samples)
            guard chain.process(samples) else {
                return false
            }
        }
        read(input, inputIndex, audioMixerFramesPerBlock, samples)
        if samples == self.samples {
            measurePeak()
        }
        voice.process(samples)
        effectHistory?.copy(samples)
        return chain.process(samples)
    }

    private func requiredFrames(_ chain: AudioMixerEffectChain) -> Int {
        audioMixerFramesPerBlock + max(audioMixerFadeFrames, Int(voice.latency + chain.latency))
    }

    private func activateEffects(_ chain: AudioMixerEffectChain) {
        effectAddress = .passUnretained(chain)
        pendingEffectAddress = nil
    }

    private func processEffects(_ input: AudioMixerInput, _ index: Int64, canTransition: Bool) {
        voice.process(samples)
        if canTransition, let pendingEffects, let effectHistory, pendingEffects.latency == effects.latency {
            effectTransition.copy(effectHistory.samples)
            pendingEffects.process(effectTransition.samples)
            effectTransition.copy(samples)
            pendingEffects.process(effectTransition.samples)
            effectHistory.copy(samples)
            effects.process(samples)
            effectTransition.crossfade(into: samples)
            activateEffects(pendingEffects)
        } else {
            effectHistory?.copy(samples)
            effects.process(samples)
            if canTransition, let pendingEffects,
               input.writeIndex - index >= Int64(requiredFrames(pendingEffects)),
               start(pendingEffects, input, index, effectTransition.samples, resetChain: false)
            {
                effectTransition.crossfade(into: samples)
                activateEffects(pendingEffects)
            }
        }
    }

    private func readBlock(_ input: AudioMixerInput, _ index: Int64) {
        read(input, index, audioMixerFramesPerBlock, samples)
        measurePeak()
    }

    private func measurePeak() {
        var blockPeak: Float = 0
        vDSP_maxmgv(samples, 1, &blockPeak, vDSP_Length(audioMixerFramesPerBlock))
        peak = max(peak, blockPeak)
    }

    private func read(_ input: AudioMixerInput,
                      _ index: Int64,
                      _ count: Int,
                      _ samples: UnsafeMutablePointer<Float>)
    {
        input.read(channel: readChannel, at: index, count: count, into: samples)
    }

    private func seek(_ input: AudioMixerInput, _ previousIndex: Int64) {
        read(input, previousIndex, audioMixerFadeFrames, previousSamples)
        crossfadeAudioMixerSamples(from: previousSamples, to: samples, output: previousSamples)
        samples.update(from: previousSamples, count: audioMixerFadeFrames)
    }

    private func fadeIn() {
        fadeInAudioMixerSamples(samples: samples, position: 0, count: audioMixerFadeFrames)
    }

    private func fadeOut(_ end: Int) {
        guard end >= audioMixerFadeFrames else {
            samples.update(repeating: 0, count: audioMixerFramesPerBlock)
            return
        }
        let fadeStart = end - audioMixerFadeFrames
        fadeOutAudioMixerSamples(samples: samples + fadeStart, position: 0, count: audioMixerFadeFrames)
        (samples + end).update(repeating: 0, count: audioMixerFramesPerBlock - end)
    }

    private func send(to bus: AudioMixerBus, _ startGain: Float, _ endGain: Float) {
        var gain = startGain
        var step = (endGain - startGain) / Float(audioMixerFramesPerBlock)
        let frames = vDSP_Length(audioMixerFramesPerBlock)
        vDSP_vrampmuladd(samples, 1, &gain, &step, bus.samples, 1, frames)
    }
}

final class AudioMixerBus {
    let buffer: AVAudioPCMBuffer
    let samples: UnsafeMutablePointer<Float>
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var isMuted = false
    private var effectAddress: Unmanaged<AudioMixerEffectChain>?
    private var pendingEffectAddress: Unmanaged<AudioMixerEffectChain>?

    private var effects: AudioMixerEffectChain? {
        effectAddress?.takeUnretainedValue()
    }

    private var pendingEffects: AudioMixerEffectChain? {
        pendingEffectAddress?.takeUnretainedValue()
    }

    private let effectTransition = AudioMixerEffectBuffer()
    private let effectHistory = AudioMixerEffectBuffer()
    private var hasHistory = false
    private var peak: Float = 0

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: audioMixerSampleRate, channels: 1)!
        let frames = AVAudioFrameCount(audioMixerFramesPerBlock)
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = buffer.frameCapacity
        samples = buffer.floatChannelData![0]
    }

    func setGain(_ gain: Float) {
        targetGain = gain
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    func setEffects(_ effects: AudioMixerEffectChain) {
        pendingEffectAddress = self.effects === effects || (self.effects == nil && effects.isEmpty)
            ? nil : .passUnretained(effects)
    }

    func clear() {
        vDSP_vclr(samples, 1, vDSP_Length(audioMixerFramesPerBlock))
    }

    func reset() {
        effects?.reset()
        hasHistory = false
    }

    func skip() {
        gain = isMuted ? 0 : targetGain
        hasHistory = false
    }

    func resumeHistory(from bus: AudioMixerBus) {
        hasHistory = bus.hasHistory
        if hasHistory {
            effectHistory.copy(bus.effectHistory.samples)
        }
    }

    func finish() {
        processEffects()
        let endGain = isMuted ? 0 : targetGain
        var step = (endGain - gain) / Float(audioMixerFramesPerBlock)
        let frames = vDSP_Length(audioMixerFramesPerBlock)
        vDSP_vrampmul(samples, 1, &gain, &step, samples, 1, frames)
        gain = endGain
        var low: Float = -1
        var high: Float = 1
        vDSP_vclip(samples, 1, &low, &high, samples, 1, frames)
        var blockPeak: Float = 0
        vDSP_maxmgv(samples, 1, &blockPeak, frames)
        peak = max(peak, blockPeak)
    }

    func takeLevel() -> Float {
        defer {
            peak = 0
        }
        return peak
    }

    private func processEffects() {
        if let pendingEffects {
            if hasHistory {
                effectTransition.copy(effectHistory.samples)
                pendingEffects.process(effectTransition.samples)
            }
            effectTransition.copy(samples)
        }
        effectHistory.copy(samples)
        hasHistory = true
        effects?.process(samples)
        if let pendingEffects {
            pendingEffects.process(effectTransition.samples)
            effectTransition.crossfade(into: samples)
            effectAddress = pendingEffects.isEmpty ? nil : .passUnretained(pendingEffects)
            pendingEffectAddress = nil
        }
    }
}

final class AudioMixer {
    private var renderedLatency = audioMixerMinimumLatency
    private(set) var numberOfSkips = 0
    private let streamBus = AudioMixerBus()
    private let recordingBus = AudioMixerBus()
    private var recordingBlocks = 0
    private var nextBlockStart: Int64?
    private let latencyReport = AudioMixerReport { logger.debug("audio-mixer: Latency \($0) frames") }
    private let skipReport = AudioMixerReport { logger.info("audio-mixer: Skipping \($0) frames") }
    private let stats = AudioMixerReport { logger.debug("audio-mixer: \($0) skips") }
    private var graphAddress: Unmanaged<AudioMixerGraph>?
    private var previousAddress: Unmanaged<AudioMixerGraph>?
    private var needsGraphUpdate = false
    private(set) var isTransitioning = false

    private var graph: AudioMixerGraph? {
        graphAddress?.takeUnretainedValue()
    }

    private var previousGraph: AudioMixerGraph? {
        previousAddress?.takeUnretainedValue()
    }

    var latency: Int64 {
        if needsGraphUpdate, let graph {
            return max(renderedLatency, graph.targetLatency)
        }
        return renderedLatency
    }

    init() {
        prepareAudioMixerFades()
    }

    func install(_ graph: AudioMixerGraph) {
        if !needsGraphUpdate {
            previousAddress = graphAddress
        }
        graphAddress = .passUnretained(graph)
        needsGraphUpdate = true
        isTransitioning = true
    }

    func reportStats() {
        stats.record(numberOfSkips)
        graph?.builtinInput?.audio.reportStats()
        if let graph {
            for input in graph.bufferedInputs.values {
                input.audio.reportStats()
            }
        }
    }

    func setMasterGain(_ gain: Float) {
        streamBus.setGain(gain)
        recordingBus.setGain(gain)
    }

    func setMasterMuted(_ muted: Bool) {
        streamBus.setMuted(muted)
        recordingBus.setMuted(muted)
    }

    func takeLevels() -> AudioMixerLevels {
        var peaks: [String: Float] = [:]
        for entry in graph?.entries ?? [] {
            peaks[entry.source.id] = entry.source.takePeak()
        }
        return AudioMixerLevels(sources: peaks, output: streamBus.takeLevel())
    }

    func appendBuiltin(_ sampleBuffer: CMSampleBuffer, _ presentationTimeStamp: CMTime, delay: Double = 0) {
        let input = graph?.builtinInput ?? previousGraph?.builtinInput
        input?.append(sampleBuffer, presentationTimeStamp + CMTime(seconds: delay))
    }

    func appendBuffered(cameraId: UUID, _ sampleBuffer: CMSampleBuffer) {
        (graph?.bufferedInputs[cameraId] ?? previousGraph?.bufferedInputs[cameraId])?
            .append(sampleBuffer, sampleBuffer.presentationTimeStamp)
    }

    func renderNextBlock(now: CMTime) -> (
        presentationTimeStamp: CMTime,
        buffer: AVAudioPCMBuffer,
        recordingBuffer: AVAudioPCMBuffer?
    )? {
        guard let graph else {
            return nil
        }
        let frames = Int64(audioMixerFramesPerBlock)
        let due = makeAudioMixerIndex(now) - latency - frames
        var blockStart = nextBlockStart ?? due
        guard blockStart <= due else {
            return nil
        }
        if due - blockStart > Int64(audioMixerSampleRate) {
            skipReport.record(Int(due - blockStart))
            numberOfSkips += 1
            blockStart = due
            streamBus.reset()
            recordingBus.reset()
            for entry in graph.entries {
                entry.source.reset()
            }
        }
        let recordingBuffer = render(graph, blockStart)
        nextBlockStart = blockStart + frames
        let presentationTimeStamp = blockStart
        return (
            CMTime(value: presentationTimeStamp, timescale: CMTimeScale(audioMixerSampleRate)),
            streamBus.buffer,
            recordingBuffer
        )
    }

    private func render(_ graph: AudioMixerGraph, _ blockStart: Int64) -> AVAudioPCMBuffer? {
        let previous = needsGraphUpdate ? previousGraph : nil
        if needsGraphUpdate {
            let config = graph.configuration
            if let old = previous?.configuration.streamEffects, !old.isEmpty, old !== config.streamEffects {
                recordingBlocks = 2
            }
            streamBus.setEffects(config.streamEffects)
            recordingBus.setEffects(config.recordingEffects)
        }
        let wasRecordingRendered = recordingBlocks > 0
        if !graph.configuration.streamEffects.isEmpty {
            recordingBlocks = 2
        }
        for entry in graph.entries where entry.source.hasDifferentSends(entry.prepared.settings.sends) {
            recordingBlocks = 2
            break
        }
        if let previous {
            for index in graph.removed {
                let entry = previous.entries[index]
                if entry.source.hasDifferentSends(entry.prepared.settings.sends) {
                    recordingBlocks = 2
                    break
                }
            }
        }
        let isRecordingRendered = recordingBlocks > 0
        let recording = isRecordingRendered ? recordingBus : nil
        streamBus.clear()
        recording?.clear()
        if let previous {
            for index in graph.removed {
                let entry = previous.entries[index]
                entry.source.remove()
                entry.source.render(entry.input.audio, blockStart, streamBus, recording)
            }
        }
        var latency = graph.targetLatency
        var pending = false
        for entry in graph.entries {
            let source = entry.source
            if needsGraphUpdate {
                source.update(entry.prepared)
                if entry.isNew, entry.isSharedInput, let nextBlockStart {
                    if let delay = entry.replacedDelay {
                        source.startIndex = nextBlockStart - delay
                    } else {
                        source.startIndex = entry.input.startIndex
                    }
                }
            }
            source.render(entry.input.audio, blockStart, streamBus, recording)
            latency = max(latency, audioMixerMinimumLatency + source.effectsLatency - source.delay)
            pending = pending || source.hasPendingEffects
        }
        if isRecordingRendered, !wasRecordingRendered {
            recordingBus.resumeHistory(from: streamBus)
        }
        streamBus.finish()
        if isRecordingRendered {
            recordingBus.finish()
        } else {
            recordingBus.skip()
        }
        recordingBlocks = max(recordingBlocks - 1, 0)
        needsGraphUpdate = false
        previousAddress = nil
        isTransitioning = pending
        if latency != renderedLatency {
            latencyReport.record(Int(latency))
            renderedLatency = latency
        }
        return isRecordingRendered ? recordingBus.buffer : nil
    }
}
