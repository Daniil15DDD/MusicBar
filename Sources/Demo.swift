import SwiftUI
import AppKit

/// Set while rendering the README images.
enum DemoMode { static var staticWaveform = false }

/// `MusicBar --render <dir> [--art <image>]` draws the real views with demo data to PNGs (used for the README images).
@MainActor
enum Demo {
    static func run(dir: URL, artPath: String?, lock: NowPlaying? = nil, lockArtPath: String? = nil, lockMotionPath: String? = nil) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DemoMode.staticWaveform = true
        let art = artPath.flatMap { NSImage(contentsOfFile: $0) } ?? render(cover, scale: 1)!
        func np(_ playing: Bool) -> NowPlaying {
            NowPlaying(player: .music, title: "Sweater Weather", artist: "The Neighbourhood", album: "I Love You.",
                       duration: 240, position: 90, isPlaying: playing, shuffle: true, repeatMode: "all", favorited: true)
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

        func strip(_ m: MediaController, width: CGFloat, menus: Bool) -> some View {
            HStack(spacing: 14) {
                if menus {
                    Text("Music").fontWeight(.bold)
                    ForEach(["File", "Edit", "View", "Window"], id: \.self) { Text($0) }
                }
                Spacer(minLength: 0)
                bar(m)
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
                Text("Mon 22:49")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(width: width, height: 30)
            .background(Color.black.opacity(0.35))
        }

        save(render(strip(playing, width: 560, menus: false).background(Color(white: 0.08)).environment(\.colorScheme, .dark)), dir.appendingPathComponent("menubar-playing.png"))
        save(render(strip(paused, width: 560, menus: false).background(Color(white: 0.08)).environment(\.colorScheme, .dark)), dir.appendingPathComponent("menubar-paused.png"))
        save(render(popover(playing).environment(\.colorScheme, .dark)), dir.appendingPathComponent("popover.png"))

        let hero = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.18, green: 0.08, blue: 0.35), Color(red: 0.03, green: 0.03, blue: 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                strip(playing, width: 1280, menus: true)
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
                    Spacer(minLength: 0)
                    popover(playing).padding(.trailing, -10)
                }
                .padding(.horizontal, 60)
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(width: 1280, height: 640)
        save(render(hero), dir.appendingPathComponent("hero.png"))

        // Lock screen: the real AppKit views, rendered offscreen with the song that is playing now.
        if let lock, let lockArt = lockArtPath.flatMap({ NSImage(contentsOfFile: $0) }) {
            save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: true), dir.appendingPathComponent("lockscreen-fullscreen.png"))
            save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: false), dir.appendingPathComponent("lockscreen-card.png"))
            if let still = lockMotionPath.flatMap({ NSImage(contentsOfFile: $0) }) {
                save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: true, motionStill: still), dir.appendingPathComponent("lockscreen-moving.png"))
            }
        }
    }

    /// Renders the lock screen card (and, for fullscreen, the backdrop) offscreen. The glass blur and the user's wallpaper
    /// are not available offscreen, so a soft gradient stands in for the wallpaper.
    static func renderLock(_ m: MediaController, fullscreen: Bool, motionStill: NSImage? = nil, size: NSSize = NSSize(width: 1440, height: 900)) -> NSImage? {
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        let wallpaper = CAGradientLayer()
        wallpaper.frame = root.bounds
        wallpaper.colors = [NSColor(red: 0.20, green: 0.19, blue: 0.18, alpha: 1).cgColor, NSColor(red: 0.07, green: 0.06, blue: 0.06, alpha: 1).cgColor]
        root.layer?.addSublayer(wallpaper)
        let win = NSWindow(contentRect: root.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = root
        let card = LockCardView(media: m)
        card.frame.origin = NSPoint(x: (size.width - LockCardView.size.width) / 2, y: size.height * 0.22 - LockCardView.size.height / 2)
        if fullscreen {
            let backdrop = LockBackdropView(media: m, frame: root.bounds)
            root.addSubview(backdrop)
            if let motionStill { backdrop.previewMotionStill(motionStill) } else { backdrop.show() }
        } else {
            // the system clock the real lock screen shows above the card
            let t = NSTextField(labelWithString: "9:41")
            t.font = NSFont.systemFont(ofSize: 150, weight: .thin); t.textColor = .white; t.alignment = .center
            t.frame = NSRect(x: 0, y: size.height * 0.62, width: size.width, height: 190)
            root.addSubview(t)
        }
        root.addSubview(card)
        card.setActive(true)
        card.useFlatBackgroundForScreenshots(fullscreen: fullscreen)
        root.layoutSubtreeIfNeeded()
        win.displayIfNeeded()
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        ctx.cgContext.scaleBy(x: scale, y: scale)
        root.layer?.render(in: ctx.cgContext)
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
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
