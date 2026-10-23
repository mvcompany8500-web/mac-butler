// Cut in while it talks — through speakers, no headphones needed.
// We know how loud we are playing at every moment; the mic hears that times a room factor ("coupling").
// You, close to the mic, push the level well above it. Apple's voice-processing echo canceller didn't help
// with a USB mic + separate speakers, so this compares levels instead.
// Tuned on real recordings (`MacButler --echotest`): no false stops on its own voice, ~9 in 10 cut-ins caught in ~0.6 s.
import Foundation

final class DoubleTalk {
    static let k: Float = 3            // your voice must be this many times louder than the expected echo
    static let minLevel: Float = 0.03  // …and loud in absolute terms
    static let need = 2                // …for this many 0.1 s chunks in a row
    private let lock = NSLock()
    private var plays: [(t: TimeInterval, v: Float)] = []
    private var ratios: [Float] = []
    private var streak = 0
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
        lock.lock(); plays = []; lock.unlock(); ratios = []; streak = 0; active = true
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

    /// One ~0.1 s mic level from the ear. True once it's clearly you talking over it.
    func isUser(_ mic: Float) -> Bool {
        guard active else { return false }
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock(); let p = plays.filter { now - $0.t < 0.3 }.map(\.v).max() ?? 0; lock.unlock()
        if p > 0.03 { ratios.append(mic / p) }
        // A video playing in the room is loud too — you have to be clearly above that as well.
        let loud = mic > max(Self.minLevel, ambient * 2.5) && (p <= 0.01 || mic > p * coupling * Self.k)
        streak = loud ? streak + 1 : 0
        return streak >= Self.need
    }
}
