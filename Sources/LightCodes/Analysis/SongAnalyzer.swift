import AVFoundation
import Accelerate

/// What we learn about a song before you start designing.
struct SongAnalysis {
    var duration: Double
    /// Waveform peaks, `peaksPerSecond` values per second, 0...1.
    var peaks: [Float]
    /// Share of bass in each peak bucket, 0...1 — used to colour the waveform.
    var bass: [Float]
    var peaksPerSecond: Double
    var bpm: Double
    var beats: [Double]
    var downbeatIndex: Int
    var sections: [SongSection]
}

/// Tempo, beat and phrase detection.
/// Pipeline: spectral-flux onset envelope -> autocorrelation tempo ->
/// phase search for the beat grid -> per-beat snap to nearby onsets ->
/// bar energy -> phrase segmentation.
enum SongAnalyzer {
    static let peaksPerSecond = 100.0
    private static let fftSize = 1024
    private static let hop = 512

    static func analyze(url: URL, progress: (Double) -> Void) throws -> SongAnalysis {
        let (mono, sr) = try readMono(url: url)
        progress(0.15)
        let duration = Double(mono.count) / sr

        let (peaks, bass) = waveform(mono, sr: sr)
        progress(0.3)

        let (onset, lowEnergy) = onsetEnvelope(mono)
        let fps = sr / Double(hop)
        progress(0.65)

        let bpm = estimateTempo(onset, fps: fps)
        let beats = beatGrid(onset, fps: fps, bpm: bpm, duration: duration)
        progress(0.8)

        let downbeat = findDownbeat(beats: beats, low: lowEnergy, fps: fps)
        let sections = findSections(beats: beats, downbeat: downbeat, onset: onset,
                                    fps: fps, duration: duration)
        progress(1)

        return SongAnalysis(duration: duration, peaks: peaks, bass: bass,
                            peaksPerSecond: peaksPerSecond, bpm: bpm, beats: beats,
                            downbeatIndex: downbeat, sections: sections)
    }

    // MARK: Decoding

