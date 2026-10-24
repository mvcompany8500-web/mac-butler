// Settings live in ~/.macbutler/config.json (override the folder with MACBUTLER_HOME).
// Every key is optional — missing keys fall back to the defaults below.
import Foundation

struct ElevenLabsConfig: Codable {
    var apiKey = ""            // or leave empty and use apiKeyFile / ELEVENLABS_API_KEY env
    var apiKeyFile = ""        // a dotenv file that contains ELEVENLABS_API_KEY=...
    var voiceId = ""
    var model = "eleven_flash_v2_5"
    var speed = 1.0

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), z = ElevenLabsConfig()
        apiKey = (try? c.decode(String.self, forKey: .apiKey)) ?? z.apiKey
        apiKeyFile = (try? c.decode(String.self, forKey: .apiKeyFile)) ?? z.apiKeyFile
        voiceId = (try? c.decode(String.self, forKey: .voiceId)) ?? z.voiceId
        model = (try? c.decode(String.self, forKey: .model)) ?? z.model
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? z.speed
    }
}

struct Config: Codable {
    var language = Config.systemLanguage   // "ko", "en", "ja", "zh", "es", "fr", "de", "pt", "it", "vi", "th", "id" … (default: your Mac's language)
    var activation = "voice"            // "voice": say the wake word (or tap/hold the hotkey) · "hold": only while holding the hotkey — nothing is transcribed otherwise
    var userName = ""                   // how the assistant addresses you, e.g. "대표님", "Tony"
    var assistantName = "Jarvis"
    var wakeWords: [String] = []        // empty → language default
    var greetPhrases: [String] = []     // empty → language default ("아빠 왔어", "daddy's home" …)
    var greetingText = ""               // empty → "어서 오십시오, {user}" / "Welcome home, {user}."
    var bootTitle = "M A C   B U T L E R"
    var bootSubtitle = ""               // empty → "{user}의 개인 비서" / "Personal assistant of {user}" (or a generic line)
    var greetOpen: [String] = []        // URLs to open when greeted

    var brainProvider = "claude-code"   // "claude-code" (default, your Claude subscription) · "codex" (your signed-in Codex CLI) · "aside" (Aside app CLI) · "anthropic" · "openai" · "gemini" · "openrouter" · "groq" · "ollama" · "lmstudio" · "openai-compatible" — keys go in the Keychain (`MacButler --set-key openai`)
    var brainModel = ""                 // model for an API brain, e.g. "gpt-5-mini", "gemini-3-flash", "claude-sonnet-5-5"; empty → provider default / a local server's first model
    var brainBaseURL = ""               // only for "openai-compatible" (or to point a provider elsewhere): https://…/v1, or http://127.0.0.1:…/v1
    var brainEffort = "low"             // codex only: how hard it thinks — "low" (fast, default) · "medium" · "high"
    var claudePath = ""                 // empty → auto-detect `claude`
    var claudeModel = "sonnet"
    var confirmDelegate = "never"       // how boldly it acts: "never" = do it right away (default) · "brain" = ask before Claude hands work on · "always" = ask first, ask when unsure
    var freeMode = false               // 자유 모드: sending, posting, deleting and hand-offs to Claude go without asking — paying always asks
    var freeModeAsked = false          // the one-time 「다음부터는 묻지 않을까요?」 has been asked
    var proRemote = true               // Pro: call this Mac from the phone (only does anything while linked and a member)
    var growTogether = ""              // 「다 같이 키우기」: "" = not asked yet · "together" (share safe learned sentences, take the pack) · "solo" (take the pack only)
    var brainAccess = "safe"            // "safe": fixed tool allowlist, no shell/file writes/web fetch · "full": any Bash (power users)
    var whisperModel = ""               // empty → ~/.macbutler/models/ggml-large-v3-turbo-q8_0.bin
    var whisperServer = ""              // empty → auto-detect `whisper-server`

