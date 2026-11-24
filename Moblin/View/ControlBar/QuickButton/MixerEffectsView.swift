import SwiftUI

private let effectsSampleRate: Double = 48000

func formatMixerFrequency(_ frequency: Float) -> String {
    guard frequency.isFinite else {
        return "-"
    }
    if frequency >= 1000 {
        return "\(formatOneDecimal(frequency / 1000)) kHz"
    }
    return "\(Int(frequency.clamped(to: 0 ... 1000).rounded())) Hz"
}

private func formatDb(_ value: Float) -> String {
    "\(formatOneDecimal(value)) dB"
}

private func formatMilliseconds(_ seconds: Float) -> String {
    guard seconds.isFinite else {
        return "-"
    }
    return "\(Int((seconds.clamped(to: 0 ... 60) * 1000).rounded())) ms"
}

func makeMixerEqualizerSummary(_ equalizer: SettingsAudioMixerEqualizer) -> String {
    String(localized: """
    \(formatMixerFrequency(equalizer.frequency)), \(formatDb(equalizer.gain)), \
    width \(formatOneDecimal(equalizer.bandwidth)) oct
    """)
}

private func makeExpanderSummary(_ expander: SettingsAudioMixerExpander) -> String {
    String(localized: "Below \(formatDb(expander.threshold)), ratio \(formatOneDecimal(expander.ratio))")
}

private func makeCompressorSummary(_ compressor: SettingsAudioMixerCompressor) -> String {
    String(localized: "\(formatDb(compressor.threshold)), headroom \(formatDb(compressor.headroom))")
}

private func makeDeEsserSummary(_ deEsser: SettingsAudioMixerDeEsser) -> String {
    String(localized: """
    \(formatMixerFrequency(deEsser.frequency)), \(formatDb(deEsser.threshold)), \
    up to \(formatDb(deEsser.maximumReduction))
    """)
}

func makeMixerSourceEffectsSummary(_ effects: SettingsMicsMicEffects) -> String {
    var names: [String] = []
    if effects.expander.enabled {
        names.append(String(localized: "Expander"))
    }
    if effects.equalizers.contains(where: \.enabled) {
        names.append(String(localized: "EQ"))
    }
    if effects.compressor.enabled {
        names.append(String(localized: "Compressor"))
    }
    if effects.deEsser.enabled {
        names.append(String(localized: "De-esser"))
    }
    return names.isEmpty ? String(localized: "Off") : names.joined(separator: ", ")
}

func makeMixerOutputEffectsSummary(_ effects: SettingsAudioOutputEffects) -> String {
    var names: [String] = []
    if effects.equalizers.contains(where: \.enabled) {
        names.append(String(localized: "EQ"))
    }
    if effects.deEsser.enabled {
        names.append(String(localized: "De-esser"))
    }
    return names.isEmpty ? String(localized: "Off") : names.joined(separator: ", ")
}

func mixerEqualizerResponse(_ equalizers: [SettingsAudioMixerEqualizer], frequency: Double) -> Double {
    var total: Double = 0
    for equalizer in equalizers where equalizer.enabled {
        let gain = Double(equalizer.gain)
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * Double(equalizer.frequency) / effectsSampleRate
        let bandwidth = Double(equalizer.bandwidth.clamped(to: 0.05 ... 5))
        let alpha = sin(w0) * sinh(log(2) / 2 * bandwidth * w0 / sin(w0))
        let b0 = 1 + alpha * a
        let b1 = -2 * cos(w0)
        let b2 = 1 - alpha * a
        let a0 = 1 + alpha / a
        let a1 = -2 * cos(w0)
        let a2 = 1 - alpha / a
        let w = 2 * Double.pi * frequency / effectsSampleRate
        let numerator = magnitudeSquared(b0, b1, b2, w)
        let denominator = magnitudeSquared(a0, a1, a2, w)
        total += 10 * log10(numerator / denominator)
    }
    return total
}

