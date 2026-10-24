// 「다 같이 키우기」 (2026-10-24): what one Sasarisa learns helps everyone's — like a fleet learning together.
//  1. Consent, asked once: grow together (share) or grow alone (nothing leaves this Mac). Changeable in Settings.
//  2. Shared, only with consent, once a day: the short sentences the router turned into a *safe* quick command
//     (volume, video, closing pages, opening an app…) and the command, plus 「아니」 vetoes — with a random install id.
//     Never: audio, conversations, screen, files, names, search words, timer labels, dictation, Claude tasks.
//  3. The server keeps a pair only when 5+ installs on 3+ networks said it, the same sentence mostly means the same
//     command, and few vetoed it; old votes fade after 180 days.
//  4. Every Sasarisa downloads that pack once a day and checks each pair again before using it (safe quick command
//     only, short, no digits runs). Local learning always wins over the pack.
import AppKit

enum GrowTogether {
    static let server = "https://maker.buffm.com/api/butler"
    private static var packFile: URL { Paths.home.appendingPathComponent("shared-aliases.json") }
    private static var stateFile: URL { Paths.home.appendingPathComponent("grow-state.json") }
    struct State: Codable { var install = UUID().uuidString; var lastUpload = Date.distantPast; var lastPack = Date.distantPast
        var sent: [String] = []; var vetoes: [String: String] = [:] }
    static var state: State = {
        (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }()
    static func saveState() {
        if let d = try? JSONEncoder().encode(state) { FileManager.default.createFile(atPath: stateFile.path, contents: d, attributes: [.posixPermissions: 0o600]) }
    }
    private(set) static var pack: [String: String] = {
        (try? Data(contentsOf: packFile)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }()

    /// A quick command that carries nothing personal — the only kind that is ever shared or taken from the pack.
    static func isShareable(_ canon: String, parser: Parser) -> Bool {
        switch parser.parse(canon, hasYouTubeList: false) {
        case .media, .mediaNext, .displayOff, .closeOpened, .browser, .volume, .clock, .cancelTimers, .undo, .whatDid,
             .hush, .bye, .enter, .closeTabs, .openApp: return true
        default: return false
        }
    }
    /// The spoken side: short, no long number runs, no addresses.
    static func cleanSaid(_ said: String) -> Bool {
        let s = Parser.squash(said)
        return s.count >= 2 && s.count <= 24 && s.range(of: "[0-9]{3,}", options: .regularExpression) == nil
            && !s.contains("@") && !s.lowercased().contains("http")
    }

    /// Pack lookup (after local aliases). nil if this Mac vetoed it.
    static func lookup(_ said: String, parser: Parser) -> String? {
        let k = Parser.squash(said)
        guard let c = pack[k], state.vetoes[k] != c, isShareable(c, parser: parser) else { return nil }
        return c
    }
    /// 「아니 / 틀렸어」 right after a pack sentence ran: never use it here again, and tell the pack (if sharing).
    static func veto(_ said: String) {
        let k = Parser.squash(said)
        guard let c = pack[k] else { return }
        state.vetoes[k] = c; saveState(); log("shared alias vetoed: \(k) → \(c)")
    }

    // MARK: consent

    /// Asks once (a small window). "together" / "solo" are saved as `growTogether`.
    static func askIfNeeded(_ cfg: Config, then: @escaping (String) -> Void) {
        guard cfg.growTogether.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let ko = cfg.ko
            let a = NSAlert()
            a.messageText = ko ? "\(cfg.assistantName)를 어떻게 키울까요?" : "How should \(cfg.assistantName) grow?"
            a.informativeText = ko
                ? "다 같이 키우기를 고르면, 알아들은 짧은 말과 그 말로 한 빠른 명령(예: 「소리 좀 줄여 봐」 → 소리 줄이기)만 이름 없이 모읍니다. 여러 사람이 같은 말을 쓸 때만 모두의 \(cfg.assistantName)에 들어가서, 새로 설치한 사람도 처음부터 잘 알아듣습니다.\n\n목소리·대화 내용·화면·파일·이름·검색어는 보내지 않고, 서버에도 저장하지 않습니다. 설정에서 언제든 바꿀 수 있습니다."
                : "Grow together shares only the short sentences it understood and the quick command they ran (e.g. “turn it down a bit” → volume down), with no name attached. A sentence reaches everyone's \(cfg.assistantName) only when many people use it — so a fresh install understands you from day one.\n\nNo audio, conversations, screen, files, names or search words are sent or stored. You can change this any time in Settings."
            a.addButton(withTitle: ko ? "다 같이 키우기" : "Grow together")
            a.addButton(withTitle: ko ? "혼자 키우기" : "Grow alone")
            NSApp.activate(ignoringOtherApps: true)
            let choice = a.runModal() == .alertFirstButtonReturn ? "together" : "solo"
            Config.set("growTogether", choice); log("grow: \(choice)")
            then(choice)
        }
    }

    // MARK: daily sync

    /// Upload (only with consent) and download the pack, at most once a day each. Runs off the main thread.
    static func sync(_ cfg: Config, parser: Parser, mode: String) {
        DispatchQueue.global(qos: .utility).async {
            if mode == "together", Date().timeIntervalSince(state.lastUpload) > 20 * 3600 { upload(cfg, parser: parser) }
            if Date().timeIntervalSince(state.lastPack) > 20 * 3600 || pack.isEmpty { download(cfg, parser: parser) }
        }
    }
    static func payload(_ cfg: Config, parser: Parser) -> [String: Any]? {
        let sent = Set(state.sent)
        let items = Aliases.all.filter { !sent.contains($0.key + "\u{1F}" + $0.value) && cleanSaid($0.key) && isShareable($0.value, parser: parser) }
            .prefix(50).map { ["s": $0.key, "c": $0.value] }
        let vetoes = state.vetoes.map { ["s": $0.key, "c": $0.value] }.prefix(50)
        guard !items.isEmpty || !vetoes.isEmpty else { return nil }
        return ["v": 1, "lang": cfg.lang, "install": state.install, "items": Array(items), "veto": Array(vetoes),
                "app": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""]
    }
    private static func upload(_ cfg: Config, parser: Parser) {
        guard let body = payload(cfg, parser: parser), let url = URL(string: server + "/learn"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { state.lastUpload = Date(); saveState(); return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = data
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200 {
                let items = (body["items"] as? [[String: String]]) ?? []
                state.sent += items.map { ($0["s"] ?? "") + "\u{1F}" + ($0["c"] ?? "") }
                if state.sent.count > 2000 { state.sent.removeFirst(state.sent.count - 2000) }
                log("grow: shared \(items.count) sentences")
            }
            state.lastUpload = Date(); saveState(); sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
    }
    private static func download(_ cfg: Config, parser: Parser) {
        guard let url = URL(string: server + "/pack?lang=" + cfg.lang) else { return }
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 15)) { data, resp, _ in
            defer { sem.signal() }
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data,
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let items = o["items"] as? [[String: String]] else { return }
            var p: [String: String] = [:]
            for it in items.prefix(5000) {
                guard let s = it["s"], let c = it["c"], cleanSaid(s), c.count <= 40, isShareable(c, parser: parser) else { continue }
                p[Parser.squash(s)] = c
            }
            pack = p
            if let d = try? JSONEncoder().encode(p) { FileManager.default.createFile(atPath: packFile.path, contents: d, attributes: [.posixPermissions: 0o600]) }
            state.lastPack = Date(); saveState()
            log("grow: pack \(p.count) sentences")
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
    }
}
