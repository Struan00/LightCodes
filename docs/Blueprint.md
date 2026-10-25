# LightCodes — Build Blueprint (from studying QLC+)

## What QLC+ does (and what we copy / simplify)

| QLC+ concept (source file) | What it is | LightCodes version |
|---|---|---|
| `MasterTimer` (engine/src/mastertimer.cpp) | Fixed-rate tick (~50 Hz) that recomputes every light and sends DMX | `Engine` tick at 44 Hz driven by the **audio playback clock**, not wall time |
| `Universe` (universe.cpp) | 512-byte buffer per DMX line; HTP for dimmers, LTP for others; Grand Master | `DMXUniverse` struct: `[UInt8](512)`; HTP/LTP merge; master fader + blackout |
| `QLCFixtureDef` / `.qxf` XML (resources/fixtures, 146 brands) | Fixture "personality": channels + presets (Intensity, Red, Green, Strobe…) | Import Open Fixture Library JSON; map to simple roles: *Dimmer, Color, Strobe, Other* |
| `Fixture` + address | A real light patched at a DMX start address | "Add light → pick type → address" wizard |
| `Scene` / `Chaser` / `EFX` / `RGBMatrix` | Static looks, step sequences, movement, pixel effects | **Clips**: On, Off, Fade, Pulse-on-beat, Strobe, Color, Chase (across a group) |
| `Show` / `Track` / `ShowFunction` / `ShowRunner` | Timeline: tracks of functions with start time + duration, BPM grid | **Timeline**: song waveform on top, one lane per light/group, snap-to-beat |
| `GenericFader` / `FadeChannel` | Smooth value interpolation | Envelope curves (linear / ease / snap) |
| plugins/dmxusb `enttecdmxusbpro.cpp` | Packet: `0x7E 0x06 lenLSB lenMSB 0x00 <512 bytes> 0xE7` | `EnttecProOutput` over serial (ORSSerialPort / IOKit) |
| plugins/dmxusb `enttecdmxusbopen.cpp` | Open DMX: raw 250 kbaud + manual BREAK, timing-sensitive | Supported but marked "budget / less stable" |
| plugins/artnet, E1.31 | DMX over network (UDP) | `ArtNetOutput` — wireless/ethernet nodes, also great for testing |
| (no real equivalent) | QLC+ has only basic audio triggers | **Our edge:** beat/section analysis + "Auto-Show" generator |

**What we drop for beginners:** Virtual Console, input profiles, scripting, MIDI mapping, multi-universe complexity (v1 = 1 universe, 512 channels).

Licence note: QLC+ is Apache-2.0. We learn from its design and may reuse fixture data with attribution; we write our own Swift code.

## Architecture (Swift / SwiftUI, macOS 14+)

```
LightCodes/
  App/            LightCodesApp.swift, AppState (Observable)
  Audio/          AudioPlayer (AVAudioEngine), Waveform, BeatAnalyzer
  Analysis/       BPM + beat grid, onsets, energy curve, section detection
  Fixtures/       FixtureDef, FixtureLibrary (OFL import), PatchedLight
  Show/           Show, Lane, Clip, ClipKind, Envelope, AutoShowGenerator
  Engine/         Engine (tick loop), DMXUniverse, Merger (HTP/LTP)
  Output/         DMXOutput protocol, EnttecPro, OpenDMX, ArtNet, Simulator
  UI/             Timeline, LaneView, ClipView, Inspector, PatchWizard, StageVisualizer
  Persistence/    .beatlights project file (Codable JSON + copied audio ref)
```

### Core data model
```swift
struct PatchedLight { id; name; fixtureDef; address: Int; groupIDs }
struct Clip { id; laneID; start: Double /*seconds*/; duration; kind: ClipKind; envelope; intensity; color? }
enum ClipKind { on, fade(from,to), pulse(everyBeats), strobe(hz), color(RGB), chase(order, stepBeats) }
struct Show { audioURL; bpm; beats: [Double]; sections: [Section]; lanes: [Lane]; clips: [Clip] }
```

### Sync strategy ("perfect" timing)
1. Playback clock = `AVAudioPlayerNode.playerTime` (sample-accurate).
2. Engine tick (44 Hz, high-priority DispatchSourceTimer) asks: "what time is the audio at *now*?" → evaluates all clips → fills universe → sends.
3. Global **latency offset** slider (ms) to compensate for interface + fixture lag; test with a "flash on every beat" calibration.

### Song analysis
- Decode with AVAudioFile → mono float buffer.
- Onset strength (spectral flux, via Accelerate/vDSP FFT) → tempo by autocorrelation → beat grid by dynamic programming (same idea as librosa's beat tracker).
- Energy (RMS per bar) + novelty curve → sections (intro / verse / build / drop / outro).
- Manual override: tap-tempo, drag the first downbeat, nudge the grid.

### Auto-Show generator (beginner magic)
Rules per section energy: low → slow fades/warm colors; build → accelerating pulses; drop → full strobe/chase on beats; outro → fade out. Output is ordinary clips, so it's all editable.

## Beginner UX
1. **New Show → drop a song** → analysis runs (progress bar).
2. **Add Lights** wizard: search library (or "Generic dimmer / RGB / RGBW PAR"), enter address, see a picture of the DIP/menu setting.
3. **Auto-Show** button, or drag clips from a palette onto lanes; snap to beats.
4. **Stage preview** (virtual lights glow on screen) works with no hardware — Simulator output.
5. **Connect**: auto-detect Enttec/USB-DMX or Art-Net node; "Test lights" button flashes each light in turn.
6. **Perform mode**: big play button, blackout, master fader, latency offset.

## Build milestones
1. Project skeleton + audio playback + waveform + transport.
2. Beat/tempo analysis + beat grid overlay.
3. Fixture model + generic fixtures + patch wizard.
4. Timeline lanes, clips, drag/resize/snap, inspector.
5. Engine + universe + on-screen Stage Simulator.
6. Outputs: Art-Net, Enttec Pro, Open DMX.
7. Auto-Show generator + sections.
8. Save/load, undo, polish, onboarding tutorial.

## Hardware shopping list (for testing)
- USB-DMX: Enttec DMX USB Pro (reliable) or DMXking ultraDMX Micro (Pro-compatible, cheaper).
- 2–4 generic RGB LED PARs (DMX, 3/4/7-ch modes) + DMX cables + terminator.

## Limits to be honest about
- Built and written in a Linux container: you compile/run in Xcode on your Mac; expect a fix-up round.
- Serial access needs the app's sandbox "USB" entitlement (or run unsandboxed for personal use).