    private static func readMono(url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let total = AVAudioFrameCount(file.length)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else {
            throw NSError(domain: "LightCodes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read audio"])
        }
        try file.read(into: buf)
        let n = Int(buf.frameLength)
        let chans = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        guard let data = buf.floatChannelData else { return (mono, format.sampleRate) }
        for c in 0..<chans {
            let acc = mono
            vDSP.add(acc, UnsafeBufferPointer(start: data[c], count: n), result: &mono)
        }
        let sum = mono
        vDSP.multiply(1 / Float(max(chans, 1)), sum, result: &mono)
        return (mono, format.sampleRate)
    }

    // MARK: Waveform

    private static func waveform(_ x: [Float], sr: Double) -> ([Float], [Float]) {
        let bucket = max(1, Int(sr / peaksPerSecond))
        let count = x.count / bucket
        var peaks = [Float](repeating: 0, count: count)
        var bass = [Float](repeating: 0, count: count)
        // One-pole low-pass (~150 Hz) to estimate bass share.
        let a = Float(exp(-2 * Double.pi * 150 / sr))
        var lp: Float = 0
        x.withUnsafeBufferPointer { p in
            for i in 0..<count {
                var pk: Float = 0, full: Float = 0, low: Float = 0
                let base = i * bucket
                for j in 0..<bucket {
                    let s = p[base + j]
                    lp = a * lp + (1 - a) * s
                    pk = max(pk, abs(s))
                    full += s * s
                    low += lp * lp
                }
                peaks[i] = pk
                bass[i] = full > 0 ? min(1, low / full) : 0
            }
        }
        let mx = peaks.max() ?? 1
        if mx > 0 { let raw = peaks; vDSP.multiply(1 / mx, raw, result: &peaks) }
        return (peaks, bass)
    }

    // MARK: Onsets

    /// Returns (spectral flux per frame, bass energy per frame).
    private static func onsetEnvelope(_ x: [Float]) -> ([Float], [Float]) {
        let n = fftSize, half = n / 2
        let frames = max(0, (x.count - n) / hop)
        guard frames > 0,
              let dft = try? vDSP.DFT(count: n, direction: .forward,
                                      transformType: .complexComplex, ofType: Float.self) else {
            return ([], [])
        }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        var prev = [Float](repeating: 0, count: half)
        var flux = [Float](repeating: 0, count: frames)
        var low = [Float](repeating: 0, count: frames)
        var re = [Float](repeating: 0, count: n)
        let im = [Float](repeating: 0, count: n)
        var outR = [Float](repeating: 0, count: n)
        var outI = [Float](repeating: 0, count: n)
        var mag = [Float](repeating: 0, count: half)
        let lowBins = max(2, half * 150 / 22050)

        for f in 0..<frames {
            let start = f * hop
            x.withUnsafeBufferPointer { p in
                vDSP.multiply(UnsafeBufferPointer(rebasing: p[start..<start + n]), window, result: &re)
            }
            dft.transform(inputReal: re, inputImaginary: im, outputReal: &outR, outputImaginary: &outI)
            for k in 0..<half {
                // Log-compressed magnitude, as in most onset detectors.
                mag[k] = log1p(10 * sqrt(outR[k] * outR[k] + outI[k] * outI[k]))
            }
            var s: Float = 0
            for k in 0..<half {
                let d = mag[k] - prev[k]
                if d > 0 { s += d }
            }
            flux[f] = s
            low[f] = mag[0..<lowBins].reduce(0, +)
            swap(&prev, &mag)
        }
        // Remove slow trend so only "hits" remain.
        let smooth = movingAverage(flux, radius: 8)
        for i in 0..<frames { flux[i] = max(0, flux[i] - smooth[i]) }
        let mx = flux.max() ?? 1
        if mx > 0 { let raw = flux; vDSP.multiply(1 / mx, raw, result: &flux) }
        return (flux, low)
    }

    private static func movingAverage(_ x: [Float], radius: Int) -> [Float] {
        guard !x.isEmpty else { return x }
        var prefix = [Float](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { prefix[i + 1] = prefix[i] + x[i] }
        return (0..<x.count).map { i in
            let a = max(0, i - radius), b = min(x.count, i + radius + 1)
            return (prefix[b] - prefix[a]) / Float(b - a)
        }
    }

    // MARK: Tempo

    private static func estimateTempo(_ onset: [Float], fps: Double) -> Double {
        let minLag = Int(fps * 60 / 180), maxLag = Int(fps * 60 / 70)
        guard onset.count > maxLag * 2 else { return 120 }
        var best = 0.0, bestLag = Int(fps * 0.5)
        onset.withUnsafeBufferPointer { p in
            for lag in minLag...maxLag {
                var s: Float = 0
                vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + lag, 1, &s, vDSP_Length(onset.count - lag))
                let bpm = 60 * fps / Double(lag)
                // Gentle preference for 90-140 BPM, where most pop/dance music sits.
                let w = exp(-pow(log2(bpm / 120), 2) / (2 * 0.6 * 0.6))
                let score = Double(s) * w
                if score > best { best = score; bestLag = lag }
            }
        }
        // Parabolic refinement for sub-frame accuracy.
        func ac(_ lag: Int) -> Double {
            var s: Float = 0
            onset.withUnsafeBufferPointer { p in
                vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + lag, 1, &s, vDSP_Length(onset.count - lag))
            }
            return Double(s)
        }
        let y0 = ac(bestLag - 1), y1 = ac(bestLag), y2 = ac(bestLag + 1)
        let denom = y0 - 2 * y1 + y2
        let offset = denom != 0 ? 0.5 * (y0 - y2) / denom : 0
        let lag = Double(bestLag) + max(-0.5, min(0.5, offset))
        return (60 * fps / lag * 10).rounded() / 10
    }

    // MARK: Beat grid

    private static func beatGrid(_ onset: [Float], fps: Double, bpm: Double, duration: Double) -> [Double] {
        guard !onset.isEmpty else { return [] }
        let period = 60 / bpm
        // Find the phase that lines the grid up with the most onset energy.
        var bestPhase = 0.0, bestScore: Float = -1
        for step in 0..<64 {
            let phase = period * Double(step) / 64
            var s: Float = 0
            var t = phase
            while t < duration {
                let i = Int(t * fps)
                if i < onset.count { s += onset[i] }
                t += period
            }
            if s > bestScore { bestScore = s; bestPhase = phase }
        }
        // Walk the grid, letting each beat snap to a strong onset within ±8%.
        var beats: [Double] = []
        var t = bestPhase
        let win = Int(period * 0.08 * fps)
        while t < duration {
            let c = Int(t * fps)
            var bi = c, bv: Float = 0
            for i in max(0, c - win)...min(onset.count - 1, c + win) where onset[i] > bv {
                bv = onset[i]; bi = i
            }
            let snapped = bv > 0.25 ? Double(bi) / fps : t
            beats.append(snapped)
            // Next beat from the snapped one, but pulled toward the ideal grid.
            t = 0.7 * (snapped + period) + 0.3 * (t + period)
        }
        return beats
    }

    private static func findDownbeat(beats: [Double], low: [Float], fps: Double) -> Int {
        guard beats.count >= 8, !low.isEmpty else { return 0 }
        var scores = [Float](repeating: 0, count: 4)
        for (i, b) in beats.enumerated() {
            let f = min(low.count - 1, Int(b * fps))
            scores[i % 4] += low[f]
        }
        return scores.indices.max { scores[$0] < scores[$1] } ?? 0
    }

    // MARK: Sections

    private static func findSections(beats: [Double], downbeat: Int, onset: [Float],
                                     fps: Double, duration: Double) -> [SongSection] {
        guard beats.count > downbeat + 16 else {
            return [SongSection(kind: .verse, start: 0, end: duration, energy: 0.5)]
        }
        // Energy per 4-bar phrase (16 beats).
        var phraseStarts: [Double] = [0]
        var i = downbeat + 16
        while i < beats.count { phraseStarts.append(beats[i]); i += 16 }
        var energies: [Double] = []
        for (k, s) in phraseStarts.enumerated() {
            let e = k + 1 < phraseStarts.count ? phraseStarts[k + 1] : duration
            let a = Int(s * fps), b = min(onset.count, Int(e * fps))
            let slice = a < b ? onset[a..<b] : []
            energies.append(slice.isEmpty ? 0 : Double(slice.reduce(0, +)) / Double(slice.count))
        }
        let sorted = energies.sorted()
        let lo = sorted[sorted.count / 3], hi = sorted[sorted.count * 2 / 3]
        let maxE = max(sorted.last ?? 1, 0.0001)

        var out: [SongSection] = []
        for (k, e) in energies.enumerated() {
            let start = phraseStarts[k]
            let end = k + 1 < phraseStarts.count ? phraseStarts[k + 1] : duration
            let next = k + 1 < energies.count ? energies[k + 1] : e
            var kind: SectionKind
            if e >= hi { kind = .drop }
            else if e <= lo { kind = .breakdown }
            else { kind = .verse }
            if kind != .drop && next >= hi && next > e * 1.2 { kind = .build }
            if k == 0 && kind != .drop { kind = .intro }
            if k == energies.count - 1 && kind != .drop { kind = .outro }
            if let last = out.last, last.kind == kind {
                out[out.count - 1].end = end
            } else {
                out.append(SongSection(kind: kind, start: start, end: end, energy: e / maxE))
            }
        }
        return out
    }
}
