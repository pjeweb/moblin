import Foundation
import SwiftUI

struct QuickButtonMicMicView: View {
    let model: Model
    @ObservedObject var mic: SettingsMicsMic
    @ObservedObject var modelMic: Mic

    var body: some View {
        HStack {
            DraggableItemPrefixView()
            Image(systemName: mic.connected ? "cable.connector" : "cable.connector.slash")
            Text(mic.name)
                .lineLimit(1)
            Spacer()
            if model.database.debug.audioMixer {
                MixerEffectsMarkView(effects: mic.effects)
            }
            Image(systemName: "checkmark")
                .foregroundStyle(mic == modelMic.current ? .blue : .clear)
                .bold()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if mic.connected {
                model.manualSelectMicById(id: mic.id)
            }
        }
    }
}

struct QuickButtonMicView: View {
    let model: Model
    @ObservedObject var mics: SettingsMics
    @ObservedObject var modelMic: Mic

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(mics.mics) { mic in
                        QuickButtonMicMicView(model: model, mic: mic, modelMic: modelMic)
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
                .onChange(of: mics.mics) { _ in
                    model.updateMixedMics()
                }
            } footer: {
                VStack(alignment: .leading) {
                    Text("Highest priority mic at the top of the list.")
                    Text("")
                    if model.database.debug.audioMixer {
                        Text("Tap a mic to make it the main mic. Mix more sources in Audio.")
                        Text("")
                    }
                    SwipeLeftToDeleteHelpView(kind: String(localized: "a mic"))
                }
            }
            if model.database.debug.audioMixer {
                ShortcutSectionView {
                    NavigationLink {
                        QuickButtonMixerView(model: model, mics: mics, modelMic: modelMic)
                    } label: {
                        Label("Audio", systemImage: "slider.vertical.3")
                    }
                }
            }
            if false {
                Section {
                    Toggle("Auto switch", isOn: $mics.autoSwitch)
                } footer: {
                    Text("Automatically switch to highest priority mic when plugged in.")
                }
            }
        }
        .navigationTitle("Mic")
    }
}
