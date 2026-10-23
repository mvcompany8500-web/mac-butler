// Speech output. Out of the box: the best macOS voice installed for your language (free, offline) — a Premium /
// Enhanced voice if you've downloaded one in System Settings. Optional: ElevenLabs (your own API key).
// Both play through one measured engine so you can cut in over the speakers. stop() cuts it off instantly.
import AppKit
import AVFoundation

final class Mouth: NSObject, AVAudioPlayerDelegate {
    private let cfg: Config
    private var proc: Process?
    private var player: AVAudioPlayer?
    private var task: URLSessionDataTask?
    private var finish: (() -> Void)?
    private var token = 0
    let echo = DoubleTalk()             // knows how loud we're playing → tells your voice from ours
    private lazy var elevenKey: String? = {
        let e = cfg.elevenLabs
        if !e.apiKey.isEmpty { return e.apiKey }
        if !e.apiKeyFile.isEmpty, let k = dotenv(e.apiKeyFile, "ELEVENLABS_API_KEY") { return k }
        return ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
    }()

    init(cfg: Config) { self.cfg = cfg }

    func speak(_ raw: String, done: @escaping () -> Void) {
        stop()
        let text = cfg.ko ? KoreanReader.read(raw) : raw      // numbers & model names the way a Korean reads them
        token += 1
        let my = token
        finish = done
        if cfg.tts == "elevenlabs", let key = elevenKey, !cfg.elevenLabs.voiceId.isEmpty {
            eleven(text, key: key, my: my)
        } else {
            say(text, my: my)
        }
    }

    private func complete(_ my: Int) {
        guard my == token, let f = finish else { return }
        finish = nil
        f()
    }

    /// The best macOS voice for the language: Premium > Enhanced > the standard one ("Yuna", "Samantha").
    /// Novelty and "Eloquence" voices are skipped. `chosen` = a voice picked in Settings (identifier or name).
    static func bestVoice(locale: String, chosen: String = "") -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        if !chosen.isEmpty, let v = all.first(where: { $0.identifier == chosen || $0.name == chosen }) { return v }
        let lang = locale.replacingOccurrences(of: "_", with: "-")
        var mine = all.filter { $0.language == lang }
        if mine.isEmpty { mine = all.filter { $0.language.hasPrefix(String(lang.prefix(2))) } }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int { v.quality.rawValue * 10 + (v.identifier.hasPrefix("com.apple.voice.") ? 1 : 0) }
        let natural = mine.filter { $0.identifier.hasPrefix("com.apple.voice.") || $0.quality != .default }
        return natural.max { rank($0) < rank($1) } ?? mine.first
    }

    private let synth = AVSpeechSynthesizer()
    /// macOS voice → rendered to a file (≈0.5 s) → played like any other voice, so barge-in works the same.
    private func say(_ text: String, my: Int) {
        guard let voice = Mouth.bestVoice(locale: cfg.locale, chosen: cfg.sayVoice) else { sayCommand(text, my: my); return }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = min(max(Float(cfg.sayRate) / 190 * 0.52, 0.3), 0.7)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mb-say-\(my).caf")
        var file: AVAudioFile?, wrote = false, ended = false
        synth.write(u) { [weak self] buf in
            guard let pcm = buf as? AVAudioPCMBuffer, !ended else { return }
            if pcm.frameLength == 0 {
                ended = true; file = nil         // closes the file
                DispatchQueue.main.async {
                    guard let self, my == self.token else { return }
                    if !(wrote && self.playFile(tmp, my: my)) { self.sayCommand(text, my: my) }
                }
                return
            }
            if file == nil { file = try? AVAudioFile(forWriting: tmp, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved) }
            if (try? file?.write(from: pcm)) != nil { wrote = true }
        }
    }

    /// Last resort: the `say` command (no barge-in level tracking).
    private func sayCommand(_ text: String, my: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args: [String] = []
        if !cfg.sayVoice.isEmpty { args += ["-v", AVSpeechSynthesisVoice(identifier: cfg.sayVoice)?.name ?? cfg.sayVoice] }
        if let d = AudioDevices.device(uid: cfg.outputDevice) { args += ["-a", String(d.id)] }
        args += ["-r", String(cfg.sayRate), text]
        p.arguments = args
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.complete(my) } }
        proc = p
        do { try p.run() } catch { complete(my) }
    }

    private func eleven(_ text: String, key: String, my: Int) {
        let e = cfg.elevenLabs
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(e.voiceId)?output_format=mp3_44100_128")!)
        req.httpMethod = "POST"; req.timeoutInterval = 12
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": text, "model_id": e.model,
                                   "voice_settings": ["stability": 0.45, "similarity_boost": 0.8, "style": 0.3, "speed": e.speed]]
        if cfg.ko, e.model.contains("v2_5") { body["language_code"] = "ko" }   // only Flash/Turbo v2.5 accept it
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        task = URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            DispatchQueue.main.async {
                guard let self, my == self.token else { return }
                let ok = (resp as? HTTPURLResponse)?.statusCode == 200
                guard ok, let data else { log("elevenlabs failed → macOS voice"); self.say(text, my: my); return }
                if self.playOnDevice(data, my: my) { return }
                guard let p = try? AVAudioPlayer(data: data) else { self.say(text, my: my); return }
                p.delegate = self
                self.player = p
                p.play()
            }
        }
        task?.resume()
    }

    /// Plays through the chosen speaker with a dedicated engine (AVAudioPlayer can't pick a device),
    /// measuring the level as it goes so a voice over the top of it can be told apart from our echo.
    private var outEngine: AVAudioEngine?
    private func playOnDevice(_ data: Data, my: Int) -> Bool {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mb-say-\(my).mp3")
        guard (try? data.write(to: tmp)) != nil else { return false }
        return playFile(tmp, my: my)
    }
    private func playFile(_ tmp: URL, my: Int) -> Bool {
        guard let file = try? AVAudioFile(forReading: tmp) else { return false }
        let e = AVAudioEngine(), node = AVAudioPlayerNode()
        if !cfg.outputDevice.isEmpty { AudioDevices.use(cfg.outputDevice, on: e.outputNode.audioUnit) }
        e.attach(node); e.connect(node, to: e.mainMixerNode, format: file.processingFormat)
        let echo = self.echo
        e.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buf, _ in echo.played(Mouth.rms(buf)) }
        do { try e.start() } catch { return false }
        outEngine = e
        echo.begin()
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: tmp)
                guard let self, my == self.token else { return }
                self.echo.end(interrupted: false); self.outEngine?.stop(); self.complete(my)
            }
        }
        node.play()
        return true
    }
    static func rms(_ buf: AVAudioPCMBuffer) -> Float {
        guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return 0 }
        var s: Float = 0
        for i in 0..<Int(buf.frameLength) { s += ch[i] * ch[i] }
        return sqrt(s / Float(buf.frameLength))
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { complete(token) }

    /// Stops immediately without calling the completion (the caller already moved on).
    func stop() {
        token += 1
        finish = nil
        task?.cancel(); task = nil
        player?.stop(); player = nil
        echo.end(interrupted: true)
        outEngine?.mainMixerNode.removeTap(onBus: 0); outEngine?.stop(); outEngine = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        if let p = proc, p.isRunning { p.terminate() }
        proc = nil
    }

    /// Plays a file (greeting / boot sound) without blocking.
    static func play(_ url: URL) { Sound.file(url) }
}
