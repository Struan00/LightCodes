import SwiftUI
import AppKit

@main
struct LightCodesApp: App {
    @State private var state = AppState()

    init() {
        // Running via `swift run` gives no app bundle; make it a proper foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("LightCodes") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1240, minHeight: 740)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Song…") { state.chooseSong() }.keyboardShortcut("n")
                Button("Open Show…") { state.open() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Show") { state.save() }.keyboardShortcut("s")
                Button("Save Show As…") { state.save(as: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { state.undo() }.keyboardShortcut("z")
                Button("Redo") { state.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Duplicate Clips") { state.duplicateSelection() }.keyboardShortcut("d")
                Button("Delete Clips") { state.deleteSelection() }.keyboardShortcut(.delete)
            }
            CommandMenu("Show") {
                Button("Auto-Show") { state.runAutoShow() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Lights & Output…") { state.showPatch = true }.keyboardShortcut("l")
                Divider()
                Button("Clear All Clips") { state.clearShow() }
            }
        }
    }
}
