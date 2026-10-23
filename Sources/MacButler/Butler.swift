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
    let router: Router
    var lastRouted: (said: String, at: Date)?
    var brainSteps = 0                    // tool steps the brain has taken this turn (router may only overtake it at 0)
    let hud = HUD()
    let mouth: Mouth
    let brain: Thinker
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
    var spokeAt = Date.distantPast        // when it last stopped talking (finished or interrupted)
    var lastSpoken = ""                   // its last spoken answer — its echo can lead the next recording
    var lastMedia: (play: Bool, at: Date)?
    var lastSite: (label: String, url: String, at: Date)?
    // What it opened for you (this run): page hosts and apps it started — 「창 다 꺼」 closes exactly these.
    var openedHosts: Set<String> = []
    var openedApps: Set<String> = []
    static let neverClose: Set<String> = ["Claude", "Finder", "Terminal", "iTerm2", "Xcode", "Visual Studio Code", "Cursor", "Mac Butler", "MacButler"]   // 「쿠팡에서 맥미니」 → then just 「M6 찾아」 stays on Coupang
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
        Utterances.enabled = cfg.keepAudio
                // Command words help Apple's recognizer get them right from the first partial (Jarhead does the same).
        let commandWords = cfg.ko ? ["클로드", "엔터", "받아써", "그만", "유튜브", "쿠팡", "네이버", "구글", "검색해", "틀어", "재생", "멈춰", "다음 영상",
                                     "창 다 꺼", "닫아", "뒤로 가", "화면 꺼", "다시 틀어", "최저가", "맥미니"]
                                  : ["Claude", "enter", "stop", "YouTube", "search", "play", "pause", "next video", "close", "go back"]
        ear = Ear(locale: cfg.locale, hints: Array((cfg.wakes + cfg.greets + commandWords + cfg.customWords).prefix(100)), inputUID: cfg.inputDevice)
        mouth = Mouth(cfg: cfg)
        brain = Brains.make(cfg)
        router = Router(cfg: cfg)
        whisper = Whisper(model: cfg.whisperModelPath, binary: cfg.whisperBinary, language: cfg.lang,
                          prompt: String(((cfg.wakes + [cfg.user, "Claude", "YouTube"] + cfg.customWords).joined(separator: ", ") + ".").prefix(500)))
    }

    func start() {
        hud.showIdleOrb = cfg.showIdleOrb
        ear.silenceSec = cfg.silenceSec
        ear.onLevel = { [weak self] v in
            guard let self else { return }
            self.hud.orb.level(v)
            self.mouth.echo.listen(v)
            if self.mode == .speaking, !self.bargeAny, self.cfg.bargeIn != "wake", self.mouth.echo.isUser(v, voicing: self.ear.voicing) { self.bargeInByVoice() }
        }
        ear.onPartial = { [weak self] t in self?.partial(t) }
        ear.onUtterance = { [weak self] t, a in self?.utterance(t, audio: a) }
        brain.warm()
        router.warm()
        Growth.sweep()
        Timers.onFire = { [weak self] label in self?.timerFired(label) }
        Timers.restore()
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
    lazy var control = ControlSocket(handler: { [weak self] cmd, text in self?.signal(cmd, text) },
                                     respond: { [weak self] cmd, text in
                                         guard let self else { return cmd == "delegate" ? "pending" : "ask" }
                                         return cmd == "delegate" ? self.delegateFromBrain(text) : self.confirmAction(text)
                                     })
    private func listenForSignals() { control.start() }
    func signal(_ cmd: String, _ text: String) {
        switch cmd {
        case "type":
            if cfg.brainAccess != "full", let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, Butler.protectedApps.contains(b) || b == Bundle.main.bundleIdentifier {
                log("blocked typing into protected app \(b)"); return
            }
            if cfg.brainAccess != "full", AX.focusedIsSecure() { log("blocked typing into a password field"); return }
            // A line break typed into a chat box or form is Enter — it would send/submit without the send check.
            let line = cfg.brainAccess == "full" ? text : text.replacingOccurrences(of: #"[\r\n\u{2028}\u{2029}]+"#, with: " ", options: .regularExpression)
            DispatchQueue.global().async { Hands.typeVisible(line) }
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
            if self.mode == .dictation { self.dictate(full) } else { self.byHold = true; self.handle(cmd); self.byHold = false }
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
            // …but not for a stray word from someone else in the room ("할게"): a real command, the wake word, or a full sentence.
            if brain.busy, parser.wakeRange(t) != nil || parser.parse(a, hasYouTubeList: !ytList.isEmpty) != .none || Parser.squash(a).count >= 8 {
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
        let apple = dropEcho(apple)
        lastLive = parser.stripWake(apple)
        whisper.transcribe(audio, fallback: apple) { [weak self] full in
            guard let self else { return }
            self.studyWords(whisper: full, live: apple)
            var t = self.dropEcho(full)
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
        if pendingAction != nil, answerAction(cmd) { return }
        if pendingDelegate != nil, answerPending(cmd) { return }
        let q = Parser.squash(cmd)
        if learnCandidate != nil, ["아니", "틀렸", "그게아니", "안됐", "잘못", "no", "wrong"].contains(where: { q.hasPrefix($0) }) {
            log("not learning: \(learnCandidate!.phrase)"); learnCandidate = nil
        }
        if let r = lastRouted, Date().timeIntervalSince(r.at) < 20, ["아니", "틀렸", "그게아니", "no", "wrong"].contains(where: { q.hasPrefix($0) }) {
            Aliases.forget(r.said); lastRouted = nil; log("forgot alias: \(r.said)")
        }
        let intent = parser.parse(cmd, hasYouTubeList: !ytList.isEmpty)
        log("intent: \(intent)")
        switch intent {
        case .greet: greet()
        case .dictation:
            mode = .dictation
            speak(S.dictationStart) { [weak self] in guard let self else { return }; self.mode = .dictation; self.hud.show(self.S.dictation, "", color: lime) }
        case .enter: Hands.key(Hands.enter); done(S.key, "⏎")
        case .hush:
            // Nothing of ours to silence but a video is playing → "멈춰" means the video.
            // (Right after it was talking, "멈춰" was meant for its voice — that's already stopped.)
            if Date().timeIntervalSince(spokeAt) > 3, AudioDevices.outputBusy(cfg.outputDevice, micUID: cfg.inputDevice) == true { media(play: false) } else { converse() }
        case .media(let play): media(play: play)
        case .mediaNext:
            Hands.mediaKey(17)            // ⏭ — YouTube skips to the next video
            played(S.t("다음 영상", "Next"), "⏭")
        case .browser(let what):
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            guard ["Safari", "Google Chrome", "Arc", "Microsoft Edge", "Firefox", "Whale", "Naver Whale"].contains(front) else { ask(cmd); return }
            switch what {
            case "back": Hands.key(33, .maskCommand)        // ⌘[
            case "forward": Hands.key(30, .maskCommand)     // ⌘]
            default: Hands.key(15, .maskCommand)            // ⌘R
            }
            done(front, what == "back" ? S.t("뒤로", "Back") : what == "forward" ? S.t("앞으로", "Forward") : S.t("새로고침", "Reloaded"))
        case .volume(let set, let delta, let mute):
            let script = mute ? "set volume output muted true"
                : set.map { "set volume output volume \($0) without output muted" }
                ?? "set volume output volume ((output volume of (get volume settings)) + \(delta)) without output muted"
            var err: NSDictionary?; NSAppleScript(source: script)?.executeAndReturnError(&err)
            let now = NSAppleScript(source: "output volume of (get volume settings)")?.executeAndReturnError(&err).int32Value ?? 0
            done(S.t("소리", "Volume"), mute ? S.t("음소거", "Muted") : "\(now)")
        case .clock(let date):
            let f = DateFormatter(); f.locale = Locale(identifier: cfg.locale)
            f.dateFormat = date ? (cfg.ko ? "M월 d일 EEEE" : "EEEE, MMMM d") : (cfg.ko ? "a h시 m분" : "h:mm a")
            let line = cfg.ko ? "\(cfg.user.isEmpty ? "" : cfg.user + ", ")\(date ? "오늘은 " : "지금은 ")\(f.string(from: Date()))입니다." : (date ? "Today is " : "It's ") + f.string(from: Date()) + "."
            speak(line) { [weak self] in self?.converse(keep: true) }
        case .timer(let secs, let label):
            let at = Date().addingTimeInterval(TimeInterval(secs))
            Timers.add(at: at, label: label)
            let f = DateFormatter(); f.locale = Locale(identifier: cfg.locale); f.dateFormat = cfg.ko ? "a h:mm" : "h:mm a"
            let span = secs < 3600 ? (secs % 60 == 0 ? S.t("\(secs / 60)분", "\(secs / 60) min") : S.t("\(secs / 60)분 \(secs % 60)초", "\(secs / 60)m \(secs % 60)s")) : f.string(from: at)
            Sound.named("Pop")
            done(S.t("타이머", "Timer"), (label.isEmpty ? "" : label + " · ") + span + S.t(" 뒤에 알려 드릴게요", " — I'll tell you"))
        case .cancelTimers:
            let n = Timers.cancelAll(); done(S.t("타이머", "Timer"), S.t("\(n)개 취소", "\(n) cancelled"))
        case .map(let place):
            open("https://map.naver.com/p/search/" + enc(place)); done(S.t("지도", "Map"), place)
        case .routine(let name):
            let steps = Routines.all[name] ?? []
            log("routine \(name): \(steps)")
            handle(steps.joined(separator: " 그리고 "))       // runs as one multi-command
            hud.show("◉ " + name, steps.joined(separator: " → "), heard: nil, color: lime, speed: 2)
        case .makeRoutine(let name, let steps):
            Routines.save(name, steps)
            speak(cfg.ko ? "앞으로 「\(name)」 하시면 \(steps.joined(separator: ", ")) 할게요." : "From now on, “\(name)” will \(steps.joined(separator: ", ")).") { [weak self] in self?.converse(keep: true) }
        case .badRoutine(let name):
            speak(cfg.ko ? "「\(name)」 루틴에는 바로 할 수 있는 일만 넣을 수 있어요. 열기, 틀기, 소리, 지도, 타이머 같은 거요." : "Routines can only hold quick actions — open, play, volume, maps, timers.") { [weak self] in self?.converse(keep: true) }
        case .forgetRoutine(let name):
            Routines.remove(name); done(S.t("루틴 지움", "Routine removed"), name)
        case .multi(let parts):
            log("multi: \(parts)")
            hud.show(S.t("◉ 차례로 하는 중", "◉ Doing them in order"), parts.joined(separator: " → "), heard: nil, color: amber, speed: 3)
            for (i, p) in parts.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.6) { [weak self] in self?.handle(p) }
            }
        case .closeOpened:
            let n = closeOpened()
            if n == 0, AudioDevices.outputBusy(cfg.outputDevice, micUID: cfg.inputDevice) == true { media(play: false); return }   // nothing of ours open, but something's playing
            if n > 0 { done(S.t("닫음", "Closed"), S.t("열어 둔 것 \(n)개", "\(n) things it opened")) } else { done(S.t("닫을 게 없음", "Nothing to close"), S.t("이번에 연 창이 없어요", "Nothing opened this time")) }
        case .displayOff:
            done(S.t("화면 끔", "Display off"), "🌙")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["displaysleepnow"]; try? p.run()
            }
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
            open("https://www.youtube.com/watch?v=" + ytList[n - 1].id); played("\(S.youtube) #\(n)", ytList[n - 1].title); ensurePlaying()
        case .search(let q) where lastSite.map({ Date().timeIntervalSince($0.at) < 120 }) == true:
            let s = lastSite!; lastSite = (s.label, s.url, Date()); open(s.url + enc(q)); done(s.label, q)
        case .search(let q): open((cfg.ko ? "https://www.google.com/search?hl=ko&q=" : "https://www.google.com/search?q=") + enc(q)); done(S.searched, q)
        case .remember(let note): Memory.note(note); Sound.named("Pop"); done(S.t("기억함", "Remembered"), note)
        case .web(let label, let q, let url):
            if !q.isEmpty { lastSite = (label, url, Date()) }
            open(q.isEmpty ? url : url + enc(q)); done(label, q.isEmpty ? url : q)
        case .closeTabs(let label, let host):
            let n = closeTabs(host)
            if n > 0 { done(S.t("창 닫음", "Closed"), "\(label) ×\(n)") } else { done(S.t("닫을 창 없음", "Nothing to close"), label) }
        case .openApp(let spoken, let app):
            noteOpened(app: app)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", app]; try? p.run()
            done(S.opened, spoken)
        case .none:
            if let canon = Aliases.lookup(cmd), isQuick(canon) { log("alias: \(cmd) → \(canon)"); lastRouted = (cmd, Date()); handle(canon); return }
            Growth.miss(cmd, front: NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
            if let steps = Learning.lookup(cmd) {      // learned before → instant, no Claude call
                brainCommand = cmd; brainByHold = byHold
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
            routeOrAsk(cmd)
        }
    }

    /// What Claude should know without spending a tool call: the page in front (if a browser) and what Mac Butler opened.
    func screenContext(_ front: String) -> String {
        var lines: [String] = []
        if ["Safari", "Google Chrome"].contains(front) {
            let src = front == "Safari" ? "tell application \"Safari\" to if (count of windows) > 0 then return (name of current tab of front window) & \" | \" & (URL of current tab of front window)"
                                        : "tell application \"Google Chrome\" to if (count of windows) > 0 then return (title of active tab of front window) & \" | \" & (URL of active tab of front window)"
            var err: NSDictionary?
            if let page = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue, !page.isEmpty {
                lines.append(S.t("앞에 보이는 페이지: ", "Page in front: ") + String(page.prefix(200)))
            }
        }
        if !openedHosts.isEmpty || !openedApps.isEmpty {
            lines.append(S.t("자비스가 연 것: ", "Opened by Mac Butler: ") + (openedHosts.sorted() + openedApps.sorted()).joined(separator: ", "))
        }
        return lines.map { "[" + $0 + "]" }.joined(separator: "\n")
    }
    func noteOpened(url: String) {
        if let h = URL(string: url)?.host(percentEncoded: true), Butler.safeHost(h) { openedHosts.insert(h.lowercased()) }
    }
    /// Hosts end up inside AppleScript (closeTabs) — only plain host names, nothing that could break out of the quotes.
    static func safeHost(_ h: String) -> Bool { h.count < 254 && h.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil }
    /// An app it starts (not one that was already running) — so closing it later never takes away your own window.
    func noteOpened(app: String) {
        guard !Butler.neverClose.contains(app), !NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == app }) else { return }
        openedApps.insert(app)
    }
    /// What Claude opened in its last turn (`jax open-url …`, `jax open-app …`).
    func noteOpened(fromBrain cmds: [String]) {
        for c in cmds {
            if let r = c.range(of: #"open-url\s+"?(https?://[^\s"']+)"#, options: .regularExpression) {
                let u = String(c[r]).replacingOccurrences(of: #"open-url\s+"?"#, with: "", options: .regularExpression)
                noteOpened(url: u)
            }
            if let r = c.range(of: #"open-app\s+"?([^"]+?)"?\s*$"#, options: .regularExpression) {
                noteOpened(app: String(c[r]).replacingOccurrences(of: #"open-app\s+"?"#, with: "", options: .regularExpression).replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces))
            }
        }
    }
    /// 「창 다 꺼」: the pages it opened (by exact host — not Gmail because it opened a Google search) and the apps it
    /// started. Claude, Finder, terminals and editors are never touched.
    func closeOpened() -> Int {
        var n = 0
        for h in openedHosts { n += closeTabs("://" + h + "/", frontFirst: false) }
        for app in openedApps where !Butler.neverClose.contains(app) {
            for a in NSWorkspace.shared.runningApplications where a.localizedName == app { if a.terminate() { n += 1 } }
        }
        log("closed what it opened: \(n) (hosts \(openedHosts.sorted()), apps \(openedApps.sorted()))")
        openedHosts = []; openedApps = []
        return n
    }
    /// Closes the browser tabs on that site — the front window first; if none there, any window.
    /// (YouTube Studio and the like are left alone. Only browsers already running are touched.)
    func closeTabs(_ host: String, frontFirst: Bool = true) -> Int {
        guard host.range(of: #"^[A-Za-z0-9.:/-]+$"#, options: .regularExpression) != nil else { log("close tabs: refused odd host \(host.debugDescription)"); return 0 }
        var total = 0
        for (bundle, app) in [("com.google.Chrome", "Google Chrome"), ("com.apple.Safari", "Safari")]
        where !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty {
            for scope in frontFirst ? ["{front window}", "windows"] : ["windows"] {
                let src = """
                tell application "\(app)"
                  if (count of windows) is 0 then return 0
                  set n to 0
                  repeat with w in \(scope)
                    repeat with i from (count of tabs of w) to 1 by -1
                      set u to URL of tab i of w
                      if u contains "\(host)" and u does not contain "studio." then
                        close tab i of w
                        set n to n + 1
                      end if
                    end repeat
                  end repeat
                  return n
                end tell
                """
                var err: NSDictionary?
                let n = Int(NSAppleScript(source: src)?.executeAndReturnError(&err).int32Value ?? 0)
                if let err { log("close tabs (\(app)): \(err[NSAppleScript.errorMessage] ?? err)") }
                total += n
                if n > 0 { break }
            }
        }
        log("closed \(total) \(host) tab(s)")
        return total
    }
    /// Pause / resume the video or music that's playing (the ⏯ key, so it works whichever window is in front).
    func media(play: Bool) {
        // ⏯ toggles — press it only when it changes something. Can't tell (headset)? Assume it's needed,
        // but never twice within 5 s for the same wish (a paused player can take a moment to go quiet).
        let busy = AudioDevices.outputBusy(cfg.outputDevice, micUID: cfg.inputDevice) ?? !play
        let repeatWish = lastMedia.map { $0.play == play && Date().timeIntervalSince($0.at) < 5 } ?? false
        if play != busy, !repeatWish { Hands.playPause(); lastMedia = (play, Date()) }
        if play { played(S.t("다시 재생", "Resumed"), "▶︎") } else { done(S.t("멈춤", "Paused"), "⏸") }
    }
    /// Quick commands only — what the router / aliases may trigger.
    func isQuick(_ canon: String) -> Bool {
        switch parser.parse(canon, hasYouTubeList: !ytList.isEmpty) {
        case .none, .claude, .type, .dictation, .remember, .makeRoutine, .badRoutine, .forgetRoutine, .greet, .bye, .hush, .enter: return false
        default: return true
        }
    }
    /// Loose phrasing: the brain starts right away and, at the same time, the fast router (2–4 s) tries to map the
    /// sentence to a quick command. If the router wins before the brain has touched anything, the brain is
    /// cancelled quietly and the quick command runs; otherwise the brain just carries on — no extra wait either way.
    /// What the router mapped is remembered, so the same sentence is instant next time.
    func routeOrAsk(_ cmd: String) {
        ask(cmd)
        guard router.enabled, cmd.count <= 60, brain.installed else { return }
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        router.route(cmd, front: front, timeout: 6) { [weak self] canon in
            guard let self, let canon, self.isQuick(canon) else { return }
            guard self.mode == .busy, self.brainCommand == cmd, self.brainSteps == 0, self.brain.busy else {
                log("router late (brain already acting): \(cmd) → \(canon)"); Aliases.learn(cmd, canon); return
            }
            self.brain.cancel(silently: true)
            Aliases.learn(cmd, canon); self.lastRouted = (cmd, Date())
            self.mode = .awake
            self.handle(canon)
        }
    }
    func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
    func open(_ url: String) {
        noteOpened(url: url)
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
                if let v = list.first { self.open("https://www.youtube.com/watch?v=" + v.id); self.played(self.S.youtubePlay, v.title); self.ensurePlaying() }
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

    // MARK: send / pay / post / delete — the hands ask before they press (see jax `confirmIrreversible`)
    var brainCommand = ""          // what the user said that the brain (or a learned replay) is acting on right now
    var brainByHold = false        // …and whether they said it holding the hotkey (no TV can do that)
    var byHold = false             // set while handling a push-to-talk command
    var pendingAction: (kind: String, bundle: String, what: String, args: [String], at: Date)?
    static let askedFor: [String: [String]] = [
        "send": ["보내", "전송", "송신", "send"],
        "pay": ["결제", "구매", "구입", "주문", "송금", "이체", "pay", "buy", "purchase", "order", "checkout"],
        "post": ["게시", "올려", "올리", "업로드", "등록", "post", "publish", "upload", "tweet"],
        "delete": ["삭제", "지워", "지우", "비워", "delete", "remove", "trash"]]
    /// Called on the socket thread (synchronously) when a tool is about to press something irreversible.
    /// "yes" only when the user's own words asked for that kind of action; otherwise it's held for a spoken yes.
    func confirmAction(_ text: String) -> String {
        let p = text.components(separatedBy: "\u{1F}")
        guard p.count >= 4 else { return "ask" }
        let kind = p[0]
        // Pressed without asking only when the user held the hotkey and said it (a TV or a video can say "보내",
        // it can't hold the key). Spoken the normal way, it asks once.
        if cfg.confirmDelegate != "always", brainByHold, Butler.userAskedFor(kind, brainCommand) {
            log("confirm \(kind): asked for (hotkey) in 「\(brainCommand)」 → \(p[2])"); return "yes"
        }
        pendingAction = (kind, p[1], p[2], Array(p[3...]), Date())
        log("confirm \(kind): holding \(p[2]) for a yes")
        return "ask"
    }
    /// A Claude Code session can do far more than the safe brain, so work the brain wants to hand over always waits for
    /// a spoken yes, whatever `confirmDelegate` says — the brain may have been talked into it by a page title or a link.
    /// ("바로 실행" applies only to a hand-off the user asked for directly — the `.claude` quick command.)
    func delegateFromBrain(_ text: String) -> String {
        let parts = text.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[1].isEmpty else { return "pending" }
        let here = parts[0] == "." || parts[0] == "지금" || parts[0].lowercased() == "here"
        pendingDelegate = (here ? "" : parts[0], parts[1], parts[0].isEmpty)
        log("delegate pending (needs a yes): \(parts[1])")
        return "pending"
    }
    static func userAskedFor(_ kind: String, _ said: String) -> Bool {
        let s = said.lowercased()
        return (askedFor[kind] ?? []).contains(where: s.contains)
    }
    func showPendingAction(_ what: String) {
        hud.show(S.t("◌ 누를까요? 「응」 / 「아니」", "◌ Press it? “yes” / “no”"), what, heard: nil, color: amber)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            if let a = self?.pendingAction, Date().timeIntervalSince(a.at) >= 25 { self?.pendingAction = nil; log("held action expired") }
        }
    }
    /// Returns true if the utterance answered “press it?”.
    func answerAction(_ a: String) -> Bool {
        guard let p = pendingAction else { return false }
        pendingAction = nil
        guard Date().timeIntervalSince(p.at) < 60 else { return false }
        let s = Parser.squash(a)
        let yes = ["응", "네", "예", "그래", "좋아", "눌러", "해", "보내", "결제", "올려", "지워", "ㅇㅇ", "yes", "yeah", "doit", "go", "sure", "ok", "okay", "send"]
        let no = ["아니", "아니야", "취소", "하지마", "됐어", "no", "nope", "cancel", "stop"]
        if no.contains(where: { s.hasPrefix($0) }) || s.contains("말고") { Sound.named("Pop"); log("held action cancelled"); done(S.t("취소", "Cancelled"), p.what); return true }
        guard yes.contains(where: { s.hasPrefix($0) }) else { log("held action dropped (no clear yes)"); return false }
        // Only in the app it was meant for — if the screen moved on, pressing now could hit something else.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == p.bundle else {
            fail(S.t("화면이 바뀌어서 누르지 않았습니다.", "The screen changed, so I didn't press it.")); return true
        }
        log("held action confirmed: \(p.what)")
        DispatchQueue.global().async { [weak self] in
            let proc = Process()
            proc.executableURL = Paths.tools.appendingPathComponent("jax")
            proc.arguments = p.args
            var env = ProcessInfo.processInfo.environment
            env["MACBUTLER_SAFE"] = "1"; env["MACBUTLER_CONFIRMED"] = "1"; env["MACBUTLER_BUNDLE"] = Bundle.main.bundleIdentifier ?? ""
            proc.environment = env
            proc.standardOutput = FileHandle.nullDevice; proc.standardError = FileHandle.nullDevice
            let ok = (try? proc.run()) != nil && { proc.waitUntilExit(); return proc.terminationStatus == 0 }()
            DispatchQueue.main.async {
                guard let self else { return }
                if ok { Sound.named("Pop"); self.done(self.S.t("눌렀음", "Done"), p.what) }
                else { self.fail(self.S.t("누르지 못했습니다.", "Couldn't press it.")) }
            }
        }
        return true
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
        brainCommand = cmd; brainByHold = byHold; pendingAction = nil
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        hud.show(S.thinking, "…", heard: cmd, color: amber, speed: 3)
        Sound.soft("Purr")      // heard you — thinking (so the wait isn't silent)
        brainSteps = 0
        brain.ask(cmd, live: lastLive, frontApp: front, context: screenContext(front), step: { [weak self] label in
            guard let self else { return }
            self.brainSteps += 1
            self.hud.show(self.S.working, label, heard: nil, color: amber, speed: 3)
        }, done: { [weak self] answer in
            guard let self else { return }
            log("brain → \(answer)")
            Memory.exchange(user: cmd, reply: answer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.brain.warm() }   // swap in a fresh brain now if it got heavy, not on the next question
            self.noteOpened(fromBrain: self.brain.lastCommands)
            let correction = ["아니", "그게 아니", "no ", "not "].contains { cmd.lowercased().hasPrefix($0) }
            if !correction, let steps = Learning.replayable(self.brain.lastCommands) {
                self.learnCandidate = (cmd, steps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in   // no “아니” within 12 s → keep it
                    guard let self, let c = self.learnCandidate, c.phrase == cmd else { return }
                    Learning.remember(c.phrase, c.steps); self.learnCandidate = nil
                }
            }
            let spoken = answer.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            self.speak(spoken) {
                if Parser.startedMedia(answer) { self.played(self.S.youtubePlay, spoken); return }
                self.converse(keep: true)   // leave the answer on screen
                if let a = self.pendingAction { self.showPendingAction(a.what) }
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
        lastSpoken = text
        mode = .speaking
        speakingText = text; bargedIn = false
        ear.muted = false; ear.restart()
        hud.show(S.speaking, text, heard: nil, speed: 1.5)
        mouth.speak(text) { [weak self] in
            guard let self else { return }
            self.speakingText = ""
            self.spokeAt = Date()
            if self.bargedIn { return }
            self.ignoreUntil = Date().addingTimeInterval(self.bargeAny ? 0 : 0.6)
            self.ear.restart(); then()
        }
    }
    func bargeIn(_ t: String) {
        guard !bargedIn else { return }
        bargedIn = true
        log("barge-in: \(t)")
        mouth.stop(); spokeAt = Date()
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
        mouth.stop(); spokeAt = Date()
        speakingText = ""
        ear.restart(); ear.markSegmentNow(back: 0.6)     // Whisper gets the start of what you said (not much of its own voice)
        mode = .awake; awakeStarted = Date()
        awakeUntil = Date().addingTimeInterval(cfg.followUpSec)
        whisper.warm()
        hud.show(S.conversing, S.speakNow, heard: "")
    }
    /// "대표님. 아니 아멜리아 먹방…" — right after you cut in, the recording can start with the tail of its own answer.
    /// Only its way of addressing you is dropped: your own first words may well repeat what it said ("유튜브 영상…").
    func dropEcho(_ t: String) -> String {
        guard Date().timeIntervalSince(spokeAt) < 20, !lastSpoken.isEmpty else { return t }
        let me = Parser.squash(cfg.user)
        guard !me.isEmpty else { return t }
        var words = t.split(separator: " ").map(String.init)
        var dropped = 0
        while let w = words.first, Parser.squash(w) == me, words.count > 1 { words.removeFirst(); dropped += 1 }
        if dropped > 0 { log("dropped its own voice: \(dropped) word(s)") }
        return words.joined(separator: " ")
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
    /// Safari blocks autoplay with sound by default, so a YouTube page can open paused. If nothing is playing
    /// after 3 s and the browser is in front, press YouTube's play key (k) — once, never when it's already playing.
    func ensurePlaying() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, AudioDevices.outputBusy(self.cfg.outputDevice, micUID: self.cfg.inputDevice) == false,
                  let front = NSWorkspace.shared.frontmostApplication?.localizedName,
                  front == (self.cfg.browserApp.isEmpty ? front : self.cfg.browserApp) || ["Safari", "Google Chrome"].contains(front) else { return }
            log("video didn't start (autoplay blocked?) → pressing play")
            Hands.key(40)      // k = YouTube play/pause
        }
    }
    /// A timer went off: chime, card, and say it — unless it's busy talking or working, then just chime and show it.
    func timerFired(_ label: String) {
        Sound.named("Glass"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Sound.named("Glass") }
        let line = cfg.ko ? "\(cfg.user.isEmpty ? "" : cfg.user + ", ")\(label.isEmpty ? "시간 됐습니다." : label + " 시간입니다.")"
                          : (label.isEmpty ? "Time's up." : "Time for \(label).")
        hud.show(S.t("⏰ 타이머", "⏰ Timer"), line, heard: "", color: amber, speed: 2)
        guard mode == .idle || mode == .awake else { return }
        speak(line) { [weak self] in self?.goIdle() }
    }
    func goIdle() { mode = .idle; hud.idle() }
    func shutdown() { whisper.stop(); brain.stop(); router.stop(); mouth.stop(); control.stop() }
}
