import SwiftUI

/// LIVE REC / SHOW view: a rhythm-game "note highway". Clips stream right-to-left
/// into a fixed hit line, like Guitar Hero turned sideways. In LIVE REC you hold
/// number keys on the beat to lay light down, and get graded for timing.
struct Highway: View {
    @Environment(AppState.self) private var state
    private let pps: Double = 170

    var body: some View {
        SwiftUI.TimelineView(.animation) { _ in
            let t = state.player.currentTime
            let lanes = state.lanes
            let clips = state.project.clips
            let beats = state.project.beats
            let down = state.project.downbeatIndex
            let lit = state.engine.states(at: t)
            let live = state.mode == .live
            Canvas { ctx, size in
                let header: CGFloat = 70
                let hitX = header + (size.width - header) * 0.28
                let laneH = min(54, (size.height - 16) / CGFloat(max(1, lanes.count)))
                let top = (size.height - laneH * CGFloat(lanes.count)) / 2
                let span = Double(size.width) / pps
                func x(_ time: Double) -> CGFloat { hitX + CGFloat((time - t) * pps) }

                // Beat lines scrolling toward the hit line
                for (i, b) in beats.enumerated() where b > t - span && b < t + span {
                    let bx = x(b)
                    guard bx > header else { continue }
                    let bar = (i - down) % 4 == 0
                    var p = Path(); p.move(to: CGPoint(x: bx, y: top)); p.addLine(to: CGPoint(x: bx, y: top + laneH * CGFloat(lanes.count)))
                    ctx.stroke(p, with: .color(.white.opacity(bar ? 0.16 : 0.05)), lineWidth: bar ? 1.5 : 1)
                }

                var glowCtx = ctx
                glowCtx.blendMode = .plusLighter

                for (i, light) in lanes.enumerated() {
                    let y = top + CGFloat(i) * laneH
                    let row = CGRect(x: header, y: y + 3, width: size.width - header, height: laneH - 6)
                    ctx.fill(Path(roundedRect: row, cornerRadius: 8), with: .color(.white.opacity(i % 2 == 0 ? 0.035 : 0.02)))

                    // Clips on this lane
                    let id = light?.id
                    for c in clips where c.lightID == id && c.end > t - span * 0.3 && c.start < t + span {
                        let x0 = max(header, x(c.start)), x1 = x(c.end)
                        guard x1 > x0 else { continue }
                        let r = CGRect(x: x0, y: y + 8, width: x1 - x0, height: laneH - 16)
                        let col = c.kind == .blackout ? Color(white: 0.3) : c.color.color
                        let passed = c.start <= t
                        ctx.fill(Path(roundedRect: r, cornerRadius: 6),
                                 with: .color(col.opacity(passed ? 0.25 : 0.55)))
                        ctx.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(col), lineWidth: 1.5)
                        // Leading "note head"
                        if x(c.start) >= header {
                            let head = CGRect(x: x(c.start) - 3, y: y + 5, width: 6, height: laneH - 10)
                            ctx.fill(Path(roundedRect: head, cornerRadius: 3), with: .color(col))
                        }
                    }

                    // Gate at the hit line glows with the light's actual output
                    let s: LightState
                    if let light { s = lit[light.id] ?? LightState() }
                    else { s = lit.values.max { $0.intensity < $1.intensity } ?? LightState() }
                    let gate = CGRect(x: hitX - 18, y: y + 4, width: 36, height: laneH - 8)
                    glowCtx.fill(Path(ellipseIn: gate.insetBy(dx: -30, dy: -10)),
                                 with: .radialGradient(Gradient(colors: [s.color.color.opacity(0.8 * s.intensity), .clear]),
                                                       center: CGPoint(x: gate.midX, y: gate.midY), startRadius: 0, endRadius: 48))
                    ctx.stroke(Path(roundedRect: gate, cornerRadius: 8), with: .color(.white.opacity(0.25)), lineWidth: 1)

                    // Lane label + key cap
                    let key = i == 0 ? "Q" : "\(i)"
                    let cap = CGRect(x: 10, y: y + laneH / 2 - 11, width: 22, height: 22)
                    ctx.fill(Path(roundedRect: cap, cornerRadius: 5), with: .color(.white.opacity(0.10)))
                    ctx.stroke(Path(roundedRect: cap, cornerRadius: 5), with: .color(.white.opacity(0.15)), lineWidth: 0.5)
                    ctx.draw(Text(key).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary), at: CGPoint(x: cap.midX, y: cap.midY))
                    ctx.draw(Text(light?.name ?? "All").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary),
                             at: CGPoint(x: 38, y: y + laneH / 2), anchor: .leading)
                }

                // Hit line
                var hit = Path(); hit.move(to: CGPoint(x: hitX, y: top - 6)); hit.addLine(to: CGPoint(x: hitX, y: top + laneH * CGFloat(lanes.count) + 6))
                ctx.stroke(hit, with: .color(live ? Color.red : Color.accentColor), lineWidth: 2)

                if live && !state.isPlaying {
                    ctx.draw(Text("Hold 1–9 (or Q for all) on the beat to record light. Recording starts on your first key.")
                        .font(.callout).foregroundStyle(.secondary),
                             at: CGPoint(x: size.width / 2, y: size.height - 14))
                }
            }
        }
        .surface(cornerRadius: 16)
        .overlay(alignment: .topTrailing) {
            if state.mode == .live {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                    Text("Recording · \(state.paletteKind.title)").font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCapsule()
                .padding(10)
            }
        }
    }
}
