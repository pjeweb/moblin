import CoreMedia
import Foundation

private final class AudioMixerMailbox<Value: AnyObject>: @unchecked Sendable {
    private let slot = makeAudioMixerAtomic(0)

    deinit {
        _ = exchange(nil)
        free(slot)
    }

    func exchange(_ value: Value?) -> Value? {
        let pointer = value.map { Unmanaged.passRetained($0).toOpaque() }
        let address = exchangeAudioMixerAtomic(slot, Int(bitPattern: pointer))
        guard let previous = UnsafeRawPointer(bitPattern: address) else {
            return nil
        }
        return Unmanaged<Value>.fromOpaque(previous).takeRetainedValue()
    }
}

final class AudioMixerMaintenance: @unchecked Sendable {
    static let shared = AudioMixerMaintenance()
    let queue = DispatchQueue(label: "audio-mixer-effects", qos: .userInitiated)
    private var retiredEffects: [() -> Bool] = []
    private var timer: DispatchSourceTimer?

    private init() {}

    func register(_ poll: @escaping @Sendable () -> Bool) {
        queue.async { [self] in
            retiredEffects.append(poll)
            guard self.timer == nil else {
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50),
                           leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                self?.collect()
            }
            self.timer = timer
            timer.resume()
        }
    }

    private func collect() {
        retiredEffects.removeAll { $0() }
        if retiredEffects.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }
}

final class AudioMixerReport: Sendable {
    private final class Record: @unchecked Sendable {
        let value = makeAudioMixerAtomic(Int.min)
        let retired = makeAudioMixerAtomic(0)

        deinit {
            free(value)
            free(retired)
        }
    }

    private let record = Record()

    init(retaining resource: (any Sendable)? = nil, _ report: @escaping @Sendable (Int) -> Void = { _ in }) {
        AudioMixerMaintenance.shared.register { [record] in
            withExtendedLifetime(resource) {
                let retired = loadAudioMixerAtomic(record.retired) != 0
                let value = exchangeAudioMixerAtomic(record.value, Int.min)
                if value != Int.min {
                    report(value)
                }
                return retired
            }
        }
    }

    deinit {
        storeAudioMixerAtomic(record.retired, 1)
    }

    func record(_ value: Int) {
        storeAudioMixerAtomic(record.value, value)
    }
}

final class AudioMixerPreparedSource {
    let settings: AudioMixerSourceSettings
    let voice: AudioMixerEffectChain
    let effects: AudioMixerEffectChain
    let delay: Int64

    init(_ settings: AudioMixerSourceSettings, previous: AudioMixerPreparedSource?) {
        self.settings = settings
        delay = Int64((settings.delay * audioMixerSampleRate).rounded())
        let voice = previous?.voice
            ?? AudioMixerEffectChain(settings.voice ? makeAudioMixerVoiceEffects() : [])
        self.voice = voice
        if let previous, previous.settings.effects == settings.effects {
            effects = previous.effects
        } else {
            var stages: [any AudioMixerEffectStage] = []
            var latency = voice.latency
            for setting in settings.effects {
                guard let stage = setting.makeStage() else {
                    continue
                }
                guard latency + stage.latency <= audioMixerFramesPerBlock else {
                    logger.info("audio-mixer: Source \(settings.id) dropped effect (\(stage.latency) frames)")
                    continue
                }
                latency += stage.latency
                stages.append(stage)
            }
            effects = AudioMixerEffectChain(stages)
        }
    }
}

final class AudioMixerConfiguration {
    let sources: [AudioMixerPreparedSource]
    let masterSettings: [AudioMixerEffectSettings]
    let streamEffects: AudioMixerEffectChain
    let recordingEffects: AudioMixerEffectChain

