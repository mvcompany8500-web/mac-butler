// `MacButler --echotest <audio file> <report file>` — plays the file through the speaker the way Mouth does,
// listens on the mic the way Ear does, and reports whether its own voice would have been taken for yours.
import AVFoundation
import Speech

enum EchoTest {
    static func run(_ path: String) -> String {
        let cfg = Config.load()
        let dt = DoubleTalk()
        let e = AVAudioEngine(), pe = AVAudioEngine(), node = AVAudioPlayerNode()
        if !cfg.inputDevice.isEmpty { AudioDevices.use(cfg.inputDevice, on: e.inputNode.audioUnit) }
        if !cfg.outputDevice.isEmpty { AudioDevices.use(cfg.outputDevice, on: pe.outputNode.audioUnit) }
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return "no file" }
        pe.attach(node); pe.connect(node, to: pe.mainMixerNode, format: file.processingFormat)
        pe.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buf, _ in dt.played(Mouth.rms(buf)) }
        let rec = SFSpeechRecognizer(locale: Locale(identifier: cfg.locale))!
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        var text = "", levels: [Float] = [], falseStops = 0
        let input = e.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
            let v = Mouth.rms(buf)
            DispatchQueue.main.async { levels.append(v); if dt.isUser(v) { falseStops += 1 } }
        }
        let task = rec.recognitionTask(with: req) { r, _ in if let r { DispatchQueue.main.async { text = r.bestTranscription.formattedString } } }
        do { try e.start(); try pe.start() } catch { return "engine failed: \(error)" }
        var finished = false
        dt.begin()
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in finished = true }
        node.play()
        let deadline = Date().addingTimeInterval(60)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        dt.end(interrupted: falseStops > 0)
        req.endAudio(); RunLoop.main.run(until: Date().addingTimeInterval(0.8)); task.cancel()
        input.removeTap(onBus: 0); pe.mainMixerNode.removeTap(onBus: 0); e.stop(); pe.stop()
        let s = levels.sorted()
        return String(format: "false stops: %d · echo level p50 %.3f p99 %.3f · coupling %.3f\nmic heard: %@",
                      falseStops, s.isEmpty ? 0 : s[s.count / 2], s.isEmpty ? 0 : s[min(s.count - 1, s.count * 99 / 100)], dt.coupling, text.isEmpty ? "(nothing)" : text)
    }
}
