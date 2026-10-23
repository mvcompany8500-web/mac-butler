// The conductor: listens, decides, acts, speaks.
import AppKit

final class Butler {
    enum Mode { case idle, awake, dictation, busy, speaking }
    var mode: Mode = .idle
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
    static let claudeBundle = "com.anthropic.claudefordesktop"

    init(cfg: Config) {
        self.cfg = cfg
        S = Strings(ko: cfg.ko, name: cfg.assistantName)
        parser = Parser(cfg: cfg)
        ear = Ear(locale: cfg.locale, hints: cfg.wakes + cfg.greets + (cfg.ko ? ["클로드", "엔터", "받아써", "그만"] : ["Claude", "enter", "stop"]))
        mouth = Mouth(cfg: cfg)
        brain = Brain(cfg: cfg)
        whisper = Whisper(model: cfg.whisperModelPath, binary: cfg.whisperBinary, language: cfg.ko ? "ko" : "en",
                          prompt: (cfg.wakes + [cfg.user, "Claude", "YouTube"]).joined(separator: ", ") + ".")
    }

    func start() {
        hud.showIdleOrb = cfg.showIdleOrb
        ear.silenceSec = cfg.silenceSec
        ear.onLevel = { [weak self] v in self?.hud.orb.level(v) }
        ear.onPartial = { [weak self] t in self?.partial(t) }
        ear.onUtterance = { [weak self] t, a in self?.utterance(t, audio: a) }
        brain.warm()
        listenForSignals()
        do { try ear.start() } catch { log("mic failed: \(error)"); hud.show("⚠︎", S.micError, color: amber) }
        if !brain.installed { hud.show("⚠︎", S.noClaude, color: amber) }
        log("ready · whisper=\(whisper.available) claude=\(brain.installed) tts=\(cfg.tts)")
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.mode == .awake else { return }
            if self.awakeStarted.map({ Date().timeIntervalSince($0) > self.cfg.maxUtteranceSec }) == true { self.awakeStarted = nil; self.ear.forceFlush() }
            if Date() > self.awakeUntil { self.goIdle() }
        }
    }

    /// Local signals from the bundled tools (`butler`). Same-machine only.
    private func listenForSignals() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.macbutler.type"), object: nil, queue: .main) { n in
            guard let t = n.object as? String else { return }
            DispatchQueue.global().async { Hands.typeVisible(t) }
        }
        dnc.addObserver(forName: .init("com.macbutler.delegate"), object: nil, queue: .main) { [weak self] n in
            let parts = (n.object as? String ?? "").split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let self, parts.count == 2, !parts[1].isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.claudeMacro(target: parts[0], message: parts[1], newSession: parts[0].isEmpty) }
        }
        dnc.addObserver(forName: .init("com.macbutler.settings"), object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            if (n.object as? String) == "close" { SettingsWindow.window?.close() } else { SettingsWindow.show(cfg: self.cfg) }
        }
        // Text instead of voice — for testing and screen recordings.
        dnc.addObserver(forName: .init("com.macbutler.say"), object: nil, queue: .main) { [weak self] n in
            guard let self, let t = n.object as? String else { return }
            log("text command: \(t)")
            if self.parser.isGreeting(t) { self.greet(); return }
            if self.mode == .idle { self.mode = .awake; self.awakeUntil = Date().addingTimeInterval(self.cfg.followUpSec) }
            self.utterance(t, audio: [])
        }
    }

    // MARK: listening

    /// Same as saying the wake word (hotkey). While speaking it interrupts; while awake it ends the conversation.
    func manualWake() {
        guard enabled else { return }
        switch mode {
        case .idle: whisper.warm(); converse(chime: true)
        case .speaking: mouth.stop(); speakingText = ""; bargedIn = true; ear.restart(); converse(chime: true)
        case .awake: NSSound(named: "Pop")?.play(); goIdle()
        case .busy: brain.cancel()
        case .dictation: converse(chime: true)
        }
    }

    func partial(_ t: String) {
        guard enabled else { return }
        switch mode {
        case .idle:
            if parser.isGreeting(t) { greet(); return }
            if let r = parser.wakeRange(t) {        // react the moment the wake word appears
                whisper.warm()
                NSSound(named: NSSound.Name(cfg.chime))?.play()
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
            if !speakingText.isEmpty, !isEcho(t) { bargeIn(t) }
        case .busy: break
        }
    }

    func utterance(_ t: String, audio: [Float]) {
        guard enabled else { return }
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
            if parser.wakeRange(t) != nil, parser.isHush(parser.stripWake(t)) || parser.isBye(parser.stripWake(t)) { brain.cancel() }
        case .speaking:
            if !speakingText.isEmpty, !isEcho(t) {
                bargeIn(t); awakeStarted = nil
                refine(audio, t) { [weak self] full in self?.command(full) }
            }
        }
    }

    /// Apple's text is shown instantly; the command itself uses Whisper's more accurate text.
    func refine(_ audio: [Float], _ apple: String, then: @escaping (String) -> Void) {
        if !audio.isEmpty && whisper.available { hud.show(S.transcribing, apple, speed: 2) }
        whisper.transcribe(audio, fallback: apple, done: then)
    }
    func command(_ full: String) {
        guard mode != .busy, mode != .speaking else { return }
        let cmd = parser.stripWake(full)
        if cmd.isEmpty { converse(chime: true) } else { handle(cmd) }
    }

    /// Stay in conversation: no wake word needed until `followUpSec` of silence or "that's all".
    func converse(chime: Bool = false, keep: Bool = false) {
        if chime { NSSound(named: NSSound.Name(cfg.chime))?.play() }
        mode = .awake; awakeStarted = nil
        awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
        whisper.warm()
        if keep { hud.setStatus(S.conversing) } else { hud.show(S.conversing, S.speakNow) }
    }

    // MARK: acting

    func handle(_ cmd: String) {
        let intent = parser.parse(cmd, hasYouTubeList: !ytList.isEmpty)
        log("intent: \(intent)")
        switch intent {
        case .greet: greet()
        case .dictation:
            mode = .dictation
            speak(S.dictationStart) { [weak self] in guard let self else { return }; self.mode = .dictation; self.hud.show(self.S.dictation, "", color: lime) }
        case .enter: Hands.key(Hands.enter); done(S.key, "⏎")
        case .hush: converse()
        case .bye: NSSound(named: "Pop")?.play(); goIdle()
        case .type(let text): Hands.paste(text); done(S.typed, text)
        case .claude(let target, let message, let newSession): claudeMacro(target: target, message: message, newSession: newSession)
        case .youtube(let q):
            if q.isEmpty { open("https://www.youtube.com/"); played(S.youtube, "YouTube") } else { youtube(q) }
        case .youtubeNth(let n):
            guard n >= 1, n <= ytList.count else { ask(cmd); return }
            open("https://www.youtube.com/watch?v=" + ytList[n - 1].id); played("\(S.youtube) #\(n)", ytList[n - 1].title)
        case .search(let q): open((cfg.ko ? "https://www.google.com/search?hl=ko&q=" : "https://www.google.com/search?q=") + enc(q)); done(S.searched, q)
        case .openApp(let spoken, let app):
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", app]; try? p.run()
            done(S.opened, spoken)
        case .none: ask(cmd)
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
            DispatchQueue.main.async { self.hud.show(self.S.claudeTyping, message, heard: nil, color: amber, speed: 3) }
            AX.focus(box)
            Thread.sleep(forTimeInterval: 0.15)
            Hands.typeVisible(message)
            Thread.sleep(forTimeInterval: 0.25)
            Hands.key(Hands.enter)
            DispatchQueue.main.async { NSSound(named: "Pop")?.play(); self.done(newSession ? self.S.claudeDelegated : self.S.claudeSent, message) }
        }
    }
    func fail(_ why: String) { speak(why) { [weak self] in self?.converse(keep: true) } }

    func dictate(_ t: String) {
        let s = Parser.squash(t)
        if parser.isBye(t) || parser.isHush(t) || ["그만", "끝", "받아쓰기끝"].contains(s) { NSSound(named: "Pop")?.play(); converse(); return }
        if ["엔터", "보내", "전송", "줄바꿈", "enter", "newline", "send"].contains(s) { Hands.key(Hands.enter); hud.body("⏎"); return }
        if ["지워", "취소", "되돌려", "undo", "deletethat"].contains(s) { Hands.key(6, .maskCommand); hud.body("↶"); return }
        var text = t.trimmingCharacters(in: .whitespaces)
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
        brain.ask(cmd, frontApp: front, step: { [weak self] label in
            guard let self else { return }
            self.hud.show(self.S.working, label, heard: nil, color: amber, speed: 3)
        }, done: { [weak self] answer in
            guard let self else { return }
            log("brain → \(answer)")
            let spoken = answer.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            self.speak(spoken) { self.converse(keep: true) }   // leave the answer on screen
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
    func shutdown() { whisper.stop(); brain.stop(); mouth.stop() }
}
