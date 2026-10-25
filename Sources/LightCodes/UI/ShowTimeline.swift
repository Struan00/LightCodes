import SwiftUI

enum TimelineMetrics {
    static let ruler: CGFloat = 22
    static let sections: CGFloat = 26
    static let wave: CGFloat = 64
    static let lane: CGFloat = 44
    static let header: CGFloat = 132
    static var top: CGFloat { ruler + sections + wave }
}

/// BUILD mode editor. Layout follows the industry-standard DAW pattern used by
/// SoundSwitch, xLights and Lightkey: song on top, one lane per light, a Master
/// lane for "everything", clips that snap to a detected beat grid.
struct ShowTimeline: View {
    @Environment(AppState.self) private var state
    typealias M = TimelineMetrics

    var body: some View {
        @Bindable var state = state
        let pps = state.pixelsPerSecond
        let width = max(400, state.duration * pps + 200)

        VStack(spacing: 0) {
            toolbar
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: M.top)
                        ForEach(Array(state.lanes.enumerated()), id: \.offset) { i, light in
                            LaneHeader(index: i, light: light)
                        }
                    }
                    .frame(width: M.header)
                    .background(Theme.bg1.opacity(0.6))

                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            GridBackground(width: width)
                            VStack(spacing: 0) {
                                Ruler(width: width)
                                SectionStrip(width: width)
                                WaveformStrip(width: width)
                                ForEach(Array(state.lanes.enumerated()), id: \.offset) { i, _ in
                                    LaneRow(index: i, width: width)
                                }
                            }
                            Playhead()
                        }
                        .frame(width: width, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                }
            }
        }
        .glassPanel(corner: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var toolbar: some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            Text("TIMELINE").font(Theme.display(11, .black)).tracking(2).foregroundStyle(Theme.dim)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnet").foregroundStyle(state.snap == .off ? Theme.dim : Theme.cyan)
                Picker("", selection: $state.snap) {
                    ForEach(SnapDivision.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 230).labelsHidden()
            }
            HStack(spacing: 6) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(Theme.dim)
                Slider(value: $state.pixelsPerSecond, in: 20...400).frame(width: 120).tint(Theme.cyan)
                Image(systemName: "plus.magnifyingglass").foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - Background grid

struct GridBackground: View {
    @Environment(AppState.self) private var state
    var width: CGFloat

    var body: some View {
        let pps = state.pixelsPerSecond
        let beats = state.project.beats
        let down = state.project.downbeatIndex
        let laneCount = state.lanes.count
        Canvas { ctx, size in
            let top = TimelineMetrics.top
            // Zebra lanes
            for i in 0..<laneCount where i % 2 == 0 {
                let r = CGRect(x: 0, y: top + CGFloat(i) * TimelineMetrics.lane, width: size.width, height: TimelineMetrics.lane)
                ctx.fill(Path(r), with: .color(.white.opacity(0.018)))
            }
            // Beat lines: bars bright, beats faint (fade out when zoomed far out)
            let showBeats = pps * (60 / max(60, state.project.bpm)) > 9
            for (i, b) in beats.enumerated() {
                let bar = (i - down) % 4 == 0
                guard bar || showBeats else { continue }
                let x = b * pps
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.white.opacity(bar ? 0.10 : 0.035)), lineWidth: bar ? 1 : 0.5)
            }
        }
        .frame(width: width, height: TimelineMetrics.top + CGFloat(laneCount) * TimelineMetrics.lane)
        .allowsHitTesting(false)
    }
}

// MARK: - Ruler

struct Ruler: View {
    @Environment(AppState.self) private var state
    var width: CGFloat

    var body: some View {
        let pps = state.pixelsPerSecond
        let beats = state.project.beats
        let down = state.project.downbeatIndex
        Canvas { ctx, size in
            let barPx = pps * 4 * 60 / max(60, state.project.bpm)
            let every = barPx > 60 ? 1 : barPx > 25 ? 4 : 8
            var bar = 0
            for i in stride(from: down, to: beats.count, by: 4) {
                bar += 1
                guard (bar - 1) % every == 0 else { continue }
                let x = beats[i] * pps
                ctx.draw(Text("\(bar)").font(Theme.mono(10, .bold)).foregroundStyle(Theme.dim),
                         at: CGPoint(x: x + 4, y: size.height / 2), anchor: .leading)
                var p = Path(); p.move(to: CGPoint(x: x, y: size.height * 0.4)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(Theme.dim), lineWidth: 1)
            }
        }
        .frame(width: width, height: TimelineMetrics.ruler)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            state.selection = []
            state.seek(max(0, v.location.x / pps))
        })
        .help("Click or drag to scrub")
    }
}

// MARK: - Phrase strip

struct SectionStrip: View {
    @Environment(AppState.self) private var state
    var width: CGFloat

