import Combine
import SwiftUI

private let mixerIconSize: CGFloat = 34

private func mixerSourceImage(mic: SettingsMicsMic) -> String {
    if mic.isScreenCapture() {
        "rectangle.on.rectangle"
    } else if mic.isMediaPlayer() {
        "play.rectangle"
    } else if mic.isNetwork() {
        "dot.radiowaves.left.and.right"
    } else {
        "mic"
    }
}

private func mixerMeterFraction(_ level: Float) -> CGFloat {
    CGFloat((level - zeroThresholdDb).clamped(to: 0 ... -zeroThresholdDb) / -zeroThresholdDb)
}

private struct MixerMeterView: View {
    @ObservedObject var level: AudioLevel
    var dimmed = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let green = mixerMeterFraction(min(level.level, yellowThresholdDb))
            let yellow = mixerMeterFraction(min(level.level, redThresholdDb))
            let red = mixerMeterFraction(level.level)
            HStack(spacing: 0) {
                Rectangle()
                    .frame(width: green * width)
                    .foregroundStyle(.green)
                Rectangle()
                    .frame(width: (yellow - green) * width)
                    .foregroundStyle(.yellow)
                Rectangle()
                    .frame(width: (red - yellow) * width)
                    .foregroundStyle(.red)
                Spacer(minLength: 0)
            }
            .background(Color(UIColor.tertiarySystemFill))
        }
        .frame(height: 5)
        .opacity(dimmed ? 0.5 : 1)
    }
}

private struct MixerTagView: View {
    let text: Text

    var body: some View {
        text
            .font(.caption)
            .bold()
            .padding(.horizontal, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.secondary)
            }
    }
}

private struct MixerMuteImageView: View {
    let muted: Bool
    let image: String
    var main = false

    var body: some View {
        Image(systemName: muted ? "speaker.slash.fill" : image)
            .frame(width: mixerIconSize, height: mixerIconSize)
            .foregroundStyle(muted ? .white : main ? Color(UIColor.systemBackground) : .primary)
            .background {
                Circle()
                    .foregroundStyle(muted ? .red : main ? .primary : Color(UIColor.tertiarySystemFill))
            }
    }
}

private struct MixerSourceHeaderView: View {
    let model: Model
    @ObservedObject var mic: SettingsMicsMic
    let main: Bool
    var expanded: Bool?
    var swapMic: (() -> Void)?

    var body: some View {
        HStack {
            MixerMuteImageView(muted: mic.muted, image: mixerSourceImage(mic: mic), main: main)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(mic.name)
                        .lineLimit(2)
                    Spacer()
                    if mic.muted, expanded != true {
                        Text("Muted")
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .fixedSize()
                    } else {
                        Text("\(formatOneDecimal(mic.gainDb)) dB")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let expanded, swapMic == nil {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                HStack {
                    MixerMeterView(level: model.audioMixerMeters.source(id: mic.id), dimmed: mic.muted)
                    MixerEffectsMarkView(effects: mic.effects)
                    if main {
                        MixerTagView(text: Text("Main"))
                    }
                    if mic.output != .streamAndRecording {
                        MixerTagView(text: Text(mic.output.toString()))
                    }
                }
            }
            if let swapMic {
                Button {
                    swapMic()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: mixerIconSize, height: mixerIconSize)
                        .foregroundStyle(.blue)
                        .background {
                            Circle()
                                .foregroundStyle(Color(UIColor.tertiarySystemFill))
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Change main mic")
            }
        }
    }
}

private struct MixerSourceView: View {
    let model: Model
    @ObservedObject var mic: SettingsMicsMic
    let main: Bool
    let expanded: Bool
    let toggleExpanded: () -> Void
    let showSettings: () -> Void
    var swapMic: (() -> Void)?

    var body: some View {
        MixerSourceHeaderView(model: model, mic: mic, main: main, expanded: expanded, swapMic: swapMic)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleExpanded()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    showSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .tint(.gray)
                Button {
                    model.setMicMuted(mic: mic, muted: !mic.muted)
                } label: {
                    if mic.muted {
                        Label("Unmute", systemImage: "speaker.wave.2")
                    } else {
                        Label("Mute", systemImage: "speaker.slash")
                    }
                }
                .tint(mic.muted ? .blue : .red)
            }
    }
}

private struct MixerSourceGainView: View {
    let model: Model
    @ObservedObject var mic: SettingsMicsMic
    let showSettings: () -> Void

