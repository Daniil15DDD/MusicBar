<div align="center">

<img src="assets/hero.png" alt="MusicBar: album cover and live waveform in the macOS menu bar" width="100%">

# MusicBar

**Your album cover and a live waveform, right in the macOS menu bar.**
A tiny, native Now Playing for Apple Music and Spotify, with a popover you will actually enjoy using.

[![macOS](https://img.shields.io/badge/macOS-14.2%2B-black?logo=apple&logoColor=white)](#install)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138?logo=swift&logoColor=white)](#how-it-works)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20me-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/barabashka123)

</div>

---

## Why

macOS shows a generic icon for Now Playing. MusicBar puts the **real cover art** in the menu bar with a small animated waveform beside it, like the Dynamic Island on iPhone. Click it for a compact player.

<div align="center">
<img src="assets/menubar-playing.png" height="64" alt="Playing">
&nbsp;&nbsp;&nbsp;
<img src="assets/menubar-paused.png" height="64" alt="Paused: darker cover and pause icon">
<br>
<sub>Playing &nbsp;·&nbsp; Paused (cover dims, pause icon)</sub>
</div>

## Features

- **Real album artwork** in the actual menu bar item (not a floating window), rounded like Apple's.
- **Animated waveform** next to it. It runs only while a track plays, and shows a pause icon when paused.
- **Compact popover**: cover, title, artist, album, draggable progress bar, previous / play-pause / next, shuffle, repeat.
- **Favourite** the current song and open an **Equalizer** panel (presets and on/off) for Apple Music.
- **Press animation** on play/pause, instant response, no flicker when the song changes.
- **Apple Music and Spotify**, auto-detected, switches between them gracefully.
- **Light on resources**: event-driven updates, no Dock icon, no windows until you click.
- **Settings**: launch at login, hide artwork or waveform, choose the player, click behaviour, what to show when nothing plays.
- **No audio recording by default.** See [the waveform](#about-the-waveform).

<div align="center">
<img src="assets/popover.png" width="360" alt="The MusicBar popover">
</div>

## Install

No Xcode needed, the Command Line Tools are enough:

```bash
git clone https://github.com/Daniil15DDD/MusicBar.git
cd MusicBar
./build.sh
open build/MusicBar.app
```

Or generate an Xcode project: `brew install xcodegen && xcodegen`, then open `MusicBar.xcodeproj`.

Requires **macOS 14.2+**, Apple Silicon or Intel. The build is ad-hoc signed; for sharing builds, sign with your Developer ID and notarize.

On first launch macOS asks to let MusicBar control **Music** and **Spotify**. Allow both (System Settings → Privacy & Security → Automation).

## About the waveform

Honest answer: by default the bars move like Boring Notch's: a lively, music-style animation that **does not listen to your audio**. Apple Music and Spotify streams are protected, and reading what they play means capturing system audio, which needs a permission prompt and shows macOS's recording indicator.

If you want it to react to the actual sound, turn on **Settings → Make waveform react to the audio**. MusicBar then reads live levels (five frequency bands) from a system audio tap, only while a track is playing. Nothing is recorded or stored. It is off by default.

## How it works

- `MediaController` reads Music and Spotify through AppleScript (public API, no private frameworks). It updates from Music's and Spotify's own distributed notifications, with a slow safety poll, and caches artwork per track.
- The menu bar item is an `NSStatusItem` whose button hosts a SwiftUI view with a fixed width, so it never jumps when the song changes.
- The popover is SwiftUI in an `NSPopover` and is released when closed.
- `swift build`-free: `build.sh` compiles a universal binary with `swiftc` and signs it.

Regenerate the images in `assets/` with `build/MusicBar.app/Contents/MacOS/MusicBar --render assets`.

## Limitations

- Only Apple Music and Spotify are supported (system-wide Now Playing needs private APIs, so it is not used).
- Favourite and Equalizer are Apple Music only. Spotify's scripting interface does not offer them.
- The Equalizer panel controls presets and on/off; Apple Music does not let scripts open its own EQ window.
- Streamed songs have no readable audio file, so there is no offline analysis.

## Troubleshooting

- **No song info:** check Automation permission. Reset with `tccutil reset AppleEvents` and relaunch.
- **No artwork:** some streamed tracks expose none to AppleScript; a placeholder is shown.
- **Item hidden:** a crowded menu bar or the notch can hide it. Quit other items, or move it with ⌘-drag.

## Support

If MusicBar makes your menu bar nicer, you can support development:

[![Support me on Ko-fi](https://img.shields.io/badge/Support%20me%20on-Ko--fi-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/barabashka123)

A star on the repo helps others find it too.

## Credits and license

Inspired by the Now Playing experience in iOS and by [Boring Notch](https://github.com/TheBoredTeam/boring.notch). No code was copied. MIT licensed, see [LICENSE](LICENSE).
