import SwiftUI
import AppKit

/// `MusicBar --render <dir> [--art <image>]` draws the real views with demo data to PNGs (used for the README images).
@MainActor
enum Demo {
    static func run(dir: URL, artPath: String?) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let art = artPath.flatMap { NSImage(contentsOfFile: $0) } ?? render(cover, scale: 1)!
        func np(_ playing: Bool) -> NowPlaying {
            NowPlaying(player: .music, title: "One More Hour", artist: "Tame Impala", album: "The Slow Rush",
                       duration: 433, position: 84, isPlaying: playing, shuffle: true, repeatMode: "all", favorited: true)
        }
        let playing = MediaController(demo: np(true), artwork: art)
        let paused = MediaController(demo: np(false), artwork: art)
        let audio = AudioLevels()

        func bar(_ m: MediaController) -> some View {
            MenuBarContent(media: m, audio: audio)
                .frame(width: 46, height: 24)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.12)))
        }
        func popover(_ m: MediaController) -> some View {
            PopoverView(media: m, audio: audio, openSettings: {})
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.16)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .padding(24)
        }

        save(render(bar(playing).padding(14).background(Color(white: 0.08)).environment(\.colorScheme, .dark)), dir.appendingPathComponent("menubar-playing.png"))
        save(render(bar(paused).padding(14).background(Color(white: 0.08)).environment(\.colorScheme, .dark)), dir.appendingPathComponent("menubar-paused.png"))
        save(render(popover(playing).environment(\.colorScheme, .dark)), dir.appendingPathComponent("popover.png"))

        let hero = ZStack {
            LinearGradient(colors: [Color(red: 0.18, green: 0.08, blue: 0.35), Color(red: 0.03, green: 0.03, blue: 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("MusicBar").font(.system(size: 76, weight: .bold, design: .rounded))
                    Text("Your album cover and a live waveform, right in the macOS menu bar.")
                        .font(.system(size: 28)).foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 10) {
                        ForEach(["Apple Music", "Spotify", "macOS 14.2+", "Free & open source"], id: \.self) { t in
                            Text(t).font(.system(size: 17, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(.white.opacity(0.14)))
                        }
                    }
                }
                .frame(width: 600, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    bar(playing).padding(.trailing, 60)
                    popover(playing)
                }
            }
            .padding(.horizontal, 60)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(width: 1280, height: 640)
        save(render(hero), dir.appendingPathComponent("hero.png"))
    }

    /// Generated fallback cover, used when no `--art` image is passed.
    static var cover: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.45, blue: 0.3), Color(red: 0.35, green: 0.1, blue: 0.55)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(.white.opacity(0.9)).frame(width: 120).offset(y: -20)
            ForEach(0..<6, id: \.self) { i in
                Rectangle().fill(Color(red: 0.2, green: 0.05, blue: 0.35).opacity(0.55)).frame(height: 10).offset(y: CGFloat(30 + i * 24))
            }
        }
        .frame(width: 300, height: 300)
    }

    static func render<V: View>(_ v: V, scale: CGFloat = 2) -> NSImage? {
        let r = ImageRenderer(content: v)
        r.scale = scale
        return r.nsImage
    }

    static func save(_ img: NSImage?, _ url: URL) {
        guard let t = img?.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) else {
            print("failed:", url.lastPathComponent); return
        }
        try? png.write(to: url)
        print("wrote", url.path)
    }
}
