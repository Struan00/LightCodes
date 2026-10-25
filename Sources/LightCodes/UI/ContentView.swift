import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var state = state
        ZStack {
            Backdrop()
            VStack(spacing: 12) {
                TopBar()
                if state.project.audioPath == nil {
                    SongDropZone()
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Palette().frame(width: 230)
                        VStack(spacing: 12) {
                            StageView().frame(height: 290)
                            if state.mode == .build { ShowTimeline() } else { Highway() }
                        }
                        if state.mode == .build {
                            Inspector().frame(width: 260)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    HintBar()
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.mode)

            if state.analyzing { AnalyzingOverlay() }
        }
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
        .alert("Hmm", isPresented: Binding(get: { state.errorMessage != nil },
                                           set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
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

/// Deep-space background with a faint perspective floor grid.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bg1, Theme.bg0], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.violet.opacity(0.18), .clear], center: .init(x: 0.3, y: 0), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Theme.magenta.opacity(0.10), .clear], center: .init(x: 0.9, y: 1), startRadius: 0, endRadius: 600)
            Canvas { ctx, size in
                var p = Path()
                let horizon = size.height * 0.15
                for i in 0...24 {
                    let x = size.width * Double(i) / 24
                    p.move(to: CGPoint(x: size.width / 2 + (x - size.width / 2) * 0.2, y: horizon))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                ctx.stroke(p, with: .color(.white.opacity(0.018)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}

struct TopBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        HStack(spacing: 14) {
            // Logo
            HStack(spacing: 8) {
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.brand)
                    .glow(Theme.magenta, radius: 10)
                Text("LIGHTCODES")
                    .font(Theme.display(17, .black))
                    .tracking(3)
                    .foregroundStyle(Theme.brand)
            }
            .padding(.leading, 70) // clear the traffic lights

            Divider().frame(height: 22).overlay(Theme.line)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.project.songTitle).font(Theme.display(14, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(state.project.audioPath == nil ? "No song loaded" : "\(state.project.lights.count) lights · \(state.project.clips.count) clips")
                    .font(Theme.mono(10, .regular)).foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: 220, alignment: .leading)

            Spacer()

            Transport()

            Spacer()

            ModeSwitcher(mode: $state.mode)

            Button { state.showPatch = true } label: {
                Chip(icon: state.output == nil ? "eye" : "dot.radiowaves.left.and.right",
                     text: state.output == nil ? "PREVIEW" : "LIVE DMX",
                     color: state.output == nil ? Theme.dim : Theme.lime)
            }
            .buttonStyle(.plain)
            .help(state.outputName)
        }
        .padding(.vertical, 6)
    }
}

struct Transport: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 12) {
            Button { state.jump(beats: -16) } label: { Image(systemName: "backward.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim)

            Button { state.togglePlay() } label: {
                ZStack {
                    Circle().fill(Theme.brand).frame(width: 44, height: 44)
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.black)
                        .offset(x: state.isPlaying ? 0 : 2)
                }
                .glow(Theme.magenta, radius: state.isPlaying ? 22 : 12)
            }
            .buttonStyle(.plain)
            .disabled(state.project.audioPath == nil)

            Button { state.jump(beats: 16) } label: { Image(systemName: "forward.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim)

            SwiftUI.TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                let t = state.player.currentTime
                let beat = currentBeat(t)
                HStack(spacing: 10) {
                    Text(formatTime(t)).font(Theme.mono(18, .bold)).foregroundStyle(Theme.text)
                        .frame(width: 96, alignment: .leading)
                    // Bar.beat counter with a beat light.
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(i == beat.inBar ? (i == 0 ? Theme.magenta : Theme.cyan) : Theme.line)
                                .frame(width: 7, height: 7)
                                .glow(i == beat.inBar ? Theme.cyan : .clear, radius: 6)
                        }
                    }
                    Text("BAR \(beat.bar)").font(Theme.mono(11)).foregroundStyle(Theme.dim).frame(width: 56, alignment: .leading)
                }
            }
            Chip(icon: "metronome.fill", text: String(format: "%.1f BPM", state.project.bpm), color: Theme.amber)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .glassPanel(corner: 30)
    }

    private func currentBeat(_ t: Double) -> (bar: Int, inBar: Int) {
        let beats = state.project.beats
        guard let i = beats.lastIndex(where: { $0 <= t }) else { return (0, -1) }
        let rel = i - state.project.downbeatIndex
        let m = ((rel % 4) + 4) % 4
        return (rel >= 0 ? rel / 4 + 1 : 0, m)
    }
}

struct ModeSwitcher: View {
    @Binding var mode: Mode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Mode.allCases) { m in
                Button { mode = m } label: {
                    HStack(spacing: 6) {
                        Image(systemName: m.symbol)
                        Text(m.rawValue).tracking(1)
                    }
                    .font(Theme.display(11, .heavy))
                    .foregroundStyle(mode == m ? .black : Theme.dim)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background {
                        if mode == m {
                            Capsule().fill(m == .live ? Theme.magenta : Theme.cyan)
                                .glow(m == .live ? Theme.magenta : Theme.cyan, radius: 10)
                                .matchedGeometryEffect(id: "mode", in: ns)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassPanel(corner: 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: mode)
    }
}

/// First-run screen: one obvious thing to do.
struct SongDropZone: View {
    @Environment(AppState.self) private var state
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Theme.brand, lineWidth: 2)
                        .frame(width: 140 + CGFloat(i) * 60, height: 140 + CGFloat(i) * 60)
                        .opacity(pulse ? 0 : 0.5 - Double(i) * 0.12)
                        .scaleEffect(pulse ? 1.25 : 0.9)
                        .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.4), value: pulse)
                }
                Image(systemName: "music.note")
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(Theme.brand)
                    .glow(Theme.violet, radius: 24)
            }
            .frame(height: 300)
            Text("Drop a song to begin")
                .font(Theme.display(34, .black))
                .foregroundStyle(Theme.text)
            Text("LightCodes finds the beat, the bars and the drops — then you paint light onto them.")
                .font(.system(size: 15)).foregroundStyle(Theme.dim)
            HStack(spacing: 12) {
                Button("Choose Song…") { state.chooseSong() }
                    .buttonStyle(NeonButtonStyle(color: Theme.cyan, filled: true))
                Button("Open Show…") { state.open() }
                    .buttonStyle(NeonButtonStyle(color: Theme.violet))
            }
            HStack(spacing: 28) {
                step(1, "Drop a song", "waveform")
                step(2, "Auto-Show or paint clips", "paintbrush.pointed.fill")
                step(3, "Plug in lights & perform", "light.beacon.max.fill")
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }

    private func step(_ n: Int, _ t: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(Theme.display(14, .black)).foregroundStyle(.black)
                .frame(width: 26, height: 26).background(Theme.cyan, in: Circle())
            Image(systemName: icon).foregroundStyle(Theme.cyan)
            Text(t).font(Theme.display(13, .semibold)).foregroundStyle(Theme.text)
        }
    }
}

