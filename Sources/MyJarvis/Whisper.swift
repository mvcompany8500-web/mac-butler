// Local Whisper (whisper.cpp `whisper-server`) for accurate final text.
// Started on demand, stopped after 3 idle minutes (~1 GB of memory).
import Foundation

final class Whisper {
    let model: String
    let binary: String?
    let language: String
    let prompt: String
    let port = 8178
    private var proc: Process?
    private var lastUse = Date()
    private var queue: [([Float], String, (String) -> Void)] = []
    private var running = false

    init(model: String, binary: String?, language: String, prompt: String) {
        self.model = model; self.binary = binary; self.language = language; self.prompt = prompt
        // Clean up a server left behind by a previous run.
        let k = Process(); k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        k.arguments = ["-f", "whisper-server .*--port \(port)"]; try? k.run(); k.waitUntilExit()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, let p = self.proc, p.isRunning, Date().timeIntervalSince(self.lastUse) > 180 else { return }
            p.terminate(); self.proc = nil; log("whisper idle → stopped")
        }
    }
    var available: Bool { binary != nil && FileManager.default.fileExists(atPath: model) }

    func warm() {
        lastUse = Date()
        guard available, let binary, proc?.isRunning != true else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["-m", model, "--host", "127.0.0.1", "--port", String(port), "-l", language, "-t", "4"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); proc = p; log("whisper on") } catch { log("whisper failed: \(error)") }
    }
    func stop() { proc?.terminate(); proc = nil }

    /// One at a time so dictation stays in order. Falls back to Apple's text on any failure.
    func transcribe(_ audio: [Float], fallback: String, done: @escaping (String) -> Void) {
        guard available, audio.count > 8000 else { done(fallback); return }
        queue.append((audio, fallback, done)); next()
    }
    private func next() {
        guard !running, !queue.isEmpty else { return }
        running = true
        let (audio, fallback, done) = queue.removeFirst()
        warm()
        let wav = Whisper.wav(audio)
        attempt(wav, tries: 30) { [weak self] text in
            guard let self else { return }
            var t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if Whisper.isHallucination(t, apple: fallback) { t = "" }
            if self.language == "ko", !t.isEmpty, Whisper.hangulRatio(fallback) > 0.5, Whisper.hangulRatio(t) < 0.5 { t = "" }
            log("whisper: \(t.isEmpty ? "(using Apple text)" : t)")
            done(t.isEmpty ? fallback : t)
            self.running = false; self.next()
        }
    }
    private func attempt(_ wav: Data, tries: Int, done: @escaping (String?) -> Void) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        req.httpMethod = "POST"; req.timeoutInterval = 15
        let b = "mj\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(b)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ n: String, _ v: String) { body.append("--\(b)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!) }
        field("response_format", "json"); field("language", language); field("temperature", "0")
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append("--\(b)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav); body.append("\r\n--\(b)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                if err != nil, tries > 0 {   // model still loading
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.attempt(wav, tries: tries - 1, done: done) }
                    return
                }
                let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                done(obj?["text"] as? String)
            }
        }.resume()
    }

    static func hangulRatio(_ x: String) -> Double {
        Double(x.unicodeScalars.filter { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }.count) / Double(max(x.filter { $0.isLetter }.count, 1))
    }
    /// Classic Whisper hallucinations on silence/noise.
    static func isHallucination(_ t: String, apple: String) -> Bool {
        if t.isEmpty { return true }
        let bad = ["시청해 주셔서", "구독과 좋아요", "구독 좋아요", "MBC 뉴스", "자막 제공", "감사합니다.", "Thanks for watching", "Thank you for watching", "Subtitles by"]
        return bad.contains { t.contains($0) && !apple.contains($0.replacingOccurrences(of: ".", with: "")) }
    }
    static func wav(_ f: [Float], rate: Int = 16000) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + f.count * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(f.count * 2))
        var pcm = [Int16](repeating: 0, count: f.count)
        for i in 0..<f.count { pcm[i] = Int16(max(-1, min(1, f[i])) * 32767) }
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
