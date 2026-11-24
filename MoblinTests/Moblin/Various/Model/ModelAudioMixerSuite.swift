import Foundation
@testable import Moblin
import Testing

private func createBuiltinMic(_ orientation: SettingsMic, _ dataSourceId: Int) -> SettingsMicsMic {
    let mic = SettingsMicsMic(
        name: orientation.rawValue,
        inputUid: "BuiltInMicrophoneDevice",
        connected: true
    )
    mic.dataSourceId = dataSourceId
    mic.builtInOrientation = orientation
    return mic
}

private func createChannelMic(_ mic: SettingsMicsMic, _ channel: Int) -> SettingsMicsMic {
    let channelMic = SettingsMicsMic(
        name: "\(mic.name) \(channel + 1)",
        inputUid: mic.inputUid,
        connected: true
    )
    channelMic.channel = channel
    return channelMic
}

private func createMixedMic(_ mic: SettingsMicsMic) -> SettingsMicsMic {
    let mixedMic = SettingsMicsMic(name: mic.name, inputUid: mic.inputUid, connected: mic.connected)
    mixedMic.dataSourceId = mic.dataSourceId
    mixedMic.builtInOrientation = mic.builtInOrientation
    mixedMic.mixed = true
    return mixedMic
}

private let frontMic = createBuiltinMic(.front, 1)
private let backMic = createBuiltinMic(.back, 2)
private let usbMic = SettingsMicsMic(name: "USB Audio", inputUid: "AppleUSBAudioEngine:1", connected: true)
private let usbMic1 = createChannelMic(usbMic, 0)
private let usbMic2 = createChannelMic(usbMic, 1)
private let interfaceMic1 = createChannelMic(
    SettingsMicsMic(name: "Interface", inputUid: "AppleUSBAudioEngine:2", connected: true),
    0
)
private let srtlaMic = SettingsMicsMic(name: srtlaCamera(name: "Cam 2"),
                                       inputUid: UUID().uuidString,
                                       connected: true)
private let rtmpMic = SettingsMicsMic(name: rtmpCamera(name: "Cam 3"),
                                      inputUid: UUID().uuidString,
                                      connected: false)
private let mediaPlayerMic = SettingsMicsMic(name: mediaPlayerCamera(name: "Music"),
                                             inputUid: UUID().uuidString,
                                             connected: true)
private let screenCaptureMic = SettingsMicsMic(name: screenCaptureCameraName,
                                               inputUid: screenCaptureCameraId.uuidString,
                                               connected: true)

struct ModelAudioMixerSuite {
    struct MixableCase: CustomTestStringConvertible {
        let mic: SettingsMicsMic
        let current: SettingsMicsMic
        let expected: Bool

        var testDescription: String {
            "\(mic.name) into \(current.name)"
        }
    }

    struct MixedMicsCase: CustomTestStringConvertible {
        let testDescription: String
        let mics: [SettingsMicsMic]
        let current: SettingsMicsMic
        let expected: [SettingsMicsMic]
    }

    struct ChannelMicCase: CustomTestStringConvertible {
        let testDescription: String
        let inputUid: String
        let numberOfChannels: Int
        let expected: Bool
    }

    @Test(arguments: [
        MixableCase(mic: srtlaMic, current: frontMic, expected: true),
        MixableCase(mic: mediaPlayerMic, current: usbMic, expected: true),
        MixableCase(mic: screenCaptureMic, current: srtlaMic, expected: true),
        MixableCase(mic: rtmpMic, current: srtlaMic, expected: true),
        MixableCase(mic: frontMic, current: srtlaMic, expected: false),
        MixableCase(mic: usbMic, current: frontMic, expected: false),
        MixableCase(mic: backMic, current: frontMic, expected: false),
        MixableCase(mic: srtlaMic, current: srtlaMic, expected: false),
        MixableCase(mic: usbMic2, current: usbMic1, expected: true),
        MixableCase(mic: srtlaMic, current: usbMic1, expected: true),
        MixableCase(mic: usbMic1, current: usbMic, expected: false),
        MixableCase(mic: usbMic, current: usbMic1, expected: false),
        MixableCase(mic: interfaceMic1, current: usbMic1, expected: false),
    ])
    func mixable(_ testCase: MixableCase) {
        #expect(isAudioMicMixable(mic: testCase.mic, current: testCase.current) == testCase.expected)
    }

