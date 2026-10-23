// The brain: one long-lived Claude Code process (`claude -p` with stream-json in/out).
// Keeping it warm removes the 2–4 s start-up on every command.
import AppKit

final class Brain {
    private let cfg: Config
    private let strings: Strings
    private var proc: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var step: ((String) -> Void)?
    private var done: ((String) -> Void)?
    private var finalTimer: DispatchWorkItem?
    private var pendingText: String?
    private var sent = 0, received = 0
    private var lastUse = Date()
    init(cfg: Config) { self.cfg = cfg; self.strings = Strings(ko: cfg.ko) }
    var busy: Bool { done != nil }
    var installed: Bool { cfg.claudeBinary != nil }

    /// System prompt: ~/.myjarvis/prompt.md if present, otherwise the bundled template for the language.
    func systemPrompt() -> String {
        let user = Paths.home.appendingPathComponent("prompt.md")
        let bundled = Paths.resources.appendingPathComponent("prompts/prompt.\(cfg.ko ? "ko" : "en").md")
        var s = (try? String(contentsOf: user, encoding: .utf8)) ?? (try? String(contentsOf: bundled, encoding: .utf8)) ?? "You are {assistant}, a voice assistant for {user}."
        let scr = NSScreen.main?.frame.size ?? .zero
        s = s.replacingOccurrences(of: "{screen}", with: "\(Int(scr.width))×\(Int(scr.height))")
        return cfg.fill(s)
    }

    func warm() { ensure() }
    private func ensure() {
        if let p = proc, p.isRunning, sent < 25, Date().timeIntervalSince(lastUse) < 1800 { return }
        if let p = proc, p.isRunning, done != nil { return }   // never swap while working
        proc?.terminate()
        guard let bin = cfg.claudeBinary else { log("claude not found"); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--model", cfg.claudeModel, "--append-system-prompt", systemPrompt(),
                       "--allowedTools", "Bash,Read,Glob,Grep,WebSearch,WebFetch",
                       "--disallowedTools", "SendMessage,ToolSearch,Task,Agent"]
        p.currentDirectoryURL = Paths.home.appendingPathComponent("work")
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Paths.envPath
        p.environment = env
        let inPipe = Pipe(), out = Pipe()
        p.standardInput = inPipe; p.standardOutput = out; p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { return }
            DispatchQueue.main.async { self?.feed(d) }
        }
        p.terminationHandler = { [weak self] dead in
            DispatchQueue.main.async {
                guard let self, self.proc === dead else { return }
                self.proc = nil
                if self.done != nil { self.finish(self.strings.failed) }
            }
        }
        do { try p.run() } catch { log("claude failed to start: \(error)"); return }
        proc = p; stdin = inPipe.fileHandleForWriting
        sent = 0; received = 0; buffer = Data()
        log("brain warm")
    }
    private func feed(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { handle(obj) }
        }
    }
    private func handle(_ obj: [String: Any]) {
        let type = obj["type"] as? String
        if type == "result" {
            received += 1
            if received == sent, done != nil { finish((obj["result"] as? String) ?? pendingText ?? "") }
            return
        }
        guard done != nil, received == sent - 1 else { return }   // ignore the tail of an older turn
        guard type == "assistant", let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { return }
        let tools = content.filter { $0["type"] as? String == "tool_use" }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        if !tools.isEmpty {
            finalTimer?.cancel(); pendingText = nil
            for c in tools {
                let inp = c["input"] as? [String: Any]
                step?((inp?["description"] as? String) ?? strings.toolNames[c["name"] as? String ?? ""] ?? strings.working)
            }
        } else if !text.isEmpty {
            // Text with no tool call is almost always the final answer — speak it now instead of
            // waiting 1–2 s for the turn summary. If a tool call follows within 0.35 s, cancel.
            pendingText = text
            finalTimer?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.finish(text) }
            finalTimer = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        }
    }
    private func finish(_ r: String) {
        finalTimer?.cancel(); finalTimer = nil; pendingText = nil
        guard let d = done else { return }
        done = nil; step = nil; lastUse = Date()
        let t = r.trimmingCharacters(in: .whitespacesAndNewlines)
        d(t.isEmpty ? strings.failed : t)
    }

    func ask(_ command: String, frontApp: String, step: @escaping (String) -> Void, done: @escaping (String) -> Void) {
        ensure()
        guard let stdin else { done(strings.noClaude); return }
        let now = DateFormatter(); now.locale = Locale(identifier: cfg.locale)
        now.dateFormat = cfg.ko ? "M월 d일 EEEE a h시 m분" : "EEEE, MMM d, h:mm a"
        let input = cfg.ko ? "[지금 \(now.string(from: Date())) · 맨 앞 앱: \(frontApp)]\n\(cfg.user) 말: \(command)"
                           : "[Now \(now.string(from: Date())) · front app: \(frontApp)]\n\(cfg.user) says: \(command)"
        let msg: [String: Any] = ["type": "user", "message": ["role": "user", "content": input]]
        guard var data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        data.append(0x0A)
        self.step = step; self.done = done; sent += 1
        stdin.write(data)
        log("brain ← \(command)")
    }
    func stop() { proc?.terminate(); proc = nil }
    func cancel() {
        guard done != nil else { return }
        let p = proc; proc = nil; p?.terminate()
        finish(strings.stopped)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.ensure() }
    }
}
