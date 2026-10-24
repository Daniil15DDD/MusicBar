import SwiftUI

/// What the ⓘ next to a setting shows: a short explanation and small pictures of each choice (drawn here, not screenshots,
/// so they never go out of date with the app's icons).
enum SettingInfo {
    case launchAtLogin, player, popoverClick, artwork, waveform, reactiveAudio, fallback
    case lockPlayer, glass, lyricsButton, queueButton, tintLyrics, contrast, clockStyle, clockWeight, clockSize, spotify

    var title: String {
        switch self {
        case .launchAtLogin: return "Launch at login"
        case .player: return "Player"
        case .popoverClick: return "Open the player on click"
        case .artwork: return "Album artwork"
        case .waveform: return "Animated waveform"
        case .reactiveAudio: return "Waveform follows the music"
        case .fallback: return "When nothing is playing"
        case .lockPlayer: return "Player on the lock screen"
        case .glass: return "Liquid Glass card"
        case .lyricsButton: return "Lyrics button"
        case .queueButton: return "Queue button"
        case .tintLyrics: return "Tint lyrics with the song's colour"
        case .contrast: return "Contrast"
        case .clockStyle: return "Clock style"
        case .clockWeight: return "Clock weight"
        case .clockSize: return "Clock size"
        case .spotify: return "Spotify (optional)"
        }
    }

    var detail: String {
        switch self {
        case .launchAtLogin: return "Opens ORBT when you sign in to your Mac, so the album cover is always in your menu bar."
        case .player: return "Automatic follows whichever app is playing. Pick Apple Music or Spotify to always show that one."
        case .popoverClick: return "On: clicking the menu bar item opens the mini player. Off: a click plays or pauses. Right-click always opens the menu."
        case .artwork: return "Shows the cover of the current song in the menu bar."
        case .waveform: return "Bars that move while music plays. When it's off you only see the cover."
        case .reactiveAudio: return "Off: the bars move on their own, in time with the song's tempo. On: they react to the real audio, which makes macOS ask for audio-capture permission. Nothing is recorded or stored."
        case .fallback: return "What the menu bar item shows while nothing is playing."
        case .lockPlayer: return "Shows a small player over the macOS lock screen. Click its cover for the full-screen view."
        case .glass: return "On: a clear glass card that shows your wallpaper through it. Off: a darker, frosted card."
        case .lyricsButton: return "A button in the corner of the full-screen view opens time-synced lyrics. They are looked up on lrclib.net, which receives the song title, artist and length."
        case .queueButton: return "A button in the corner of the full-screen view shows the next songs: the Apple Music playlist, or Spotify's real queue once Spotify is connected."
        case .tintLyrics: return "Mixes the cover's main colour into the lyrics' white. Off keeps them plain white."
        case .contrast: return "Keeps the clock readable on a bright cover, like a white album. Automatic: the clock and buttons take the cover's own colour, darkened (near-black if it has none). High: white text and the picture is always darkened. Off: nothing changes."
        case .clockStyle: return "The font of the clock on the full-screen lock screen."
        case .clockWeight: return "How thick the clock's strokes are, from ultra light to bold."
        case .clockSize: return "Drag to make the clock smaller or bigger."
        case .spotify: return "Adds Spotify's real queue and a save button. Spotify needs your own free developer app (its owner needs Premium): create one, add the redirect URI http://127.0.0.1/callback, and paste its Client ID. ORBT logs in once in your browser and keeps the token in the Keychain."
        }
    }

    var columns: Int { self == .clockStyle || self == .clockWeight ? 4 : self == .clockSize ? 3 : 2 }