    init(sources: [AudioMixerSourceSettings], master: [AudioMixerEffectSettings],
         previous: AudioMixerConfiguration?)
    {
        var available = previous?.sources ?? []
        self.sources = sources.map { settings in
            let index = available.firstIndex { $0.settings.hasSameInput(as: settings) }
            return AudioMixerPreparedSource(settings, previous: index.map { available.remove(at: $0) })
        }
        masterSettings = master
        if let previous, previous.masterSettings == master {
            streamEffects = previous.streamEffects
            recordingEffects = previous.recordingEffects
        } else {
            var stream: [any AudioMixerEffectStage] = []
            var recording: [any AudioMixerEffectStage] = []
            for effect in master {
                guard effect.canUseOnMaster,
                      let streamStage = effect.makeStage(),
                      let recordingStage = effect.makeStage()
                else {
                    continue
                }
                guard streamStage.latency == 0, recordingStage.latency == 0 else {
                    logger.info("audio-mixer: Master effect requires lookahead")
                    continue
                }
                stream.append(streamStage)
                recording.append(recordingStage)
            }
            streamEffects = AudioMixerEffectChain(stream)
            recordingEffects = AudioMixerEffectChain(recording)
        }
    }
}

final class AudioMixerGraph {
    final class Input {
        let audio: AudioMixerInput
        private var firstWriteIndex: Int64?

        init(_ audio: AudioMixerInput) {
            self.audio = audio
        }

        var startIndex: Int64 {
            firstWriteIndex ?? audio.writeIndex
        }

        func append(_ buffer: CMSampleBuffer, _ time: CMTime) {
            if firstWriteIndex == nil {
                firstWriteIndex = audio.writeIndex
            }
            audio.append(buffer, time)
        }
    }

    struct Entry {
        let source: AudioMixerSource
        let prepared: AudioMixerPreparedSource
        let input: Input
        let isNew: Bool
        let isSharedInput: Bool
        let replacedDelay: Int64?
    }

    let configuration: AudioMixerConfiguration
    let entries: [Entry]
    let removed: [Int]
    let builtinInput: Input?
    let bufferedInputs: [UUID: Input]
    let targetLatency: Int64

    init(_ configuration: AudioMixerConfiguration, previous: AudioMixerGraph?) {
        self.configuration = configuration
        let prior = previous?.entries ?? []
        let voices = Set(configuration.sources.map { ObjectIdentifier($0.voice) })
        let removed = prior.indices.filter { !voices.contains(ObjectIdentifier(prior[$0].prepared.voice)) }
        self.removed = removed

        var builtin: Input?
        var buffered: [UUID: Input] = [:]
        entries = configuration.sources.map { prepared in
            let id = prepared.settings.bufferedAudio
            let input: Input
            let oldInput: Input?
            if let id {
                oldInput = previous?.bufferedInputs[id]
                input = buffered[id] ?? Input(oldInput?.audio ?? AudioMixerInput(
                    kind: .buffered,
                    cameraId: id
                ))
                buffered[id] = input
            } else {
                oldInput = previous?.builtinInput
                input = builtin ?? Input(oldInput?.audio ?? AudioMixerInput(kind: .builtin))
                builtin = input
            }
            if let existing = prior.first(where: { $0.prepared.voice === prepared.voice }) {
                return Entry(source: existing.source, prepared: prepared, input: input, isNew: false,
                             isSharedInput: true, replacedDelay: nil)
            }
            let replacedDelay = removed.lazy
                .filter { prior[$0].prepared.settings.bufferedAudio == id }
                .map { prior[$0].prepared.delay }
                .min()
            return Entry(source: AudioMixerSource(prepared), prepared: prepared, input: input, isNew: true,
                         isSharedInput: oldInput != nil, replacedDelay: replacedDelay)
        }
        builtinInput = builtin
        bufferedInputs = buffered
        targetLatency = audioMixerMinimumLatency + configuration.sources.reduce(0) {
            max($0, $1.voice.latency + $1.effects.latency - $1.delay)
        }
    }
}

final class AudioMixerPreparation: @unchecked Sendable {
    private final class Request {
        let sources: [AudioMixerSourceSettings]?
        let master: [AudioMixerEffectSettings]

        init(sources: [AudioMixerSourceSettings]?, master: [AudioMixerEffectSettings]) {
            self.sources = sources
            self.master = master
        }
    }

    private final class Update {
        let graph: AudioMixerGraph?
        let mixer: AudioMixer?

