import Foundation

/// One-click show: turns the song's phrases into editable clips.
/// Same idea as SoundSwitch's Autoscript — energy decides the "move".
enum AutoShow {
    static func generate(sections: [SongSection], beats: [Double], bpm: Double,
                         lights: [PatchedLight]) -> [Clip] {
        let beat = 60 / bpm
        var clips: [Clip] = []
        func master(_ kind: ClipKind, _ s: Double, _ e: Double, _ c: RGB,
                    _ i: Double = 1, rate: Double = 1) {
            guard e - s > 0.05 else { return }
            clips.append(Clip(lightID: nil, kind: kind, start: s, duration: e - s,
                              color: c, intensity: i, rate: rate))
        }

        for (n, sec) in sections.enumerated() {
            let s = sec.start, e = sec.end
            // Punctuate every phrase change.
            if n > 0 { master(.flash, s, s + beat, .white) }
            switch sec.kind {
            case .intro:
                master(.fadeIn, s, e, .violet, 0.6)
            case .verse:
                master(.pulse, s, e, .cyan, 0.7, rate: 2)
                // Alternate lights on the off-beats for movement.
                for (i, light) in lights.enumerated() where i % 2 == 1 {
                    clips.append(Clip(lightID: light.id, kind: .pulse, start: s + beat, duration: e - s - beat,
                                      color: .violet, intensity: 0.5, rate: 2))
                }
            case .build:
                let strobeAt = max(s, e - 4 * beat)
                master(.pulse, s, strobeAt, .amber, 0.8, rate: 1)
                master(.chase, s, strobeAt, .amber, 0.6, rate: 0.5)
                master(.strobe, strobeAt, e, .white, 1, rate: 2)
            case .drop:
                master(.pulse, s, e, .magenta, 1, rate: 1)
                master(.chase, s, e, .cyan, 0.9, rate: 0.5)
            case .breakdown:
                master(.hold, s, e, .lime, 0.35)
                master(.chase, s, e, .lime, 0.7, rate: 2)
            case .outro:
                master(.fadeOut, s, e, .violet, 0.7)
            }
        }
        return clips
    }
}