    var tiles: [InfoTile] {
        switch self {
        case .launchAtLogin, .player, .spotify:
            return []
        case .popoverClick:
            return [InfoTile("On") { PopoverMock() },
                    InfoTile("Off: a click plays or pauses") { MiniMenuBar(item: barsItem(bars: nil, extra: "playpause.fill")).frame(height: 76, alignment: .top) }]
        case .artwork:
            return [InfoTile("On") { MiniMenuBar(item: barsItem()) }, InfoTile("Off") { MiniMenuBar(item: barsItem(cover: false)) }]
        case .waveform:
            return [InfoTile("On") { MiniMenuBar(item: barsItem()) }, InfoTile("Off") { MiniMenuBar(item: barsItem(bars: nil)) }]
        case .reactiveAudio:
            return [InfoTile("On: follows the audio") { MiniMenuBar(item: barsItem(bars: barsJagged, extra: "speaker.wave.2.fill")) },
                    InfoTile("Off: moves on its own") { MiniMenuBar(item: barsItem()) }]
        case .fallback:
            return [InfoTile("Music note") { MiniMenuBar(item: barsItem(cover: false, bars: nil, note: true)) },
                    InfoTile("Last album cover") { MiniMenuBar(item: barsItem(bars: nil, dim: true)) },
                    InfoTile("Hidden") { MiniMenuBar(item: AnyView(EmptyView())) }]
        case .lockPlayer:
            return [InfoTile("On") { MiniLock() }, InfoTile("Off") { MiniLock(card: false) }]
        case .glass:
            return [InfoTile("On: clear glass") { MiniLock(clear: true) }, InfoTile("Off: frosted") { MiniLock(clear: false) }]
        case .lyricsButton:
            return [InfoTile("On") { MiniLock(lyrics: true) }, InfoTile("Off") { MiniLock() }]
        case .queueButton:
            return [InfoTile("On") { MiniLock(queue: true) }, InfoTile("Off") { MiniLock() }]
        case .tintLyrics:
            return [InfoTile("On") { MiniLock(card: false, lyricColor: Color(red: 1, green: 0.88, blue: 0.74)) },
                    InfoTile("Off") { MiniLock(card: false, lyricColor: .white) }]
        case .contrast:
            return [InfoTile("Automatic") { MiniLock(card: false, bright: true, clockColor: Color(red: 0.36, green: 0.22, blue: 0.12)) },
                    InfoTile("High") { MiniLock(card: false, bright: true, darken: 0.5) },
                    InfoTile("Off") { MiniLock(card: false, bright: true) }]
        case .clockStyle:
            return [clockSample("Serif", .system(size: 20, weight: .light, design: .serif)),
                    clockSample("Sans", .system(size: 20, weight: .light)),
                    clockSample("Rounded", .system(size: 20, weight: .light, design: .rounded)),
                    clockSample("Mono", .system(size: 20, weight: .light, design: .monospaced)),
                    clockSample("Cooper", .custom("Cooper Black", size: 18)),
                    clockSample("Zapfino", .custom("Zapfino", size: 11)),
                    clockSample("Blackmoor", .custom("Blackmoor LET", size: 20))]
        case .clockWeight:
            return [clockSample("Ultra light", .system(size: 20, weight: .ultraLight, design: .serif)),
                    clockSample("Light", .system(size: 20, weight: .light, design: .serif)),
                    clockSample("Regular", .system(size: 20, weight: .regular, design: .serif)),
                    clockSample("Bold", .system(size: 20, weight: .bold, design: .serif))]
        case .clockSize:
            return [clockSample("Smaller", .system(size: 14, weight: .light, design: .serif)),
                    clockSample("Normal", .system(size: 20, weight: .light, design: .serif)),
                    clockSample("Bigger", .system(size: 28, weight: .light, design: .serif))]
        }
    }
}

struct InfoTile: Identifiable {
    let id = UUID()
    let caption: String
    let view: AnyView
    init<V: View>(_ caption: String, @ViewBuilder _ view: () -> V) { self.caption = caption; self.view = AnyView(view()) }
}

/// The ⓘ button: click it to read what the setting does and see each choice.
struct InfoButton: View {
    let info: SettingInfo
    // Local instead of @State: the app is built with swiftc alone, which has no SwiftUI macro plugin
    @StateObject private var shown = Local(false)
    @StateObject private var hover = Local(false)