    var body: some View {
        HStack {
            Button {
                model.setMicMuted(mic: mic, muted: !mic.muted)
            } label: {
                MixerMuteImageView(muted: mic.muted, image: "speaker.wave.2.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(mic.muted ? Text("Unmute") : Text("Mute"))
            Slider(value: $mic.gainDb, in: -24.0 ... 24.0, step: 1.0)
                .onChange(of: mic.gainDb) { _ in
                    model.updateAudioGain()
                }
            Button {
                showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: mixerIconSize, height: mixerIconSize)
                    .foregroundStyle(.primary)
                    .background {
                        Circle()
                            .foregroundStyle(Color(UIColor.tertiarySystemFill))
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings")
        }
    }
}

private struct MixerSourceDelayView: View {
    let model: Model
    @ObservedObject var mic: SettingsMicsMic

    var body: some View {
        let range = makeMicDelayRange(audioMixer: true)
        HStack {
            Text("Delay")
                .fixedSize()
            Slider(
                value: Binding(get: { mic.delay.clamped(to: range) }, set: { mic.delay = $0 }),
                in: range,
                step: 0.01,
                onEditingChanged: { begin in
                    guard !begin else {
                        return
                    }
                    model.updateMicDelay()
                }
            )
            Text("\(formatThreeDecimals(mic.delay.clamped(to: range))) s")
                .frame(width: 70)
        }
    }
}

private struct MixerSourceSettingsView: View {
    let model: Model
    @ObservedObject var mic: SettingsMicsMic
    @ObservedObject var modelMic: Mic
    @Environment(\.dismiss) var dismiss

    var body: some View {
        let main = mic == modelMic.current
        Form {
            Section {
                MixerSourceHeaderView(model: model, mic: mic, main: main)
            }
            Section {
                Picker("Processing", selection: $mic.processing) {
                    ForEach(SettingsMicsMicProcessing.allCases, id: \.self) {
                        Text($0.toString())
                    }
                }
                .onChange(of: mic.processing) { _ in
                    model.updateMixedMics()
                }
                MixerSourceEffectsLinkView(model: model, effects: mic.effects)
            } footer: {
                Text("Voice removes rumble and evens out the level of speech.")
            }
            Section {
                MixerSourceDelayView(model: model, mic: mic)
            } footer: {
                Text("A positive delay makes the audio later, a negative delay earlier.")
            }
            Section {
                Picker("Output", selection: $mic.output) {
                    ForEach(SettingsMicsMicOutput.allCases, id: \.self) {
                        Text($0.toString())
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: mic.output) { _ in
                    model.updateMixedMics()
                }
            } header: {
                Text("Output")
            }
            if !main {
                Section {
                    Button(role: .destructive) {
                        model.setMicMixed(mic: mic, mixed: false)
                        dismiss()
                    } label: {
                        HCenter {
                            Text("Remove from mix")
                        }
                    }
                }
            }
        }
        .navigationTitle(mic.name)
    }
}

private struct MixerAddSourceRowView: View {
    let image: String
    let text: String
    var effects: SettingsMicsMicEffects?
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                IconAndTextView(image: image, text: text)
                Spacer()
                if let effects {
                    MixerEffectsMarkView(effects: effects)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(11)
    }
}

private func isMixerSourceAddable(_ mic: SettingsMicsMic, current: SettingsMicsMic) -> Bool {
    isAudioMicAddable(mic: mic, current: current)
}

private struct MixerAddSourceItemView: View {
    let model: Model
    @ObservedObject var mic: SettingsMicsMic
    let current: SettingsMicsMic
    let dismiss: () -> Void

    var body: some View {
        if isMixerSourceAddable(mic, current: current) {
            MixerAddSourceRowView(image: mixerSourceImage(mic: mic),
                                  text: mic.name,
                                  effects: mic.effects)
            {
                if isMixerSourceAddable(mic, current: current) {
                    model.setMicMixed(mic: mic, mixed: true)
                }
                dismiss()
            }
        }
    }
}

private struct MixerAddSourceDividerView: View {
    let mics: [SettingsMicsMic]
    let current: SettingsMicsMic
    @State private var visible: Bool

    init(mics: [SettingsMicsMic], current: SettingsMicsMic) {
        self.mics = mics
        self.current = current
        _visible = State(initialValue: Self.isVisible(mics, current))
    }

    private static func isVisible(_ mics: [SettingsMicsMic], _ current: SettingsMicsMic) -> Bool {
        mics.contains(where: { isMixerSourceAddable($0, current: current) })
    }

    private func update() {
        visible = Self.isVisible(mics, current)
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(height: 0)
            if visible {
                Divider()
            }
        }
        .onChange(of: mics) { _ in
            update()
        }
        .onReceive(Publishers.MergeMany(mics.map(\.objectWillChange)).receive(on: DispatchQueue.main)) { _ in
            update()
        }
    }
}

private struct MixerAddSourceListView: View {
    let model: Model
    @ObservedObject var mics: SettingsMics
    let current: SettingsMicsMic
    let createSource: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MixerAddSourceRowView(image: "plus.square.dashed",
                                      text: String(localized: "New source"))
                {
                    dismiss()
                    createSource()
                }
                MixerAddSourceDividerView(mics: mics.mics, current: current)
                ForEach(mics.mics) { mic in
                    MixerAddSourceItemView(model: model, mic: mic, current: current, dismiss: dismiss)
                }
            }
        }
        .frame(minWidth: 260)
        .padding(5)
    }
}

private struct MixerAddSourceView: View {
    let model: Model
    let mics: SettingsMics
    let current: SettingsMicsMic
    let createSource: () -> Void
    @State private var presentingAddSource = false