struct AnalyzingOverlay: View {
    @Environment(AppState.self) private var state
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            SwiftUI.TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let p = state.progress.value
                VStack(spacing: 16) {
                    ProgressView(value: p)
                        .progressViewStyle(.linear).tint(Theme.cyan).frame(width: 320)
                    Text("Listening to your song…").font(Theme.display(20, .heavy)).foregroundStyle(Theme.text)
                    Text(stage(p)).font(Theme.mono(12, .regular)).foregroundStyle(Theme.dim)
                }
                .padding(36)
                .glassPanel(corner: 24)
            }
        }
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

struct HintBar: View {
    @Environment(AppState.self) private var state
    var body: some View {
        HStack(spacing: 18) {
            switch state.mode {
            case .build:
                hint("click lane", "place clip"); hint("drag", "move · snap"); hint("⌘D", "duplicate")
                hint("⌫", "delete"); hint("⌘⇧A", "auto-show")
            case .live:
                hint("1–9", "hold a light"); hint("Q", "all lights"); hint("tap on the beat", "score PERFECTs")
            case .show:
                hint("SPACE", "play / pause"); hint("master fader", "dim everything")
            }
            Spacer()
            hint("SPACE", "play"); hint("← →", "jump 1 bar"); hint("TAB", "switch mode")
        }
        .font(Theme.mono(10, .regular))
        .padding(.horizontal, 6)
    }
    private func hint(_ k: String, _ v: String) -> some View {
        HStack(spacing: 5) {
            Text(k).foregroundStyle(Theme.cyan).padding(.horizontal, 5).padding(.vertical, 2)
                .background(Theme.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(v).foregroundStyle(Theme.dim)
        }
    }
}