    var body: some View {
        Button { shown.v.toggle() } label: {
            Image(systemName: "info.circle").foregroundStyle(hover.v || shown.v ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hover.v = $0 }
        .help("What does this do?")
        .accessibilityLabel("About \(info.title)")
        .popover(isPresented: $shown.v, arrowEdge: .trailing) { InfoCard(info: info) }
    }
}

/// A setting's name with its ⓘ right next to it.
struct InfoLabel: View {
    let title: String
    let info: SettingInfo
    init(_ title: String, _ info: SettingInfo) { self.title = title; self.info = info }
    var body: some View { HStack(spacing: 6) { Text(title); InfoButton(info: info) } }
}

struct InfoCard: View {
    let info: SettingInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(info.title).font(.headline)
            Text(info.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !info.tiles.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: info.columns), alignment: .leading, spacing: 12) {
                    ForEach(info.tiles) { t in
                        VStack(spacing: 5) {
                            t.view
                            Text(t.caption).font(.caption.weight(.medium)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 410)
    }
}

// MARK: - Little pictures

private let wallpaper = LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.42), Color(red: 0.55, green: 0.25, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
private let brightWallpaper = LinearGradient(colors: [Color(white: 0.98), Color(white: 0.86)], startPoint: .top, endPoint: .bottom)
private let barsLive: [CGFloat] = [8, 16, 11, 17, 9]
private let barsJagged: [CGFloat] = [5, 17, 7, 18, 6]

private struct Cover: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(LinearGradient(colors: [.orange, .brown], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }
}

private struct Bars: View {
    var heights: [CGFloat]
    var body: some View {
        HStack(spacing: 2) { ForEach(heights.indices, id: \.self) { Capsule().frame(width: 2.5, height: heights[$0]) } }.frame(height: 18)
    }
}

/// What ORBT draws in the menu bar: [note] [cover] [bars] [extra symbol].
private func barsItem(cover: Bool = true, bars: [CGFloat]? = barsLive, dim: Bool = false, note: Bool = false, extra: String? = nil) -> AnyView {
    AnyView(HStack(spacing: 4) {
        if note { Image(systemName: "music.note").font(.system(size: 10, weight: .medium)) }
        if cover { Cover(size: 14).opacity(dim ? 0.5 : 1) }
        if let bars { Bars(heights: bars) }
        if let extra { Image(systemName: extra).font(.system(size: 8)) }
    })
}

private struct MiniMenuBar: View {
    let item: AnyView
    var body: some View {
        HStack(spacing: 8) {
            Text("Music").font(.system(size: 9, weight: .bold)).lineLimit(1).fixedSize()
            Spacer(minLength: 4)
            item
            Image(systemName: "wifi").font(.system(size: 8))
            Text("9:41").font(.system(size: 9)).lineLimit(1).fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(width: 176, height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.85)))
    }
}

private struct PopoverMock: View {
    var body: some View {
        VStack(spacing: 4) {
            MiniMenuBar(item: barsItem())
            HStack(spacing: 8) {
                Cover(size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(.white.opacity(0.85)).frame(width: 52, height: 4)
                    Capsule().fill(.white.opacity(0.4)).frame(width: 38, height: 3)
                }
                Spacer()
            }
            .padding(8)
            .frame(width: 130, height: 46)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.2)))
        }
        .frame(width: 176, height: 76, alignment: .top)
    }
}

/// A miniature lock screen. `card`: the player card; `clear`: clear glass vs frosted; `lyrics`/`queue`: the corner buttons;
/// `lyricColor`: show lyric lines in this colour instead of the card; `bright`/`darken`/`clockColor`: a bright cover case.
private struct MiniLock: View {
    var card = true
    var clear = true
    var lyrics = false
    var queue = false
    var lyricColor: Color? = nil
    var bright = false
    var darken = 0.0
    var clockColor = Color.white

    var body: some View {
        ZStack {
            Rectangle().fill(bright ? AnyShapeStyle(brightWallpaper) : AnyShapeStyle(wallpaper))
            // soft colour blobs, so glass reads as glass
            Circle().fill(Color.pink.opacity(bright ? 0.15 : 0.5)).frame(width: 70).offset(x: -50, y: 30).blur(radius: 14)
            Circle().fill(Color.cyan.opacity(bright ? 0.12 : 0.4)).frame(width: 60).offset(x: 55, y: -5).blur(radius: 14)
            Color.black.opacity(darken)
            VStack(spacing: 0) {
                Text("Sat 24 Oct").font(.system(size: 7, weight: .semibold, design: .serif))
                Text("10:42").font(.system(size: 30, weight: .light, design: .serif))
            }
            .foregroundStyle(clockColor)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            if let c = lyricColor {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The current line").font(.system(size: 11, weight: .bold))
                    Text("Next line").font(.system(size: 8, weight: .bold)).opacity(0.5)
                    Text("Another line").font(.system(size: 8, weight: .bold)).opacity(0.35)
                }
                .foregroundStyle(c)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .offset(y: 32)
            }
            if card { playerCard.offset(y: 34) }
            if lyrics || queue {
                HStack(spacing: 6) {
                    if lyrics { Image(systemName: "quote.bubble") }
                    if queue { Image(systemName: "list.bullet") }
                }
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.25)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(7)
            }
        }
        .frame(width: 176, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var playerCard: some View {
        HStack(spacing: 6) {
            Cover(size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(.white.opacity(0.9)).frame(width: 40, height: 3.5)
                Capsule().fill(.white.opacity(0.5)).frame(width: 28, height: 3)
                HStack(spacing: 5) { ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.85)).frame(width: 4, height: 4) } }
            }
        }
        .padding(7)
        .frame(width: 96, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(clear ? Color.white.opacity(0.14) : Color(white: 0.2).opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(clear ? 0.55 : 0.12), lineWidth: 0.8))
        )
    }
}

private func clockSample(_ name: String, _ font: Font) -> InfoTile {
    InfoTile(name) {
        Text("10:42").font(font).foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            .frame(width: 84, height: 42)
            .background(wallpaper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
