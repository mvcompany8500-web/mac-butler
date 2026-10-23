// The conductor: listens, decides, acts, speaks.
import AppKit

final class Butler {
    enum Mode { case idle, awake, dictation, busy, speaking }
    var mode: Mode = .idle { didSet { if mode != oldValue { modeSince = Date() } } }
    var modeSince = Date()
    let cfg: Config
    let S: Strings
    let parser: Parser
    let ear: Ear
    let hud = HUD()
    let mouth: Mouth
    let brain: Brain
    let whisper: Whisper
    var awakeUntil = Date.distantPast
    var awakeStarted: Date?
    var enabled = true
    var speakingText = ""
    var bargedIn = false
    var ytList: [(id: String, title: String)] = []
    var cancelSend = false
    var lastLive = ""
    var ignoreUntil = Date.distantPast    // our own voice's tail right after speaking
    /// Can anything you say interrupt it? Only when its voice can't reach the mic (headphones).
    lazy var bargeAny: Bool = {
        if cfg.bargeIn == "any" { return true }
        if cfg.bargeIn == "wake" { return false }
        let out = AudioDevices.device(uid: cfg.outputDevice)?.name ?? AudioDevices.defaultOutputName()
        let n = out.lowercased()
        let headphones = ["airpods", "buds", "headphone", "headset", "beats", "이어폰", "wh-", "wf-", "qc"].contains { n.contains($0) } && !n.contains("외장")
        log("barge-in mode: \(headphones ? "any speech (headphones)" : "wake word / stop words only (speakers)") · output: \(out)")
        return headphones
    }()
    func canBargeIn(_ t: String) -> Bool {
        if bargeAny { return true }
        let a = parser.stripWake(t)
        return parser.wakeRange(t) != nil || parser.isHush(a) || ["멈춰", "그만", "스톱", "stop", "잠깐", "됐어"].contains { Parser.squash(a).hasPrefix($0) }
    }            // what Apple's live recognizer heard for the current command
    var learnCandidate: (phrase: String, steps: [[String]])?      // set when you say “취소/멈춰” while a Claude message is about to be sent
    static let claudeBundle = "com.anthropic.claudefordesktop"

    init(cfg: Config) {
        self.cfg = cfg
        S = Strings(ko: cfg.ko, name: cfg.assistantName)
        parser = Parser(cfg: cfg)
        Sound.outputUID = cfg.outputDevice
        hud.position = cfg.hudPosition
        ear = Ear(locale: cfg.locale, hints: Array((cfg.wakes + cfg.greets + cfg.customWords + (cfg.ko ? ["클로드", "엔터", "받아써", "그만"] : ["Claude", "enter", "stop"])).prefix(100)), inputUID: cfg.inputDevice)
        mouth = Mouth(cfg: cfg)
        brain = Brain(cfg: cfg)
        whisper = Whisper(model: cfg.whisperModelPath, binary: cfg.whisperBinary, language: cfg.lang,
                          prompt: String(((cfg.wakes + [cfg.user, "Claude", "YouTube"] + cfg.customWords).joined(separator: ", ") + ".").prefix(500)))
    }