    @Test(arguments: [
        MixedMicsCase(testDescription: "Only mixed mics",
                      mics: [srtlaMic, createMixedMic(mediaPlayerMic), frontMic],
                      current: frontMic,
                      expected: [mediaPlayerMic]),
        MixedMicsCase(testDescription: "Disconnected mixed mic",
                      mics: [createMixedMic(srtlaMic), createMixedMic(rtmpMic), frontMic],
                      current: frontMic,
                      expected: [srtlaMic]),
        MixedMicsCase(testDescription: "Mixed current mic",
                      mics: [createMixedMic(srtlaMic), createMixedMic(mediaPlayerMic)],
                      current: srtlaMic,
                      expected: [mediaPlayerMic]),
        MixedMicsCase(testDescription: "Mixed built-in and external mics",
                      mics: [
                          createMixedMic(backMic),
                          createMixedMic(usbMic),
                          createMixedMic(screenCaptureMic),
                      ],
                      current: srtlaMic,
                      expected: [screenCaptureMic]),
        MixedMicsCase(testDescription: "List order",
                      mics: [
                          createMixedMic(screenCaptureMic),
                          createMixedMic(mediaPlayerMic),
                          createMixedMic(srtlaMic),
                      ],
                      current: frontMic,
                      expected: [screenCaptureMic, mediaPlayerMic, srtlaMic]),
    ])
    func mixedMics(_ testCase: MixedMicsCase) {
        #expect(makeAudioMixerMixedMics(mics: testCase.mics, current: testCase.current) == testCase.expected)
    }