    var tts = "say"                     // "say" (free macOS voices, default) · "elevenlabs" · "openai" · "azure" · "http" (your own voice server)
    var ttsVoice = ""                   // voice for openai / azure / http, e.g. "alloy", "ko-KR-SunHiNeural"
    var ttsModel = ""                   // openai only; empty → gpt-4o-mini-tts
    var ttsRegion = ""                  // azure only, e.g. "koreacentral"
    var ttsURL = ""                     // http only: https://… (or http://127.0.0.1:…) that turns {"text","voice","language"} into audio
    var sayVoice = ""                   // empty → system voice for the language
    var sayRate = 190
    var elevenLabs = ElevenLabsConfig()

    var inputDevice = ""                // microphone (Core Audio UID); empty = system default
    var outputDevice = ""               // speaker for voice & sounds (Core Audio UID); empty = system default
    var bargeIn = "auto"                // interrupting while it talks: "any" (headphones) · "wake" (speakers: only the wake word / stop words / hotkey) · "auto"
    var browserApp = "Safari"           // every Mac has it; "Google Chrome" etc. also work · "" = your default browser
    var apps: [String: String] = [:]    // extra spoken name → app name, e.g. {"브루": "Vrew"}
    var customWords: [String] = []     // names & jargon you say often — boosts both recognizers (Handy's list is imported automatically)
    var fillerWords: [String] = []     // dropped from dictation; empty → language default
    var silenceSec = 1.5
    var followUpSec = 30.0
    var maxUtteranceSec = 25.0
    var chime = "Tink"
    var pauseInCalls = true             // stop listening while Zoom / FaceTime / Meet … (or Handy) uses the mic
    var router = "on"                   // fast model that maps loose phrasing to quick commands: "on" (= haiku) · "off" · a model id
    var keepAudio = false               // keep the last 30 utterances (audio + text) locally to check recognition
    var showIdleOrb = true
    var hudPosition = "bottomRight"     // where the orb & card sit: "bottomRight" (default) · "bottomLeft" · "top"
    var hotkey = "rightOption"          // tap to wake without speaking: "rightOption", "rightCommand", "none"

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), z = Config()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: k)) ?? def }
        language = v(.language, z.language); activation = v(.activation, z.activation); userName = v(.userName, z.userName); assistantName = v(.assistantName, z.assistantName)
        wakeWords = v(.wakeWords, z.wakeWords); greetPhrases = v(.greetPhrases, z.greetPhrases)
        greetingText = v(.greetingText, z.greetingText); bootTitle = v(.bootTitle, z.bootTitle); bootSubtitle = v(.bootSubtitle, z.bootSubtitle)
        greetOpen = v(.greetOpen, z.greetOpen)
        brainProvider = v(.brainProvider, z.brainProvider); brainModel = v(.brainModel, z.brainModel); brainBaseURL = v(.brainBaseURL, z.brainBaseURL); brainEffort = v(.brainEffort, z.brainEffort)
        claudePath = v(.claudePath, z.claudePath); claudeModel = v(.claudeModel, z.claudeModel); brainAccess = v(.brainAccess, z.brainAccess); confirmDelegate = v(.confirmDelegate, z.confirmDelegate); freeMode = v(.freeMode, z.freeMode); freeModeAsked = v(.freeModeAsked, z.freeModeAsked); growTogether = v(.growTogether, z.growTogether); proRemote = v(.proRemote, z.proRemote)
        whisperModel = v(.whisperModel, z.whisperModel); whisperServer = v(.whisperServer, z.whisperServer)
        tts = v(.tts, z.tts); ttsVoice = v(.ttsVoice, z.ttsVoice); ttsModel = v(.ttsModel, z.ttsModel); ttsRegion = v(.ttsRegion, z.ttsRegion); ttsURL = v(.ttsURL, z.ttsURL); sayVoice = v(.sayVoice, z.sayVoice); sayRate = v(.sayRate, z.sayRate); elevenLabs = v(.elevenLabs, z.elevenLabs)
        inputDevice = v(.inputDevice, z.inputDevice); outputDevice = v(.outputDevice, z.outputDevice)
        bargeIn = v(.bargeIn, z.bargeIn)
        browserApp = v(.browserApp, z.browserApp); apps = v(.apps, z.apps)
        customWords = v(.customWords, z.customWords); fillerWords = v(.fillerWords, z.fillerWords)
        silenceSec = v(.silenceSec, z.silenceSec); followUpSec = v(.followUpSec, z.followUpSec); maxUtteranceSec = v(.maxUtteranceSec, z.maxUtteranceSec)
        chime = v(.chime, z.chime); keepAudio = v(.keepAudio, z.keepAudio); router = v(.router, z.router); pauseInCalls = v(.pauseInCalls, z.pauseInCalls); showIdleOrb = v(.showIdleOrb, z.showIdleOrb); hudPosition = v(.hudPosition, z.hudPosition); hotkey = v(.hotkey, z.hotkey)
    }

    // MARK: resolved values

    var ko: Bool { language.hasPrefix("ko") }
    static let languages: [(code: String, name: String, locale: String)] = [
        ("ko", "한국어", "ko-KR"), ("en", "English", "en-US"), ("ja", "日本語", "ja-JP"), ("zh", "中文", "zh-CN"),
        ("es", "Español", "es-ES"), ("fr", "Français", "fr-FR"), ("de", "Deutsch", "de-DE"), ("pt", "Português", "pt-BR"),
        ("it", "Italiano", "it-IT"), ("vi", "Tiếng Việt", "vi-VN"), ("th", "ไทย", "th-TH"), ("id", "Bahasa Indonesia", "id-ID")]
    static var systemLanguage: String {
        let code = String((Locale.preferredLanguages.first ?? "en").prefix(2))
        return languages.contains { $0.code == code } ? code : "en"
    }
    var lang: String { String(language.prefix(2)) }
    var languageName: String { Config.languages.first { $0.code == lang }?.name ?? "English" }
    var user: String { userName.isEmpty ? (ko ? "주인님" : "sir") : userName }
    var locale: String { Config.languages.first { $0.code == lang }?.locale ?? "en-US" }
    var wakes: [String] {
        if !wakeWords.isEmpty { return wakeWords }
        switch lang {
        case "ko": return ["자비스", "헤이 자비스"]
        case "ja": return ["ジャービス", "jarvis"]
        case "zh": return ["贾维斯", "jarvis"]
        default: return ["jarvis", "hey jarvis"]
        }
    }
    var greets: [String] {
        if !greetPhrases.isEmpty { return greetPhrases }
        return ko ? ["아빠 왔어", "아빠 왔다", "일어나 \(assistantName)", "\(assistantName) 일어나", "자비스 일어나"]
                  : ["daddy's home", "i'm home", "wake up \(assistantName)"]
    }
    var greeting: String { fill(greetingText.isEmpty ? (ko ? "어서 오십시오, {user}" : "Welcome home, {user}.") : greetingText) }
    var subtitle: String {
        if !bootSubtitle.isEmpty { return fill(bootSubtitle) }
        if userName.isEmpty { return ko ? "나만의 AI 비서" : "Your personal AI assistant" }
        return fill(ko ? "{user}의 개인 비서" : "Personal assistant of {user}")
    }
    func fill(_ s: String) -> String { s.replacingOccurrences(of: "{user}", with: user).replacingOccurrences(of: "{assistant}", with: assistantName) }

    var whisperModelPath: String { whisperModel.isEmpty ? Paths.home.appendingPathComponent("models/ggml-large-v3-turbo-q8_0.bin").path : (whisperModel as NSString).expandingTildeInPath }
    var claudeBinary: String? { claudePath.isEmpty ? Paths.which("claude", extra: ["~/.claude/local/claude", "~/.local/bin/claude"]) : (claudePath as NSString).expandingTildeInPath }
    var whisperBinary: String? { whisperServer.isEmpty ? Paths.which("whisper-server") : (whisperServer as NSString).expandingTildeInPath }

    var fillers: [String] { fillerWords.isEmpty ? (ko ? ["음", "으음", "어어", "음음"] : ["um", "uh", "erm"]) : fillerWords }

    /// Custom words and filler words from Handy (cjpais/Handy) if it is installed — your vocabulary carries over.
    static func handyVocabulary() -> (words: [String], fillers: [String])? {
        let p = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.pais.handy/settings_store.json")
        guard let d = try? Data(contentsOf: p), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let s = (obj["settings"] as? [String: Any]) ?? obj
        let w = s["custom_words"] as? [String] ?? [], f = s["custom_filler_words"] as? [String] ?? []
        return w.isEmpty && f.isEmpty ? nil : (w, f)
    }

    /// Change one key in config.json in place (everything else kept).
    static func set(_ key: String, _ value: Any) {
        let url = Paths.home.appendingPathComponent("config.json")
        var obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        obj[key] = value
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            FileManager.default.createFile(atPath: url.path, contents: d, attributes: [.posixPermissions: 0o600])
        }
    }
    static func load() -> Config {
        let url = Paths.home.appendingPathComponent("config.json")
        if let d = try? Data(contentsOf: url) {
            do {
                var c = try JSONDecoder().decode(Config.self, from: d)
                // First run after this feature: bring over Handy's vocabulary once.
                if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any], obj["customWords"] == nil, let h = handyVocabulary() {
                    c.customWords = h.words; c.fillerWords = h.fillers.isEmpty ? c.fillerWords : h.fillers
                    var o = obj; o["customWords"] = c.customWords; o["fillerWords"] = c.fillerWords
                    if let out = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) { try? out.write(to: url) }
                    log("imported \(c.customWords.count) custom words from Handy")
                }
                return c
            } catch { log("config.json unreadable, using defaults: \(error)") }
            return Config()
        }
        let c = Config()
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        try? enc.encode(c).write(to: url)
        return c
    }
}

