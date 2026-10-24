import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class PassthroughHostingView<C: View>: NSHostingView<C> {
    // Let clicks fall through to the status item button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Content drawn inside the real NSStatusItem button: [artwork][waveform].
struct MenuBarContent: View {
    @ObservedObject var media: MediaController
    @ObservedObject var audio: AudioLevels
    @AppStorage("showWaveform") var showWaveform = true
    @AppStorage("showArtwork") var showArtwork = true
    @AppStorage("fallback") var fallback = "icon"
    @StateObject private var pulse = Local<CGFloat>(1)

    var body: some View {
        HStack(spacing: 5) {
            if let info = media.info {
                if showArtwork {
                    // Fades darker when paused; pulses on every play/pause change.
                    artwork(media.thumbnail ?? media.artwork, dim: false)
                        .brightness(info.isPlaying ? 0 : -0.25)
                        .scaleEffect(pulse.v)
                }
                if !info.isPlaying {
                    Image(systemName: "pause.fill").font(.system(size: 10, weight: .semibold)).frame(width: 16, height: 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else if showWaveform {
                    WaveformView(isAnimating: info.isPlaying, levels: audio.running && audio.live ? audio.levels : nil, bpm: info.bpm, seed: info.seed, barWidth: 2, spacing: 2)
                        .frame(width: 16, height: 12)
                }
            } else if fallback == "lastArtwork", showArtwork, let img = media.lastArtwork {
                artwork(media.thumbnail ?? img, dim: true)
            } else {
                Image(systemName: "music.note").font(.system(size: 14, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.35), value: media.info?.isPlaying)
        .onChange(of: media.info?.isPlaying) { _, _ in pulse.press() }
    }

    private func artwork(_ img: NSImage?, dim: Bool) -> some View {
        Group {
            if let img {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack { Color.gray.opacity(0.35); Image(systemName: "music.note").font(.system(size: 11)) }
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .opacity(dim ? 0.5 : 1)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let media = MediaController()
    let audio = AudioLevels()
    var lockScreen: LockScreenController?
    var item: NSStatusItem!
    let popover = NSPopover()
    var settingsWindow: NSWindow?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ n: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
            func arg(_ name: String) -> String? { CommandLine.arguments.firstIndex(of: name).flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil } }
            // --lock-info "title|artist|album|duration|position" with --lock-art <image>: the song for the lock screen images
            var lock: NowPlaying?
            if let f = arg("--lock-info")?.components(separatedBy: "|"), f.count == 5 {
                lock = NowPlaying(player: .music, title: f[0], artist: f[1], album: f[2], duration: Double(f[3]) ?? 0, position: Double(f[4]) ?? 0,
                                  isPlaying: true, shuffle: true, repeatMode: "all", favorited: true)
            }
            MainActor.assumeIsolated { Demo.run(dir: URL(fileURLWithPath: CommandLine.arguments[i + 1]), artPath: arg("--art"), lock: lock, lockArtPath: arg("--lock-art"), lockMotionPath: arg("--lock-motion")) }
            exit(0)
        }
        item = NSStatusBar.system.statusItem(withLength: 46)
        if let button = item.button {
            let host = PassthroughHostingView(rootView: MenuBarContent(media: media, audio: audio))
            host.frame = button.bounds
            host.autoresizingMask = [.width, .height]
            button.addSubview(host)
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        lockScreen = LockScreenController(media: media)
        popover.behavior = .transient
        // Hide the pointer arrow (undocumented NSPopover switch; guarded so a future macOS just keeps the arrow).
        if popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) { popover.setValue(true, forKey: "shouldHideAnchor") }
        popover.delegate = self

        media.$info.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.applyVisibility() }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyVisibility(); self?.media.refresh()
        }
        applyVisibility()
    }

    func applicationWillTerminate(_ n: Notification) { audio.stop() }

    func applyVisibility() {
        let d = UserDefaults.standard
        let hideWhenStopped = (d.string(forKey: "fallback") ?? "icon") == "hidden" && media.info == nil
        item.isVisible = !hideWhenStopped
        // Audio capture is opt-in: only while playing AND enabled in settings.
        if d.bool(forKey: "reactiveAudio"), media.info?.isPlaying == true { audio.start() } else { audio.stop() }
    }

    @objc func clicked() {
        guard let button = item.button, let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit ORBT", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            button.performClick(nil)
            item.menu = nil
            return
        }
        if UserDefaults.standard.object(forKey: "openPopoverOnClick") as? Bool ?? true {
            if popover.isShown { popover.performClose(nil) } else { showPopover(button) }
        } else {
            media.togglePlayPause()
        }
    }

    func showPopover(_ button: NSStatusBarButton) {
        media.refresh()
        popover.contentViewController = NSHostingController(rootView: PopoverView(media: media, audio: audio, openSettings: { [weak self] in self?.openSettings() }))
        // Anchor to a thin strip at the item's bottom edge so the popover hugs the menu bar.
        let b = button.bounds
        let edge = NSRect(x: b.minX, y: button.isFlipped ? b.maxY - 1 : b.minY, width: b.width, height: 1)
        popover.show(relativeTo: edge, of: button, preferredEdge: .minY)
        // macOS can leave a large gap under the menu bar; close it by measuring against the item's window.
        if let pw = popover.contentViewController?.view.window, let bw = button.window {
            let gap = bw.frame.minY - pw.frame.maxY
            if gap > 2 { pw.setFrameOrigin(NSPoint(x: pw.frame.minX, y: pw.frame.minY + gap - 2)) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // Release the SwiftUI tree (and its animation timeline) when the popover closes.
    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }

    @objc func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "ORBT Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            // Clicking anywhere else closes it, so it can't come back to the front by itself when the menu bar item activates the app again.
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { [weak w] _ in w?.close() }
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
