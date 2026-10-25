import Foundation

/// What one light is doing at one instant.
struct LightState: Equatable {
    var intensity: Double = 0
    var color: RGB = .white
}

/// Pure function of (show, time) -> light states. Both the on-screen stage and the
/// DMX output call this, so what you see is exactly what the rig gets.
/// Rules borrowed from QLC+'s Universe: intensity merges HTP (highest wins),
/// colour merges LTP (latest-starting clip wins). Blackout overrides everything.
struct LightEngine {
    var lights: [PatchedLight]
    var clips: [Clip]
    var beats: [Double]
    var bpm: Double

    func states(at t: Double, master: Double = 1) -> [UUID: LightState] {
        var out: [UUID: LightState] = [:]
        var colorStart: [UUID: Double] = [:]
        var blackout = Set<UUID>()
        let order = lights.sorted { $0.stageX < $1.stageX }.map(\.id)

        for clip in clips where t >= clip.start && t < clip.end {
            let targets = clip.lightID.map { [$0] } ?? order
            for (index, id) in targets.enumerated() {
                if clip.kind == .blackout { blackout.insert(id); continue }
                let v = level(clip, at: t, index: index, count: targets.count) * clip.intensity
                var s = out[id] ?? LightState()
                s.intensity = max(s.intensity, v)
                if v > 0.001, clip.start >= (colorStart[id] ?? -.infinity) {
                    s.color = clip.color
                    colorStart[id] = clip.start
                }
                out[id] = s
            }
        }
        for id in blackout { out[id] = LightState(intensity: 0, color: out[id]?.color ?? .white) }
        if master < 1 { for (k, v) in out { out[k]!.intensity = v.intensity * master } }
        return out
    }

    /// 0...1 brightness of a clip at time t.
    private func level(_ c: Clip, at t: Double, index: Int, count: Int) -> Double {
        let p = c.duration > 0 ? (t - c.start) / c.duration : 1
        switch c.kind {
        case .hold:
            return 1
        case .flash:
            return pow(1 - p, 2.2)
        case .fadeIn:
            return p * p
        case .fadeOut:
            return (1 - p) * (1 - p)
        case .pulse:
            let ph = beatPhase(t, every: max(0.25, c.rate))
            return 0.08 + 0.92 * pow(1 - ph, 3)
        case .strobe:
            let hz = max(1, c.rate * 4)
            return (t - c.start).truncatingRemainder(dividingBy: 1 / hz) < 0.5 / hz ? 1 : 0
        case .chase:
            guard count > 0 else { return 0 }
            let stepLen = 60 / bpm * max(0.25, c.rate)
            let step = Int(floor((t - c.start) / stepLen))
            let local = ((t - c.start) / stepLen).truncatingRemainder(dividingBy: 1)
            return step % count == index ? 0.25 + 0.75 * (1 - local) : 0
        case .blackout:
            return 0
        }
    }

    /// 0 on the beat, rising to 1 just before the next one.
    private func beatPhase(_ t: Double, every n: Double) -> Double {
        let period = 60 / bpm * n
        guard let first = beats.first else { return t.truncatingRemainder(dividingBy: period) / period }
        let x = (t - first) / period
        return x - floor(x)
    }

    // MARK: DMX

    /// Fills a 512-channel universe from light states.
    func universe(from states: [UUID: LightState]) -> [UInt8] {
        var dmx = [UInt8](repeating: 0, count: 512)
        for light in lights {
            let s = states[light.id] ?? LightState()
            let hasDimmer = light.profile.channels.contains { $0.role == .dimmer }
            let scale = hasDimmer ? 1 : s.intensity
            let w = min(s.color.r, s.color.g, s.color.b)
            for (i, ch) in light.profile.channels.enumerated() {
                let addr = light.address - 1 + i
                guard addr >= 0 && addr < 512 else { continue }
                let v: Double
                switch ch.role {
                case .dimmer: v = s.intensity
                case .red: v = s.color.r * scale
                case .green: v = s.color.g * scale
                case .blue: v = s.color.b * scale
                case .white: v = w * scale
                case .amber: v = min(s.color.r, s.color.g * 1.6) * 0.5 * scale
                case .strobe: v = 0 // strobing is done in software, so it stays in sync
                case .fixed: dmx[addr] = ch.fixedValue; continue
                }
                dmx[addr] = UInt8(max(0, min(255, (v * 255).rounded())))
            }
        }
        return dmx
    }
}
