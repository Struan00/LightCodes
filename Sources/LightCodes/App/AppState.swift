import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Mode: String, CaseIterable, Identifiable {
    case build = "BUILD", live = "LIVE REC", show = "SHOW"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .build: "square.stack.3d.up.fill"
        case .live: "record.circle"
        case .show: "play.tv.fill"
        }
    }
}

/// Rhythm-game style feedback when you tap lights in by hand.
struct HitJudgement: Identifiable {
    enum Grade: String { case perfect = "PERFECT", great = "GREAT", good = "GOOD", off = "OFF-BEAT" }
    let id = UUID()
    let grade: Grade
    let lane: Int
    let date = Date()
}

enum SnapDivision: Double, CaseIterable, Identifiable {
    case off = 0, bar = 4, beat = 1, half = 0.5, quarter = 0.25
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .off: "Free"
        case .bar: "Bar"
        case .beat: "1/4"
        case .half: "1/8"
        case .quarter: "1/16"
        }
    }
}

/// Analysis progress written from a background thread, read by the UI.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0.0
    var value: Double {
        get { lock.withLock { v } }
        set { lock.withLock { v = newValue } }
    }
}

/// Thread-safe copy of what the output loop needs.
private final class EngineBox {
    private let lock = NSLock()
    private var engine = LightEngine(lights: [], clips: [], beats: [], bpm: 120)
    private var latency = 0.04
    private var master = 1.0
    private var output: DMXOutput?
    func setOutput(_ o: DMXOutput?) { lock.withLock { output = o } }
    func currentOutput() -> DMXOutput? { lock.withLock { output } }
    func set(_ e: LightEngine, latency l: Double, master m: Double) {
        lock.withLock { engine = e; latency = l; master = m }
    }
    func get() -> (LightEngine, Double, Double) { lock.withLock { (engine, latency, master) } }
}

@Observable
@MainActor
final class AppState {
    // MARK: Song + show
    var project = Project() { didSet { syncEngine() } }
    var analysis: SongAnalysis?
    var analyzing = false
    let progress = ProgressBox()
    var errorMessage: String?
    var fileURL: URL?

    // MARK: Playback
    let player = AudioPlayer()
    var isPlaying = false
    var duration: Double { analysis?.duration ?? player.duration }
    var master = 1.0 { didSet { syncEngine() } }

    // MARK: Editing
    var mode: Mode = .build
    var selection: Set<UUID> = []
    var pixelsPerSecond: Double = 80
    var snap: SnapDivision = .beat
    var showPatch = false
    var paletteKind: ClipKind = .flash
    var paletteColor: RGB = .cyan

    // MARK: Live record
    var judgements: [HitJudgement] = []
    var combo = 0
    var bestCombo = 0
    var score = 0
    private var held: [Int: (start: Double, clipID: UUID)] = [:]

    // MARK: Output
    var output: DMXOutput? { didSet { box.setOutput(output) } }
    var outputName: String { output?.name ?? "Stage preview only" }
    private let box = EngineBox()
    private var outputTimer: DispatchSourceTimer?

    private var undoStack: [Project] = []
    private var redoStack: [Project] = []

    init() {
        player.onFinished = { [weak self] in self?.isPlaying = false }
        syncEngine()
        startOutputLoop()
    }

    var engine: LightEngine {
        LightEngine(lights: project.lights, clips: project.clips, beats: project.beats, bpm: project.bpm)
    }

    /// Lanes in display order. Index 0 is always the Master lane.
    var lanes: [PatchedLight?] { [nil] + project.lights.map { Optional($0) } }

    private func syncEngine() {
        box.set(engine, latency: project.latencyMs / 1000, master: master)
    }

    // MARK: Undo

    func checkpoint() {
        undoStack.append(project)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let p = undoStack.popLast() else { return }
        redoStack.append(project); project = p
    }

    func redo() {
        guard let p = redoStack.popLast() else { return }
        undoStack.append(project); project = p
    }

    // MARK: Song loading

