// Mac Butler Pro (2026-10-24): what runs on TurtleMaker's servers, for TurtleMaker members — call your Mac from your
// phone, and the natural voice. Everything that runs on your Mac stays free; nothing here is needed for it.
//  · Linking: the Mac gets a short code, you approve it in any browser signed in to your TurtleMaker account
//    (maker.buffm.com/butler/link), and the Mac receives a device key (Keychain only; the server keeps a hash).
//  · Remote: while linked and a member, the Mac waits on the server (an outgoing request — no open ports) for what you
//    typed on the phone (maker.buffm.com/butler/remote), runs it like a spoken command, and sends back one line.
//    From the phone nothing irreversible happens unless free mode is on, and payments never do.
//  · Voice: `tts = "pro"` — the server reads the line with ElevenLabs within the monthly allowance; anything else
//    (over the allowance, not a member, offline) falls back to the free macOS voice.
import AppKit

enum ProAccount {
    static let server = "https://maker.buffm.com"
    static let keyAccount = "butler-pro"
    static var token: String? { Keys.get(keyAccount) }
    struct Status { var email = ""; var active = false; var voice = false; var plan = ""; var used = 0; var limit = 25000 }
    private(set) static var status: Status?

    static func authed(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 15) -> URLRequest? {
        guard let t = token, let url = URL(string: server + path) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: timeout); r.httpMethod = method
        r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }
    /// Blocking JSON call — off the main thread only.
    static func call(_ req: URLRequest) -> (code: Int, json: [String: Any]) {
        let sem = DispatchSemaphore(value: 0); var out: (Int, [String: Any]) = (0, [:])
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            out = ((resp as? HTTPURLResponse)?.statusCode ?? 0, d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:])
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + req.timeoutInterval + 5)
        return out
    }

    // MARK: linking

    /// Starts linking: opens the approval page and reports the code; `done(true)` once approved (polls up to 10 minutes).
    static func link(name: String, code: @escaping (String) -> Void, done: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            guard let url = URL(string: server + "/api/butler/link/start") else { return }
            var r = URLRequest(url: url, timeoutInterval: 15); r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
            let s = call(r)
            guard s.code == 200, let c = s.json["code"] as? String, let poll = s.json["poll"] as? String,
                  let page = (s.json["url"] as? String).flatMap(URL.init(string:)), page.host == "maker.buffm.com" else {
                DispatchQueue.main.async { done(false) }; return
            }
            DispatchQueue.main.async { code(c); NSWorkspace.shared.open(page) }
            for _ in 0..<300 {
                Thread.sleep(forTimeInterval: 2)
                var p = URLRequest(url: URL(string: server + "/api/butler/link/poll")!, timeoutInterval: 15); p.httpMethod = "POST"
                p.setValue("application/json", forHTTPHeaderField: "Content-Type")
                p.httpBody = try? JSONSerialization.data(withJSONObject: ["poll": poll])
                let res = call(p)
                if res.json["status"] as? String == "ok", let t = res.json["token"] as? String, t.count == 64 {
                    Keys.set(keyAccount, t); log("pro: linked \(res.json["email"] as? String ?? "")")
                    _ = refresh(); DispatchQueue.main.async { done(true) }; return
                }
                if res.code == 404 { break }
            }
            DispatchQueue.main.async { done(false) }
        }
    }
    static func unlink() {
        if let r = authed("/api/butler/unlink", method: "POST", body: [:]) { DispatchQueue.global().async { _ = call(r) } }
        Keys.remove(keyAccount); status = nil; log("pro: unlinked")
    }
    /// Membership and voice allowance (blocking).
    @discardableResult static func refresh() -> Status? {
        guard let r = authed("/api/butler/me") else { status = nil; return nil }
        let res = call(r)
        if res.code == 401 { Keys.remove(keyAccount); status = nil; return nil }
        guard res.code == 200 else { return status }
        let pro = res.json["pro"] as? [String: Any] ?? [:], v = res.json["voice"] as? [String: Any] ?? [:]
        status = Status(email: res.json["email"] as? String ?? "", active: pro["active"] as? Bool ?? false, voice: pro["voice"] as? Bool ?? false,
                        plan: pro["plan"] as? String ?? "", used: v["used"] as? Int ?? 0, limit: v["limit"] as? Int ?? 25000)
        return status
    }

    // MARK: voice

    /// Not a member / over the allowance / the server is full → don't ask again for an hour (the free voice meanwhile).
    static var voiceOffUntil = Date.distantPast
    /// The request for `tts = "pro"`; nil when not linked. Short questions and greetings are marked common so the server
    /// can reuse the sound (free for everyone); answers are never stored.
    /// Voices the server reads with (ElevenLabs, Korean): id, Korean label, English label. The first is the default.
    static let voices: [(id: String, ko: String, en: String)] = [
        ("CxErO97xpQgQXYmapDKX", "테오 — 남성, 대화체", "Teo — male, conversational"),
        ("QPFsEL6IBxlT15xfiD6C", "하나 — 여성, 밝고 자연스러움", "Hana — female, bright and natural"),
        ("qfwDoLSKOhzIgz7XedPT", "선 — 여성, 차분한 아나운서", "Sun — female, calm announcer")]
    static func speechRequest(_ text: String, voice: String = "") -> URLRequest? {
        let common = text.count <= 40 && (text.hasSuffix("?") || text.contains("어서 오") || text.lowercased().hasPrefix("welcome"))
        var body: [String: Any] = ["text": text, "common": common]
        if voices.contains(where: { $0.id == voice }) { body["voice"] = voice }
        return authed("/api/butler/tts", method: "POST", body: body, timeout: 12)
    }

    // MARK: remote

    /// Waits for phone commands while linked and a member. `run(text, id)` runs one; report with `reply(id, text)`.
    static func startRemote(run: @escaping (String, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var pause: TimeInterval = 0
            while true {
                if pause > 0 { Thread.sleep(forTimeInterval: pause); pause = 0 }
                guard token != nil, let r = authed("/api/butler/remote/next", timeout: 40) else { Thread.sleep(forTimeInterval: 60); continue }
                let res = call(r)
                switch res.code {
                case 200:
                    if let id = res.json["id"] as? String, let text = res.json["text"] as? String, !text.isEmpty {
                        log("pro remote ← \(text)"); DispatchQueue.main.async { run(text, id) }
                    }
                case 402: pause = 3600          // not a member: no waiting on the server at all for an hour
                case 401: Keys.remove(keyAccount); status = nil; pause = 3600
                default: pause = 15
                }
            }
        }
    }
    static func reply(_ id: String, _ text: String) {
        guard let r = authed("/api/butler/remote/done", method: "POST", body: ["id": id, "result": String(text.prefix(400))]) else { return }
        DispatchQueue.global().async { _ = call(r) }
    }
}
