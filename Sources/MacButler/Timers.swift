// Timers & reminders: 「라면 3분」, 「10분 뒤에 알려 줘」, 「5시에 회의 알려 줘」.
// They only remind — they never act. Kept in ~/.macbutler/timers.json so a restart doesn't lose them.
import Foundation

enum Timers {
    struct Item: Codable { let at: Date; let label: String }
    static var onFire: (String) -> Void = { _ in }
    private static var items: [Item] = []
    private static var live: [Timer] = []
    private static var file: URL { Paths.home.appendingPathComponent("timers.json") }

    static func add(at: Date, label: String) {
        items.append(Item(at: at, label: label)); save(); schedule(items.last!)
        log("timer: \(label.isEmpty ? "-" : label) at \(at)")
    }
    static func restore() {
        guard let d = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Item].self, from: d) else { return }
        // ones that went off while the Mac was off/asleep: say them now if under 10 minutes late, else drop
        items = saved.filter { $0.at > Date().addingTimeInterval(-600) }
        save()
        items.forEach(schedule)
    }
    static func cancelLast() {
        guard let last = items.last else { return }
        items.removeLast(); save()
        if let t = live.last { t.invalidate(); live.removeLast() }
        log("timer cancelled: \(last.label)")
    }
    @discardableResult static func cancelAll() -> Int {
        let n = items.count
        live.forEach { $0.invalidate() }; live = []; items = []; save()
        return n
    }
    private static func schedule(_ it: Item) {
        let t = Timer(fire: max(it.at, Date().addingTimeInterval(0.5)), interval: 0, repeats: false) { t in
            items.removeAll { $0.at == it.at && $0.label == it.label }; save()
            live.removeAll { $0 === t }
            onFire(it.label)
        }
        RunLoop.main.add(t, forMode: .common); live.append(t)
    }
    private static func save() {
        guard let d = try? JSONEncoder().encode(items) else { return }
        FileManager.default.createFile(atPath: file.path, contents: d, attributes: [.posixPermissions: 0o600])
    }
}
