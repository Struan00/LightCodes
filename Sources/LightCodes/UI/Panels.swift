import SwiftUI

/// Sidebar: the "moves" you paint with, colours, and the Auto-Show button.
struct Palette: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List(selection: Binding<ClipKind?>(get: { state.paletteKind },
                                           set: { if let k = $0 { state.paletteKind = k } })) {
            Section {
                Button { state.runAutoShow() } label: {
                    Label("Auto-Show", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
                .disabled(state.project.sections.isEmpty)
                .help("Builds a full show from the song's phrases. Everything stays editable. (⇧⌘A)")
                .padding(.vertical, 4)
            }

            Section("Moves") {
                ForEach(ClipKind.allCases) { kind in
                    MoveRow(kind: kind).tag(kind)
                }
            }

            Section("Colour") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(RGB.swatches, id: \.self) { c in
                        SwatchButton(color: c, selected: state.paletteColor == c) { state.paletteColor = c }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button { state.showPatch = true } label: {
                    Label("Lights & Output", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                Button { state.chooseSong() } label: {
                    Label("Change Song", systemImage: "music.note").frame(maxWidth: .infinity)
                }
            }
            .glassButton()
            .padding(12)
        }
    }
}

struct MoveRow: View {
    @Environment(AppState.self) private var state
    var kind: ClipKind

    var body: some View {
        let selected = state.paletteKind == kind
        HStack(spacing: 10) {
            EnvelopeShape(kind: kind, rate: 1, beatPx: 8)
                .stroke(selected ? state.paletteColor.color : Color.secondary, lineWidth: 1.5)
                .frame(width: 28, height: 12)
            Text(kind.title)
        }
        .draggable(kind.rawValue) {
            Label(kind.title, systemImage: kind.symbol)
                .padding(8)
                .glass(cornerRadius: 10)
        }
        .help("\(kind.hint). Click to choose, then click a lane, or drag it onto a lane.")
    }
}

/// Inspector: tweak the selected clip(s).
struct Inspector: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            if let clip = selectedClip {
                editor(clip)
            } else {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "cursorarrow.click.2")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No Clip Selected").font(.headline)
                        Text("Pick a move in the sidebar, then click a lane on the beat you want. Shift-click to select several clips.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                LatencySection()
            }
        }
        .formStyle(.grouped)
    }

    private var selectedClip: Clip? {
        guard let id = state.selection.first else { return nil }
        return state.project.clips.first { $0.id == id }
    }

    /// Applies a change to every selected clip.
    private func apply(_ change: @escaping (inout Clip) -> Void) {
        for id in state.selection { state.updateClip(id, change) }
    }

    @ViewBuilder private func editor(_ clip: Clip) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: clip.kind.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(clip.color.color)
                    .frame(width: 32, height: 32)
                    .background(clip.color.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.kind.title).font(.headline)
                    Text(state.selection.count > 1 ? "\(state.selection.count) clips selected" : clip.kind.hint)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("Move", selection: Binding(get: { clip.kind }, set: { k in state.checkpoint(); apply { $0.kind = k } })) {
                ForEach(ClipKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        }

        Section("Colour") {
            HStack(spacing: 2) {
                ForEach(RGB.swatches, id: \.self) { c in
                    SwatchButton(color: c, selected: clip.color == c) { state.checkpoint(); apply { $0.color = c } }
                }
            }
            ColorPicker("Custom", selection: Binding(
                get: { clip.color.color },
                set: { col in
                    let ns = NSColor(col).usingColorSpace(.deviceRGB) ?? .white
                    apply { $0.color = RGB(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent) }
                }))
        }

        Section {
            Slider(value: Binding(get: { clip.intensity }, set: { v in apply { $0.intensity = v } }), in: 0...1) {
                Text("Brightness")
            }
            .labelsHidden()
            if [.pulse, .chase, .strobe].contains(clip.kind) {
                Picker(clip.kind == .strobe ? "Speed" : "Every", selection: Binding(get: { clip.rate },
                                                                                   set: { v in state.checkpoint(); apply { $0.rate = v } })) {
                    if clip.kind == .strobe {
                        Text("Slow").tag(1.0); Text("Med").tag(2.0); Text("Fast").tag(4.0); Text("Max").tag(6.0)
                    } else {
                        Text("¼").tag(0.25); Text("½").tag(0.5); Text("1").tag(1.0); Text("2").tag(2.0); Text("4").tag(4.0)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            HStack {
                Text("Brightness")
                Spacer()
                Text("\(Int(clip.intensity * 100))%").monospacedDigit()
            }
        }

        Section("Timing") {
            LabeledContent("Start", value: formatTime(clip.start))
            LabeledContent("Length", value: String(format: "%.2g beats", clip.duration / state.beatLength))
        }

        Section {
            HStack {
                Button("Duplicate") { state.duplicateSelection() }
                Spacer()
                Button("Delete", role: .destructive) { state.deleteSelection() }
            }
        }
    }
}

/// Explains and tunes the "lights fire early" offset.
struct LatencySection: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        Section {
            Slider(value: $state.project.latencyMs, in: 0...300, step: 5) { Text("Offset") }
                .labelsHidden()
        } header: {
            HStack {
                Text("Sync Offset")
                Spacer()
                Text("\(Int(state.project.latencyMs)) ms").monospacedDigit()
            }
        } footer: {
            Text("If the lights trail the music, slide right. They'll be told what to do this much earlier.")
        }
    }
}
