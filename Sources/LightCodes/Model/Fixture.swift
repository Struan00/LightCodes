import Foundation

/// What a single DMX channel on a light does.
/// Modelled on QLC+'s channel presets, reduced to what a beginner needs.
enum ChannelRole: String, Codable, CaseIterable {
    case dimmer, red, green, blue, white, amber, strobe
    /// A channel we hold at a fixed value (e.g. a "mode" channel that must be 0).
    case fixed
}

struct FixtureChannel: Codable, Hashable {
    var role: ChannelRole
    var fixedValue: UInt8 = 0
}

/// A light "personality": the ordered list of channels it listens to.
struct FixtureProfile: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var blurb: String
    var channels: [FixtureChannel]

    var channelCount: Int { channels.count }
    var hasColor: Bool { channels.contains { $0.role == .red } }

    static let library: [FixtureProfile] = [
        FixtureProfile(id: "dimmer-1", name: "Dimmer", blurb: "1 channel · plain white / single colour",
                       channels: [.init(role: .dimmer)]),
        FixtureProfile(id: "rgb-3", name: "RGB PAR", blurb: "3 channels · Red, Green, Blue",
                       channels: [.init(role: .red), .init(role: .green), .init(role: .blue)]),
        FixtureProfile(id: "drgb-4", name: "Dimmer + RGB", blurb: "4 channels · Dimmer, R, G, B",
                       channels: [.init(role: .dimmer), .init(role: .red), .init(role: .green), .init(role: .blue)]),
        FixtureProfile(id: "rgbw-4", name: "RGBW PAR", blurb: "4 channels · R, G, B, White",
                       channels: [.init(role: .red), .init(role: .green), .init(role: .blue), .init(role: .white)]),
        FixtureProfile(id: "par-7", name: "Generic 7ch PAR", blurb: "7 channels · Dim, R, G, B, Strobe, Mode, Speed",
                       channels: [.init(role: .dimmer), .init(role: .red), .init(role: .green), .init(role: .blue),
                                  .init(role: .strobe), .init(role: .fixed), .init(role: .fixed)]),
        FixtureProfile(id: "rgbwa-6", name: "RGBWA + Dimmer", blurb: "6 channels · Dim, R, G, B, W, Amber",
                       channels: [.init(role: .dimmer), .init(role: .red), .init(role: .green), .init(role: .blue),
                                  .init(role: .white), .init(role: .amber)]),
    ]
}

/// A real light patched into the rig at a DMX start address.
struct PatchedLight: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var profile: FixtureProfile
    /// 1-based DMX start address, the number you set on the light's menu.
    var address: Int
    /// Position on the virtual stage, 0...1 across.
    var stageX: Double

    var lastAddress: Int { address + profile.channelCount - 1 }
}