    var body: some View {
        let pps = state.pixelsPerSecond
        ZStack(alignment: .topLeading) {
            ForEach(state.project.sections) { sec in
                let c = sec.kind.tint.color
                let w = max(4, (sec.end - sec.start) * pps - 3)
                HStack(spacing: 6) {
                    Text(sec.kind.title.uppercased()).font(Theme.display(10, .black)).tracking(1.5)
                    if w > 120 { EnergyBar(level: sec.energy, color: c) }
                }
                .foregroundStyle(c)
                .padding(.horizontal, 8)
                .frame(width: w, height: TimelineMetrics.sections - 6, alignment: .leading)
                .background(c.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.opacity(0.5), lineWidth: 1))
                .clipped()
                .offset(x: sec.start * pps + 1, y: 3)
                .onTapGesture { state.seek(sec.start) }
                .contextMenu {
                    ForEach(SectionKind.allCases, id: \.self) { k in
                        Button("Mark as \(k.title)") {
                            state.checkpoint()
                            if let i = state.project.sections.firstIndex(where: { $0.id == sec.id }) {
                                state.project.sections[i].kind = k
                            }
                        }
                    }
                }
                .help("\(sec.kind.title) · click to jump · right-click to relabel")
            }
        }
        .frame(width: width, height: TimelineMetrics.sections, alignment: .topLeading)
    }
}

// MARK: - Waveform

struct WaveformStrip: View {
    @Environment(AppState.self) private var state
    var width: CGFloat

    var body: some View {
        let pps = state.pixelsPerSecond
        Canvas { ctx, size in
            guard let a = state.analysis, !a.peaks.isEmpty else { return }
            let mid = size.height / 2
            let step: CGFloat = 2
            var x: CGFloat = 0
            while x < size.width {
                let t0 = Double(x) / pps, t1 = Double(x + step) / pps
                let i0 = Int(t0 * a.peaksPerSecond), i1 = max(i0 + 1, Int(t1 * a.peaksPerSecond))
                guard i0 < a.peaks.count else { break }
                var pk: Float = 0, bass: Float = 0
                for i in i0..<min(i1, a.peaks.count) { pk = max(pk, a.peaks[i]); bass = max(bass, a.bass[i]) }
                let hgt = CGFloat(pk) * (mid - 2)
                // Bass-heavy = magenta, bright/treble = cyan (like rekordbox's colour waveform).
                let col = RGB.cyan.mixed(with: .magenta, Double(min(1, bass * 1.4))).color
                ctx.fill(Path(CGRect(x: x, y: mid - hgt, width: step - 0.5, height: hgt * 2)), with: .color(col.opacity(0.85)))
                x += step
            }
        }
        .frame(width: width, height: TimelineMetrics.wave)
        .background(Color.black.opacity(0.25))
        .contentShape(Rectangle())
        .onTapGesture { loc in state.seek(loc.x / pps) }
    }
}

// MARK: - Lanes

struct LaneHeader: View {
    @Environment(AppState.self) private var state
    var index: Int
    var light: PatchedLight?

