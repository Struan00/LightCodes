import SwiftUI

/// Live virtual rig: truss, fixtures, volumetric beams, floor pools and haze.
/// Shows exactly what the DMX output sends, so you can design with no hardware.
struct StageView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        SwiftUI.TimelineView(.animation) { tl in
            let t = state.player.currentTime
            let engine = state.engine
            let states = engine.states(at: t, master: state.master)
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, states: states, time: tl.date.timeIntervalSinceReferenceDate)
            }
            .overlay(alignment: .topLeading) { sectionBadge(t) }
            .overlay(alignment: .topTrailing) {
                if state.mode == .live { ScoreHUD() }
                if state.mode == .show { MasterFader() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func draw(ctx: GraphicsContext, size: CGSize, states: [UUID: LightState], time: Double) {
        let w = size.width, h = size.height
        let trussY = h * 0.13
        let floorY = h * 0.86

        // Room
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(white: 0.02), Color(red: 0.04, green: 0.035, blue: 0.07)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        // Floor
        var floor = Path()
        floor.addRect(CGRect(x: 0, y: floorY, width: w, height: h - floorY))
        ctx.fill(floor, with: .color(Color(white: 0.035)))
        var grid = Path()
        for i in 0...20 {
            let x = w * Double(i) / 20
            grid.move(to: CGPoint(x: w / 2 + (x - w / 2) * 0.55, y: floorY))
            grid.addLine(to: CGPoint(x: x, y: h))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.04)), lineWidth: 1)

        // Truss
        let truss = CGRect(x: w * 0.05, y: trussY - 7, width: w * 0.9, height: 14)
        ctx.fill(Path(roundedRect: truss, cornerRadius: 3), with: .color(Color(white: 0.13)))
        var lattice = Path()
        stride(from: truss.minX, to: truss.maxX, by: 14).forEach { x in
            lattice.move(to: CGPoint(x: x, y: truss.minY)); lattice.addLine(to: CGPoint(x: x + 14, y: truss.maxY))
        }
        ctx.stroke(lattice, with: .color(Color(white: 0.22)), lineWidth: 1)

        let lights = state.project.lights
        var beams = ctx
        beams.blendMode = .plusLighter

        for light in lights {
            let s = states[light.id] ?? LightState()
            let x = w * light.stageX
            let col = s.color.color
            let k = s.intensity
            let lens = CGPoint(x: x, y: trussY + 16)

            if k > 0.01 {
                // Beam cone
                let spread = w * 0.075
                var cone = Path()
                cone.move(to: CGPoint(x: lens.x - 6, y: lens.y))
                cone.addLine(to: CGPoint(x: lens.x + 6, y: lens.y))
                cone.addLine(to: CGPoint(x: x + spread, y: floorY))
                cone.addLine(to: CGPoint(x: x - spread, y: floorY))
                cone.closeSubpath()
                beams.fill(cone, with: .linearGradient(
                    Gradient(colors: [col.opacity(0.55 * k), col.opacity(0.10 * k)]),
                    startPoint: lens, endPoint: CGPoint(x: x, y: floorY)))

                // Haze shimmer inside the beam
                let shimmer = 0.5 + 0.5 * sin(time * 1.7 + light.stageX * 20)
                beams.fill(cone, with: .color(col.opacity(0.05 * k * shimmer)))

                // Floor pool
                let pool = CGRect(x: x - spread * 1.4, y: floorY - 9, width: spread * 2.8, height: 22)
                beams.fill(Path(ellipseIn: pool), with: .radialGradient(
                    Gradient(colors: [col.opacity(0.75 * k), .clear]),
                    center: CGPoint(x: pool.midX, y: pool.midY), startRadius: 0, endRadius: spread * 1.4))

                // Lens bloom
                beams.fill(Path(ellipseIn: CGRect(x: lens.x - 34, y: lens.y - 34, width: 68, height: 68)),
                           with: .radialGradient(Gradient(colors: [col.opacity(0.9 * k), .clear]),
                                                 center: lens, startRadius: 0, endRadius: 34))
            }

            // Fixture body
            let body = CGRect(x: x - 13, y: trussY - 2, width: 26, height: 20)
            ctx.fill(Path(roundedRect: body, cornerRadius: 5), with: .color(Color(white: 0.09)))
            ctx.stroke(Path(roundedRect: body, cornerRadius: 5), with: .color(.white.opacity(0.12)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: lens.x - 7, y: lens.y - 5, width: 14, height: 8)),
                     with: .color(k > 0.01 ? col.opacity(0.4 + 0.6 * k) : Color(white: 0.2)))

            // Label
            ctx.draw(Text(light.name).font(Theme.mono(9, .medium)).foregroundStyle(Theme.dim),
                     at: CGPoint(x: x, y: floorY + 18))
        }

        if lights.isEmpty {
            ctx.draw(Text("No lights yet — open Lights & Output to add some").font(Theme.display(14, .semibold))
                .foregroundStyle(Theme.dim), at: CGPoint(x: w / 2, y: h / 2))
        }
    }

    @ViewBuilder private func sectionBadge(_ t: Double) -> some View {
        if let sec = state.project.sections.first(where: { t >= $0.start && t < $0.end }) {
            HStack(spacing: 8) {
                Circle().fill(sec.kind.tint.color).frame(width: 8, height: 8).glow(sec.kind.tint.color, radius: 8)
                Text(sec.kind.title.uppercased()).font(Theme.display(12, .black)).tracking(2)
                    .foregroundStyle(sec.kind.tint.color)
                EnergyBar(level: sec.energy, color: sec.kind.tint.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassPanel(corner: 12)
            .padding(12)
            .animation(.easeInOut, value: sec.id)
        }
    }
}

struct EnergyBar: View {
    var level: Double
    var color: Color
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(i) / 8 < level ? color : Theme.line)
                    .frame(width: 4, height: 6 + CGFloat(i))
            }
        }
    }
}