    func chooseSong() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        panel.prompt = "Use This Song"
        if panel.runModal() == .OK, let url = panel.url { loadSong(url) }
    }

    func loadSong(_ url: URL, keepShow: Bool = false) {
        do {
            try player.load(url: url)
        } catch {
            errorMessage = "Couldn't open that song: \(error.localizedDescription)"
            return
        }
        isPlaying = false
        if !keepShow {
            checkpoint()
            project.audioPath = url.path
            project.songTitle = url.deletingPathExtension().lastPathComponent
            project.clips = []
        }
        analyzing = true
        progress.value = 0
        let box = progress
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try SongAnalyzer.analyze(url: url) { box.value = $0 }
                }.value
                analysis = result
                if !keepShow {
                    project.bpm = result.bpm
                    project.beats = result.beats
                    project.downbeatIndex = result.downbeatIndex
                    project.sections = result.sections
                    if project.lights.isEmpty { addStarterRig() }
                }
            } catch {
                errorMessage = "Analysis failed: \(error.localizedDescription)"
            }
            analyzing = false
        }
    }

    /// Four RGB PARs so a brand-new user sees something immediately.
    func addStarterRig() {
        let p = FixtureProfile.library.first { $0.id == "drgb-4" }!
        for i in 0..<4 {
            project.lights.append(PatchedLight(name: "Light \(i + 1)", profile: p,
                                               address: 1 + i * p.channelCount,
                                               stageX: 0.2 + Double(i) * 0.2))
        }
    }

    // MARK: Transport

    func togglePlay() {
        if player.isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func seek(_ t: Double) { player.seek(to: t) }

    func jump(beats n: Int) {
        let t = player.currentTime
        let beats = project.beats
        guard !beats.isEmpty else { seek(t + Double(n) * 60 / project.bpm); return }
        let i = beats.lastIndex { $0 <= t + 0.01 } ?? 0
        seek(beats[max(0, min(beats.count - 1, i + n))])
    }

    // MARK: Time helpers

    func snapped(_ t: Double) -> Double {
        guard snap != .off else { return max(0, t) }
        let grid = gridTimes(every: snap.rawValue)
        guard !grid.isEmpty else { return max(0, t) }
        var lo = 0, hi = grid.count - 1
        while lo < hi { let m = (lo + hi) / 2; if grid[m] < t { lo = m + 1 } else { hi = m } }
        let a = grid[max(0, lo - 1)], b = grid[lo]
        return abs(a - t) < abs(b - t) ? a : b
    }

    /// Grid line times for a given division in beats (subdivides detected beats).
    func gridTimes(every div: Double) -> [Double] {
        let beats = project.beats
        guard beats.count > 1 else { return [] }
        if div >= 1 {
            let step = Int(div)
            let offset = step == 4 ? project.downbeatIndex % 4 : 0
            return stride(from: offset, to: beats.count, by: step).map { beats[$0] }
        }
        let sub = Int((1 / div).rounded())
        var out: [Double] = []
        out.reserveCapacity(beats.count * sub)
        for i in 0..<(beats.count - 1) {
            let a = beats[i], d = (beats[i + 1] - a) / Double(sub)
            for k in 0..<sub { out.append(a + Double(k) * d) }
        }
        out.append(beats.last!)
        return out
    }

    var beatLength: Double { 60 / project.bpm }

    func isDownbeat(_ beatIndex: Int) -> Bool { (beatIndex - project.downbeatIndex) % 4 == 0 }

    // MARK: Editing

    func addClip(kind: ClipKind, lane: Int, at time: Double, color: RGB? = nil) {
        checkpoint()
        let light = lanes.indices.contains(lane) ? lanes[lane] : nil
        let start = snapped(time)
        let clip = Clip(lightID: light?.id, kind: kind, start: start,
                        duration: kind.defaultBeats * beatLength,
                        color: color ?? paletteColor, intensity: 1,
                        rate: kind == .strobe ? 2 : (kind == .chase ? 0.5 : 1))
        project.clips.append(clip)
        selection = [clip.id]
    }

    func updateClip(_ id: UUID, _ change: (inout Clip) -> Void) {
        guard let i = project.clips.firstIndex(where: { $0.id == id }) else { return }
        // Copy out and back so `change` may read other state without an exclusivity conflict.
        var c = project.clips[i]
        change(&c)
        project.clips[i] = c
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        checkpoint()
        project.clips.removeAll { selection.contains($0.id) }
        selection = []
    }

    func duplicateSelection() {
        let picked = project.clips.filter { selection.contains($0.id) }
        guard let first = picked.map(\.start).min(), let last = picked.map(\.end).max() else { return }
        checkpoint()
        let shift = snapped(last) - snapped(first) > 0 ? snapped(last) - snapped(first) : last - first
        var new: Set<UUID> = []
        for var c in picked {
            c.id = UUID(); c.start += shift
            project.clips.append(c); new.insert(c.id)
        }
        selection = new
    }

    func runAutoShow() {
        checkpoint()
        project.clips = AutoShow.generate(sections: project.sections, beats: project.beats,
                                          bpm: project.bpm, lights: project.lights)
        selection = []
    }

    func clearShow() { checkpoint(); project.clips = []; selection = [] }

    // MARK: Lights

    func addLight(profile: FixtureProfile) {
        checkpoint()
        let next = (project.lights.map(\.lastAddress).max() ?? 0) + 1
        let n = project.lights.count
        project.lights.append(PatchedLight(name: "Light \(n + 1)", profile: profile, address: next,
                                           stageX: min(0.95, 0.1 + Double(n) * 0.12)))
        respaceStage()
    }

    func removeLight(_ id: UUID) {
        checkpoint()
        project.lights.removeAll { $0.id == id }
        project.clips.removeAll { $0.lightID == id }
        respaceStage()
    }

    func respaceStage() {
        let n = project.lights.count
        for i in project.lights.indices {
            project.lights[i].stageX = n == 1 ? 0.5 : 0.12 + 0.76 * Double(i) / Double(n - 1)
        }
    }

    func addressConflicts() -> Set<UUID> {
        var bad = Set<UUID>()
        let l = project.lights
        for a in l.indices { for b in l.indices where a < b {
            if l[a].address <= l[b].lastAddress && l[b].address <= l[a].lastAddress {
                bad.insert(l[a].id); bad.insert(l[b].id)
            }
        } }
        return bad
    }

    /// Flash each light in turn so you can check the cabling and addresses.
    func testLights() {
        let start = player.currentTime + 0.1
        checkpoint()
        let ids = project.lights.map(\.id)
        var temp: [Clip] = []
        for (i, id) in ids.enumerated() {
            temp.append(Clip(lightID: id, kind: .flash, start: start + Double(i) * 0.5, duration: 0.5, color: .white))
        }
        let saved = project.clips
        project.clips += temp
        if !player.isPlaying { togglePlay() }
        let wait = Double(ids.count) * 0.5 + 0.4
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self else { return }
            self.project.clips = saved
            _ = self.undoStack.popLast()
        }
    }

    // MARK: Live record (keys 1-9 = lanes, Q = master)

    func liveKeyDown(lane: Int) {
        guard mode == .live, held[lane] == nil, lanes.indices.contains(lane) else { return }
        if !player.isPlaying { togglePlay() }
        let t = player.currentTime
        if held.isEmpty { checkpoint() }
        let raw = snap == .off ? t : snapped(t)
        let clip = Clip(lightID: lanes[lane]?.id, kind: paletteKind == .chase && lane != 0 ? .hold : paletteKind,
                        start: raw, duration: 0.05, color: paletteColor)
        project.clips.append(clip)
        held[lane] = (t, clip.id)
        judge(t, lane: lane)
    }

    func liveKeyUp(lane: Int) {
        guard let h = held.removeValue(forKey: lane) else { return }
        let t = player.currentTime
        updateClip(h.clipID) { c in
            let end = snap == .off ? t : max(c.start + beatLength * max(0.25, snap.rawValue), snapped(t))
            c.duration = max(beatLength / 4, end - c.start)
        }
    }

    private func judge(_ t: Double, lane: Int) {
        let beats = gridTimes(every: 0.5)
        let d = beats.map { abs($0 - t) }.min() ?? 1
        let grade: HitJudgement.Grade = d < 0.04 ? .perfect : d < 0.08 ? .great : d < 0.13 ? .good : .off
        switch grade {
        case .perfect: combo += 1; score += 300 * max(1, combo / 8)
        case .great: combo += 1; score += 200
        case .good: combo += 1; score += 100
        case .off: combo = 0
        }
        bestCombo = max(bestCombo, combo)
        judgements.append(HitJudgement(grade: grade, lane: lane))
        if judgements.count > 12 { judgements.removeFirst() }
    }

    // MARK: Output

    func connectArtNet() {
        output?.close()
        output = ArtNetOutput(host: project.artNetHost)
    }

    func connectUSB(path: String, pro: Bool) {
        output?.close()
        output = pro ? EnttecProOutput(path: path) as DMXOutput? : OpenDMXOutput(path: path)
        if output == nil { errorMessage = "Couldn't open \(path). Is it plugged in, and not used by another app?" }
    }

    func disconnect() { output?.close(); output = nil }

    /// 44 Hz DMX refresh (DMX's practical max for 512 channels), driven by the audio clock.
    private func startOutputLoop() {
        // Serial queue: ticks must never overlap, or outputs see concurrent send() calls.
        let queue = DispatchQueue(label: "lightcodes.output", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(23), leeway: .milliseconds(1))
        let box = self.box
        let player = self.player
        timer.setEventHandler {
            guard let out = box.currentOutput() else { return }
            let (engine, latency, master) = box.get()
            let t = player.currentTime + latency
            out.send(engine.universe(from: engine.states(at: t, master: master)))
        }
        timer.resume()
        outputTimer = timer
    }

    // MARK: Files

    func save(as saveAs: Bool = false) {
        var url = fileURL
        if url == nil || saveAs {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "lightcodes") ?? .json]
            panel.nameFieldStringValue = project.songTitle + ".lightcodes"
            guard panel.runModal() == .OK else { return }
            url = panel.url
        }
        guard let url else { return }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(project).write(to: url)
            fileURL = url
        } catch { errorMessage = "Save failed: \(error.localizedDescription)" }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lightcodes") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let p = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
            project = p
            fileURL = url
            undoStack = []; redoStack = []
            if let path = p.audioPath { loadSong(URL(fileURLWithPath: path), keepShow: true) }
        } catch { errorMessage = "Couldn't open show: \(error.localizedDescription)" }
    }
}