private func magnitudeSquared(_ c0: Double, _ c1: Double, _ c2: Double, _ w: Double) -> Double {
    let real = c0 + c1 * cos(w) + c2 * cos(2 * w)
    let imaginary = -c1 * sin(w) - c2 * sin(2 * w)
    return real * real + imaginary * imaginary
}

struct MixerEffectsMarkView: View {
    @ObservedObject var effects: SettingsMicsMicEffects

    var body: some View {
        if effects.isEnabled {
            MixerFxMarkView()
        }
    }
}

struct MixerOutputEffectsMarkView: View {
    @ObservedObject var effects: SettingsAudioOutputEffects

    var body: some View {
        if effects.isEnabled {
            MixerFxMarkView()
        }
    }
}

struct MixerFxMarkView: View {
    var body: some View {
        Text(verbatim: "fx")
            .font(.system(.footnote, design: .serif))
            .italic()
            .bold()
            .foregroundStyle(.secondary)
            .accessibilityLabel("Effects")
    }
}

private struct MixerEqualizerCurveView: View {
    let equalizers: [SettingsAudioMixerEqualizer]

    private func x(_ frequency: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(log10(frequency / 20) / 3) * width
    }

    private func y(_ gain: Double, _ height: CGFloat) -> CGFloat {
        height / 2 - CGFloat(gain.clamped(to: -12 ... 12) / 12) * (height / 2 - 4)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                Path { path in
                    for frequency in [100.0, 1000, 10000] {
                        path.move(to: CGPoint(x: x(frequency, width), y: 0))
                        path.addLine(to: CGPoint(x: x(frequency, width), y: height))
                    }
                    path.move(to: CGPoint(x: 0, y: height / 2))
                    path.addLine(to: CGPoint(x: width, y: height / 2))
                }
                .stroke(Color(UIColor.separator), lineWidth: 1)
                Path { path in
                    let steps = 120
                    for step in 0 ... steps {
                        let frequency = 20 * pow(1000, Double(step) / Double(steps))
                        let response = mixerEqualizerResponse(equalizers, frequency: frequency)
                        let point = CGPoint(x: x(frequency, width), y: y(response, height))
                        if step == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(.blue, lineWidth: 2)
                ForEach(equalizers.filter(\.enabled)) { equalizer in
                    let frequency = Double(equalizer.frequency)
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .position(x: x(frequency, width),
                                  y: y(mixerEqualizerResponse(equalizers, frequency: frequency), height))
                }
            }
        }
        .frame(height: 64)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

struct MixerEffectDraft {
    private(set) var value: Float?
    private(set) var isEditing = false

    mutating func beginEditing() {
        isEditing = true
    }

    mutating func set(_ newValue: Float) -> Bool {
        value = newValue
        return !isEditing
    }

    mutating func endEditing() -> Float? {
        isEditing = false
        return take()
    }

    mutating func take() -> Float? {
        defer {
            value = nil
        }
        return value
    }
}

private struct MixerEffectSliderView: View {
    let label: LocalizedStringKey
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    var logarithmic = false
    let format: (Float) -> String
    let onEditingEnded: () -> Void
    @State private var draft = MixerEffectDraft()
    @State private var pendingCommit: Task<Void, Never>?

    private var current: Float {
        (draft.value ?? value).clamped(to: range)
    }

    private var position: Binding<Float> {
        Binding(get: {
            logarithmic ? log10(current) : current
        }, set: {
            let newValue = logarithmic ? pow(10, $0) : $0
            if draft.set(((newValue / step).rounded() * step).clamped(to: range)) {
                commitAfterPause()
            }
        })
    }

    private var positionRange: ClosedRange<Float> {
        logarithmic ? log10(range.lowerBound) ... log10(range.upperBound) : range
    }

    private func editingChanged(_ editing: Bool) {
        pendingCommit?.cancel()
        if editing {
            draft.beginEditing()
        } else {
            save(draft.endEditing())
            onEditingEnded()
        }
    }

    private func commitAfterPause() {
        pendingCommit?.cancel()
        pendingCommit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            commitPending()
        }
    }

    private func commitPending() {
        guard let pending = draft.take() else {
            return
        }
        save(pending)
        onEditingEnded()
    }

    private func save(_ newValue: Float?) {
        if let newValue {
            value = newValue
        }
    }

    var body: some View {
        HStack {
            Text(label)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(width: 105, alignment: .leading)
            if logarithmic {
                Slider(value: position, in: positionRange, onEditingChanged: editingChanged)
            } else {
                Slider(value: position, in: positionRange, step: step, onEditingChanged: editingChanged)
            }
            Text(format(current))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 75, alignment: .trailing)
        }
        .onDisappear {
            pendingCommit?.cancel()
            if !draft.isEditing {
                commitPending()
            }
        }
    }
}

