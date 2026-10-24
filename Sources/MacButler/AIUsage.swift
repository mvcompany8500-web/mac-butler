// How much of your AI plan is left, and how much of it Mac Butler used (2026-10-24, owner: 「토큰이 얼마 있는지, 사사리사가
// 얼마나 쓰는지 알아야지」). Nothing is sent anywhere — it is read from what the brains already report:
//  · Claude Code: every stream-json run carries a `rate_limit_event` with the 5-hour and 7-day windows of your plan.
//  · Codex: its own session logs (~/.codex/sessions) carry `rate_limits` (the weekly window, plus the 5-hour one when there is one).
//  · Mac Butler's share: the tokens of its own brain and router runs, per day (usage.json, see `Usage`).
import Foundation

enum AIUsage {
    struct Window: Codable { var used: Double; var resets: Date?; var label: String }       // used: 0…1
    struct Plan: Codable { var provider: String; var windows: [Window]; var seen: Date }
    static var url: URL { Paths.home.appendingPathComponent("plan-usage.json") }

    static func load() -> [String: Plan] {
        guard let d = try? Data(contentsOf: url) else { return [:] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode([String: Plan].self, from: d)) ?? [:]
    }
    private static func save(_ p: Plan) {
        var all = load(); all[p.provider] = p
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(all) { FileManager.default.createFile(atPath: url.path, contents: d, attributes: [.posixPermissions: 0o600]) }
    }

    /// Claude Code's `{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.1,…},…}}}`
    static func noteClaude(_ obj: [String: Any]) {
        guard obj["type"] as? String == "rate_limit_event", let info = obj["rate_limit_info"] as? [String: Any] else { return }
        let wins = info["unifiedWindows"] as? [String: [String: Any]] ?? [:]
        let names = [("five_hour", "5시간"), ("seven_day", "7일"), ("seven_day_opus", "7일 · Opus")]
        let windows = names.compactMap { key, label -> Window? in
            guard let w = wins[key], let u = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return Window(used: min(max(u, 0), 1), resets: (w["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }, label: label)
        }
        if !windows.isEmpty { save(Plan(provider: "claude", windows: windows, seen: Date())) }
    }

    /// The newest `rate_limits` Codex wrote in its session logs (last 3 days).
    static func refreshCodex() {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"
        var files: [(URL, Date)] = []
        for back in 0..<3 {
            let dir = root.appendingPathComponent(f.string(from: Date().addingTimeInterval(Double(-back) * 86400)))
            for u in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where u.pathExtension == "jsonl" {
                files.append((u, (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
            }
        }
        for (u, when) in files.sorted(by: { $0.1 > $1.1 }).prefix(5) {
            guard let h = try? FileHandle(forReadingFrom: u) else { continue }
            let size = (try? h.seekToEnd()) ?? 0
            try? h.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
            let text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self); try? h.close()
            for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let rl = findRateLimits(obj) else { continue }
                var windows: [Window] = []
                for key in ["primary", "secondary"] {
                    guard let w = rl[key] as? [String: Any], let p = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
                    let mins = (w["window_minutes"] as? NSNumber)?.intValue ?? 0
                    windows.append(Window(used: min(max(p / 100, 0), 1), resets: (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
                                          label: mins >= 10000 ? "7일" : mins >= 240 && mins <= 360 ? "5시간" : "\(mins / 60)시간"))
                }
                if !windows.isEmpty { save(Plan(provider: "codex", windows: windows, seen: when)); return }
            }
        }
    }
    private static func findRateLimits(_ o: Any) -> [String: Any]? {
        if let d = o as? [String: Any] {
            if let r = d["rate_limits"] as? [String: Any] { return r }
            for v in d.values { if let r = findRateLimits(v) { return r } }
        } else if let a = o as? [Any] { for v in a { if let r = findRateLimits(v) { return r } } }
        return nil
    }

    /// Mac Butler's own use per day for the last `days` days: (day label, calls, tokens it read + wrote).
    static func daily(_ days: Int = 7) -> [(day: String, calls: Int, tokens: Int)] {
        let all = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: Usage.url))) as? [String: [String: Int]]) ?? [:]
        let key = DateFormatter(); key.dateFormat = "yyyy-MM-dd"
        let label = DateFormatter(); label.dateFormat = "M/d"
        return (0..<days).reversed().map { back in
            let d = Date().addingTimeInterval(Double(-back) * 86400), v = all[key.string(from: d)] ?? [:]
            return (label.string(from: d), v["calls"] ?? 0, (v["input"] ?? 0) + (v["output"] ?? 0) + (v["cacheWrite"] ?? 0) + (v["cacheRead"] ?? 0) / 10)
        }
    }
}