enum Paths {
    static let home: URL = {
        let env = ProcessInfo.processInfo.environment["MACBUTLER_HOME"]
        let fm = FileManager.default
        let def = fm.homeDirectoryForCurrentUser.appendingPathComponent(".macbutler")
        let old = fm.homeDirectoryForCurrentUser.appendingPathComponent(".myjarvis")   // name before 0.2
        if env == nil, !fm.fileExists(atPath: def.path), fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: def) }
        let u = env.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? def
        // Owner-only: settings, logs (they contain what you said) and the control socket live here.
        for sub in ["", "logs", "work", "voice", "models"] {
            let d = u.appendingPathComponent(sub)
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path)
        }
        return u
    }()
    static var resources: URL { Bundle.main.resourceURL ?? URL(fileURLWithPath: ".") }
    static var tools: URL { resources.appendingPathComponent("bin") }
    static let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    static var envPath: String { ([tools.path] + searchPath).joined(separator: ":") }

    static func which(_ name: String, extra: [String] = []) -> String? {
        let fm = FileManager.default
        for d in searchPath where fm.isExecutableFile(atPath: d + "/" + name) { return d + "/" + name }
        for e in extra { let p = (e as NSString).expandingTildeInPath; if fm.isExecutableFile(atPath: p) { return p } }
        return nil
    }
    /// First existing file among voice/<name>.{m4a,mp3,wav,aiff}
    static func voiceFile(_ name: String) -> URL? {
        for ext in ["m4a", "mp3", "wav", "aiff"] {
            let u = home.appendingPathComponent("voice/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) \(s)\n"
    let url = Paths.home.appendingPathComponent("logs/butler.log")
    let fm = FileManager.default
    if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 5_000_000 {   // keep ~5 MB + one old file
        let old = url.deletingPathExtension().appendingPathExtension("old.log")
        try? fm.removeItem(at: old); try? fm.moveItem(at: url, to: old)
    }
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { fm.createFile(atPath: url.path, contents: line.data(using: .utf8), attributes: [.posixPermissions: 0o600]) }
}

/// Reads KEY=value from a dotenv file.
func dotenv(_ path: String, _ key: String) -> String? {
    guard let s = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8) else { return nil }
    for line in s.split(separator: "\n") where line.hasPrefix(key + "=") {
        return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' \r"))
    }
    return nil
}