    func start() {
        hud.showIdleOrb = cfg.showIdleOrb
        ear.silenceSec = cfg.silenceSec
        ear.onLevel = { [weak self] v in
            guard let self else { return }
            self.hud.orb.level(v)
            if self.mode == .speaking, !self.bargeAny, self.cfg.bargeIn != "wake", self.mouth.echo.isUser(v) { self.bargeInByVoice() }
        }
        ear.onPartial = { [weak self] t in self?.partial(t) }
        ear.onUtterance = { [weak self] t, a in self?.utterance(t, audio: a) }
        brain.warm()
        Growth.sweep()
        listenForSignals()
        do { try ear.start() } catch { log("mic failed: \(error)"); hud.show("⚠︎", S.micError, color: amber) }
        if !brain.installed { hud.show("⚠︎", S.noClaude, color: amber) }
        log("ready · whisper=\(whisper.available) claude=\(brain.installed) tts=\(cfg.tts)")
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.mode == .awake else { return }
            if self.awakeStarted.map({ Date().timeIntervalSince($0) > self.cfg.maxUtteranceSec }) == true { self.awakeStarted = nil; self.ear.forceFlush() }
            if Date() > self.awakeUntil { self.goIdle() }
        }
        // Never get stuck: a voice reply or a Claude task that hangs must not leave it deaf.
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let age = Date().timeIntervalSince(self.modeSince)
            if self.mode == .speaking, age > 90 { log("watchdog: stuck speaking → idle"); self.mouth.stop(); self.speakingText = ""; self.ear.muted = false; self.ear.restart(); self.goIdle() }
            if self.mode == .busy, age > 180 { log("watchdog: task took too long → stop"); self.brain.cancel(); self.goIdle() }
        }
    }

    /// Commands from the bundled tools (`butler`, `jax field`) over the private control socket (see ControlSocket).
    lazy var control = ControlSocket { [weak self] cmd, text in self?.signal(cmd, text) }
    private func listenForSignals() { control.start() }
    func signal(_ cmd: String, _ text: String) {
        switch cmd {
        case "type":
            if cfg.brainAccess != "full", let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, Butler.protectedApps.contains(b) || b == Bundle.main.bundleIdentifier {
                log("blocked typing into protected app \(b)"); return
            }
            DispatchQueue.global().async { Hands.typeVisible(text) }
        case "delegate":   // from the brain: it asks the question in its own answer, we just hold the task
            let parts = text.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { return }
            let here = parts[0] == "." || parts[0] == "지금" || parts[0].lowercased() == "here"
            askToDelegate(target: here ? "" : parts[0], message: parts[1], newSession: parts[0].isEmpty, speakQuestion: false)
        case "session":   // switch the Claude app to a session by name — navigation only, nothing typed
            openClaudeSession(text)
        case "settings": if text == "close" { SettingsWindow.window?.close() } else { SettingsWindow.show(cfg: cfg) }
        case "setup": if text == "close" { SetupWindow.window?.close() } else { SetupWindow.show(cfg: cfg) }
        case "say":   // text instead of voice — for testing and screen recordings
            log("text command: \(text)")
            if parser.isGreeting(text) { greet(); return }
            if mode == .idle { mode = .awake; awakeUntil = Date().addingTimeInterval(cfg.followUpSec) }
            utterance(text, audio: [])
        default: break
        }
    }

    // MARK: listening

    /// Hold the hotkey and talk; release to run it right away (exact audio, no waiting for silence).
    func holdBegan() {
        guard enabled else { return }
        if mode == .speaking { mouth.stop(); speakingText = ""; bargedIn = true }
        if brain.busy { brain.cancel(silently: true) }
        whisper.warm()
        ear.muted = false
        ear.beginHold()
        mode = .awake; awakeStarted = nil; awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
        Sound.named(cfg.chime)
        hud.show(S.t("● 듣는 중 · 손을 떼면 실행", "● Listening · release to run"), S.speakNow, heard: "")
    }
    func holdEnded() {
        let (t, audio) = ear.endHold()
        log("hold: \(audio.count / 16) ms, live text: \(t)")
        guard audio.count > 4800 else { converse(); return }
        hud.show(S.transcribing, t.isEmpty ? "…" : t, speed: 2)
        lastLive = parser.stripWake(t)
        whisper.transcribe(audio, fallback: t) { [weak self] full in
            guard let self else { return }
            let cmd = self.parser.stripWake(full)
            if cmd.isEmpty { self.converse(); return }
            if self.mode == .dictation { self.dictate(full) } else { self.handle(cmd) }
        }
    }
    func holdCancelled() { ear.cancelHold() }

    /// Recognizer hints grow with what you say (saved to config.json customWords, used from the next launch).
    func studyWords(whisper w: String, live: String) {
        let new = Growth.study(whisper: w, live: live, known: cfg.customWords + cfg.wakes)
        guard !new.isEmpty else { return }
        let url = Paths.home.appendingPathComponent("config.json")
        var obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        var words = obj["customWords"] as? [String] ?? cfg.customWords
        words.append(contentsOf: new.filter { !words.contains($0) })
        obj["customWords"] = Array(words.suffix(150))
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) { try? d.write(to: url) }
    }

    /// Same as saying the wake word (hotkey). While speaking it interrupts; while awake it ends the conversation.
    func manualWake() {
        guard enabled else { return }
        switch mode {
        case .idle: whisper.warm(); converse(chime: true)
        case .speaking: mouth.stop(); speakingText = ""; bargedIn = true; ear.restart(); converse(chime: true)
        case .awake: Sound.named("Pop"); goIdle()
        case .busy: brain.cancel()
        case .dictation: converse(chime: true)
        }
    }

    func partial(_ t: String) {
        guard enabled, cfg.activation != "hold" || ear.holding || mode == .speaking || mode == .dictation else { return }
        switch mode {
        case .idle:
            if parser.isGreeting(t) { greet(); return }
            if let r = parser.wakeRange(t) {        // react the moment the wake word appears
                whisper.warm()
                Sound.named(cfg.chime)
                mode = .awake; awakeStarted = Date()
                awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
                let rest = Parser.clean(String(t[r.upperBound...]))
                hud.show(S.listening, rest.isEmpty ? S.speakNow : rest)
            }
        case .awake:
            if parser.isGreeting(t) { greet(); return }
            if awakeStarted == nil { awakeStarted = Date() }
            awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
            hud.show(S.conversing, t)
        case .dictation: hud.show(S.dictation, t, color: lime)
        case .speaking:
            if !speakingText.isEmpty, !isEcho(t), canBargeIn(t) { bargeIn(t) }
        case .busy:
            if brain.busy { hud.show(S.listening, t, heard: nil, color: amber, speed: 3) }
            let q = Parser.squash(t)
            if ["취소", "멈춰", "하지마", "아니", "스톱", "stop", "cancel"].contains(where: { q.hasSuffix($0) }) { cancelSend = true }
        }
    }

    func utterance(_ t: String, audio: [Float]) {
        guard enabled, !ear.holding else { return }   // push-to-talk delivers its own utterance on release
        if Date() < ignoreUntil, mode == .awake { log("ignored (our own voice tail): \(t)"); return }
        if cfg.activation == "hold", mode != .dictation, mode != .speaking { return }   // hold-only: nothing is acted on without the key
        log("heard[\(mode)]: \(t)")
        switch mode {
        case .idle:
            if parser.isGreeting(t) { greet(); return }
            guard parser.wakeRange(t) != nil else { return }
            mode = .awake; awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
            fallthrough
        case .awake:
            awakeStarted = nil
            if parser.isGreeting(t) { return }      // already started from the partial
            let a = parser.stripWake(t)
            if a.isEmpty { hud.show(S.conversing, S.speakNow); return }
            if parser.instant(a) { handle(a); return }
            refine(audio, t) { [weak self] full in self?.command(full) }
        case .dictation:
            whisper.transcribe(audio, fallback: t) { [weak self] full in self?.dictate(full) }
        case .busy:
            let a = parser.stripWake(t)
            if parser.isHush(a) || parser.isBye(a) || Parser.cancelledAtEnd(" " + a) || ["취소", "멈춰", "stop", "cancel"].contains(Parser.squash(a)) {
                cancelSend = true
                if brain.busy { brain.cancel() }
                return
            }
            // A new command while Claude is still thinking: drop the old one and take the new one right away.
            // (While a message is being typed into the Claude app we don't interrupt — only “취소” stops it.)
            if brain.busy, a.count >= 2 {
                log("interrupt → new command: \(a)")
                brain.cancel(silently: true)
                mode = .awake; awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
                refine(audio, t) { [weak self] full in self?.command(full) }
            }
        case .speaking:
            if !speakingText.isEmpty, !isEcho(t), canBargeIn(t) {
                bargeIn(t); awakeStarted = nil
                refine(audio, t) { [weak self] full in self?.command(full) }
            }
        }
    }

    /// Apple's text is shown instantly; the command itself uses Whisper's more accurate text.
    func refine(_ audio: [Float], _ apple: String, then: @escaping (String) -> Void) {
        if !audio.isEmpty && whisper.available { hud.show(S.transcribing, apple, speed: 2) }
        lastLive = parser.stripWake(apple)
        whisper.transcribe(audio, fallback: apple) { [weak self] full in
            guard let self else { return }
            self.studyWords(whisper: full, live: apple)
            var t = full
            // If you said the wake word, nothing before it belongs to this command.
            if self.parser.wakeRange(apple) != nil, let r = self.parser.wakeRange(t), r.lowerBound > t.startIndex { t = String(t[r.lowerBound...]) }
            then(t)
        }
    }
    func command(_ full: String) {
        guard mode != .busy, mode != .speaking else { return }
        var cmd = parser.stripWake(full)
        // Whisper's text didn't match a quick command but the live text does → trust the live text for this one.
        if parser.parse(cmd, hasYouTubeList: !ytList.isEmpty) == .none, !lastLive.isEmpty,
           parser.parse(lastLive, hasYouTubeList: !ytList.isEmpty) != .none { log("using live text for quick command: \(lastLive)"); cmd = lastLive }
        if cmd.isEmpty { converse(chime: true) } else { handle(cmd) }
    }

    /// Stay in conversation: no wake word needed until `followUpSec` of silence or "that's all".
    func converse(chime: Bool = false, keep: Bool = false) {
        if chime { Sound.named(cfg.chime) }
        mode = .awake; awakeStarted = nil
        awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
        whisper.warm()
        if keep { hud.setStatus(S.conversing) } else { hud.show(S.conversing, S.speakNow) }
    }

    // MARK: acting

    func handle(_ cmd: String) {
        if pendingDelegate != nil, answerPending(cmd) { return }
        let q = Parser.squash(cmd)
        if learnCandidate != nil, ["아니", "틀렸", "그게아니", "안됐", "잘못", "no", "wrong"].contains(where: { q.hasPrefix($0) }) {
            log("not learning: \(learnCandidate!.phrase)"); learnCandidate = nil
        }
        let intent = parser.parse(cmd, hasYouTubeList: !ytList.isEmpty)
        log("intent: \(intent)")
        switch intent {
        case .greet: greet()
        case .dictation:
            mode = .dictation
            speak(S.dictationStart) { [weak self] in guard let self else { return }; self.mode = .dictation; self.hud.show(self.S.dictation, "", color: lime) }
        case .enter: Hands.key(Hands.enter); done(S.key, "⏎")
        case .hush: converse()
        case .bye: Sound.named("Pop"); goIdle()
        case .type(let text): Hands.paste(text); done(S.typed, text)
        case .claude(let target, let message, let newSession):
            // Your own spoken request goes straight through (unless confirmDelegate = "always").
            if cfg.confirmDelegate == "always" { askToDelegate(target: target, message: message, newSession: newSession) }
            else { claudeMacro(target: target, message: message, newSession: newSession) }
        case .youtube(let q):
            if q.isEmpty { open("https://www.youtube.com/"); played(S.youtube, "YouTube") } else { youtube(q) }
        case .youtubeNth(let n):
            guard n >= 1, n <= ytList.count else { ask(cmd); return }
            open("https://www.youtube.com/watch?v=" + ytList[n - 1].id); played("\(S.youtube) #\(n)", ytList[n - 1].title)
        case .search(let q): open((cfg.ko ? "https://www.google.com/search?hl=ko&q=" : "https://www.google.com/search?q=") + enc(q)); done(S.searched, q)
        case .remember(let note): Memory.note(note); Sound.named("Pop"); done(S.t("기억함", "Remembered"), note)
        case .web(let label, let q, let url): open(q.isEmpty ? url : url + enc(q)); done(label, q.isEmpty ? url : q)
        case .openApp(let spoken, let app):
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", app]; try? p.run()
            done(S.opened, spoken)
        case .none:
            if let steps = Learning.lookup(cmd) {      // learned before → instant, no Claude call
                hud.show(S.t("◌ 기억한 대로 하는 중", "◌ Doing it the way I learned"), cmd, heard: nil, color: amber, speed: 3)
                DispatchQueue.global().async { [weak self] in
                    let ok = Learning.replay(steps)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if ok { Learning.used(cmd); Growth.fastHit(); Sound.named("Pop"); self.done(self.S.t("기억한 대로", "Done (learned)"), cmd) }
                        else { Learning.forget(cmd); self.ask(cmd) }   // screen changed — ask Claude and relearn
                    }
                }
                return
            }
            ask(cmd)
        }
    }

    func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
    func open(_ url: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = cfg.browserApp.isEmpty ? [url] : ["-a", cfg.browserApp, url]
        try? p.run()
    }

    /// Reads the YouTube results page (~1 s) and plays the first video; remembers the list for "play the second one".
    func youtube(_ q: String) {
        hud.show(S.youtubeFind, q, heard: nil, color: amber, speed: 3)
        var req = URLRequest(url: URL(string: "https://www.youtube.com/results?search_query=" + enc(q))!)
        req.setValue(cfg.ko ? "ko-KR,ko" : "en-US,en", forHTTPHeaderField: "Accept-Language")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let list = Butler.parseYouTube(data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
            DispatchQueue.main.async {
                guard let self else { return }
                self.ytList = list
                if let v = list.first { self.open("https://www.youtube.com/watch?v=" + v.id); self.played(self.S.youtubePlay, v.title) }
                else { self.open("https://www.youtube.com/results?search_query=" + self.enc(q)); self.done(self.S.youtube, q) }
            }
        }.resume()
    }
    static func parseYouTube(_ html: String) -> [(id: String, title: String)] {
        guard let re = try? NSRegularExpression(pattern: "\"videoRenderer\":\\{\"videoId\":\"([\\w-]{11})\".*?\"title\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"\\}") else { return [] }
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).prefix(10).compactMap { m in
            guard let a = Range(m.range(at: 1), in: html), let b = Range(m.range(at: 2), in: html) else { return nil }
            return (String(html[a]), String(html[b]))
        }
    }

    /// Brings the Claude app forward → (finds the named session, or opens a new one) → types into the prompt box → Enter.
    /// Uses Accessibility only: the mouse pointer never moves.
    func claudeMacro(target: String, message: String, newSession: Bool) {
        mode = .busy
        hud.show(S.claudeOpen, message, heard: target.isEmpty ? "Claude" : "\(target) · Claude", color: amber, speed: 3)
        log("claude[\(target)\(newSession ? " new" : "")]: \(message)")
        NSRunningApplication.runningApplications(withBundleIdentifier: Butler.claudeBundle).first?.activate()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            Thread.sleep(forTimeInterval: 0.3)
            guard let app = AX.app(Butler.claudeBundle) else { DispatchQueue.main.async { self.fail(self.S.claudeNotRunning) }; return }
            var wins = AX.windows(app)
            if wins.isEmpty { Thread.sleep(forTimeInterval: 0.4); wins = AX.windows(app) }
            guard var win = wins.first else { DispatchQueue.main.async { self.fail(self.S.claudeNoWindow) }; return }
            if newSession {
                if let b = AX.button(in: win, titled: ["새로 생성", "새 세션", "New session", "New chat", "New"]) {
                    DispatchQueue.main.async { self.hud.show(self.S.claudeNew, message, heard: nil, color: amber, speed: 3) }
                    AX.press(b)
                    Thread.sleep(forTimeInterval: 0.9)
                }
            } else if !target.isEmpty {
                if let (w, item, _) = wins.compactMap({ w in AX.session(w, target).map { (w, $0.0, $0.1) } }).max(by: { $0.2 < $1.2 }) {
                    win = w
                    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                    DispatchQueue.main.async { self.hud.show(self.S.claudeFindSession, (AX.attr(item, "AXTitle") as? String) ?? target, heard: nil, color: amber, speed: 3) }
                    AX.press(item)
                    Thread.sleep(forTimeInterval: 0.6)
                } else {
                    log("session not found: \(target) → typing into the current one")
                }
            }
            guard let box = AX.composer(win) else { DispatchQueue.main.async { self.fail(self.S.claudeNoInput) }; return }
            DispatchQueue.main.async { self.cancelSend = false; self.hud.show(self.S.claudeTyping, message, heard: nil, color: amber, speed: 3) }
            AX.focus(box)
            Thread.sleep(forTimeInterval: 0.15)
            DispatchQueue.main.sync { Hands.paste(message) }   // instant (typing 30 chars/s was the slow part)
            // Last chance: 0.8 s to say “취소 / stop” before Enter.
            DispatchQueue.main.async { self.hud.show(self.S.t("◌ 곧 보냄 · 「취소」 하면 멈춤", "◌ Sending… say “stop” to cancel"), message, heard: nil, color: amber, speed: 3) }
            Thread.sleep(forTimeInterval: 0.8)
            var cancelled = false
            DispatchQueue.main.sync { cancelled = self.cancelSend; self.cancelSend = false }
            if cancelled {
                Hands.key(0, .maskCommand); Thread.sleep(forTimeInterval: 0.05); Hands.key(51)   // ⌘A, delete — clear what we typed
                DispatchQueue.main.async { Sound.named("Pop"); log("claude send cancelled"); self.done(self.S.t("취소", "Cancelled"), message) }
                return
            }
            Hands.key(Hands.enter)
            DispatchQueue.main.async { Sound.named("Pop"); self.done(newSession ? self.S.claudeDelegated : self.S.claudeSent, message) }
        }
    }
    // MARK: confirm before handing work to a full-power Claude session
    // Voices from a TV or a web page must not be able to start work on your computer. Say “응 / 맡겨 / yes”.
    static let protectedApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby", "com.apple.ScriptEditor2", "com.apple.Automator",
        "com.apple.shortcuts", "com.apple.systempreferences", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.apple.SecurityAgent", "com.apple.UserNotificationCenter", "com.apple.coreservices.uiagent", "com.apple.installer",
        "com.apple.dt.Xcode", "com.apple.Console", "com.anthropic.claudefordesktop", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.1password.1password", "com.bitwarden.desktop"]
    var pendingDelegate: (target: String, message: String, newSession: Bool)?
    func askToDelegate(target: String, message: String, newSession: Bool, speakQuestion: Bool = true) {
        guard cfg.confirmDelegate != "never" else { claudeMacro(target: target, message: message, newSession: newSession); return }
        pendingDelegate = (target, message, newSession)
        let where_ = newSession ? S.t("클로드 새 세션", "a new Claude session") : (target.isEmpty ? "Claude" : target)
        log("delegate pending: \(message)")
        guard speakQuestion else { return }
        speak(S.t("\(where_)에 맡길까요?", "Hand this to \(where_)?")) { [weak self] in
            guard let self else { return }
            self.converse(keep: true)
            self.hud.show(self.S.t("◌ 맡길까요? 「응」 / 「아니」", "◌ Hand it over? “yes” / “no”"), message, heard: nil, color: amber)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                if self?.pendingDelegate?.message == message { self?.pendingDelegate = nil; log("delegate expired") }
            }
        }
    }
    /// Returns true if the utterance answered a pending hand-off question.
    func answerPending(_ a: String) -> Bool {
        guard let p = pendingDelegate else { return false }
        let s = Parser.squash(a)
        let yes = ["응", "네", "예", "맡겨", "그래", "좋아", "해", "보내", "ㅇㅇ", "yes", "yeah", "doit", "go", "sure", "ok", "okay"]
        let no = ["아니", "아니야", "취소", "하지마", "됐어", "no", "nope", "cancel", "stop"]
        pendingDelegate = nil
        if no.contains(where: { s.hasPrefix($0) }) || s.contains("말고") || s.contains("하지마") { Sound.named("Pop"); log("delegate cancelled"); converse(keep: true); return true }
        if yes.contains(where: { s.hasPrefix($0) }) { claudeMacro(target: p.target, message: p.message, newSession: p.newSession); return true }
        log("delegate dropped (no clear yes)")
        return false
    }

    func openClaudeSession(_ name: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: Butler.claudeBundle).first?.activate()
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            Thread.sleep(forTimeInterval: 0.3)
            guard let app = AX.app(Butler.claudeBundle) else { return }
            if let (w, item, _) = AX.windows(app).compactMap({ w in AX.session(w, name).map { (w, $0.0, $0.1) } }).max(by: { $0.2 < $1.2 }) {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString); AX.press(item)
                let title = (AX.attr(item, "AXTitle") as? String) ?? name
                DispatchQueue.main.async { self.done(self.S.t("세션 열기", "Opened"), title) }
            } else { DispatchQueue.main.async { self.fail(self.S.t("그 세션을 못 찾았습니다.", "Couldn't find that session.")) } }
        }
    }

    func fail(_ why: String) { speak(why) { [weak self] in self?.converse(keep: true) } }

    func dictate(_ t: String) {
        let s = Parser.squash(t)
        if parser.isBye(t) || parser.isHush(t) || ["그만", "끝", "받아쓰기끝"].contains(s) { Sound.named("Pop"); converse(); return }
        if ["엔터", "보내", "전송", "줄바꿈", "enter", "newline", "send"].contains(s) { Hands.key(Hands.enter); hud.body("⏎"); return }
        if ["지워", "취소", "되돌려", "undo", "deletethat"].contains(s) { Hands.key(6, .maskCommand); hud.body("↶"); return }
        var text = t.split(separator: " ").filter { w in !cfg.fillers.contains(w.trimmingCharacters(in: .punctuationCharacters)) }.joined(separator: " ")
        var enter = false
        for suf in [" 엔터", " 보내", " enter", " send"] where text.lowercased().hasSuffix(suf) { text = String(text.dropLast(suf.count)); enter = true }
        Hands.paste(text + " ")
        if enter { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Hands.key(Hands.enter) } }
    }

    func ask(_ cmd: String) {
        guard brain.installed else { fail(S.noClaude); return }
        mode = .busy
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        hud.show(S.thinking, "…", heard: cmd, color: amber, speed: 3)
        brain.ask(cmd, live: lastLive, frontApp: front, step: { [weak self] label in
            guard let self else { return }
            self.hud.show(self.S.working, label, heard: nil, color: amber, speed: 3)
        }, done: { [weak self] answer in
            guard let self else { return }
            log("brain → \(answer)")
            Memory.exchange(user: cmd, reply: answer)
            if let steps = Learning.replayable(self.brain.lastCommands) {
                self.learnCandidate = (cmd, steps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in   // no “아니” within 12 s → keep it
                    guard let self, let c = self.learnCandidate, c.phrase == cmd else { return }
                    Learning.remember(c.phrase, c.steps); self.learnCandidate = nil
                }
            }
            let spoken = answer.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            self.speak(spoken) {
                self.converse(keep: true)   // leave the answer on screen
                if let p = self.pendingDelegate {
                    self.hud.show(self.S.t("◌ 맡길까요? 「응」 / 「아니」", "◌ Hand it over? “yes” / “no”"), p.message, heard: nil, color: amber)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                        if self?.pendingDelegate?.message == p.message { self?.pendingDelegate = nil; log("delegate expired") }
                    }
                }
            }
        })
    }

    // MARK: greeting / speaking

    func greet() {
        if mode == .speaking { return }
        mode = .speaking
        ear.muted = true
        hud.hideAll(true)
        let text = BootScene.Text(title: cfg.bootTitle, subtitle: cfg.subtitle, hello: cfg.greeting, strings: S, locale: cfg.locale)
        BootScene.play(target: hud.orbCenterOnScreen, text: text, sound: Paths.voiceFile("boot")) { [weak self] in
            guard let self else { return }
            self.hud.hideAll(false)
            self.hud.show(self.S.speaking, self.cfg.greeting, heard: "", speed: 1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.ear.muted = false; self.ear.restart(); self.converse(keep: true) }
        }
        for u in cfg.greetOpen { if let url = URL(string: u) { NSWorkspace.shared.open(url) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.35) { [weak self] in   // when the greeting text is typed out
            guard let self else { return }
            if let f = Paths.voiceFile("greeting") { Mouth.play(f) } else { self.mouth.speak(self.cfg.greeting) {} }
        }
    }

    /// The ear stays open while speaking — if the user starts talking, stop and listen (barge-in).
    func speak(_ text: String, then: @escaping () -> Void) {
        mode = .speaking
        speakingText = text; bargedIn = false
        ear.muted = false; ear.restart()
        hud.show(S.speaking, text, heard: nil, speed: 1.5)
        mouth.speak(text) { [weak self] in
            guard let self else { return }
            self.speakingText = ""
            if self.bargedIn { return }
            self.ignoreUntil = Date().addingTimeInterval(self.bargeAny ? 0 : 0.6)
            self.ear.restart(); then()
        }
    }
    func bargeIn(_ t: String) {
        guard !bargedIn else { return }
        bargedIn = true
        log("barge-in: \(t)")
        mouth.stop()
        speakingText = ""
        ear.markSegmentNow()
        mode = .awake; awakeStarted = Date()
        awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
        whisper.warm()
        hud.show(S.conversing, t, heard: "")
    }
    /// You started talking over its voice through the speakers (louder than its echo): stop and take what you say next.
    func bargeInByVoice() {
        guard !bargedIn else { return }
        bargedIn = true
        log("barge-in: your voice over the speaker")
        mouth.stop()
        speakingText = ""
        ear.restart(); ear.markSegmentNow(back: 1.0)     // Whisper gets the start of what you said too
        mode = .awake; awakeStarted = Date()
        awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
        whisper.warm()
        hud.show(S.conversing, S.speakNow, heard: "")
    }
    /// Don't mistake our own voice (from speakers) for the user.
    func isEcho(_ t: String) -> Bool {
        let a = Parser.squash(t), b = Parser.squash(speakingText)
        if a.count < 2 { return true }
        if b.contains(a) { return true }
        let bs = Set(b), hit = a.filter { bs.contains($0) }.count
        return a.count >= 4 && Double(hit) / Double(a.count) > 0.85
    }
    func done(_ kind: String, _ body: String) {
        hud.show("✓ \(kind)", body, color: lime)
        mode = .awake; awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in if self?.mode == .awake { self?.converse() } }
    }
    /// After starting a video/music, go idle so its audio isn't taken as commands.
    func played(_ kind: String, _ body: String) {
        hud.show("▶ \(kind)", body, color: lime)
        mode = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in if self?.mode == .idle { self?.hud.idle() } }
    }
    func goIdle() { mode = .idle; hud.idle() }
    func shutdown() { whisper.stop(); brain.stop(); mouth.stop(); control.stop() }
}