    var body: some View {
        Button {
            presentingAddSource = true
        } label: {
            Label("Add to mix", systemImage: "plus")
        }
        .popover(isPresented: $presentingAddSource) {
            MixerAddSourceListView(model: model, mics: mics, current: current, createSource: createSource) {
                presentingAddSource = false
            }
            .presentationCompactAdaptation(.none)
        }
    }
}

private struct MixerNewSourceView: View {
    let model: Model
    @ObservedObject var database: Database

    var body: some View {
        Form {
            Section {
                RtmpServerSettingsView(rtmpServer: database.rtmpServer)
                SrtlaServerSettingsView(srtlaServer: database.srtlaServer)
                SrtClientSettingsView(srtClient: database.srtClient)
                RistServerSettingsView(model: model, ristServer: database.ristServer)
                RtspClientSettingsView(model: model, rtspClient: database.rtspClient)
                WhipServerSettingsView(whipServer: database.whipServer)
                WhepClientSettingsView(model: model, whepClient: database.whepClient)
            } header: {
                Text("Ingests")
            } footer: {
                Text("A new stream is listed under Add to mix once it connects.")
            }
            Section {
                NavigationLink {
                    MediaPlayersSettingsView(model: model, mediaPlayers: database.mediaPlayers)
                } label: {
                    Label("Media players", systemImage: "play.rectangle.on.rectangle")
                }
            }
        }
        .navigationTitle("New source")
    }
}

private struct MixerOutputView: View {
    let meters: AudioMixerMeters
    @ObservedObject var audio: SettingsAudio
    @ObservedObject var provider: AudioProvider
    let expanded: Bool
    let toggleExpanded: () -> Void

    @ViewBuilder
    private var status: some View {
        if provider.muted {
            Text("Muted")
                .font(.caption)
                .bold()
                .foregroundStyle(.red)
                .fixedSize()
        }
    }

    private var gain: some View {
        HStack {
            MixerOutputEffectsMarkView(effects: audio.outputEffects)
            Spacer(minLength: 4)
            Text("\(formatOneDecimal(audio.gainDb)) dB")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Output gain")
                        .lineLimit(1)
                        .fixedSize()
                    status
                    gain
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output gain")
                            .lineLimit(2)
                        status
                    }
                    gain
                }
            }
            MixerMeterView(level: meters.output)
            Text("Stream")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleExpanded()
        }
    }
}

private struct MixerOutputGainView: View {
    let model: Model
    @ObservedObject var audio: SettingsAudio

    var body: some View {
        Slider(value: $audio.gainDb, in: 0.0 ... 24.0, step: 1.0)
            .onChange(of: audio.gainDb) { _ in
                model.updateAudioGain()
            }
    }
}

struct QuickButtonMixerView: View {
    let model: Model
    @ObservedObject var mics: SettingsMics
    @ObservedObject var modelMic: Mic
    @State private var expandedId: String?
    @State private var outputExpanded = false
    @State private var settingsMicId: String?
    @State private var presentingSettings = false
    @State private var swappingMic = false
    @State private var presentingNewSource = false

    private func toggleExpanded(id: String, proxy: ScrollViewProxy) {
        expandedId = expandedId == id ? nil : id
        outputExpanded = false
        scrollTo(expandedId, proxy: proxy)
    }

