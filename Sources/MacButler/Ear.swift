// Always-on microphone → live partial text (Apple on-device speech) + utterance audio (16 kHz) for Whisper.
import AVFoundation
import Speech

final class Ear {
    private var engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var lastText = ""
    private var lastChange = Date()
    private var taskStart = Date()
    private var gen = 0
    private var floor: Float = 0.01
    private var lastLoud = Date.distantPast
    private let hints: [String]
    var muted = false
    var silenceSec = 1.8
    var onPartial: (String) -> Void = { _ in }
    var onUtterance: (String, [Float]) -> Void = { _, _ in }
    var onLevel: (Float) -> Void = { _ in }

    // Last 40 s of 16 kHz mono audio; each utterance is cut from here and re-transcribed by Whisper.
    private var ring: [Float] = []
    private var ringBase = 0
    private var segStart = 0
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var ringEnd: Int { ringBase + ring.count }

    private let inputUID: String
    init(locale: String, hints: [String], inputUID: String = "") {
        self.inputUID = inputUID
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) ?? SFSpeechRecognizer()!
        self.hints = hints
    }

    private func segment() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let a = max(max(segStart, speechOnset) - ringBase, 0)
        return a < ring.count ? Array(ring[a...]) : []
    }

    private var lastBuffer = Date()
    private var speechOnset = 0                 // absolute sample where the current utterance began (VAD)
    private var engineObserver: NSObjectProtocol?

    func start() throws {
        try startEngine()
        restart()
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        // The mic stops when another app (e.g. a dictation app) or a device change reconfigures audio.
        // Restart on Apple's notification, and as a watchdog if no audio arrived for 3 s.
        observeEngine()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastRestart) > 3 else { return }
            self.lock.lock(); let last = self.lastBuffer; self.lock.unlock()
            if Date().timeIntervalSince(last) > 3 { log("ear: no audio for 3 s → restarting mic"); self.restartEngine() }
            // Voice is coming in but the recognizer has produced nothing for 10 s → it's stuck; start a fresh task.
            if !self.muted, !self.holding, Date().timeIntervalSince(self.lastLoud) < 2, Date().timeIntervalSince(self.lastChange) > 20,
               Date().timeIntervalSince(self.taskStart) > 20 { log("ear: speech but no text for 20 s → restarting recognizer"); self.restart() }
        }
        // Heartbeat for troubleshooting: loudest level heard in the last minute.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            log(String(format: "ear: alive · peak %.3f · floor %.4f", self.peak, self.floor)); self.peak = 0
        }
        log("ear on: on-device=\(recognizer.supportsOnDeviceRecognition)")
    }

    private var lastRestart = Date.distantPast
    private var peak: Float = 0
    private func observeEngine() {
        if let o = engineObserver { NotificationCenter.default.removeObserver(o) }
        engineObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Our own restart (or picking a device) also fires this — only react if the mic really stopped,
            // and never more than once every 3 s (this used to loop 70 times a minute).
            guard !self.engine.isRunning, Date().timeIntervalSince(self.lastRestart) > 3 else { return }
            log("ear: audio configuration changed → restarting mic"); self.restartEngine()
        }
    }
    private func restartEngine() {
        lastRestart = Date()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine = AVAudioEngine()          // a fresh engine so the chosen mic is applied cleanly
        observeEngine()
        lock.lock(); lastBuffer = Date(); lock.unlock()
        do { try startEngine(); restart() } catch { log("ear: mic restart failed: \(error)") }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        if !inputUID.isEmpty, !AudioDevices.use(inputUID, on: input.audioUnit) { log("ear: chosen mic not found → system default") }
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { throw NSError(domain: "Ear", code: 1, userInfo: [NSLocalizedDescriptionKey: "no input device"]) }
        converter = AVAudioConverter(from: fmt, to: target)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            guard let self else { return }
            self.lock.lock(); self.lastBuffer = Date(); self.lock.unlock()
            if let conv = self.converter {
                let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / fmt.sampleRate) + 32
                if let out = AVAudioPCMBuffer(pcmFormat: self.target, frameCapacity: cap) {
                    var fed = false
                    conv.convert(to: out, error: nil) { _, st in
                        if fed { st.pointee = .noDataNow; return nil }
                        fed = true; st.pointee = .haveData; return buf
                    }
                    if let d = out.floatChannelData?[0], out.frameLength > 0 {
                        self.lock.lock()
                        self.ring.append(contentsOf: UnsafeBufferPointer(start: d, count: Int(out.frameLength)))
                        let over = self.ring.count - 16000 * 40
                        if over > 0 { self.ring.removeFirst(over); self.ringBase += over }
                        self.lock.unlock()
                    }
                }
            }
            if let ch = buf.floatChannelData?[0] {
                var sum: Float = 0
                let n = Int(buf.frameLength)
                for i in 0..<n { sum += ch[i] * ch[i] }
                let rms = sqrt(sum / Float(max(n, 1)))
                DispatchQueue.main.async {
                    self.peak = max(self.peak, rms)
                    if !self.muted {
                        self.floor = rms < self.floor ? rms : self.floor * 0.998 + rms * 0.002
                        if rms > max(self.floor * 3.5, 0.003) {
                            // Voice after a real pause = a new utterance starts here (keep 0.4 s of lead-in).
                            if Date().timeIntervalSince(self.lastLoud) > self.silenceSec {
                                self.lock.lock(); self.speechOnset = max(self.ringEnd - 6400, self.ringBase); self.lock.unlock()
                            }
                            self.lastLoud = Date()
                        }
                    }
                    self.onLevel(self.muted ? 0 : rms)
                }
            }
            if self.muted { return }
            self.lock.lock(); let r = self.request; self.lock.unlock()
            r?.append(buf)
        }
        engine.prepare()
        try engine.start()
    }

    func restart() {
        gen += 1
        let myGen = gen
        task?.cancel()
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
        r.contextualStrings = hints
        lock.lock(); request = r; segStart = max(ringEnd - 4800, ringBase); lock.unlock()   // keep 0.3 s before
        lastText = ""; lastChange = Date(); taskStart = Date()
        task = recognizer.recognitionTask(with: r) { [weak self] res, err in
            DispatchQueue.main.async {
                guard let self, myGen == self.gen else { return }
                if let res {
                    let t = res.bestTranscription.formattedString
                    // The recognizer sometimes drops what it heard and starts over — hand the dropped text over first.
                    if !self.lastText.isEmpty, Ear.isReset(self.lastText, t) {
                        let prev = self.lastText
                        self.lastText = ""
                        let audio = self.segment()
                        self.lock.lock(); self.segStart = self.ringEnd; self.lock.unlock()
                        self.onUtterance(prev, audio)
                        if myGen != self.gen { return }
                    }
                    if t != self.lastText { self.lastText = t; self.lastChange = Date(); self.onPartial(t) }
                    if res.isFinal { self.flush() }
                } else if err != nil {
                    self.restart()
                }
            }
        }
    }

    static func isReset(_ a: String, _ b: String) -> Bool {
        let x = a.replacingOccurrences(of: " ", with: ""), y = b.replacingOccurrences(of: " ", with: "")
        if y.count >= x.count / 2 { return false }
        return !x.hasPrefix(String(y.prefix(2)))
    }

    func forceFlush() { if !lastText.isEmpty { flush() } }

    // Push-to-talk (hold the hotkey): exact start/stop like Handy — no guessing where speech begins or ends.
    private(set) var holding = false
    private var holdStart = 0
    func beginHold() { lock.lock(); holdStart = max(ringEnd - 3200, ringBase); lock.unlock(); holding = true; restart() }
    /// Returns what Apple heard live and the exact audio between press and release.
    func endHold() -> (String, [Float]) {
        holding = false
        lock.lock(); let a = max(holdStart - ringBase, 0); let audio = a < ring.count ? Array(ring[a...]) : []; lock.unlock()
        let t = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        restart()
        return (t, audio)
    }
    func cancelHold() { holding = false }
    /// Count only audio from ~0.4 s ago as the current utterance (used when the user interrupts).
    func markSegmentNow(back sec: Double = 0.4) { lock.lock(); segStart = max(ringEnd - Int(sec * 16000), ringBase); lock.unlock() }

    private func flush() {
        let t = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        let audio = segment()
        restart()
        if !t.isEmpty { onUtterance(t, audio) }
    }

    private func tick() {
        if muted || holding { return }
        let quiet = Date().timeIntervalSince(lastLoud) > 0.7
        if !lastText.isEmpty, quiet, Date().timeIntervalSince(lastChange) > silenceSec { flush() }
        else if lastText.isEmpty, Date().timeIntervalSince(taskStart) > 50 { restart() }
    }
}
