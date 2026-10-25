import Foundation
import SwiftUI

/// RGB colour stored 0...1, Codable so it can be saved.
struct RGB: Codable, Hashable {
    var r: Double, g: Double, b: Double

    static let white   = RGB(r: 1, g: 1, b: 1)
    static let cyan    = RGB(r: 0.10, g: 0.90, b: 1.00)
    static let magenta = RGB(r: 1.00, g: 0.15, b: 0.75)
    static let lime    = RGB(r: 0.60, g: 1.00, b: 0.20)
    static let amber   = RGB(r: 1.00, g: 0.62, b: 0.10)
    static let violet  = RGB(r: 0.55, g: 0.30, b: 1.00)
    static let red     = RGB(r: 1.00, g: 0.12, b: 0.20)
    static let swatches: [RGB] = [.white, .cyan, .magenta, .lime, .amber, .violet, .red]

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
}

/// The "moves" you drop on the timeline. Each one is a short, readable idea.
enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case hold      // solid on
    case flash     // hit then decay
    case fadeIn
    case fadeOut
    case pulse     // flash on every beat (or every N beats)
    case strobe
    case chase     // master lane only: runs across lights left to right
    case blackout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: "Hold"
        case .flash: "Flash"
        case .fadeIn: "Fade In"
        case .fadeOut: "Fade Out"
        case .pulse: "Pulse"
        case .strobe: "Strobe"
        case .chase: "Chase"
        case .blackout: "Blackout"
        }
    }

    var symbol: String {
        switch self {
        case .hold: "rectangle.fill"
        case .flash: "bolt.fill"
        case .fadeIn: "arrow.up.right"
        case .fadeOut: "arrow.down.right"
        case .pulse: "waveform.path.ecg"
        case .strobe: "sparkles"
        case .chase: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill"
        case .blackout: "moon.fill"
        }
    }

    var hint: String {
        switch self {
        case .hold: "Light stays on for the whole clip"
        case .flash: "Punchy hit that fades away"
        case .fadeIn: "Slowly rises to full"
        case .fadeOut: "Slowly drops to dark"
        case .pulse: "Throbs on every beat"
        case .strobe: "Rapid flicker — use for drops"
        case .chase: "Runs across your lights in order"
        case .blackout: "Forces lights dark"
        }
    }

    /// Default length in beats when dropped.
    var defaultBeats: Double {
        switch self {
        case .flash: 1
        case .strobe: 4
        case .fadeIn, .fadeOut: 8
        default: 4
        }
    }
}

struct Clip: Codable, Hashable, Identifiable {
    var id = UUID()
    /// nil = master lane (all lights).
    var lightID: UUID?
    var kind: ClipKind
    var start: Double      // seconds
    var duration: Double   // seconds
    var color: RGB = .white
    var intensity: Double = 1
    /// Pulse/chase: beats per step. Strobe: flashes per second.
    var rate: Double = 1

    var end: Double { start + duration }
}

enum SectionKind: String, Codable, CaseIterable {
    case intro, verse, build, drop, breakdown, outro

    var title: String { rawValue.capitalized }
    var tint: RGB {
        switch self {
        case .intro: .violet
        case .verse: .cyan
        case .build: .amber
        case .drop: .magenta
        case .breakdown: .lime
        case .outro: .violet
        }
    }
}

/// A phrase of the song (intro, drop...), like SoundSwitch's phrase track.
struct SongSection: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: SectionKind
    var start: Double
    var end: Double
    var energy: Double
}

/// Everything about a song's show. Saved as a `.lightcodes` file.
struct Project: Codable {
    var version = 1
    var audioPath: String?
    var songTitle: String = "Untitled"
    var bpm: Double = 120
    var beats: [Double] = []
    var downbeatIndex: Int = 0
    var sections: [SongSection] = []
    var lights: [PatchedLight] = []
    var clips: [Clip] = []
    /// Lights are told what to do this many ms early, to beat hardware lag.
    var latencyMs: Double = 40
    var artNetHost: String = "255.255.255.255"
}
