# LightCodes

**Paint light onto music.** A macOS app that syncs DMX stage lights to any song, built for beginners and designed to feel like a game.

Drop in a song. LightCodes finds the beat, bars and phrases (intro, build, drop…). Hit **Auto-Show** for an instant light show, then tweak it on a beat-snapped timeline, or play your lights in live like a rhythm game.

## Run it

Requires macOS 14+ and Xcode 15+. On macOS 26 it uses Liquid Glass; on 14–15 it falls back to system materials.

```bash
swift run                 # quick dev run
./build-app.sh            # makes dist/LightCodes.app
open Package.swift        # or edit in Xcode
```

### Building with only the Command Line Tools

Full Xcode is recommended. Without it, the macOS 27 SDK fails with `plugin for module 'SwiftUIMacros' not found` (its `@State` is a macro whose plugin ships only with Xcode). Point the build at the macOS 26 SDK instead:

```bash
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
swift run
```

## How it works (in 60 seconds)

| Mode | What you do |
|---|---|
| **Build** | Pick a *move* (Flash, Pulse, Strobe, Chase…) and a colour, then click a lane. Drag to move, drag the right edge to resize, and everything snaps to the beat. |
| **Record** | Press play and hold keys **1–9** (one per light) or **Q** (all lights) on the beat. You get graded PERFECT / GREAT / GOOD and build combos. Your taps become clips. |
| **Perform** | Full-screen highway plus a master fader and blackout, for performing. |

Keys: `Space` play · `←/→` jump a bar (⇧ = 4 bars) · `Tab` switch mode · `⌘Z` undo · `⌘D` duplicate · `⌫` delete · `⌘⇧A` Auto-Show · `⌘L` lights.

## Hardware

LightCodes speaks **DMX512**, the universal standard, so any brand of DMX light works, including hired ones.

- **USB:** Enttec DMX USB Pro or DMXking ultraDMX (recommended, rock-solid timing), or Enttec Open DMX (budget).
- **Network:** any **Art-Net** node (wired or wireless).
- **No hardware?** The stage preview shows exactly what would be sent.

Setup: open **Lights & Output** (`⌘L`), add each light with its channel layout, and set the same start address on the light's own menu (e.g. `A001`). Then click **Test Lights**. If the lights trail the music, raise the **Sync Offset**.

## Design research → decisions

| Finding | Source | What LightCodes does |
|---|---|---|
| Pro "song-sync" tools (SoundSwitch) use a DAW-style layout: one track per fixture plus a Master track. | [Serato / SoundSwitch](https://serato.com/latest/blog/20116/try-soundswitch-10-available-now), [Engine DJ community](https://community.enginedj.com/t/using-soundswitch-with-serato-dj-pro-or-other-dj-software/68781) | Lanes per light plus a **MASTER** lane (key Q) |
| SoundSwitch's *Autoscript* and *phrase* detection (Intro/Main/Bridge/Outro) is its killer feature, but phrases often need manual fixing. | [bonedo.de on SoundSwitch 2.8](https://www.bonedo.de/artikel/soundswitch-2-8-lighting-software-bringt-phrasenbearbeitung-verbessertes-batch-scripting-und-neue-styles/) | Auto-detected phrase strip; **right-click to relabel**; Auto-Show built from phrases |
| xLights sequencing is built on timing tracks plus snap-to-mark; lights lag, so effects should land slightly *before* the beat. | [xLights manual: timing tracks](https://manual.xlights.org/xlights/chapters/chapter-four-sequencer/timing-tracks), [effects grid](https://manual.xlights.org/xlights/chapters/chapter-five-menus/file/settings/effects-grid) | Beat grid with 1/4–1/16 snap; global **Sync Offset** that fires lights early |
| Lightkey's Design view only shows controls the fixture actually has; it has a virtual stage. | [lightkeyapp.com](https://lightkeyapp.com/) | Simple "moves" instead of raw channels; live **stage visualiser** |
| Rhythm games: note highway, timing grades, judging on *song* time, a user latency offset. Beginners need roughly 100–150 ms windows. | [Godot rhythm guide](https://skills.cat/skills/thedivergentai/gd-agentic-skills/godot-genre-rhythm), [Giant Bomb: note highway](https://Www.giantbomb.com/note-highway/3015-7102/) | **Record** highway; PERFECT < 40 ms, GREAT < 80 ms, GOOD < 130 ms; everything clocked off audio playback |
| QLC+ engine: fixed-rate master timer, 512-ch universes, HTP intensity / LTP colour, Enttec packet format. | [QLC+ source](https://github.com/mcallegari/qlcplus) (Apache-2.0) | Same model in `Engine/` and `Output/`, rewritten in Swift |

## Code map

```
Sources/LightCodes/
  App/       LightCodesApp (menus), AppState (all state, undo, live record, output loop)
  Model/     Fixture profiles, Project/Clip/Section types
  Audio/     AudioPlayer — sample-accurate clock that drives everything
  Analysis/  SongAnalyzer — spectral-flux onsets → BPM → beat grid → phrases
  Engine/    LightEngine (clips → light states → DMX), AutoShow
  Output/    Art-Net, Enttec Pro, Open DMX
  UI/        Theme, Stage, Timeline, Highway, Palette/Inspector, Lights sheet
```

## Status

v0.1, first full pass. Written without a Mac to compile on, so expect a small round of compile fixes on first build. Next up: Open Fixture Library import, tap-tempo and beat-grid nudging, moving-head pan/tilt, MIDI controller input, and video export of the stage.