    @Test(arguments: [
        ChannelMicCase(testDescription: "Delivered channel",
                       inputUid: usbMic.inputUid,
                       numberOfChannels: 2,
                       expected: true),
        ChannelMicCase(testDescription: "Channel above the delivered count",
                       inputUid: usbMic.inputUid,
                       numberOfChannels: 1,
                       expected: false),
        ChannelMicCase(testDescription: "Count delivered by another device",
                       inputUid: frontMic.inputUid,
                       numberOfChannels: 1,
                       expected: true),
    ])
    func channelMicConnected(_ testCase: ChannelMicCase) {
        #expect(isAudioChannelMicConnected(mic: usbMic2,
                                           found: [frontMic, usbMic],
                                           inputUid: testCase.inputUid,
                                           numberOfChannels: testCase.numberOfChannels) == testCase.expected)
    }

    @Test
    func networkSourceChangeKeepsChannelOfHighestPriorityMic() {
        #expect(isAudioMicSwitchNeeded(current: nil, highestPriority: usbMic, mixed: []))
        #expect(!isAudioMicSwitchNeeded(current: usbMic1, highestPriority: usbMic, mixed: []))
        #expect(!isAudioMicSwitchNeeded(current: usbMic2, highestPriority: usbMic, mixed: [usbMic1]))
        #expect(isAudioMicSwitchNeeded(current: interfaceMic1, highestPriority: usbMic, mixed: []))
        #expect(isAudioMicSwitchNeeded(current: frontMic, highestPriority: usbMic, mixed: []))
        #expect(isAudioMicSwitchNeeded(current: usbMic, highestPriority: usbMic1, mixed: []))
        #expect(!isAudioMicSwitchNeeded(current: usbMic1, highestPriority: srtlaMic, mixed: [srtlaMic]))
        #expect(isAudioMicSwitchNeeded(current: usbMic1, highestPriority: srtlaMic, mixed: []))
    }

    @Test
    func channelMicNames() {
        let makeNames = { (channelNames: [String?]) in
            makeAudioChannelMicNames(portName: "Wireless microphone", channelNames: channelNames)
        }
        #expect(makeNames(["Wireless microphone 1", "Wireless microphone 2"])
            == ["Wireless microphone 1", "Wireless microphone 2"])
        #expect(makeNames(["Left", "Right"]) == ["Wireless microphone: Left", "Wireless microphone: Right"])
        #expect(makeNames(["", nil]) == ["Wireless microphone 1", "Wireless microphone 2"])
        #expect(makeNames(["Wireless microphone", "Wireless microphone"])
            == ["Wireless microphone 1", "Wireless microphone 2"])
        #expect(makeNames(["Mic", "Mic"]) == ["Wireless microphone 1", "Wireless microphone 2"])
    }

    @Test
    func settingsPageFollowsTheCurrentMix() {
        let main = SettingsMicsMic(name: "Camera", inputUid: "camera", connected: true)
        let guest = SettingsMicsMic(name: "Guest", inputUid: "guest", connected: true)
        let sources = makeMixerSources(currentId: main.id, mics: [usbMic, main], mixed: [guest])
        #expect(findMixerSource(id: guest.id, sources: sources) === guest)
        #expect(findMixerSource(id: main.id, sources: sources) === main)
        #expect(findMixerSource(id: nil, sources: sources) == nil)
        let afterDelete = makeMixerSources(currentId: main.id, mics: [usbMic], mixed: [guest])
        #expect(findMixerSource(id: main.id, sources: afterDelete) == nil)
        #expect(findMixerSource(id: guest.id, sources: afterDelete) === guest)
    }

    @Test
    func deletedMainMicKeepsOtherSourcesAddable() {
        let deleted = SettingsMicsMic(name: rtmpCamera(name: "Old"), inputUid: "old", connected: true)
        let guest = SettingsMicsMic(name: rtmpCamera(name: "Guest"), inputUid: "guest", connected: true)
        #expect(isAudioMicAddable(mic: guest, current: deleted))
        #expect(!isAudioMicAddable(mic: frontMic, current: deleted))
        guest.mixed = true
        #expect(!isAudioMicAddable(mic: guest, current: deleted))
        #expect(makeAudioMixerMixedMics(mics: [frontMic, guest], current: deleted) == [guest])
    }

    @Test
    func deletedMainMicIsNotAMixerSource() {
        let main = SettingsMicsMic(name: "Camera", inputUid: "camera", connected: true)
        let sources = makeMixerSources(currentId: main.id, mics: [usbMic, main], mixed: [srtlaMic])
        #expect(sources == [main, srtlaMic])
        #expect(sources[0] === main)
        #expect(makeMixerSources(currentId: main.id, mics: [usbMic], mixed: [srtlaMic]) == [srtlaMic])
        #expect(makeMixerSources(currentId: main.id, mics: [usbMic], mixed: []).isEmpty)
    }

    @Test @MainActor
    func meterSurvivesAnOlderLevelsSnapshot() {
        let meters = AudioMixerMeters()
        let old = meters.source(id: "old")
        let new = meters.source(id: "new")
        let older = AudioMixerLevels(sources: ["old": 0.5], output: 0)
        meters.update(levels: older, activeIds: ["new"])
        #expect(meters.source(id: "new") === new)
        #expect(meters.source(id: "old") !== old)
        let next = AudioMixerLevels(sources: ["new": 0.5], output: 0)
        meters.update(levels: next, activeIds: ["new"])
        #expect(abs(new.level - 20 * log10(0.5)) < 0.001)
    }

    @Test
    func mutedMicHasNoGain() {
        let mic = SettingsMicsMic(name: "Mic", inputUid: "Mic", connected: true)
        mic.gainDb = -6
        #expect(abs(makeAudioMixerSourceGain(mic: mic) - 0.501) < 0.001)
        mic.muted = true
        #expect(makeAudioMixerSourceGain(mic: mic) == 0)
        mic.gainDb = 0
        mic.muted = false
        #expect(makeAudioMixerSourceGain(mic: mic) == 1)
    }

    @Test
    func sourceEffectsInFixedOrder() throws {
        let effects = SettingsMicsMicEffects()
        #expect(makeAudioMixerSourceEffects(effects: effects).isEmpty)
        effects.deEsser.enabled = true
        effects.deEsser.frequency = 7000
        effects.compressor.enabled = true
        effects.compressor.threshold = -18
        effects.compressor.headroom = 4
        effects.compressor.attack = 0.01
        effects.compressor.release = 0.2
        effects.compressor.makeupGain = 3
        var low = SettingsAudioMixerEqualizer()
        low.enabled = true
        low.gain = -4.5
        var high = SettingsAudioMixerEqualizer()
        high.enabled = true
        high.frequency = 5000
        high.gain = 2
        effects.equalizers = [low, high]
        effects.expander.enabled = true
        effects.expander.threshold = -50
        effects.expander.ratio = 3
        let result = makeAudioMixerSourceEffects(effects: effects)
        try #require(result.count == 5)
        let expander = AudioMixerExpander(threshold: -50, ratio: 3, attack: 0.003, release: 0.12)
        #expect(result[0] == .expander(expander))
        #expect(result[1] == .equalizer(AudioMixerEqualizer(frequency: 1000, gain: -4.5, bandwidth: 1)))
        #expect(result[2] == .equalizer(AudioMixerEqualizer(frequency: 5000, gain: 2, bandwidth: 1)))
        #expect(result[3] == .compressor(AudioMixerCompressor(threshold: -18,
                                                              headroom: 4,
                                                              attack: 0.01,
                                                              release: 0.2,
                                                              makeupGain: 3)))
        #expect(result[4] == .deEsser(AudioMixerDeEsserSettings(frequency: 7000,
                                                                bandwidth: 1,
                                                                threshold: -24,
                                                                maximumReduction: 9)))
    }

    @Test
    func sourceEffectsAreUpToThreeBands() {
        func band(_ frequency: Float, enabled: Bool = true) -> SettingsAudioMixerEqualizer {
            var band = SettingsAudioMixerEqualizer()
            band.enabled = enabled
            band.frequency = frequency
            return band
        }
        let effects = SettingsMicsMicEffects()
        effects.equalizers = [band(100), band(200, enabled: false), band(300), band(400)]
        #expect(makeAudioMixerSourceEffects(effects: effects) == [
            .equalizer(AudioMixerEqualizer(frequency: 100, gain: 0, bandwidth: 1)),
            .equalizer(AudioMixerEqualizer(frequency: 300, gain: 0, bandwidth: 1)),
        ])
        effects.equalizers = [band(100, enabled: false)]
        #expect(!effects.isEnabled)
        #expect(makeAudioMixerSourceEffects(effects: effects).isEmpty)
    }

    @Test
    func outputEffectsAreUpToThreeBandsAndDeEsser() throws {
        func band(_ frequency: Float, enabled: Bool = true) -> SettingsAudioMixerEqualizer {
            var band = SettingsAudioMixerEqualizer()
            band.enabled = enabled
            band.frequency = frequency
            return band
        }
        let effects = SettingsAudioOutputEffects()
        effects.equalizers = [band(100), band(200, enabled: false), band(300), band(400)]
        effects.deEsser.enabled = true
        let result = makeAudioMixerOutputEffects(effects: effects)
        try #require(result.count == 3)
        #expect(result[0] == .equalizer(AudioMixerEqualizer(frequency: 100, gain: 0, bandwidth: 1)))
        #expect(result[1] == .equalizer(AudioMixerEqualizer(frequency: 300, gain: 0, bandwidth: 1)))
        #expect(result[2] == .deEsser(AudioMixerDeEsserSettings()))
        #expect(!result.contains(.equalizer(AudioMixerEqualizer(frequency: 400, gain: 0, bandwidth: 1))))
        let onMaster = result.allSatisfy(\.canUseOnMaster)
        #expect(onMaster)
    }

    @Test
    func effectDraftSavesOnReleaseWhileDragging() {
        var draft = MixerEffectDraft()
        draft.beginEditing()
        let first = draft.set(3)
        let second = draft.set(4)
        #expect(!first && !second)
        #expect(draft.value == 4)
        let released = draft.endEditing()
        #expect(released == 4)
        #expect(draft.value == nil)
        #expect(!draft.isEditing)
    }

    @Test
    func effectDraftSavesAdjustmentsWithoutDrag() {
        var draft = MixerEffectDraft()
        let needsPause = draft.set(-6)
        #expect(needsPause)
        let pending = draft.take()
        #expect(pending == -6)
        let again = draft.take()
        #expect(again == nil)
        let released = draft.endEditing()
        #expect(released == nil)
    }
}
