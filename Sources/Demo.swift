import SwiftUI
import AppKit

/// Set while rendering the README images.
enum DemoMode { static var staticWaveform = false }

/// `ORBT --render <dir> [--art <image>]` draws the real views with demo data to PNGs (used for the README images).
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

        let lockMoving: NSImage? = {
            guard let lock, let lockArt = lockArtPath.flatMap({ NSImage(contentsOfFile: $0) }), let still = lockMotionPath.flatMap({ NSImage(contentsOfFile: $0) }) else { return nil }
            return renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: true, motionStill: still)
        }()
        let hero = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.17), Color(white: 0.02)],   // neutral black: matches the black and white logo
                           
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                strip(playing, width: 1280, menus: true)
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("ORBT").font(.system(size: 76, weight: .bold, design: .rounded))
                        Text("Your album cover and a live waveform, right in the macOS menu bar.")
                            .font(.system(size: 28)).foregroundStyle(.white.opacity(0.8))
                        // two short rows so the left column stays narrow and the lock screen fits inside the banner
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach([["Apple Music", "Spotify"], ["macOS 14.2+", "Free & open source"]], id: \.self) { row in
                                HStack(spacing: 10) {
                                    ForEach(row, id: \.self) { t in
                                        Text(t).font(.system(size: 17, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Capsule().fill(.white.opacity(0.14)))
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: 470, alignment: .leading)
                    Spacer(minLength: 0)
                    if let lockMoving {
                        // the lock screen with moving artwork, with the popover overlapping its corner
                        ZStack(alignment: .bottomLeading) {
                            Image(nsImage: lockMoving).resizable().aspectRatio(contentMode: .fit).frame(width: 600)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.18)))
                                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                            popover(playing).scaleEffect(0.78, anchor: .bottomLeading).offset(x: -70, y: 40)
                        }
                        .padding(.trailing, -20)
                    } else {
                        popover(playing).padding(.trailing, -10)
                    }
                }
                .padding(.horizontal, 60)
                .frame(maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(width: 1280, height: 640)
        save(render(hero), dir.appendingPathComponent("hero.png"))

        func stat(_ big: String, _ label: String) -> some View {
            VStack(spacing: 10) {
                Text(big).font(.system(size: 92, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 18)
                Text(label).font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            }
            .frame(width: 330, height: 220)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.14)))
        }
        let perf = ZStack {
            LinearGradient(colors: [Color(white: 0.17), Color(white: 0.02)],   // neutral black: matches the black and white logo
                           
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 44) {
                Text("Light on your Mac").font(.system(size: 64, weight: .bold, design: .rounded))
                HStack(spacing: 28) {
                    stat("~1%", "CPU while playing")
                    stat("<1%", "CPU while paused")
                    stat("~100 MB", "memory")
                }
                Text("Measured with top on an Apple Silicon MacBook, macOS 27, popover and lock screen closed.")
                    .font(.system(size: 20)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(width: 1280, height: 640)
        save(render(perf), dir.appendingPathComponent("performance.png"))

        // Lock screen: the real AppKit views, rendered offscreen with the song that is playing now.
        if let lock, let lockArt = lockArtPath.flatMap({ NSImage(contentsOfFile: $0) }) {
            save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: true), dir.appendingPathComponent("lockscreen-fullscreen.png"))
            save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: false), dir.appendingPathComponent("lockscreen-card.png"))
            save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: true, list: .lyrics), dir.appendingPathComponent("lockscreen-lyrics.png"))
            save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: true, list: .queue), dir.appendingPathComponent("lockscreen-queue.png"))
            if let still = lockMotionPath.flatMap({ NSImage(contentsOfFile: $0) }) {
                save(renderLock(MediaController(demo: lock, artwork: lockArt), fullscreen: true, motionStill: still), dir.appendingPathComponent("lockscreen-moving.png"))
            }
        }
    }

    /// Renders the lock screen card (and, for fullscreen, the backdrop) offscreen. The glass blur and the user's wallpaper
    /// are not available offscreen, so a soft gradient stands in for the wallpaper.
    static func renderLock(_ m: MediaController, fullscreen: Bool, motionStill: NSImage? = nil, list: LockBackdropView.Mode? = nil, size: NSSize = NSSize(width: 1440, height: 900)) -> NSImage? {
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        let wallpaper = CAGradientLayer()
        wallpaper.frame = root.bounds
        wallpaper.colors = [NSColor(red: 0.20, green: 0.19, blue: 0.18, alpha: 1).cgColor, NSColor(red: 0.07, green: 0.06, blue: 0.06, alpha: 1).cgColor]
        root.layer?.addSublayer(wallpaper)
        let win = NSWindow(contentRect: root.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = root
        let card = LockCardView(media: m)
        card.frame.origin = NSPoint(x: list == nil ? (size.width - LockCardView.size.width) / 2 : LockBackdropView.listColumnX(size.width), y: size.height * 0.22 - LockCardView.size.height / 2)
        var backdropView: LockBackdropView?
        if fullscreen {
            let backdrop = LockBackdropView(media: m, frame: root.bounds)
            backdropView = backdrop
            root.addSubview(backdrop)
            if let motionStill { backdrop.previewMotionStill(motionStill) } else { backdrop.show() }
            if let list {
                // placeholder text, not real lyrics
                let sample = ["Every line arrives right on time", "The current one is big and bright", "The ones around it slip away", "Soft and blurred, out of the way", "Tap any line to jump right there", "And the list scrolls itself along"]
                let lyrics = sample.enumerated().map { LyricLine(time: Double($0.offset) * 4, text: $0.element) }
                let queue = (1...7).map { QueueItem(index: $0, number: $0, title: ["Golden Hour", "Midnight Drive", "Paper Planes", "Slow Motion", "Afterglow", "Northern Lights", "Hold On"][$0 - 1], artist: ["The Waves", "Night Signals", "Lowlight", "Paper Kites", "Harbour", "Aurora Sound", "Lake & Co"][$0 - 1], duration: 180 + Double($0 * 17)) }
                backdrop.previewList(list, lyrics: lyrics, queue: queue)
            }
        } else {
            // the system clock the real lock screen shows above the card
            let t = NSTextField(labelWithString: "9:41")
            t.font = NSFont.systemFont(ofSize: 150, weight: .thin); t.textColor = .white; t.alignment = .center
            t.frame = NSRect(x: 0, y: size.height * 0.62, width: size.width, height: 190)
            root.addSubview(t)
        }
        let scale: CGFloat = 2
        func bitmap() -> NSBitmapImageRep? {
            root.layoutSubtreeIfNeeded()
            win.displayIfNeeded()
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
            ctx.cgContext.scaleBy(x: scale, y: scale)
            root.layer?.render(in: ctx.cgContext)
            return rep
        }
        // The glass blur can't render offscreen, so it is made here: the picture BEHIND the card (rendered without it) is blurred and
        // brightened once, and that stands in for the blur layer, like real Liquid Glass bending what lies behind it.
        let behind = bitmap()?.cgImage
        root.addSubview(card)
        card.setActive(true)
        card.useFlatBackgroundForScreenshots(fullscreen: fullscreen, snapshot: behind)
        if let behind { backdropView?.applyScreenshotGlass(behind) }
        guard let rep = bitmap() else { return nil }
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
