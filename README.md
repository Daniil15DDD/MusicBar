<div align="center">

<img src="assets/hero.png" alt="MusicBar: album cover and waveform in the macOS menu bar" width="100%">

# MusicBar

**Your album cover in the macOS menu bar, with a waveform next to it.**

[![macOS](https://img.shields.io/badge/macOS-14.2%2B-black?logo=apple&logoColor=white)](#install)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Download](https://img.shields.io/github/v/release/Daniil15DDD/MusicBar?label=download)](https://github.com/Daniil15DDD/MusicBar/releases/latest)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20me-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/barabashka123)

</div>

## Why

macOS shows a plain icon for Now Playing. MusicBar shows the **real cover** instead, like the iPhone's Dynamic Island. Click it for a small player.

<div align="center">
<img src="assets/menubar-playing.png" height="64" alt="Playing">
&nbsp;&nbsp;
<img src="assets/menubar-paused.png" height="64" alt="Paused">
<br><sub>Playing · Paused</sub>
<br><br>
<img src="assets/popover.png" width="360" alt="The player popover">
</div>

## Features

- Real album art and an animated waveform in the menu bar
- Compact player: seek bar, previous / play / next, shuffle, repeat
- Favourite and equalizer presets (Apple Music)
- Works with **Apple Music** and **Spotify**
- Light on resources, no Dock icon, no audio recording

## Install

1. Download `MusicBar-1.0.zip` from [Releases](https://github.com/Daniil15DDD/MusicBar/releases/latest) and unzip it.
2. Move `MusicBar.app` to Applications and right-click → **Open** (it is not notarized).
3. Allow it to control Music and Spotify when macOS asks.

Needs macOS 14.2+. To build from source instead: `git clone` this repo, then `./build.sh` (Command Line Tools are enough).

## Good to know

- The waveform is a lively animation, not a real audio analysis, so nothing is listened to. An optional setting makes it react to live audio (macOS then asks for audio-capture permission).
- Favourite and equalizer are Apple Music only.
- No song info? Check System Settings → Privacy & Security → Automation.

## Support

If you like it, you can support me on Ko-fi, and a star helps others find it.

[![Support me on Ko-fi](https://img.shields.io/badge/Support%20me%20on-Ko--fi-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/barabashka123)

MIT licensed. Inspired by iOS Now Playing and [Boring Notch](https://github.com/TheBoredTeam/boring.notch); no code copied. Album artwork shown in the images belongs to its owners.