private struct MixerEffectHeaderView: View {
    let name: LocalizedStringKey
    let summary: String
    @Binding var enabled: Bool
    let expanded: Bool
    let toggleExpanded: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(enabled ? summary : String(localized: "Off"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .onChange(of: enabled) { _ in
                    onToggle()
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleExpanded()
        }
    }
}

struct MixerEqualizerControlsView: View {
    @Binding var equalizer: SettingsAudioMixerEqualizer
    let onEditingEnded: () -> Void

    var body: some View {
        MixerEffectSliderView(label: "Frequency",
                              value: $equalizer.frequency,
                              range: audioMixerEqualizerFrequencyRange,
                              step: 1,
                              logarithmic: true,
                              format: formatMixerFrequency,
                              onEditingEnded: onEditingEnded)
        MixerEffectSliderView(label: "Gain",
                              value: $equalizer.gain,
                              range: audioMixerEqualizerGainRange,
                              step: 0.5,
                              format: formatDb,
                              onEditingEnded: onEditingEnded)
        MixerEffectSliderView(label: "Width",
                              value: $equalizer.bandwidth,
                              range: audioMixerBandwidthRange,
                              step: 0.1,
                              format: { String(localized: "\(formatOneDecimal($0)) oct") },
                              onEditingEnded: onEditingEnded)
    }
}

private struct MixerDeEsserControlsView: View {
    @Binding var deEsser: SettingsAudioMixerDeEsser
    let onEditingEnded: () -> Void

    var body: some View {
        MixerEffectSliderView(label: "Frequency",
                              value: $deEsser.frequency,
                              range: audioMixerDeEsserFrequencyRange,
                              step: 100,
                              logarithmic: true,
                              format: formatMixerFrequency,
                              onEditingEnded: onEditingEnded)
        MixerEffectSliderView(label: "Threshold",
                              value: $deEsser.threshold,
                              range: audioMixerDeEsserThresholdRange,
                              step: 1,
                              format: formatDb,
                              onEditingEnded: onEditingEnded)
        MixerEffectSliderView(label: "Maximum",
                              value: $deEsser.maximumReduction,
                              range: audioMixerMaximumReductionRange,
                              step: 0.5,
                              format: formatDb,
                              onEditingEnded: onEditingEnded)
        MixerEffectSliderView(label: "Width",
                              value: $deEsser.bandwidth,
                              range: audioMixerBandwidthRange,
                              step: 0.1,
                              format: { String(localized: "\(formatOneDecimal($0)) oct") },
                              onEditingEnded: onEditingEnded)
    }
}

private struct MixerTimingView: View {
    @Binding var attack: Float
    @Binding var release: Float
    let onEditingEnded: () -> Void

