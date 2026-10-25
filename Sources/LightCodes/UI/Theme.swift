import SwiftUI

/// LightCodes visual language: deep space background, neon light, glass panels.
enum Theme {
    static let bg0 = Color(red: 0.020, green: 0.020, blue: 0.040)
    static let bg1 = Color(red: 0.055, green: 0.050, blue: 0.095)
    static let bg2 = Color(red: 0.090, green: 0.085, blue: 0.150)
    static let line = Color.white.opacity(0.07)
    static let text = Color.white.opacity(0.92)
    static let dim = Color.white.opacity(0.45)

    static let cyan = RGB.cyan.color
    static let magenta = RGB.magenta.color
    static let lime = RGB.lime.color
    static let amber = RGB.amber.color
    static let violet = RGB.violet.color

    static let brand = LinearGradient(colors: [cyan, violet, magenta], startPoint: .leading, endPoint: .trailing)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Soft neon bloom around a view.
    func glow(_ color: Color, radius: CGFloat = 10, strength: Double = 0.8) -> some View {
        self
            .shadow(color: color.opacity(strength), radius: radius / 2)
            .shadow(color: color.opacity(strength * 0.6), radius: radius)
    }

    /// Frosted panel with a hairline border.
    func glassPanel(corner: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .background(Theme.bg1.opacity(0.75), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// Chunky, tactile game-style button.
struct NeonButtonStyle: ButtonStyle {
    var color: Color = Theme.cyan
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(13, .bold))
            .foregroundStyle(filled ? Color.black : color)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.12)))
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: 1))
            .glow(color, radius: configuration.isPressed ? 18 : 8, strength: filled ? 0.7 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small pill label (BPM, output status...).
struct Chip: View {
    var icon: String
    var text: String
    var color: Color = Theme.dim
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(Theme.mono(11))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

func formatTime(_ t: Double) -> String {
    let t = max(0, t)
    let m = Int(t) / 60, s = Int(t) % 60, cs = Int((t - floor(t)) * 100)
    return String(format: "%d:%02d.%02d", m, s, cs)
}
