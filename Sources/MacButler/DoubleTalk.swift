// Cut in while it talks — through speakers, no headphones needed.
// We know how loud we are playing at every moment; the mic hears that times a room factor ("coupling").
// You, close to the mic, push the level well above it. Apple's voice-processing echo canceller didn't help
// with a USB mic + separate speakers, so this compares levels instead.
// Tuned on real recordings (`MacButler --echotest`): no false stops on its own voice. Strict on purpose — a family member
// talking or a video must not cut it off; if a cut-in is missed, the wake word or the hotkey always works.
import Foundation

final class DoubleTalk {
    static let k: Float = 3            // your voice must be this many times louder than the expected echo
    static let minLevel: Float = 0.045 // …and loud in absolute terms (close to the mic, not someone across the room)
    static let need = 3                // …in 3 of the last 4 chunks (0.1 s each)
    static let voiced: Float = 0.42    // …and it must sound like a voice (pitch), not breath or a bump on the mic
    private let lock = NSLock()
    private var plays: [(t: TimeInterval, v: Float)] = []
    private var ratios: [Float] = []
    private var recent: [Bool] = []
    private var quiet: [Float] = []    // mic levels in the second before it started talking (a video, music, a fan…)
    private var ambient: Float = 0
    private(set) var active = false
    private(set) var coupling: Float = {
        let v = UserDefaults.standard.float(forKey: "echoCoupling")
        return v > 0 ? v : 0.12
    }()

    /// Every mic level while it isn't talking — the room's background sound right before it speaks.
    func listen(_ mic: Float) {
        guard !active else { return }
        quiet.append(mic); if quiet.count > 10 { quiet.removeFirst() }
    }
    /// Our voice started playing through an engine we can measure.
    func begin() {
        lock.lock(); plays = []; lock.unlock(); ratios = []; recent = []; active = true
        ambient = quiet.isEmpty ? 0 : quiet.sorted()[quiet.count / 2]
    }

    /// Done speaking. A full sentence nobody interrupted teaches us how loud our echo is in this room.
    func end(interrupted: Bool) {
        guard active else { return }
        active = false
        guard !interrupted, ratios.count >= 20, ambient < 0.01 else { return }   // learn only in a quiet room
        let median = ratios.sorted()[ratios.count / 2]
        coupling = min(max(coupling * 0.7 + median * 0.3, 0.03), 0.6)
        UserDefaults.standard.set(coupling, forKey: "echoCoupling")
    }

    /// Playback level (audio thread).
    func played(_ rms: Float) {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock(); plays.append((now, rms)); plays.removeAll { now - $0.t > 0.5 }; lock.unlock()
    }

    /// One ~0.1 s mic level (and how voice-like it was) from the ear. True once it's clearly you talking over it.
    func isUser(_ mic: Float, voicing: Float) -> Bool {
        guard active else { return false }
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock(); let p = plays.filter { now - $0.t < 0.3 }.map(\.v).max() ?? 0; lock.unlock()
        if p > 0.03 { ratios.append(mic / p) }
        // A video playing in the room is loud too — you have to be clearly above that as well.
        let loud = mic > max(Self.minLevel, ambient * 3) && voicing > Self.voiced && (p <= 0.01 || mic > p * coupling * Self.k)
        recent.append(loud); if recent.count > 4 { recent.removeFirst() }
        return recent.filter { $0 }.count >= Self.need
    }

    /// How much a 16 kHz chunk repeats at a human pitch (70–400 Hz), best 40 ms window. Your voice ≈ 0.5–0.9;
    /// breath, a bump or a puff on the mic ≈ 0.1–0.35. Pre-emphasis first, so low rumble can't look like pitch.
    /// (Checked on 1,391 chunks of the owner's recordings vs. coloured noise: threshold 0.42 keeps 88 %, passes 0 %.)
    static func periodicity(_ raw: UnsafePointer<Float>, _ n: Int) -> Float {
        guard n >= 640 else { return 0 }
        var x = [Float](repeating: 0, count: n)
        x[0] = raw[0]
        for i in 1..<n { x[i] = raw[i] - 0.95 * raw[i - 1] }
        var best: Float = 0
        var s = 0
        while s + 640 <= n {
            var e: Float = 0
            for i in s..<(s + 640) { e += x[i] * x[i] }
            if e > 1e-7 {
                for lag in 40...228 {
                    var c: Float = 0
                    for i in s..<(s + 640 - lag) { c += x[i] * x[i + lag] }
                    if c / e > best { best = c / e }
                }
            }
            s += 320
        }
        return best
    }
}