    private func toggleOutputExpanded(proxy: ScrollViewProxy) {
        outputExpanded.toggle()
        expandedId = nil
        scrollTo(outputExpanded ? "output" : nil, proxy: proxy)
    }

    private func scrollTo(_ id: String?, proxy: ScrollViewProxy) {
        guard let id else {
            return
        }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo("\(id) gain")
            }
        }
    }

    private func showSettings(mic: SettingsMicsMic) {
        settingsMicId = mic.id
        presentingSettings = true
    }

    private func mixerSources() -> [SettingsMicsMic] {
        makeMixerSources(currentId: modelMic.current.id, mics: mics.mics, mixed: modelMic.mixed)
    }

    var body: some View {
        let sources = mixerSources()
        let current = model.getMicById(id: modelMic.current.id)
        ScrollViewReader { proxy in
            Form {
                Section {
                    if let current {
                        MixerSourceView(model: model,
                                        mic: current,
                                        main: true,
                                        expanded: expandedId == current.id,
                                        toggleExpanded: { toggleExpanded(id: current.id, proxy: proxy) },
                                        showSettings: { showSettings(mic: current) },
                                        swapMic: {
                                            swappingMic.toggle()
                                            expandedId = nil
                                        })
                        if expandedId == current.id {
                            MixerSourceGainView(model: model, mic: current) {
                                showSettings(mic: current)
                            }
                            .id("\(current.id) gain")
                        }
                    }
                    if swappingMic || current == nil {
                        ForEach(mics.mics) { mic in
                            QuickButtonMicMicView(model: model, mic: mic, modelMic: modelMic)
                                .simultaneousGesture(TapGesture().onEnded {
                                    swappingMic = false
                                })
                                .deleteDisabled(mic == modelMic.current)
                                .contextMenuDeleteButton(disabled: mic == modelMic.current) {
                                    mics.mics.removeAll { $0.id == mic.id }
                                }
                        }
                        .onDelete { offsets in
                            mics.mics.remove(atOffsets: offsets)
                        }
                        .onMove { froms, to in
                            mics.mics.move(fromOffsets: froms, toOffset: to)
                        }
                    }
                } header: {
                    HStack {
                        Text("Mic")
                        Spacer()
                        if swappingMic, current != nil {
                            Button("Done") {
                                swappingMic = false
                            }
                            .textCase(nil)
                        }
                    }
                }
                Section {
                    ForEach(modelMic.mixed) { mic in
                        MixerSourceView(model: model,
                                        mic: mic,
                                        main: false,
                                        expanded: expandedId == mic.id,
                                        toggleExpanded: { toggleExpanded(id: mic.id, proxy: proxy) },
                                        showSettings: { showSettings(mic: mic) })
                        if expandedId == mic.id {
                            MixerSourceGainView(model: model, mic: mic) {
                                showSettings(mic: mic)
                            }
                            .id("\(mic.id) gain")
                        }
                    }
                    MixerAddSourceView(model: model, mics: mics, current: current ?? modelMic.current) {
                        presentingNewSource = true
                    }
                } header: {
                    Text("Mixed in")
                } footer: {
                    Text("Tap for gain. Swipe for mute or settings.")
                }
                Section {
                    MixerOutputView(meters: model.audioMixerMeters,
                                    audio: model.database.audio,
                                    provider: model.audio,
                                    expanded: outputExpanded)
                    {
                        toggleOutputExpanded(proxy: proxy)
                    }
                    if outputExpanded {
                        MixerOutputGainView(model: model, audio: model.database.audio)
                            .id("output gain")
                        MixerOutputEffectsLinkView(model: model, effects: model.database.audio.outputEffects)
                    }
                }
            }
            .onChange(of: sources.map(\.id)) { ids in
                if let expandedId, !ids.contains(expandedId) {
                    self.expandedId = nil
                }
                if let settingsMicId, !ids.contains(settingsMicId) {
                    presentingSettings = false
                }
            }
            .onChange(of: modelMic.current.id) { _ in
                swappingMic = false
            }
            .onChange(of: mics.mics) { _ in
                model.updateMixedMics()
            }
        }
        .navigationTitle("Audio")
        .navigationDestination(isPresented: $presentingNewSource) {
            MixerNewSourceView(model: model, database: model.database)
        }
        .navigationDestination(isPresented: $presentingSettings) {
            if let mic = findMixerSource(id: settingsMicId, sources: mixerSources()) {
                MixerSourceSettingsView(model: model, mic: mic, modelMic: modelMic)
            }
        }
    }
}
