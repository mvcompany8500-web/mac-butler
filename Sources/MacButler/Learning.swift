// Gets better with use: what Claude figured out once is remembered and replayed instantly next time
// (no Claude call, no tokens). Only safe, action-only tool steps are learned; say “아니/틀렸어” right after and it's forgotten.
// Also keeps a daily token tally so you can see what the brain costs.
import Foundation

enum Learning {
    static var url: URL { Paths.home.appendingPathComponent("learned.json") }
    struct Entry: Codable { var commands: [String]; var uses: Int; var learned: Date }
    static var store: [String: Entry] = {
        guard let d = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: d)) ?? [:]
    }()
    static func save() {
        if let d = try? JSONEncoder().encode(store) {
            FileManager.default.createFile(atPath: url.path, contents: d, attributes: [.posixPermissions: 0o600])
        }
    }
    static func key(_ phrase: String) -> String { Parser.squash(phrase) }

    /// Read-only lookups that don't change anything (not worth replaying) and coordinate clicks (screen-dependent).
    static let lookups: Set<String> = ["list", "front", "screenshot", "click"]
    static let actions: Set<String> = ["tap", "field", "key", "volume", "open-app", "open-url"]

    /// Shell-free tokenizer for `jax tap "Save"`-style lines; refuses anything with shell syntax.
    static func tokens(_ line: String) -> [String]? {
        if line.contains(where: { ";|&$`<>\\\n(){}*".contains($0) }) { return nil }
        var out: [String] = [], cur = "", quote: Character? = nil
        for ch in line {
            if let q = quote { if ch == q { quote = nil } else { cur.append(ch) }; continue }
            if ch == "\"" || ch == "'" { quote = ch; continue }
            if ch == " " { if !cur.isEmpty { out.append(cur); cur = "" }; continue }
            cur.append(ch)
        }
        if quote != nil { return nil }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
    /// The replayable part of a turn, or nil if this turn shouldn't be learned.
    static func replayable(_ cmds: [String]) -> [[String]]? {
        var steps: [[String]] = []
        for c in cmds {
            guard let t = tokens(c), let tool = t.first else { return nil }
            if tool == "jax", t.count >= 2 {
                if lookups.contains(t[1]) { if t[1] == "click" { return nil }; continue }
                guard actions.contains(t[1]) else { return nil }
                steps.append(t)
            } else if tool == "jtype" { steps.append(t) }
            else if tool == "date" { continue }
            else { return nil }          // delegate, session, anything else: never learned
        }
        return steps.isEmpty || steps.count > 6 ? nil : steps
    }
    static func remember(_ phrase: String, _ steps: [[String]]) {
        store[key(phrase)] = Entry(commands: steps.map { $0.joined(separator: "\u{1F}") }, uses: 0, learned: Date())
        save(); log("learned: \(phrase) → \(steps.map { $0.joined(separator: " ") })")
    }
    static func forget(_ phrase: String) { if store.removeValue(forKey: key(phrase)) != nil { save(); log("forgot: \(phrase)") } }
    static func lookup(_ phrase: String) -> [[String]]? {
        guard let e = store[key(phrase)] else { return nil }
        return e.commands.map { $0.components(separatedBy: "\u{1F}") }
    }
    static func used(_ phrase: String) { store[key(phrase)]?.uses += 1; save() }

    /// Runs the learned steps with the bundled tools (safe mode guards still apply).
    static func replay(_ steps: [[String]]) -> Bool {
        for s in steps {
            let p = Process()
            p.executableURL = Paths.tools.appendingPathComponent(s[0])
            p.arguments = Array(s.dropFirst())
            var env = ProcessInfo.processInfo.environment
            env["MACBUTLER_SAFE"] = "1"; env["MACBUTLER_BUNDLE"] = Bundle.main.bundleIdentifier ?? ""
            p.environment = env
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit() } catch { return false }
            if p.terminationStatus != 0 { return false }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return true
    }
}

enum Usage {
    static var url: URL { Paths.home.appendingPathComponent("usage.json") }
    /// Adds one Claude turn (from the stream-json "result" event) to today's tally.
    static func record(_ result: [String: Any]) {
        let u = result["usage"] as? [String: Any] ?? [:]
        let i = u["input_tokens"] as? Int ?? 0, o = u["output_tokens"] as? Int ?? 0
        let cr = u["cache_read_input_tokens"] as? Int ?? 0, cw = u["cache_creation_input_tokens"] as? Int ?? 0
        let ms = result["duration_ms"] as? Int ?? 0
        log("brain usage: in \(i) + cache read \(cr) + cache write \(cw), out \(o), \(ms) ms")
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: Date())
        var all = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: [String: Int]]) ?? [:]
        var d = all[day] ?? [:]
        d["calls", default: 0] += 1; d["input", default: 0] += i; d["output", default: 0] += o
        d["cacheRead", default: 0] += cr; d["cacheWrite", default: 0] += cw; d["ms", default: 0] += ms
        all[day] = d
        if let data = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys]) {
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }
    static func today() -> [String: Int] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let all = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: [String: Int]]) ?? [:]
        return all[f.string(from: Date())] ?? [:]
    }
}
