import SwiftUI

/// Four thin bars that ease to a new random height (35–100 %) every 0.3 s while playing, like Boring Notch.
/// With `levels` (opt-in live audio bands) five bars follow the music instead. Static while paused.
struct WaveformView: View {
    var isAnimating: Bool
    var levels: [Float]? = nil
    var bpm: Double = 0      // unused by the random style, kept so call sites stay unchanged
    var seed: Int = 0
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2.5

    private let resting: [CGFloat] = [0.35, 0.6, 0.85, 0.5, 0.3]

    var body: some View {
        Group {
            if isAnimating, let levels {
                bars(5) { 0.14 + 0.86 * CGFloat(min(max(levels[$0], 0), 1)) }
                    .animation(.linear(duration: 0.05), value: levels)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isAnimating)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    bars(4) { randomHeight($0, t) }
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func bars(_ n: Int, _ h: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<n, id: \.self) { i in
                Capsule().frame(width: barWidth).scaleEffect(y: h(i), anchor: .center)
            }
        }
    }

    /// New target every 0.3 s per bar (hash-based, so no state), eased from the previous target.
    private func randomHeight(_ i: Int, _ t: Double) -> CGFloat {
        guard isAnimating else { return resting[i] }
        let x = t / 0.3
        let k = floor(x)
        let f = x - k
        let eased = f * f * (3 - 2 * f)
        let a = target(i, UInt64(bitPattern: Int64(k))), b = target(i, UInt64(bitPattern: Int64(k + 1)))
        return CGFloat(a + (b - a) * eased)
    }

    private func target(_ i: Int, _ k: UInt64) -> Double {
        var h = UInt64(i + 1) &* 0x9E3779B97F4A7C15 &+ k &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 30)) &* 0x94D049BB133111EB; h ^= h >> 31
        return 0.35 + 0.65 * Double(h % 1000) / 1000
    }
}

/// Minimal @State replacement (the SwiftUI @State macro plugin ships only with full Xcode).
final class Local<T>: ObservableObject {
    @Published var v: T
    init(_ v: T) { self.v = v }
}

extension Local where T == CGFloat {
    /// One-shot "tap" feedback: dip in fast, spring back out.
    func press() {
        withAnimation(.easeOut(duration: 0.08)) { v = 0.8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { self.v = 1 }
        }
    }
}
