import SwiftUI

/// Lights & Output: add lights, set their DMX address, connect hardware, test.
struct PatchSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var usbDevices: [String] = []
    @State private var usbPro = true

    var body: some View {
        @Bindable var state = state
        let conflicts = state.addressConflicts()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Lights & Output").font(Theme.display(24, .black)).foregroundStyle(Theme.text)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(NeonButtonStyle(color: Theme.cyan, filled: true))
                    .keyboardShortcut(.defaultAction)
            }

            HStack(alignment: .top, spacing: 16) {
                // Rig
                VStack(alignment: .leading, spacing: 10) {
                    section("YOUR LIGHTS")
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(state.project.lights) { light in
                                LightRow(light: binding(for: light), conflict: conflicts.contains(light.id))
                            }
                        }
                    }
                    .frame(minHeight: 220)
                    Menu {
                        ForEach(FixtureProfile.library) { p in
                            Button("\(p.name) — \(p.blurb)") { state.addLight(profile: p) }
                        }
                    } label: {
                        Label("Add Light", systemImage: "plus.circle.fill")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    tip("Not sure which type? Check the light's manual for its \"DMX channel chart\". A cheap RGB PAR is usually **Dimmer + RGB** (4ch) or **Generic 7ch PAR**. Then set the light's address (often shown as **A001** or **d001** on its little screen) to match the @ number here.")
                }
                .frame(maxWidth: .infinity)

                // Output
                VStack(alignment: .leading, spacing: 10) {
                    section("OUTPUT")
                    HStack {
                        Circle().fill(state.output == nil ? Theme.dim : Theme.lime).frame(width: 8, height: 8)
                            .glow(state.output == nil ? .clear : Theme.lime, radius: 6)
                        Text(state.outputName).font(Theme.mono(12)).foregroundStyle(Theme.text)
                    }

                    GroupBox("USB DMX interface") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Type", selection: $usbPro) {
                                Text("Enttec Pro / DMXking (recommended)").tag(true)
                                Text("Enttec Open DMX (budget)").tag(false)
                            }
                            if usbDevices.isEmpty {
                                Text("No USB-DMX found. Plug it in, then Refresh.").font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }
                            ForEach(usbDevices, id: \.self) { d in
                                HStack {
                                    Text((d as NSString).lastPathComponent).font(Theme.mono(11))
                                    Spacer()
                                    Button("Connect") { state.connectUSB(path: d, pro: usbPro) }
                                }
                            }
                            Button("Refresh") { usbDevices = USBDMXDevices.list() }
                        }
                        .padding(6)
                    }

                    GroupBox("Art-Net (network / wireless)") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Node IP", text: $state.project.artNetHost)
                                .textFieldStyle(.roundedBorder).font(Theme.mono(12))
                            Text("255.255.255.255 broadcasts to every node on your network.")
                                .font(.system(size: 10)).foregroundStyle(Theme.dim)
                            Button("Connect Art-Net") { state.connectArtNet() }
                        }
                        .padding(6)
                    }

                    HStack {
                        Button("Test Lights") { state.testLights() }
                            .buttonStyle(NeonButtonStyle(color: Theme.lime, filled: true))
                            .help("Flashes each light in order, so you can check addresses")
                        if state.output != nil {
                            Button("Disconnect") { state.disconnect() }.buttonStyle(NeonButtonStyle(color: Theme.magenta))
                        }
                    }
                    LatencyCard()
                }
                .frame(width: 330)
            }
        }
        .padding(24)
        .frame(width: 860, height: 600)
        .background(Theme.bg1)
        .onAppear { usbDevices = USBDMXDevices.list() }
    }

    /// Looks the light up by id each time, so deleting a row can't index out of range.
    private func binding(for light: PatchedLight) -> Binding<PatchedLight> {
        Binding(
            get: { state.project.lights.first { $0.id == light.id } ?? light },
            set: { new in
                if let i = state.project.lights.firstIndex(where: { $0.id == light.id }) { state.project.lights[i] = new }
            })
    }

    private func section(_ s: String) -> some View {
        Text(s).font(Theme.display(10, .black)).tracking(2).foregroundStyle(Theme.dim)
    }

    private func tip(_ s: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.max.fill").foregroundStyle(Theme.amber)
            Text(s).font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
        .padding(10)
        .background(Theme.amber.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LightRow: View {
    @Environment(AppState.self) private var state
    @Binding var light: PatchedLight
    var conflict: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.brand).frame(width: 10, height: 10)
            TextField("Name", text: $light.name).textFieldStyle(.plain).font(Theme.display(13, .bold))
                .frame(width: 110)
            Picker("", selection: $light.profile) {
                ForEach(FixtureProfile.library) { Text($0.name).tag($0) }
            }
            .labelsHidden().frame(width: 150)
            Stepper(value: $light.address, in: 1...512) {
                Text("@\(light.address)").font(Theme.mono(12, .bold))
                    .foregroundStyle(conflict ? Theme.magenta : Theme.cyan)
            }
            Text("ch \(light.address)–\(light.lastAddress)").font(Theme.mono(10, .regular)).foregroundStyle(Theme.dim)
            if conflict {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.magenta)
                    .help("Overlaps another light's channels — change one address")
            }
            Spacer()
            Button { state.removeLight(light.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.dim)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(conflict ? Theme.magenta.opacity(0.6) : Theme.line))
    }
}
