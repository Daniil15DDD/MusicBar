import SwiftUI

struct HoverButtonStyle: ButtonStyle {
    var size: CGFloat = 40
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, size: size)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let size: CGFloat
        @StateObject private var hover = Local(false)
        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.18 : hover.v ? 0.1 : 0)))
                .contentShape(Circle())
                .onHover { hover.v = $0 }
                .animation(.easeOut(duration: 0.12), value: hover.v)
        }
    }
}

struct PopoverView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var audio: AudioLevels
    var openSettings: () -> Void
    @AppStorage("showWaveform") private var showWaveform = true
    @StateObject private var scrubBox = Local<Double?>(nil)
    @StateObject private var eqBox = Local(false)
    @StateObject private var bigBox = Local(false)
    @StateObject private var pulse = Local<CGFloat>(1)
    private var scrub: Double? { get { scrubBox.v } nonmutating set { scrubBox.v = newValue } }

    var body: some View {
        VStack(spacing: 8) {
            header
            if eqBox.v {
                EqualizerPanel(media: media)
            } else if bigBox.v {
                bigArtwork
                VStack(spacing: 2) {
                    Text(media.info?.title ?? "Not Playing").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                progress
            } else {
                HStack(spacing: 12) {
                    artwork.onTapGesture { bigBox.v = true }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.info?.title ?? "Not Playing").font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        Text(media.info?.artist ?? subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        if let album = media.info?.album, !album.isEmpty {
                            Text(album).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                progress
            }
            controls
        }
        .padding(12)
        .frame(width: 272)
        .animation(.easeInOut(duration: 0.25), value: media.info?.key)
    }

    private var subtitle: String {
        guard let i = media.info else {
            return media.permissionDenied ? "Allow MusicBar in Privacy → Automation" : "Open Music or Spotify"
        }
        return [i.artist, i.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private var header: some View {
        HStack {
            if showWaveform {
                WaveformView(isAnimating: media.info?.isPlaying ?? false, levels: audio.running && audio.live ? audio.levels : nil, bpm: media.info?.bpm ?? 0, seed: media.info?.seed ?? 0, barWidth: 2, spacing: 2)
                    .frame(width: 14, height: 11)
            }
            Text(media.info?.player.displayName ?? "MusicBar").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            headerButtons
            Button(action: openSettings) { Image(systemName: "gearshape").foregroundStyle(.secondary) }
                .buttonStyle(HoverButtonStyle(size: 24))
        }
    }

    private var artwork: some View {
        Group {
            if let img = media.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack { Color.gray.opacity(0.25); Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(.secondary) }
            }
        }
        .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .scaleEffect(pulse.v)
        .onChange(of: media.info?.isPlaying) { _, _ in pulse.press() }
        .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            }

    /// Apple Music-style big artwork: moving artwork when the album has it, otherwise the plain cover. Tap to go back.
    private var bigArtwork: some View {
        ZStack {
            Group {
                if let img = media.artwork {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack { Color.gray.opacity(0.25); Image(systemName: "music.note").font(.system(size: 60)).foregroundStyle(.secondary) }
                }
            }
            if let url = media.motionURL { LoopingVideo(url: url).transition(.opacity) }
        }
        .frame(width: 248, height: 248)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .scaleEffect(pulse.v)
        .onTapGesture { bigBox.v = false }
        .onAppear { media.loadMotionIfNeeded() }
        .onChange(of: media.info?.album) { _, _ in media.loadMotionIfNeeded() }
        .animation(.easeInOut(duration: 0.3), value: media.motionURL)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let dur = max(media.info?.duration ?? 0, 0.001)
            let live = (media.info?.position ?? 0) + ((media.info?.isPlaying ?? false) ? ctx.date.timeIntervalSince(media.sampleDate) : 0)
            let pos = min(scrub ?? live, dur)
            VStack(spacing: 0) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.15))
                        Capsule().fill(Color.primary.opacity(0.7)).frame(width: g.size.width * pos / dur)
                    }
                    .frame(height: scrub == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { scrub = min(max(0, $0.location.x / g.size.width), 1) * dur }
                        .onEnded { v in
                            let t = min(max(0, v.location.x / g.size.width), 1) * dur
                            media.seek(to: t); scrub = nil
                        })
                }
                .frame(height: 12)
                HStack {
                    Text(fmt(pos)); Spacer(); Text("-" + fmt(max(dur - pos, 0)))
                }
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            .opacity(media.info == nil ? 0.4 : 1)
        }
    }

    private var controls: some View {
        let i = media.info
        return HStack(spacing: 6) {
            Button { media.toggleShuffle() } label: { Image(systemName: "shuffle").font(.system(size: 13)) }
                .foregroundStyle(i?.shuffle == true ? Color.accentColor : .secondary)
                .buttonStyle(HoverButtonStyle(size: 30))
            Button { media.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 17)) }
                .buttonStyle(HoverButtonStyle(size: 36))
            Button { media.togglePlayPause() } label: {
                Image(systemName: i?.isPlaying ?? false ? "pause.fill" : "play.fill").font(.system(size: 24))
            }.buttonStyle(HoverButtonStyle(size: 44))
            Button { media.next() } label: { Image(systemName: "forward.fill").font(.system(size: 17)) }
                .buttonStyle(HoverButtonStyle(size: 36))
            Button { media.cycleRepeat() } label: { Image(systemName: i?.repeatMode == "one" ? "repeat.1" : "repeat").font(.system(size: 13)) }
                .foregroundStyle(i?.repeatMode ?? "off" != "off" ? Color.accentColor : .secondary)
                .buttonStyle(HoverButtonStyle(size: 30))
        }
        .disabled(media.info == nil)
    }

    /// Favourite and equalizer (Apple Music only).
    private var headerButtons: some View {
        let i = media.info
        let isMusic = i?.player == .music
        return HStack(spacing: 2) {
            Button { media.toggleFavorite() } label: { Image(systemName: i?.favorited == true ? "heart.fill" : "heart") }
                .foregroundStyle(i?.favorited == true ? Color.pink : .secondary)
            Button { eqBox.v.toggle() } label: { Image(systemName: "slider.vertical.3") }
                .foregroundStyle(eqBox.v ? Color.accentColor : .secondary)
                .help("Equalizer (Apple Music)")
        }
        .font(.system(size: 13))
        .buttonStyle(HoverButtonStyle(size: 26))
        .disabled(i == nil || !isMusic)
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// Apple Music equalizer: on/off switch and preset list.
struct EqualizerPanel: View {
    @ObservedObject var media: MediaController
    @StateObject private var enabled = Local(false)
    @StateObject private var current = Local("")
    @StateObject private var presets = Local<[String]>([])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Equalizer", isOn: Binding(get: { enabled.v }, set: { enabled.v = $0; media.setEQ(enabled: $0) }))
                .toggleStyle(.switch).font(.system(size: 13, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(presets.v, id: \.self) { name in
                        Button {
                            current.v = name; enabled.v = true; media.setEQPreset(name)
                        } label: {
                            HStack {
                                Text(name).font(.system(size: 13))
                                Spacer()
                                if enabled.v && current.v == name { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                            }
                            .padding(.horizontal, 8).frame(height: 26)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 150)
        }
        .frame(width: 244, height: 190, alignment: .top)
        .onAppear { media.loadEQ { e, c, p in enabled.v = e; current.v = c; presets.v = p } }
    }
}
