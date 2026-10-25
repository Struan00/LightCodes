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
        .surface(cornerRadius: 16)
    }

    private func draw(ctx: GraphicsContext, size: CGSize, states: [UUID: LightState], time: Double) {
        let w = size.width, h = size.height
        let trussY = h * 0.13
        let floorY = h * 0.86

        // Room
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(white: 0.015), Color(white: 0.045)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        // Floor
        var floor = Path()
        floor.addRect(CGRect(x: 0, y: floorY, width: w, height: h - floorY))
        ctx.fill(floor, with: .color(Color(white: 0.03)))
        var grid = Path()
        for i in 0...20 {
            let x = w * Double(i) / 20
            grid.move(to: CGPoint(x: w / 2 + (x - w / 2) * 0.55, y: floorY))
            grid.addLine(to: CGPoint(x: x, y: h))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.03)), lineWidth: 0.5)

        // Truss
        let truss = CGRect(x: w * 0.05, y: trussY - 7, width: w * 0.9, height: 14)
        ctx.fill(Path(roundedRect: truss, cornerRadius: 3), with: .color(Color(white: 0.10)))
        var lattice = Path()
        stride(from: truss.minX, to: truss.maxX, by: 14).forEach { x in
            lattice.move(to: CGPoint(x: x, y: truss.minY)); lattice.addLine(to: CGPoint(x: x + 14, y: truss.maxY))
        }
        ctx.stroke(lattice, with: .color(Color(white: 0.17)), lineWidth: 0.75)

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
            ctx.draw(Text(light.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary),
                     at: CGPoint(x: x, y: floorY + 18))
        }

        if lights.isEmpty {
            ctx.draw(Text("No lights yet. Open Lights & Output to add some.").font(.callout)
                .foregroundStyle(.secondary), at: CGPoint(x: w / 2, y: h / 2))
        }
    }

    @ViewBuilder private func sectionBadge(_ t: Double) -> some View {
        if let sec = state.project.sections.first(where: { t >= $0.start && t < $0.end }) {
            HStack(spacing: 8) {
                Circle().fill(sec.kind.tint.color).frame(width: 6, height: 6)
                Text(sec.kind.title).font(.subheadline.weight(.medium))
                EnergyBar(level: sec.energy, color: sec.kind.tint.color)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassCapsule()
            .padding(12)
            .animation(.smooth, value: sec.id)
        }
    }
}

struct EnergyBar: View {
    var level: Double
    var color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<6, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(i) / 6 < level ? AnyShapeStyle(color.opacity(0.85)) : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: 4 + CGFloat(i) * 1.5)
            }
        }
    }
}

/// Live-record score: combo + the latest hit grade.
struct ScoreHUD: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(state.score)")
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText()).animation(.snappy, value: state.score)
            Text("Combo ×\(state.combo)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            ZStack(alignment: .trailing) {
                ForEach(state.judgements.suffix(1)) { j in
                    Text(j.grade.rawValue.capitalized)
                        .font(.headline)
                        .foregroundStyle(color(j.grade))
                        .transition(.asymmetric(insertion: .scale(scale: 1.3).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .frame(height: 22)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: state.judgements.last?.id)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glass(cornerRadius: 18)
        .padding(12)
    }

    private func color(_ g: HitJudgement.Grade) -> Color {
        switch g {
        case .perfect: .accentColor
        case .great: .green
        case .good: .yellow
        case .off: .secondary
        }
    }
}

struct MasterFader: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            Text("Master").font(.subheadline.weight(.medium))
            Slider(value: $state.master, in: 0...1).frame(width: 160)
            Button(state.master > 0 ? "Blackout" : "Restore") { state.master = state.master > 0 ? 0 : 1 }
                .glassButton(prominent: state.master == 0)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .glass(cornerRadius: 18)
        .padding(12)
    }
}
