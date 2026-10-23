// Routines you make by voice: 「앞으로 '작업 시작' 하면 클로드 열고 로파이 틀고 소리 30으로 해」.
// Only quick commands go in (open, play, volume, maps, timers…) — never Claude hand-offs, typing, sending or paying —
// so a voice from a video can't plant anything that acts on its own. Saved in ~/.macbutler/routines.json (0600).
import Foundation

enum Routines {
    private(set) static var all: [String: [String]] = load()
    private static var file: URL { Paths.home.appendingPathComponent("routines.json") }
    private static func load() -> [String: [String]] {
        guard let d = try? Data(contentsOf: file), let r = try? JSONDecoder().decode([String: [String]].self, from: d) else { return [:] }
        return r
    }
    static func save(_ name: String, _ steps: [String]) { all[name] = steps; write() }
    @discardableResult static func remove(_ name: String) -> Bool {
        guard let k = match(name) else { return false }
        all[k] = nil; write(); return true
    }
    /// The routine whose name was said (ignoring spaces and a trailing 해/시작/모드).
    static func match(_ said: String) -> String? {
        var q = Parser.squash(said)
        for tail in ["해줘", "해", "시작해", "켜", "모드", "루틴"] where q.hasSuffix(tail) && q.count > tail.count + 1 {
            if all.keys.contains(where: { Parser.squash($0) == q }) { break }
            q = String(q.dropLast(tail.count))
        }
        return all.keys.first { Parser.squash($0) == q }
    }
    private static func write() {
        guard let d = try? JSONEncoder().encode(all) else { return }
        FileManager.default.createFile(atPath: file.path, contents: d, attributes: [.posixPermissions: 0o600])
    }
}
