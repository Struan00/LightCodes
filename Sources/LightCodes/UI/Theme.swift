import SwiftUI

/// LightCodes visual language: system typography, Liquid Glass for controls that float,
/// quiet dark surfaces for content. The only saturated colour should be the light itself.
enum Theme {
    /// Behind everything: a dark room.
    static let canvas = Color(red: 0.035, green: 0.037, blue: 0.045)
    /// Content panels (stage, timeline). Slightly translucent so ambient light bleeds through.
    static let surface = Color(red: 0.075, green: 0.078, blue: 0.09).opacity(0.88)
    static let line = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.12)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Liquid Glass on macOS 26, a system material on earlier versions.
    @ViewBuilder func glass(cornerRadius r: CGFloat = 18, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
    }

    /// Capsule-shaped glass, for small floating badges.
    @ViewBuilder func glassCapsule() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
    }

    /// Glass button style on macOS 26, bordered system style on earlier versions.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Quiet panel for content: glass is for controls, not for the things you edit.
    func surface(cornerRadius r: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return background(Theme.surface, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

/// Small secondary label (timing, counts).
struct Chip: View {
    var icon: String
    var text: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

/// A light colour swatch with a native-looking selection ring.
struct SwatchButton: View {
    var color: RGB
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle().fill(color.color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

func formatTime(_ t: Double) -> String {
    let t = max(0, t)
    let m = Int(t) / 60, s = Int(t) % 60, cs = Int((t - floor(t)) * 100)
    return String(format: "%d:%02d.%02d", m, s, cs)
}
