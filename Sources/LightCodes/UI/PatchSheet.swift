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
        VStack(spacing: 0) {
            HStack {
                Text("Lights & Output").font(.title2.weight(.semibold))
                Spacer()
                Button("Test Lights") { state.testLights() }
                    .glassButton()
                    .disabled(state.project.lights.isEmpty)
                    .help("Flashes each light in order, so you can check addresses")
                Button("Done") { dismiss() }
                    .glassButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 4)

            Form {
                Section {
                    ForEach(state.project.lights) { light in
                        LightRow(light: binding(for: light), conflict: conflicts.contains(light.id))
                    }
                    Menu {
                        ForEach(FixtureProfile.library) { p in
                            Button("\(p.name) — \(p.blurb)") { state.addLight(profile: p) }
                        }
                    } label: {
                        Label("Add Light", systemImage: "plus")
                    }
                    .fixedSize()
                } header: {
                    Text("Your Lights")
                } footer: {
                    Text("Not sure which type? Check the light's manual for its DMX channel chart. A cheap RGB PAR is usually **Dimmer + RGB** (4ch) or **Generic 7ch PAR**. Then set the address on the light's own screen (often shown as **A001** or **d001**) to match the @ number here.")
                }

                Section("Output") {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle().fill(state.output == nil ? Color.secondary : Color.green).frame(width: 7, height: 7)
                            Text(state.outputName)
                        }
                    }
                    if state.output != nil {
                        Button("Disconnect", role: .destructive) { state.disconnect() }
                    }
                }

                Section("USB DMX Interface") {
                    Picker("Type", selection: $usbPro) {
                        Text("Enttec Pro / DMXking").tag(true)
                        Text("Enttec Open DMX").tag(false)
                    }
                    if usbDevices.isEmpty {
                        Text("No USB-DMX interface found. Plug it in, then refresh.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(usbDevices, id: \.self) { d in
                        LabeledContent((d as NSString).lastPathComponent) {
                            Button("Connect") { state.connectUSB(path: d, pro: usbPro) }
                        }
                    }
                    Button("Refresh") { usbDevices = USBDMXDevices.list() }
                }

                Section {
                    TextField("Node IP", text: $state.project.artNetHost)
                        .font(Theme.mono(12))
                    Button("Connect Art-Net") { state.connectArtNet() }
                } header: {
                    Text("Art-Net")
                } footer: {
                    Text("255.255.255.255 broadcasts to every node on your network.")
                }

                LatencySection()
            }
            .formStyle(.grouped)
        }
        .frame(width: 640, height: 680)
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
}

struct LightRow: View {
    @Environment(AppState.self) private var state
    @Binding var light: PatchedLight
    var conflict: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: $light.name)
                .textFieldStyle(.plain)
                .frame(width: 100)
            Picker("Type", selection: $light.profile) {
                ForEach(FixtureProfile.library) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .frame(width: 160)
            Stepper(value: $light.address, in: 1...512) {
                Text("@\(light.address)")
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(conflict ? Color.orange : Color.primary)
            }
            Text("ch \(light.address)–\(light.lastAddress)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if conflict {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("Overlaps another light's channels. Change one address.")
            }
            Spacer()
            Button { state.removeLight(light.id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove light")
        }
    }
}
