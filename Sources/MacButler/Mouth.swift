// Speech output: ElevenLabs (if configured) or macOS `say`. stop() cuts it off instantly (barge-in).
import AppKit
import AVFoundation

final class Mouth: NSObject, AVAudioPlayerDelegate {
    private let cfg: Config
    private var proc: Process?
    private var player: AVAudioPlayer?
    private var task: URLSessionDataTask?
    private var finish: (() -> Void)?
    private var token = 0
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

    private func say(_ text: String, my: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args: [String] = []
        if !cfg.sayVoice.isEmpty { args += ["-v", cfg.sayVoice] }
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
                guard ok, let data else { log("elevenlabs failed → say"); self.say(text, my: my); return }
                if !self.cfg.outputDevice.isEmpty, self.playOnDevice(data, my: my) { return }
                guard let p = try? AVAudioPlayer(data: data) else { self.say(text, my: my); return }
                p.delegate = self
                self.player = p
                p.play()
            }
        }
        task?.resume()
    }

    /// Plays through the chosen speaker with a dedicated engine (AVAudioPlayer can't pick a device).
    private var outEngine: AVAudioEngine?
    private func playOnDevice(_ data: Data, my: Int) -> Bool {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mb-say-\(my).mp3")
        guard (try? data.write(to: tmp)) != nil, let file = try? AVAudioFile(forReading: tmp) else { return false }
        let e = AVAudioEngine(), node = AVAudioPlayerNode()
        AudioDevices.use(cfg.outputDevice, on: e.outputNode.audioUnit)
        e.attach(node); e.connect(node, to: e.mainMixerNode, format: file.processingFormat)
        do { try e.start() } catch { return false }
        outEngine = e
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { try? FileManager.default.removeItem(at: tmp); self?.outEngine?.stop(); self?.complete(my) }
        }
        node.play()
        return true
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { complete(token) }

    /// Stops immediately without calling the completion (the caller already moved on).
    func stop() {
        token += 1
        finish = nil
        task?.cancel(); task = nil
        player?.stop(); player = nil
        outEngine?.stop(); outEngine = nil
        if let p = proc, p.isRunning { p.terminate() }
        proc = nil
    }

    /// Plays a file (greeting / boot sound) without blocking.
    static func play(_ url: URL) { Sound.file(url) }
}
