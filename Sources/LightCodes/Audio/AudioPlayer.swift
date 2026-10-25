import AVFoundation

/// Sample-accurate song playback. The song's own clock drives the lights,
/// so lights can never drift away from the music.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private let lock = NSLock()

    private var segmentStart: Double = 0
    private var pausedAt: Double = 0
    private var playing = false
    /// Bumped on every schedule so stale completion handlers are ignored.
    private var generation = 0

    private(set) var duration: Double = 0
    var onFinished: (@MainActor () -> Void)?

    init() {
        engine.attach(node)
    }

    func load(url: URL) throws {
        stop()
        let f = try AVAudioFile(forReading: url)
        file = f
        // The output thread reads `duration` in currentTime, so write it under the lock too.
        lock.withLock { duration = Double(f.length) / f.processingFormat.sampleRate }
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: f.processingFormat)
        engine.prepare()
        try engine.start()
        lock.withLock { pausedAt = 0; segmentStart = 0 }
    }

    var isPlaying: Bool { lock.withLock { playing } }

    /// Current song position in seconds. Safe to call from any thread.
    var currentTime: Double {
        lock.lock(); defer { lock.unlock() }
        guard playing,
              let nodeTime = node.lastRenderTime,
              let t = node.playerTime(forNodeTime: nodeTime) else { return pausedAt }
        return min(duration, segmentStart + Double(t.sampleTime) / t.sampleRate)
    }

    func play() {
        guard let file, !isPlaying else { return }
        let from = lock.withLock { pausedAt }
        schedule(file: file, from: from >= duration - 0.05 ? 0 : from)
        if !engine.isRunning { try? engine.start() }
        node.play()
        lock.withLock { playing = true }
    }

    func pause() {
        let t = currentTime
        lock.withLock { playing = false; pausedAt = t; generation += 1 }
        node.stop()
    }

    func stop() {
        lock.withLock { playing = false; pausedAt = 0; generation += 1 }
        node.stop()
    }

    func seek(to time: Double) {
        let t = max(0, min(duration, time))
        let wasPlaying = isPlaying
        lock.withLock { playing = false; pausedAt = t; generation += 1 }
        node.stop()
        if wasPlaying { play() }
    }

    private func schedule(file: AVAudioFile, from time: Double) {
        let sr = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(time * sr)
        let frames = AVAudioFrameCount(max(0, file.length - startFrame))
        let gen = lock.withLock { () -> Int in
            generation += 1
            segmentStart = time
            return generation
        }
        guard frames > 0 else { return }
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil,
                             completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            let current = self.lock.withLock { self.generation == gen && self.playing }
            guard current else { return }
            self.lock.withLock { self.playing = false; self.pausedAt = self.duration }
            Task { @MainActor in self.onFinished?() }
        }
    }
}
