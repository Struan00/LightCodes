import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool
    @State private var showInspector = true

    var body: some View {
        @Bindable var state = state
        Group {
            if state.project.audioPath == nil {
                SongDropZone()
            } else {
                NavigationSplitView {
                    Palette()
                        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
                } detail: {
                    Workspace()
                        .inspector(isPresented: Binding(get: { state.mode == .build && showInspector },
                                                        set: { showInspector = $0 })) {
                            Inspector()
                                .inspectorColumnWidth(min: 250, ideal: 270, max: 360)
                        }
                }
            }
        }
        .background { AmbientBackdrop() }
        .overlay { if state.analyzing { AnalyzingOverlay() } }
        .navigationTitle(state.project.audioPath == nil ? "LightCodes" : state.project.songTitle)
        .navigationSubtitle(state.project.audioPath == nil ? "" :
            "\(state.project.lights.count) lights · \(state.project.clips.count) clips")
        .toolbar { toolbar }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: [.down, .up]) { press in handleKey(press) }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.loadSong(url)
            return true
        }
        .sheet(isPresented: $state.showPatch) { PatchSheet() }
        .alert("Something went wrong", isPresented: Binding(get: { state.errorMessage != nil },
                                                            set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        let hasSong = state.project.audioPath != nil
        ToolbarItem(placement: .principal) {
            Transport().disabled(!hasSong)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Mode", selection: Bindable(state).mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!hasSong)
            .help("Build, record live, or perform (Tab)")

            Button { state.showPatch = true } label: {
                Label("Lights & Output", systemImage: state.output == nil ? "lightbulb.2" : "dot.radiowaves.left.and.right")
            }
            .help(state.outputName)

            if hasSong && state.mode == .build {
                Button { showInspector.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector")
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let down = press.phase == .down
        if press.key == .space { if down { state.togglePlay() }; return .handled }
        if down {
            switch press.key {
            case .leftArrow: state.jump(beats: press.modifiers.contains(.shift) ? -16 : -4); return .handled
            case .rightArrow: state.jump(beats: press.modifiers.contains(.shift) ? 16 : 4); return .handled
            case .delete, .deleteForward: state.deleteSelection(); return .handled
            case .tab:
                let all = Mode.allCases
                state.mode = all[(all.firstIndex(of: state.mode)! + 1) % all.count]
                return .handled
            case .return: state.seek(0); return .handled
            default: break
            }
        }
        guard let ch = press.characters.lowercased().first else { return .ignored }
        let lane: Int? = ch == "q" ? 0 : ch.wholeNumberValue.flatMap { $0 >= 1 && $0 <= 9 ? $0 : nil }
        if let lane, state.mode == .live {
            down ? state.liveKeyDown(lane: lane) : state.liveKeyUp(lane: lane)
            return .handled
        }
        return .ignored
    }
}

/// Stage on top, editor below. Sits over the ambient light so the toolbar glass picks it up.
struct Workspace: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            StageView().frame(height: 280)
            if state.mode == .build { ShowTimeline() } else { Highway() }
        }
        .padding(12)
        .animation(.smooth(duration: 0.35), value: state.mode)
    }
}

/// A dark room, faintly lit by whatever the rig is doing right now,
/// so the glass above always has real light to bend.
struct AmbientBackdrop: View {
    @Environment(AppState.self) private var state

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
            let states = state.engine.states(at: state.player.currentTime, master: state.master)
            let lights = state.project.lights
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.canvas))
                // A soft, constant aura so glass never sits on flat black.
                aura(ctx, at: CGPoint(x: size.width * 0.25, y: 0), radius: size.width * 0.6,
                     color: Color(red: 0.30, green: 0.32, blue: 0.55).opacity(0.18))
                aura(ctx, at: CGPoint(x: size.width * 0.85, y: size.height), radius: size.width * 0.5,
                     color: Color(red: 0.20, green: 0.40, blue: 0.45).opacity(0.10))
                for light in lights {
                    guard let s = states[light.id], s.intensity > 0.01 else { continue }
                    aura(ctx, at: CGPoint(x: size.width * light.stageX, y: size.height * 0.12),
                         radius: max(size.width, size.height) * 0.42,
                         color: s.color.color.opacity(0.20 * s.intensity))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func aura(_ ctx: GraphicsContext, at c: CGPoint, radius r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [color, .clear]), center: c, startRadius: 0, endRadius: r))
    }
}

struct Transport: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 14) {
            Button { state.jump(beats: -16) } label: { Image(systemName: "backward.fill") }
                .help("Back 4 bars")
            Button { state.togglePlay() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
            }
            .help("Play / Pause (Space)")
            Button { state.jump(beats: 16) } label: { Image(systemName: "forward.fill") }
                .help("Forward 4 bars")

            SwiftUI.TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                let t = state.player.currentTime
                let beat = currentBeat(t)
                HStack(spacing: 12) {
                    Text(formatTime(t))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .frame(width: 66, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(i == beat.inBar ? AnyShapeStyle(i == 0 ? Color.primary : Color.accentColor)
                                                      : AnyShapeStyle(.quaternary))
                                .frame(width: 5, height: 5)
                        }
                    }
                    Text("Bar \(beat.bar)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                }
            }
            Text(String(format: "%.0f BPM", state.project.bpm))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .fixedSize()
    }

    private func currentBeat(_ t: Double) -> (bar: Int, inBar: Int) {
        let beats = state.project.beats
        guard let i = beats.lastIndex(where: { $0 <= t }) else { return (0, -1) }
        let rel = i - state.project.downbeatIndex
        let m = ((rel % 4) + 4) % 4
        return (rel >= 0 ? rel / 4 + 1 : 0, m)
    }
}

/// First-run screen: one obvious thing to do.
struct SongDropZone: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "waveform")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            VStack(spacing: 8) {
                Text("Drop a Song")
                    .font(.system(size: 30, weight: .semibold))
                Text("LightCodes finds the beat, the bars and the drops,\nthen you paint light onto them.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Choose Song…") { state.chooseSong() }
                    .glassButton(prominent: true)
                Button("Open Show…") { state.open() }
                    .glassButton()
            }
            .controlSize(.large)
            HStack(spacing: 28) {
                step("1", "Drop a song")
                step("2", "Auto-Show or paint clips")
                step("3", "Plug in lights and perform")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 56).padding(.vertical, 48)
        .glass(cornerRadius: 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ n: String, _ t: String) -> some View {
        HStack(spacing: 8) {
            Text(n)
                .font(.caption.weight(.semibold))
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())
            Text(t).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct AnalyzingOverlay: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            SwiftUI.TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let p = state.progress.value
                VStack(spacing: 14) {
                    Text("Listening to your song…").font(.headline)
                    ProgressView(value: p).progressViewStyle(.linear).frame(width: 280)
                    Text(stage(p)).font(.callout).foregroundStyle(.secondary)
                }
                .padding(32)
                .glass(cornerRadius: 24)
            }
        }
        .transition(.opacity)
    }
    private func stage(_ p: Double) -> String {
        switch p {
        case ..<0.2: "Decoding audio"
        case ..<0.4: "Drawing the waveform"
        case ..<0.7: "Finding every hit"
        case ..<0.85: "Locking onto the beat"
        default: "Spotting the drops"
        }
    }
}