        init(graph: AudioMixerGraph?, mixer: AudioMixer?) {
            self.graph = graph
            self.mixer = mixer
        }
    }

    private final class Handoff: @unchecked Sendable {
        let ready = makeAudioMixerAtomic(0)
        let retired = makeAudioMixerAtomic(0)
        let stopped: UnsafeMutablePointer<AudioMixerAtomicStorage>
        var active = 0
        var fading = 0
        var workerUpdate: Update?
        var inFlight = false

        init(stopped: UnsafeMutablePointer<AudioMixerAtomicStorage>) {
            self.stopped = stopped
        }

        deinit {
            Self.release(exchangeAudioMixerAtomic(ready, 0))
            Self.release(exchangeAudioMixerAtomic(retired, 0))
            Self.release(active)
            Self.release(fading)
            free(ready)
            free(retired)
            free(stopped)
        }

        static func update(_ address: Int) -> Update? {
            guard address != 1, let pointer = UnsafeRawPointer(bitPattern: address) else {
                return nil
            }
            return Unmanaged<Update>.fromOpaque(pointer).takeUnretainedValue()
        }

        static func release(_ address: Int) {
            if address != 1, let address = UnsafeRawPointer(bitPattern: address) {
                Unmanaged<Update>.fromOpaque(address).release()
            }
        }
    }

    private let requests = AudioMixerMailbox<Request>()
    private let stopped: UnsafeMutablePointer<AudioMixerAtomicStorage>
    private let transfer: Unmanaged<Handoff>

    private var handoff: Handoff {
        transfer.takeUnretainedValue()
    }

    init() {
        let stopped = makeAudioMixerAtomic(0)
        self.stopped = stopped
        let handoff = Handoff(stopped: stopped)
        transfer = .passUnretained(handoff)
        AudioMixerMaintenance.shared.register { [handoff, requests] in
            if loadAudioMixerAtomic(handoff.stopped) != 0 {
                return true
            }
            if handoff.inFlight {
                let retired = exchangeAudioMixerAtomic(handoff.retired, 0)
                guard retired != 0 else {
                    return false
                }
                Handoff.release(retired)
                handoff.inFlight = false
            }
            if let request = requests.exchange(nil) {
                Self.prepare(request, handoff)
            }
            return false
        }
    }

    deinit {
        storeAudioMixerAtomic(stopped, 1)
    }

    func submit(sources: [AudioMixerSourceSettings]?, master: [AudioMixerEffectSettings]) {
        _ = requests.exchange(Request(sources: sources, master: master))
    }

    private static func prepare(_ request: Request, _ handoff: Handoff) {
        let previous = handoff.workerUpdate
        let graph = request.sources.map {
            let config = AudioMixerConfiguration(sources: $0, master: request.master,
                                                 previous: previous?.graph?.configuration)
            return AudioMixerGraph(config, previous: previous?.graph)
        }
        let update = Update(graph: graph, mixer: graph.map { _ in
            previous?.mixer ?? AudioMixer()
        })
        handoff.workerUpdate = update
        handoff.inFlight = true
        storeAudioMixerAtomic(handoff.ready, Int(bitPattern: Unmanaged.passRetained(update).toOpaque()))
    }

    var mixer: AudioMixer? {
        Handoff.update(handoff.active)?.mixer
    }

    func adopt() -> Bool {
        if mixer?.isTransitioning == true || loadAudioMixerAtomic(handoff.retired) != 0 {
            return false
        }
        let address = exchangeAudioMixerAtomic(handoff.ready, 0)
        guard let next = Handoff.update(address) else {
            return false
        }
        handoff.fading = handoff.active == 0 ? 1 : handoff.active
        handoff.active = address
        if let graph = next.graph {
            next.mixer?.install(graph)
        }
        if next.mixer?.isTransitioning != true {
            finishTransition()
        }
        return true
    }

    func finishTransition() {
        guard mixer?.isTransitioning != true, handoff.fading != 0,
              loadAudioMixerAtomic(handoff.retired) == 0
        else {
            return
        }
        let retired = handoff.fading
        handoff.fading = 0
        storeAudioMixerAtomic(handoff.retired, retired)
    }
}