/// Live-record score: combo + floating hit grades.
struct ScoreHUD: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(state.score)").font(Theme.display(28, .black)).foregroundStyle(Theme.text)
                .contentTransition(.numericText()).animation(.snappy, value: state.score)
            HStack(spacing: 6) {
                Text("COMBO").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                Text("×\(state.combo)").font(Theme.display(16, .black))
                    .foregroundStyle(state.combo >= 8 ? Theme.magenta : Theme.cyan)
                    .glow(state.combo >= 8 ? Theme.magenta : .clear, radius: 10)
            }
            ZStack(alignment: .trailing) {
                ForEach(state.judgements.suffix(1)) { j in
                    Text(j.grade.rawValue)
                        .font(Theme.display(22, .black)).italic()
                        .foregroundStyle(color(j.grade))
                        .glow(color(j.grade), radius: 14)
                        .transition(.asymmetric(insertion: .scale(scale: 1.6).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .frame(height: 30)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: state.judgements.last?.id)
        }
        .padding(14)
    }

    private func color(_ g: HitJudgement.Grade) -> Color {
        switch g {
        case .perfect: Theme.magenta
        case .great: Theme.cyan
        case .good: Theme.lime
        case .off: Theme.dim
        }
    }
}

struct MasterFader: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        VStack(spacing: 8) {
            Text("MASTER").font(Theme.mono(10)).foregroundStyle(Theme.dim)
            Slider(value: $state.master, in: 0...1).frame(width: 140).tint(Theme.amber)
            Button(state.master > 0 ? "BLACKOUT" : "RESTORE") { state.master = state.master > 0 ? 0 : 1 }
                .buttonStyle(NeonButtonStyle(color: state.master > 0 ? Theme.magenta : Theme.lime))
        }
        .padding(12).glassPanel(corner: 14).padding(12)
    }
}
