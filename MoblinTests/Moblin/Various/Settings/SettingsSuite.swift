import Foundation
@testable import Moblin
import Testing

struct SettingsSuite {
    struct MicIdCase: CustomTestStringConvertible {
        let channel: Int?
        let id: String

        var testDescription: String {
            id
        }
    }

    struct MicEqualityCase: CustomTestStringConvertible {
        let testDescription: String
        let channel: Int?
        let otherChannel: Int?
        let expected: Bool
    }

    @Test
    func streamUrlSchemeSelectsProtocol() {
        let stream = SettingsStream(name: "Test")
        stream.url = "mobcam://localhost:7777"
        #expect(stream.getProtocol() == .mobcam)
        #expect(stream.getDetailedProtocol() == .mobcam)
        #expect(stream.protocolString() == "Mobcam")
        #expect(stream.mobcamPort() == 7777)
        #expect(!stream.isBonding())
        stream.url = "mobcam://localhost"
        #expect(stream.mobcamPort() == DefaultTcpPorts.mobcamStream)
    }

    @Test
    func chatFilter() {
        let filter = SettingsChatFilter()
        filter.enabled = true
        filter.user = ""
        filter.messageStartWords = ["!"]
        #expect(filter.isMatching(user: "erik", segments: [.init(id: 0, text: "!moblin")]))
        #expect(filter.isMatching(user: "erik", segments: [.init(id: 0, text: "!")]))
        #expect(!filter.isMatching(user: "erik", segments: [.init(id: 0, text: "@foo")]))
        #expect(!filter.isMatching(user: "erik", segments: [.init(id: 0, text: "@")]))
        filter.messageStartWords = ["hell", "h"]
        #expect(filter.isMatching(user: "erik",
                                  segments: [
                                      .init(id: 0, text: "hell"),
                                      .init(id: 0, text: "hi"),
                                      .init(id: 0, text: "ho"),
                                  ]))
        #expect(!filter.isMatching(user: "erik",
                                   segments: [
                                       .init(id: 0, text: "hello"),
                                       .init(id: 0, text: "hi"),
                                       .init(id: 0, text: "ho"),
                                   ]))
    }

    @Test
    func textToSpeechVoicesWithoutElevenLabsDecode() throws {
        let json = """
        {"textToSpeechLanguageVoices":{"en":{"type":"ttsMonster","apple":{"voice":""},\
        "ttsMonster":{"name":"Axel","voiceId":"abc"}}}}
        """
        let chat = try JSONDecoder().decode(SettingsChat.self, from: Data(json.utf8))
        let voice = try #require(chat.textToSpeechLanguageVoices["en"])
        #expect(voice.type == .ttsMonster)
        #expect(voice.ttsMonster.voiceId == "abc")
        #expect(voice.elevenLabs.voiceId == "")
    }

    @Test
    func textToSpeechElevenLabsVoiceRoundTrips() throws {
        let chat = SettingsChat()
        chat.elevenLabs.apiKey = "key"
        let voice = SettingsVoice()
        voice.type = .elevenLabs
        voice.elevenLabs.name = "Rachel"
        voice.elevenLabs.voiceId = "21m00Tcm4TlvDq8ikWAM"
        chat.textToSpeechLanguageVoices["en"] = voice
        let decoded = try JSONDecoder().decode(SettingsChat.self, from: JSONEncoder().encode(chat))
        #expect(decoded.elevenLabs.apiKey == "key")
        let decodedVoice = try #require(decoded.textToSpeechLanguageVoices["en"])
        #expect(decodedVoice.type == .elevenLabs)
        #expect(decodedVoice.elevenLabs.name == "Rachel")
        #expect(decodedVoice.elevenLabs.voiceId == "21m00Tcm4TlvDq8ikWAM")
    }

    @Test
    func textToSpeechSayEmotesDefaultsToOff() throws {
        let chat = try JSONDecoder().decode(SettingsChat.self, from: Data("{}".utf8))
        #expect(!chat.textToSpeechSayEmotes)
    }

    @Test
    func textToSpeechSayEmotesIsPersisted() throws {
        let chat = SettingsChat()
        chat.textToSpeechSayEmotes = true
        let decoded = try JSONDecoder().decode(SettingsChat.self, from: JSONEncoder().encode(chat))
        #expect(decoded.textToSpeechSayEmotes)
    }

    @Test
    func debugAudioMixerDefaultsToOff() throws {
        let debug = try JSONDecoder().decode(SettingsDebug.self, from: Data("{}".utf8))
        #expect(!debug.audioMixer)
    }

    @Test
    func debugAudioMixerIsPersisted() throws {
        let debug = SettingsDebug()
        debug.audioMixer = true
        let decoded = try JSONDecoder().decode(SettingsDebug.self, from: JSONEncoder().encode(debug))
        #expect(decoded.audioMixer)
    }

    @Test
    func micMixedDefaultsToOff() throws {
        let mic = try JSONDecoder().decode(SettingsMicsMic.self, from: Data("{}".utf8))
        #expect(!mic.mixed)
    }

    @Test
    func micMixedIsPersisted() throws {
        let mic = SettingsMicsMic()
        mic.mixed = true
        let decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.mixed)
    }

    @Test
    func micChannel() throws {
        let mic = SettingsMicsMic()
        var decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.channel == nil)
        mic.channel = 2
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.channel == 2)
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data("{}".utf8))
        #expect(decoded.channel == nil)
    }

    @Test
    func micProcessing() throws {
        let mic = SettingsMicsMic()
        var decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.processing == .none)
        mic.processing = .voice
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.processing == .voice)
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data("{}".utf8))
        #expect(decoded.processing == .none)
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data(#"{"processing":"Loud"}"#.utf8))
        #expect(decoded.processing == .none)
    }

    @Test
    func micOutput() throws {
        let mic = SettingsMicsMic()
        var decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.output == .streamAndRecording)
        mic.output = .stream
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.output == .stream)
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data("{}".utf8))
        #expect(decoded.output == .streamAndRecording)
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data(#"{"output":"Monitor"}"#.utf8))
        #expect(decoded.output == .streamAndRecording)
    }

    @Test
    func micEffects() throws {
        let mic = SettingsMicsMic()
        var decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(!decoded.effects.isEnabled)
        mic.effects.compressor.enabled = true
        mic.effects.compressor.threshold = -18
        var low = SettingsAudioMixerEqualizer()
        low.frequency = 250
        var high = SettingsAudioMixerEqualizer()
        high.enabled = true
        high.frequency = 4000
        mic.effects.equalizers = [low, high]
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.effects.isEnabled)
        #expect(decoded.effects.compressor == mic.effects.compressor)
        #expect(decoded.effects.equalizers == [low, high])
        #expect(!decoded.effects.expander.enabled)
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data(#"{"name":"Mic"}"#.utf8))
        #expect(!decoded.effects.isEnabled)
        #expect(decoded.effects.equalizers.isEmpty)
        #expect(decoded.effects.compressor == SettingsAudioMixerCompressor())
        let json = #"{"effects":{"deEsser":{"enabled":true}}}"#
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data(json.utf8))
        #expect(decoded.effects.deEsser.enabled)
        #expect(decoded.effects.deEsser.frequency == 6000)
        #expect(decoded.effects.compressor.threshold == -24)
    }

    @Test
    func micEffectsAreClampedOnDecode() throws {
        let json = #"""
        {"effects":{"equalizers":[{"enabled":true,"frequency":-1e30,"gain":40,"bandwidth":0}],
        "compressor":{"threshold":10,"headroom":0,"attack":5,"release":0,"makeupGain":100},
        "expander":{"threshold":-200,"ratio":0},
        "deEsser":{"frequency":100,"bandwidth":9,"threshold":20,"maximumReduction":-3}}}
        """#
        let effects = try JSONDecoder().decode(SettingsMicsMic.self, from: Data(json.utf8)).effects
        let equalizer = try #require(effects.equalizers.first)
        #expect(equalizer.frequency == audioMixerEqualizerFrequencyRange.lowerBound)
        #expect(equalizer.gain == audioMixerEqualizerGainRange.upperBound)
        #expect(equalizer.bandwidth == audioMixerBandwidthRange.lowerBound)
        #expect(effects.compressor.threshold == audioMixerCompressorThresholdRange.upperBound)
        #expect(effects.compressor.headroom == audioMixerHeadroomRange.lowerBound)
        #expect(effects.compressor.attack == audioMixerAttackRange.upperBound)
        #expect(effects.compressor.release == audioMixerReleaseRange.lowerBound)
        #expect(effects.compressor.makeupGain == audioMixerMakeupGainRange.upperBound)
        #expect(effects.expander.threshold == audioMixerExpanderThresholdRange.lowerBound)
        #expect(effects.expander.ratio == audioMixerRatioRange.lowerBound)
        #expect(effects.deEsser.frequency == audioMixerDeEsserFrequencyRange.lowerBound)
        #expect(effects.deEsser.bandwidth == audioMixerBandwidthRange.upperBound)
        #expect(effects.deEsser.threshold == audioMixerDeEsserThresholdRange.upperBound)
        #expect(effects.deEsser.maximumReduction == audioMixerMaximumReductionRange.lowerBound)
        #expect(formatMixerFrequency(equalizer.frequency) == "20 Hz")
    }

    @Test
    func audioOutputEffects() throws {
        let audio = SettingsAudio()
        var decoded = try JSONDecoder().decode(SettingsAudio.self, from: JSONEncoder().encode(audio))
        #expect(!decoded.outputEffects.isEnabled)
        var equalizer = SettingsAudioMixerEqualizer()
        equalizer.enabled = true
        equalizer.gain = 2
        audio.outputEffects.equalizers = [equalizer]
        decoded = try JSONDecoder().decode(SettingsAudio.self, from: JSONEncoder().encode(audio))
        #expect(decoded.outputEffects.equalizers == [equalizer])
        #expect(decoded.outputEffects.isEnabled)
        decoded = try JSONDecoder().decode(SettingsAudio.self, from: Data("{}".utf8))
        #expect(decoded.outputEffects.equalizers.isEmpty)
    }

    @Test
    func micMuted() throws {
        let mic = SettingsMicsMic()
        var decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(!decoded.muted)
        mic.muted = true
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: JSONEncoder().encode(mic))
        #expect(decoded.muted)
        decoded = try JSONDecoder().decode(SettingsMicsMic.self, from: Data("{}".utf8))
        #expect(!decoded.muted)
    }

    @Test(arguments: [
        MicIdCase(channel: nil, id: "AppleUSBAudioEngine:1 0"),
        MicIdCase(channel: 2, id: "AppleUSBAudioEngine:1 0 2"),
    ])
    func micId(_ testCase: MicIdCase) {
        let mic = SettingsMicsMic(name: "USB Audio", inputUid: "AppleUSBAudioEngine:1", connected: true)
        mic.channel = testCase.channel
        #expect(mic.id == testCase.id)
    }

    @Test(arguments: [
        MicEqualityCase(testDescription: "whole devices", channel: nil, otherChannel: nil, expected: true),
        MicEqualityCase(testDescription: "same channel", channel: 1, otherChannel: 1, expected: true),
        MicEqualityCase(testDescription: "only one channel", channel: 1, otherChannel: nil, expected: false),
        MicEqualityCase(testDescription: "different channels", channel: 1, otherChannel: 2, expected: false),
    ])
    func micEquality(_ testCase: MicEqualityCase) {
        let mic = SettingsMicsMic(name: "USB Audio", inputUid: "AppleUSBAudioEngine:1", connected: true)
        mic.channel = testCase.channel
        let otherMic = SettingsMicsMic(name: "USB Audio", inputUid: "AppleUSBAudioEngine:1", connected: false)
        otherMic.channel = testCase.otherChannel
        #expect((mic == otherMic) == testCase.expected)
    }

    @Test
    func widgetSceneId() throws {
        let scene = SettingsWidgetScene()
        #expect(scene.sceneId == nil)
        var decoded = try JSONDecoder().decode(SettingsWidgetScene.self, from: JSONEncoder().encode(scene))
        #expect(decoded.sceneId == nil)
        scene.sceneId = UUID()
        decoded = try JSONDecoder().decode(SettingsWidgetScene.self, from: JSONEncoder().encode(scene))
        #expect(decoded.sceneId == scene.sceneId)
        decoded = try JSONDecoder().decode(SettingsWidgetScene.self, from: Data("{}".utf8))
        #expect(decoded.sceneId == nil)
    }
}
