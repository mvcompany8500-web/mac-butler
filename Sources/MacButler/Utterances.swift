// Optional (config keepAudio): keeps the last 30 utterances — audio + what Apple and Whisper heard — in
// ~/.macbutler/utterances, owner-only, so recognition can be checked and tuned on your real voice. Never uploaded.
import Foundation

enum Utterances {
    static var enabled = false
    static var dir: URL { Paths.home.appendingPathComponent("utterances") }
    static func keep(_ wav: Data, apple: String, whisper: String) {
        guard enabled else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let name = f.string(from: Date())
        fm.createFile(atPath: dir.appendingPathComponent(name + ".wav").path, contents: wav, attributes: [.posixPermissions: 0o600])
        let note = "apple: \(apple)\nwhisper: \(whisper.isEmpty ? "(used apple)" : whisper)\n"
        fm.createFile(atPath: dir.appendingPathComponent(name + ".txt").path, contents: Data(note.utf8), attributes: [.posixPermissions: 0o600])
        let all = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".wav") }.sorted()
        for old in all.dropLast(30) {
            try? fm.removeItem(at: dir.appendingPathComponent(old))
            try? fm.removeItem(at: dir.appendingPathComponent(old.replacingOccurrences(of: ".wav", with: ".txt")))
        }
    }
}