    var body: some View {
        HStack(spacing: 8) {
            Text(index == 0 ? "Q" : "\(index)")
                .font(Theme.mono(10, .bold)).foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(index == 0 ? Theme.magenta : Theme.cyan, in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                Text(light?.name ?? "MASTER").font(Theme.display(12, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(light.map { "\($0.profile.name) · @\($0.address)" } ?? "all lights")
                    .font(Theme.mono(9, .regular)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: TimelineMetrics.lane)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct LaneRow: View {
    @Environment(AppState.self) private var state
    var index: Int
    var width: CGFloat
    @State private var dropHover = false

    var body: some View {
        let pps = state.pixelsPerSecond
        let laneID = state.lanes[index]?.id
        ZStack(alignment: .topLeading) {
            Rectangle().fill(dropHover ? Theme.cyan.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    state.addClip(kind: state.paletteKind, lane: index, at: loc.x / pps)
                }
            ForEach(state.project.clips.filter { $0.lightID == laneID }) { clip in
                ClipView(clip: clip, lane: index)
            }
        }
        .frame(width: width, height: TimelineMetrics.lane, alignment: .topLeading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .dropDestination(for: String.self) { items, loc in
            guard let raw = items.first, let kind = ClipKind(rawValue: raw) else { return false }
            state.addClip(kind: kind, lane: index, at: loc.x / pps)
            return true
        } isTargeted: { dropHover = $0 }
    }
}

struct ClipView: View {
    @Environment(AppState.self) private var state
    var clip: Clip
    var lane: Int
    @State private var origin: Clip?

    var body: some View {
        let pps = state.pixelsPerSecond
        let selected = state.selection.contains(clip.id)
        let c = clip.kind == .blackout ? Color(white: 0.25) : clip.color.color
        let w = max(8, clip.duration * pps)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [c.opacity(0.55), c.opacity(0.22)], startPoint: .top, endPoint: .bottom))
            EnvelopeShape(kind: clip.kind, rate: clip.rate, beatPx: state.beatLength * pps)
                .stroke(c, lineWidth: 1.5)
                .padding(.vertical, 6)
                .opacity(0.9)
            if w > 44 {
                HStack(spacing: 4) {
                    Image(systemName: clip.kind.symbol).font(.system(size: 10, weight: .black))
                    if w > 90 { Text(clip.kind.title).font(Theme.display(10, .heavy)) }
                }
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .padding(.leading, 6)
            }
            // Resize handle
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(selected ? 0.8 : 0.3))
                    .frame(width: 4, height: 18)
                    .padding(.trailing, 3)
                    .contentShape(Rectangle().inset(by: -6))
                    .gesture(resize(pps: pps))
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            }
        }
        .frame(width: w, height: TimelineMetrics.lane - 8)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(selected ? Color.white : c.opacity(0.8), lineWidth: selected ? 2 : 1))
        .glow(c, radius: selected ? 14 : 6, strength: selected ? 0.9 : 0.35)
        .offset(x: clip.start * pps, y: 4)
        .gesture(move(pps: pps))
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) {
                if selected { state.selection.remove(clip.id) } else { state.selection.insert(clip.id) }
            } else { state.selection = [clip.id] }
        }
        .contextMenu {
            Button("Duplicate") { state.selection = [clip.id]; state.duplicateSelection() }
            Button("Delete", role: .destructive) { state.selection = [clip.id]; state.deleteSelection() }
        }
        .help(clip.kind.hint)
    }

    private func move(pps: Double) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                if origin == nil { origin = clip; state.checkpoint(); state.selection = [clip.id] }
                guard let o = origin else { return }
                let laneShift = Int((v.translation.height / TimelineMetrics.lane).rounded())
                let target = max(0, min(state.lanes.count - 1, lane + laneShift))
                state.updateClip(clip.id) { c in
                    c.start = state.snapped(o.start + v.translation.width / pps)
                    c.lightID = state.lanes[target]?.id
                }
            }
            .onEnded { _ in origin = nil }
    }

    private func resize(pps: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if origin == nil { origin = clip; state.checkpoint() }
                guard let o = origin else { return }
                state.updateClip(clip.id) { c in
                    let end = state.snapped(o.end + v.translation.width / pps)
                    c.duration = max(state.beatLength / 4, end - c.start)
                }
            }
            .onEnded { _ in origin = nil }
    }
}

/// A tiny drawing of what the clip does to brightness — readable at a glance.
struct EnvelopeShape: Shape {
    var kind: ClipKind
    var rate: Double
    var beatPx: Double

    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.minY, bot = r.maxY
        switch kind {
        case .hold:
            p.move(to: CGPoint(x: r.minX, y: top + 2)); p.addLine(to: CGPoint(x: r.maxX, y: top + 2))
        case .flash:
            p.move(to: CGPoint(x: r.minX, y: top))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: bot), control: CGPoint(x: r.minX + r.width * 0.15, y: bot))
        case .fadeIn:
            p.move(to: CGPoint(x: r.minX, y: bot))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: top), control: CGPoint(x: r.maxX * 0.75, y: bot))
        case .fadeOut:
            p.move(to: CGPoint(x: r.minX, y: top))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: bot), control: CGPoint(x: r.minX + r.width * 0.25, y: bot))
        case .pulse, .chase:
            let step = max(6, beatPx * max(0.25, rate))
            var x = r.minX
            p.move(to: CGPoint(x: x, y: bot))
            while x < r.maxX {
                p.addLine(to: CGPoint(x: x, y: kind == .chase ? top + 6 : top))
                p.addQuadCurve(to: CGPoint(x: min(r.maxX, x + step), y: bot), control: CGPoint(x: x + step * 0.2, y: bot))
                x += step
            }
        case .strobe:
            let step = max(4, beatPx / 4)
            var x = r.minX
            while x < r.maxX {
                p.move(to: CGPoint(x: x, y: top)); p.addLine(to: CGPoint(x: x, y: bot)); x += step
            }
        case .blackout:
            p.move(to: CGPoint(x: r.minX, y: bot - 1)); p.addLine(to: CGPoint(x: r.maxX, y: bot - 1))
        }
        return p
    }
}

struct Playhead: View {
    @Environment(AppState.self) private var state
    var body: some View {
        SwiftUI.TimelineView(.animation) { _ in
            let x = state.player.currentTime * state.pixelsPerSecond
            ZStack(alignment: .top) {
                Rectangle().fill(Color.white).frame(width: 2)
                    .glow(Theme.magenta, radius: 10)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 11)).foregroundStyle(.white)
                    .offset(y: -2)
            }
            .offset(x: x - 1)
        }
        .allowsHitTesting(false)
    }
}
