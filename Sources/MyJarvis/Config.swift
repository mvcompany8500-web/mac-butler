// Settings live in ~/.myjarvis/config.json (override the folder with MYJARVIS_HOME).
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
    var language = "ko"                 // "ko" or "en"
    var userName = ""                   // how the assistant addresses you, e.g. "대표님", "Tony"
    var assistantName = "Jarvis"
    var wakeWords: [String] = []        // empty → language default
    var greetPhrases: [String] = []     // empty → language default ("아빠 왔어", "daddy's home" …)
    var greetingText = ""               // empty → "어서 오십시오, {user}" / "Welcome home, {user}."
    var bootTitle = "J . A . R . V . I . S ."
    var bootSubtitle = ""               // empty → "{user}의 개인 비서" / "Personal assistant of {user}" (or a generic line)
    var greetOpen: [String] = []        // URLs to open when greeted

    var claudePath = ""                 // empty → auto-detect `claude`
    var claudeModel = "sonnet"
    var whisperModel = ""               // empty → ~/.myjarvis/models/ggml-large-v3-turbo-q8_0.bin
    var whisperServer = ""              // empty → auto-detect `whisper-server`

    var tts = "say"                     // "say" (macOS voices) or "elevenlabs"
    var sayVoice = ""                   // empty → system voice for the language
    var sayRate = 190
    var elevenLabs = ElevenLabsConfig()

    var browserApp = "Google Chrome"
    var apps: [String: String] = [:]    // extra spoken name → app name, e.g. {"브루": "Vrew"}
    var silenceSec = 1.8
    var followUpSec = 30.0
    var maxUtteranceSec = 25.0
    var chime = "Tink"
    var showIdleOrb = true
    var hotkey = "rightOption"          // tap to wake without speaking: "rightOption", "rightCommand", "none"

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), z = Config()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: k)) ?? def }
        language = v(.language, z.language); userName = v(.userName, z.userName); assistantName = v(.assistantName, z.assistantName)
        wakeWords = v(.wakeWords, z.wakeWords); greetPhrases = v(.greetPhrases, z.greetPhrases)
        greetingText = v(.greetingText, z.greetingText); bootTitle = v(.bootTitle, z.bootTitle); bootSubtitle = v(.bootSubtitle, z.bootSubtitle)
        greetOpen = v(.greetOpen, z.greetOpen)
        claudePath = v(.claudePath, z.claudePath); claudeModel = v(.claudeModel, z.claudeModel)
        whisperModel = v(.whisperModel, z.whisperModel); whisperServer = v(.whisperServer, z.whisperServer)
        tts = v(.tts, z.tts); sayVoice = v(.sayVoice, z.sayVoice); sayRate = v(.sayRate, z.sayRate); elevenLabs = v(.elevenLabs, z.elevenLabs)
        browserApp = v(.browserApp, z.browserApp); apps = v(.apps, z.apps)
        silenceSec = v(.silenceSec, z.silenceSec); followUpSec = v(.followUpSec, z.followUpSec); maxUtteranceSec = v(.maxUtteranceSec, z.maxUtteranceSec)
        chime = v(.chime, z.chime); showIdleOrb = v(.showIdleOrb, z.showIdleOrb); hotkey = v(.hotkey, z.hotkey)
    }

    // MARK: resolved values

    var ko: Bool { language.hasPrefix("ko") }
    var user: String { userName.isEmpty ? (ko ? "주인님" : "sir") : userName }
    var locale: String { ko ? "ko-KR" : "en-US" }
    var wakes: [String] { wakeWords.isEmpty ? (ko ? ["자비스", "헤이 자비스"] : ["jarvis", "hey jarvis"]) : wakeWords }
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

    static func load() -> Config {
        let url = Paths.home.appendingPathComponent("config.json")
        if let d = try? Data(contentsOf: url) {
            do { return try JSONDecoder().decode(Config.self, from: d) } catch { log("config.json unreadable, using defaults: \(error)") }
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
        let env = ProcessInfo.processInfo.environment["MYJARVIS_HOME"]
        let u = env.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".myjarvis")
        for sub in ["", "logs", "work", "voice", "models"] {
            try? FileManager.default.createDirectory(at: u.appendingPathComponent(sub), withIntermediateDirectories: true)
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
    let url = Paths.home.appendingPathComponent("logs/jarvis.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.data(using: .utf8)!.write(to: url) }
}

/// Reads KEY=value from a dotenv file.
func dotenv(_ path: String, _ key: String) -> String? {
    guard let s = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8) else { return nil }
    for line in s.split(separator: "\n") where line.hasPrefix(key + "=") {
        return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' \r"))
    }
    return nil
}
