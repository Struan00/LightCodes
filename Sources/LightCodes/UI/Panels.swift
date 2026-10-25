import SwiftUI

/// Left column: the "moves" you paint with, colours, and the Auto-Show button.
struct Palette: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    state.runAutoShow()
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("AUTO-SHOW").tracking(1.5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonButtonStyle(color: Theme.magenta, filled: true))
                .disabled(state.project.sections.isEmpty)
                .help("Builds a full show from the song's phrases. Everything stays editable.")

                header("MOVES")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(ClipKind.allCases) { kind in
                        MoveCard(kind: kind)
                    }
                }

                header("COLOUR")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(RGB.swatches, id: \.self) { c in
                        SwatchButton(color: c, selected: state.paletteColor == c) { state.paletteColor = c }
                    }
                }

                header("RIG")
                Button { state.showPatch = true } label: {
                    Label("Lights & Output", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonButtonStyle(color: Theme.cyan))
                Button { state.chooseSong() } label: {
                    Label("Change Song", systemImage: "music.note").frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonButtonStyle(color: Theme.violet))
            }
            .padding(14)
        }
        .glassPanel(corner: 18)
    }

    private func header(_ s: String) -> some View {
        Text(s).font(Theme.display(10, .black)).tracking(2).foregroundStyle(Theme.dim)
    }
}

struct MoveCard: View {
    @Environment(AppState.self) private var state
    var kind: ClipKind
    @State private var hover = false

    var body: some View {
        let selected = state.paletteKind == kind
        let c = selected ? state.paletteColor.color : Theme.dim
        VStack(spacing: 6) {
            EnvelopeShape(kind: kind, rate: 1, beatPx: 14)
                .stroke(c, lineWidth: 2)
                .frame(height: 20)
                .glow(selected ? c : .clear, radius: 6)
            HStack(spacing: 4) {
                Image(systemName: kind.symbol).font(.system(size: 9, weight: .black))
                Text(kind.title).font(Theme.display(11, .bold))
            }
            .foregroundStyle(selected ? Theme.text : Theme.dim)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? c.opacity(0.14) : Color.white.opacity(hover ? 0.06 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? c.opacity(0.7) : Theme.line, lineWidth: 1))
        .scaleEffect(hover ? 1.04 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hover)
        .onHover { hover = $0 }
        .onTapGesture { state.paletteKind = kind }
        .draggable(kind.rawValue) {
            Label(kind.title, systemImage: kind.symbol)
                .padding(8).background(state.paletteColor.color.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        }
        .help("\(kind.hint). Click to choose, then click a lane — or drag it onto a lane.")
    }
}

struct SwatchButton: View {
    var color: RGB
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle().fill(color.color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2 : 0))
                .glow(color.color, radius: selected ? 10 : 3, strength: selected ? 0.9 : 0.4)
                .scaleEffect(selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: selected)
    }
}

/// Right column: tweak the selected clip(s).
struct Inspector: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INSPECTOR").font(Theme.display(10, .black)).tracking(2).foregroundStyle(Theme.dim)
            if let clip = selectedClip {
                editor(clip)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "cursorarrow.click.2").font(.system(size: 26)).foregroundStyle(Theme.cyan)
                    Text("Pick a move, then click a lane on the beat you want.")
                        .font(Theme.display(13, .semibold)).foregroundStyle(Theme.text)
                    Text("Select a clip to change its colour, brightness and speed. Shift-click to select several.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
                Spacer()
                LatencyCard()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(corner: 18)
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
        HStack(spacing: 10) {
            Image(systemName: clip.kind.symbol).font(.system(size: 18, weight: .black))
                .foregroundStyle(clip.color.color).glow(clip.color.color, radius: 8)
            VStack(alignment: .leading) {
                Text(clip.kind.title).font(Theme.display(18, .heavy)).foregroundStyle(Theme.text)
                Text(state.selection.count > 1 ? "\(state.selection.count) clips selected" : clip.kind.hint)
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
        }

        Picker("Move", selection: Binding(get: { clip.kind }, set: { k in state.checkpoint(); apply { $0.kind = k } })) {
            ForEach(ClipKind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }

        label("Colour")
        HStack(spacing: 6) {
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
            .font(.system(size: 11))

        label("Brightness \(Int(clip.intensity * 100))%")
        Slider(value: Binding(get: { clip.intensity }, set: { v in apply { $0.intensity = v } }), in: 0...1)
            .tint(Theme.amber)

        if [.pulse, .chase, .strobe].contains(clip.kind) {
            label(rateLabel(clip))
            Picker("", selection: Binding(get: { clip.rate }, set: { v in state.checkpoint(); apply { $0.rate = v } })) {
                if clip.kind == .strobe {
                    Text("Slow").tag(1.0); Text("Med").tag(2.0); Text("Fast").tag(4.0); Text("Insane").tag(6.0)
                } else {
                    Text("¼").tag(0.25); Text("½").tag(0.5); Text("1").tag(1.0); Text("2").tag(2.0); Text("4").tag(4.0)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
        }

        label("Timing")
        HStack {
            Chip(icon: "arrow.right.to.line", text: formatTime(clip.start), color: Theme.cyan)
            Chip(icon: "arrow.left.and.right", text: String(format: "%.1f beats", clip.duration / state.beatLength), color: Theme.violet)
        }

        HStack {
            Button("Duplicate") { state.duplicateSelection() }.buttonStyle(NeonButtonStyle(color: Theme.cyan))
            Button("Delete") { state.deleteSelection() }.buttonStyle(NeonButtonStyle(color: Theme.magenta))
        }
        .padding(.top, 6)
    }

    private func rateLabel(_ c: Clip) -> String {
        c.kind == .strobe ? "Strobe speed" : "Every … beats"
    }

    private func label(_ s: String) -> some View {
        Text(s.uppercased()).font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim).padding(.top, 2)
    }
}

/// Explains and tunes the "lights fire early" offset.
struct LatencyCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 6) {
            Text("SYNC OFFSET · \(Int(state.project.latencyMs)) ms").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim)
            Slider(value: $state.project.latencyMs, in: 0...300, step: 5).tint(Theme.lime)
            Text("If lights trail the music, slide right. They'll be told what to do this much earlier.")
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }
}