    var body: some View {
        DisclosureGroup {
            MixerEffectSliderView(label: "Attack",
                                  value: $attack,
                                  range: audioMixerAttackRange,
                                  step: 0.001,
                                  format: formatMilliseconds,
                                  onEditingEnded: onEditingEnded)
            MixerEffectSliderView(label: "Release",
                                  value: $release,
                                  range: audioMixerReleaseRange,
                                  step: 0.01,
                                  format: formatMilliseconds,
                                  onEditingEnded: onEditingEnded)
        } label: {
            HStack {
                Text("Timing")
                Spacer()
                Text("Attack \(formatMilliseconds(attack)), release \(formatMilliseconds(release))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct MixerEqualizerBandsView: View {
    @Binding var equalizers: [SettingsAudioMixerEqualizer]
    let isExpanded: (UUID) -> Bool
    let toggle: (UUID) -> Void
    let expand: (UUID) -> Void
    let update: () -> Void

    var body: some View {
        if !equalizers.isEmpty {
            MixerEqualizerCurveView(equalizers: equalizers)
        }
        ForEach($equalizers) { $equalizer in
            let index = (equalizers.firstIndex(where: { $0.id == equalizer.id }) ?? 0) + 1
            MixerEffectHeaderView(name: "Band \(index)",
                                  summary: makeMixerEqualizerSummary(equalizer),
                                  enabled: $equalizer.enabled,
                                  expanded: isExpanded(equalizer.id),
                                  toggleExpanded: { toggle(equalizer.id) },
                                  onToggle: update)
            if isExpanded(equalizer.id) {
                MixerEqualizerControlsView(equalizer: $equalizer, onEditingEnded: update)
            }
        }
        .onDelete { offsets in
            equalizers.remove(atOffsets: offsets)
            update()
        }
        if equalizers.count < audioMixerMaximumEqualizers {
            Button {
                var equalizer = SettingsAudioMixerEqualizer()
                equalizer.enabled = true
                equalizers.append(equalizer)
                expand(equalizer.id)
                update()
            } label: {
                Label("Add band", systemImage: "plus")
            }
        }
    }
}

private enum MixerSourceEffect: Equatable {
    case expander
    case equalizer(UUID)
    case compressor
    case deEsser
}

struct MixerSourceEffectsView: View {
    let model: Model
    @ObservedObject var effects: SettingsMicsMicEffects
    @State private var expanded: MixerSourceEffect?

    private func toggle(_ effect: MixerSourceEffect) {
        expanded = expanded == effect ? nil : effect
    }

    private func update() {
        model.updateMixedMics()
    }

    var body: some View {
        Form {
            Section {
                MixerEffectHeaderView(name: "Expander",
                                      summary: makeExpanderSummary(effects.expander),
                                      enabled: $effects.expander.enabled,
                                      expanded: expanded == .expander,
                                      toggleExpanded: { toggle(.expander) },
                                      onToggle: update)
                if expanded == .expander {
                    MixerEffectSliderView(label: "Threshold",
                                          value: $effects.expander.threshold,
                                          range: audioMixerExpanderThresholdRange,
                                          step: 1,
                                          format: formatDb,
                                          onEditingEnded: update)
                    MixerEffectSliderView(label: "Ratio",
                                          value: $effects.expander.ratio,
                                          range: audioMixerRatioRange,
                                          step: 0.5,
                                          format: { formatOneDecimal($0) },
                                          onEditingEnded: update)
                    MixerTimingView(attack: $effects.expander.attack,
                                    release: $effects.expander.release,
                                    onEditingEnded: update)
                }
            } footer: {
                if expanded == .expander {
                    Text("Turns down noise below the threshold.")
                }
            }
            Section {
                MixerEqualizerBandsView(equalizers: $effects.equalizers,
                                        isExpanded: { expanded == .equalizer($0) },
                                        toggle: { toggle(.equalizer($0)) },
                                        expand: { expanded = .equalizer($0) },
                                        update: update)
            } header: {
                Text("EQ")
            }
            Section {
                MixerEffectHeaderView(name: "Compressor",
                                      summary: makeCompressorSummary(effects.compressor),
                                      enabled: $effects.compressor.enabled,
                                      expanded: expanded == .compressor,
                                      toggleExpanded: { toggle(.compressor) },
                                      onToggle: update)
                if expanded == .compressor {
                    MixerEffectSliderView(label: "Threshold",
                                          value: $effects.compressor.threshold,
                                          range: audioMixerCompressorThresholdRange,
                                          step: 1,
                                          format: formatDb,
                                          onEditingEnded: update)
                    MixerEffectSliderView(label: "Headroom",
                                          value: $effects.compressor.headroom,
                                          range: audioMixerHeadroomRange,
                                          step: 0.5,
                                          format: formatDb,
                                          onEditingEnded: update)
                    MixerEffectSliderView(label: "Make-up gain",
                                          value: $effects.compressor.makeupGain,
                                          range: audioMixerMakeupGainRange,
                                          step: 0.5,
                                          format: formatDb,
                                          onEditingEnded: update)
                    MixerTimingView(attack: $effects.compressor.attack,
                                    release: $effects.compressor.release,
                                    onEditingEnded: update)
                }
            }
            Section {
                MixerEffectHeaderView(name: "De-esser",
                                      summary: makeDeEsserSummary(effects.deEsser),
                                      enabled: $effects.deEsser.enabled,
                                      expanded: expanded == .deEsser,
                                      toggleExpanded: { toggle(.deEsser) },
                                      onToggle: update)
                if expanded == .deEsser {
                    MixerDeEsserControlsView(deEsser: $effects.deEsser, onEditingEnded: update)
                }
            } footer: {
                Text("Effects run in this order, after Voice and before gain.")
            }
        }
        .navigationTitle("Effects")
    }
}

struct MixerSourceEffectsLinkView: View {
    let model: Model
    @ObservedObject var effects: SettingsMicsMicEffects

    var body: some View {
        NavigationLink {
            MixerSourceEffectsView(model: model, effects: effects)
        } label: {
            HStack {
                Text("Effects")
                Spacer()
                Text(makeMixerSourceEffectsSummary(effects))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

struct MixerOutputEffectsView: View {
    let model: Model
    @ObservedObject var effects: SettingsAudioOutputEffects
    @State private var expandedId: UUID?
    @State private var deEsserExpanded = false

    private func update() {
        model.updateMixedMics()
    }

    private func toggle(_ id: UUID) {
        expandedId = expandedId == id ? nil : id
        deEsserExpanded = false
    }

    var body: some View {
        Form {
            Section {
                MixerEqualizerBandsView(equalizers: $effects.equalizers,
                                        isExpanded: { expandedId == $0 },
                                        toggle: toggle,
                                        expand: {
                                            expandedId = $0
                                            deEsserExpanded = false
                                        },
                                        update: update)
            } header: {
                Text("EQ")
            }
            Section {
                MixerEffectHeaderView(name: "De-esser",
                                      summary: makeDeEsserSummary(effects.deEsser),
                                      enabled: $effects.deEsser.enabled,
                                      expanded: deEsserExpanded,
                                      toggleExpanded: {
                                          deEsserExpanded.toggle()
                                          expandedId = nil
                                      },
                                      onToggle: update)
                if deEsserExpanded {
                    MixerDeEsserControlsView(deEsser: $effects.deEsser, onEditingEnded: update)
                }
            } footer: {
                Text("""
                Stream and recording, before output gain. \
                Compressor and expander are set per source.
                """)
            }
        }
        .navigationTitle("Output effects")
    }
}

struct MixerOutputEffectsLinkView: View {
    let model: Model
    @ObservedObject var effects: SettingsAudioOutputEffects

    var body: some View {
        NavigationLink {
            MixerOutputEffectsView(model: model, effects: effects)
        } label: {
            HStack {
                Text("Output effects")
                Spacer()
                Text(makeMixerOutputEffectsSummary(effects))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
