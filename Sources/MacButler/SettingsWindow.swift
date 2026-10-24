// Settings window (menu → Settings…). Edits ~/.macbutler/config.json and restarts the app.
import AppKit
import SwiftUI
import AVFoundation

final class SettingsModel: ObservableObject {
    @Published var language: String
    @Published var activation: String
    @Published var userName: String
    @Published var assistantName: String
    @Published var wakeWords: String
    @Published var greetingText: String
    @Published var hotkey: String
    @Published var tts: String
    @Published var sayVoice: String
    @Published var elevenVoiceId: String
    @Published var elevenKeyFile: String
    @Published var claudeModel: String
    @Published var inputDevice: String
    @Published var bargeIn: String
    @Published var outputDevice: String
    @Published var hudPosition: String
    @Published var confirmDelegate: String
    @Published var brainProvider: String
    @Published var brainModel: String
    @Published var brainBaseURL: String
    @Published var brainKey = ""            // typed here, saved to the Keychain only — never to config.json
    @Published var ttsVoice: String
    @Published var ttsRegion: String
    @Published var ttsURL: String
    @Published var voiceKey = ""
    let inputs = AudioDevices.inputs(), outputs = AudioDevices.outputs()
    private var cfg: Config

    init(_ c: Config) {
        cfg = c
        language = c.lang; activation = c.activation; userName = c.userName; assistantName = c.assistantName
        wakeWords = c.wakeWords.joined(separator: ", "); greetingText = c.greetingText
        hotkey = c.hotkey; tts = c.tts; sayVoice = c.sayVoice
        elevenVoiceId = c.elevenLabs.voiceId; elevenKeyFile = c.elevenLabs.apiKeyFile; claudeModel = c.claudeModel
        inputDevice = c.inputDevice; outputDevice = c.outputDevice; bargeIn = c.bargeIn; hudPosition = c.hudPosition; confirmDelegate = c.confirmDelegate
        brainProvider = c.brainProvider; brainModel = c.brainModel; brainBaseURL = c.brainBaseURL
        ttsVoice = c.ttsVoice; ttsRegion = c.ttsRegion; ttsURL = c.ttsURL
    }
    /// Keychain account for the chosen voice's key.
    var voiceAccount: String { ["openai": "openai", "azure": "azure-speech", "http": "http-tts", "elevenlabs": "elevenlabs"][tts] ?? "" }
    static func keyHint(_ account: String) -> String { Keys.get(account).map { "…" + $0.suffix(4) } ?? "" }

    /// Writes only the keys this window manages; everything else in config.json is kept as is.
    func save() {
        let url = Paths.home.appendingPathComponent("config.json")
        var obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        obj["language"] = language; obj["activation"] = activation; obj["userName"] = userName; obj["assistantName"] = assistantName
        obj["wakeWords"] = wakeWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        obj["greetingText"] = greetingText; obj["hotkey"] = hotkey; obj["tts"] = tts; obj["sayVoice"] = sayVoice
        obj["claudeModel"] = claudeModel; obj["inputDevice"] = inputDevice; obj["outputDevice"] = outputDevice; obj["bargeIn"] = bargeIn; obj["hudPosition"] = hudPosition; obj["confirmDelegate"] = confirmDelegate
        obj["brainProvider"] = brainProvider; obj["brainModel"] = brainModel; obj["brainBaseURL"] = brainBaseURL
        obj["ttsVoice"] = ttsVoice; obj["ttsRegion"] = ttsRegion; obj["ttsURL"] = ttsURL
        let bk = brainKey.trimmingCharacters(in: .whitespacesAndNewlines), vk = voiceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bk.isEmpty, brainProvider != "claude-code" { Keys.set(brainProvider, bk); log("saved a key for \(brainProvider)") }
        if !vk.isEmpty, !voiceAccount.isEmpty { Keys.set(voiceAccount, vk); log("saved a key for \(voiceAccount)") }
        var el = obj["elevenLabs"] as? [String: Any] ?? [:]
        el["voiceId"] = elevenVoiceId; el["apiKeyFile"] = elevenKeyFile
        obj["elevenLabs"] = el
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: url)
            log("settings saved")
        }
    }

    /// macOS voices for the language, best first: (identifier, "Yuna · Premium").
    static func sayVoices(lang: String) -> [(id: String, label: String)] {
        let want = String((Config.languages.first { $0.code == lang }?.locale ?? "en-US").prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(want) && ($0.identifier.hasPrefix("com.apple.voice.") || $0.quality != .default || $0.identifier.contains("eloquence")) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
            .map { v in
                let q = v.quality == .premium ? " · Premium" : v.quality == .enhanced ? " · Enhanced" : v.identifier.contains("eloquence") ? " · robot" : ""
                return (v.identifier, v.name + q)
            }
    }
}

struct SettingsView: View {
    @ObservedObject var m: SettingsModel
    let S: Strings
    var onSave: () -> Void
    var body: some View {
        Form {
            Section(S.t("기본", "Basics")) {
                Picker(S.t("언어", "Language"), selection: $m.language) { ForEach(Config.languages, id: \.code) { Text($0.name).tag($0.code) } }
                Picker(S.t("부르는 방식", "How to call it"), selection: $m.activation) {
                    Text(S.t("「자비스」 부르기 (+ 단축키)", "Say the wake word (+ hotkey)")).tag("voice")
                    Text(S.t("단축키 누르고 말하기만", "Hold the hotkey only")).tag("hold")
                }
                TextField(S.t("나를 부르는 호칭", "What it calls you"), text: $m.userName, prompt: Text(S.t("예: 대표님", "e.g. Tony")))
                TextField(S.t("비서 이름", "Assistant name"), text: $m.assistantName)
                TextField(S.t("깨우는 말 (쉼표로 구분)", "Wake words (comma-separated)"), text: $m.wakeWords, prompt: Text(S.t("비우면 기본값", "empty = default")))
                TextField(S.t("인사말", "Greeting"), text: $m.greetingText, prompt: Text(S.t("어서 오십시오, {user}", "Welcome home, {user}.")))
                Picker(S.t("단축키로 부르기", "Wake hotkey"), selection: $m.hotkey) {
                    Text(S.t("오른쪽 ⌥ (톡=부르기, 누르고 말하기)", "Right ⌥ (tap = wake, hold = talk)")).tag("rightOption"); Text(S.t("오른쪽 ⌘", "Right ⌘")).tag("rightCommand"); Text(S.t("끔", "Off")).tag("none")
                }
                Picker(S.t("실행 방식", "How it acts"), selection: $m.confirmDelegate) {
                    Text(S.t("바로 실행 (기본) — 묻지 않고 한다", "Right away (default) — just does it")).tag("never")
                    Text(S.t("클로드에 일을 넘길 때만 묻기", "Ask only before handing work to Claude")).tag("brain")
                    Text(S.t("물어보고 실행 — 애매하면 묻는다", "Ask first — asks when unsure")).tag("always")
                }
                Text(S.t("어느 방식이든 보내기·결제·삭제처럼 되돌릴 수 없는 일은 한 번 묻습니다.", "In every mode it asks once before anything irreversible (sending, paying, deleting)."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(S.t("화면 위치", "On-screen position"), selection: $m.hudPosition) {
                    Text(S.t("오른쪽 아래 (기본)", "Bottom right (default)")).tag("bottomRight"); Text(S.t("왼쪽 아래", "Bottom left")).tag("bottomLeft"); Text(S.t("위 가운데", "Top center")).tag("top")
                }
            }
            Section(S.t("마이크·스피커", "Microphone & speaker")) {
                Picker(S.t("마이크", "Microphone"), selection: $m.inputDevice) {
                    Text(S.t("시스템 기본", "System default")).tag("")
                    ForEach(m.inputs, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                Picker(S.t("스피커", "Speaker"), selection: $m.outputDevice) {
                    Text(S.t("시스템 기본", "System default")).tag("")
                    ForEach(m.outputs, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                Picker(S.t("말하는 중에 끊기", "Interrupting while it talks"), selection: $m.bargeIn) {
                    Text(S.t("자동 (이어폰이면 아무 말, 스피커면 「자비스·멈춰」만)", "Auto (headphones: anything · speakers: wake/stop words)")).tag("auto")
                    Text(S.t("아무 말로나 (이어폰)", "Any speech (headphones)")).tag("any")
                    Text(S.t("「자비스·멈춰」로만 (스피커)", "Wake/stop words only (speakers)")).tag("wake")
                }
            }
            Section(S.t("목소리", "Voice")) {
                Picker(S.t("읽어 주는 엔진", "Speech engine"), selection: $m.tts) {
                    Text(S.t("맥 목소리 (무료·기본)", "macOS voice (free, default)")).tag("say")
                    Text(S.t("ElevenLabs (내 열쇠)", "ElevenLabs (your key)")).tag("elevenlabs")
                    Text(S.t("OpenAI 목소리 (내 열쇠)", "OpenAI voice (your key)")).tag("openai")
                    Text(S.t("Azure 음성 (내 열쇠, 매달 무료 한도)", "Azure Speech (your key, monthly free tier)")).tag("azure")
                    Text(S.t("내 음성 서버 (주소)", "My own voice server (URL)")).tag("http")
                }
                if m.tts == "say" {
                    Picker(S.t("맥 목소리", "macOS voice"), selection: $m.sayVoice) {
                        Text(S.t("자동 (설치된 것 중 가장 자연스러운 목소리)", "Automatic (the most natural voice installed)")).tag("")
                        ForEach(SettingsModel.sayVoices(lang: m.language), id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Text(S.t("더 자연스러운 목소리(무료): 시스템 설정 → 손쉬운 사용 → 읽기 및 말하기 → 시스템 목소리 → 목소리 관리… → Premium 받기",
                             "More natural voices (free): System Settings → Accessibility → Spoken Content → System voice → Manage Voices… → download a Premium voice"))
                        .font(.caption).foregroundStyle(.secondary)
                } else if m.tts == "elevenlabs" {
                    TextField("ElevenLabs voice ID", text: $m.elevenVoiceId)
                    TextField(S.t("API 열쇠가 든 .env 파일 경로 (또는 아래 칸)", "Path to a .env with ELEVENLABS_API_KEY (or the box below)"), text: $m.elevenKeyFile)
                } else {
                    TextField(S.t("목소리 이름", "Voice"), text: $m.ttsVoice,
                              prompt: Text(m.tts == "azure" ? "ko-KR-SunHiNeural" : m.tts == "openai" ? "alloy" : S.t("서버가 아는 이름", "a name your server knows")))
                    if m.tts == "azure" { TextField(S.t("지역", "Region"), text: $m.ttsRegion, prompt: Text("koreacentral")) }
                    if m.tts == "http" { TextField(S.t("서버 주소", "Server URL"), text: $m.ttsURL, prompt: Text("http://127.0.0.1:5002/tts")) }
                }
                if m.tts != "say" {
                    SecureField(S.t("열쇠 (키체인에 저장)", "Key (saved in the Keychain)"), text: $m.voiceKey,
                                prompt: Text(SettingsModel.keyHint(m.voiceAccount).isEmpty ? S.t(m.tts == "http" ? "필요할 때만" : "붙여 넣기", m.tts == "http" ? "only if needed" : "paste it here") : S.t("저장됨 ", "saved ") + SettingsModel.keyHint(m.voiceAccount)))
                    Text(S.t("안 되면 늘 무료 맥 목소리로 대신 읽습니다.", "If it fails, the free macOS voice reads instead.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(S.t("두뇌", "Brain")) {
                Picker(S.t("생각하는 AI", "Who does the thinking"), selection: $m.brainProvider) {
                    Text(S.t("Claude Code (내 Claude 구독, 기본)", "Claude Code (your Claude plan, default)")).tag("claude-code")
                    Text(S.t("Claude API (내 열쇠)", "Claude API (your key)")).tag("anthropic")
                    Text(S.t("GPT — OpenAI (내 열쇠)", "GPT — OpenAI (your key)")).tag("openai")
                    Text(S.t("Gemini (내 열쇠)", "Gemini (your key)")).tag("gemini")
                    Text(S.t("OpenRouter (내 열쇠, 여러 회사 모델)", "OpenRouter (your key, many models)")).tag("openrouter")
                    Text(S.t("Groq (내 열쇠)", "Groq (your key)")).tag("groq")
                    Text(S.t("내 컴퓨터 — Ollama (무료)", "This Mac — Ollama (free)")).tag("ollama")
                    Text(S.t("내 컴퓨터 — LM Studio (무료)", "This Mac — LM Studio (free)")).tag("lmstudio")
                    Text(S.t("다른 OpenAI 호환 주소", "Another OpenAI-compatible server")).tag("openai-compatible")
                    Text(S.t("Aside (내 Aside 앱, 브라우저 일)", "Aside (your Aside app, browser errands)")).tag("aside")
                }
                if m.brainProvider == "aside" {
                    Text(AsideBrain.binary == nil
                         ? S.t("Aside 명령줄 도구가 아직 없어요. Aside 설정 → 개발자에서 설치하고, 터미널에서 aside login 을 한 번 해 주세요.",
                               "The Aside CLI isn't installed yet. Install it in Aside → Settings → Developer, then run aside login once in Terminal.")
                         : S.t("소리·앱 열기·타이머 같은 빠른 명령은 자비스가 직접 하고, 나머지 일은 Aside 브라우저가 합니다. 결제·보내기·지우기 직전에는 멈추고 묻게 시킵니다.",
                               "Quick commands (volume, apps, timers) stay in Mac Butler; everything else goes to Aside's browser, told to stop and ask before paying, sending or deleting."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if m.brainProvider == "claude-code" {
                    Picker(S.t("Claude 모델", "Claude model"), selection: $m.claudeModel) { Text("Sonnet").tag("sonnet"); Text("Haiku").tag("haiku"); Text("Opus").tag("opus") }
                } else {
                    TextField(S.t("모델 이름", "Model"), text: $m.brainModel,
                              prompt: Text(["anthropic": "claude-sonnet-5-5", "ollama": S.t("비우면 설치된 첫 모델", "empty = first installed"),
                                            "lmstudio": S.t("비우면 불러온 첫 모델", "empty = first loaded")][m.brainProvider] ?? S.t("그 회사 모델 목록의 이름", "a name from their model list")))
                    if m.brainProvider == "openai-compatible" {
                        TextField(S.t("서버 주소", "Server URL"), text: $m.brainBaseURL, prompt: Text("https://…/v1"))
                    }
                    if !["ollama", "lmstudio"].contains(m.brainProvider) {
                        SecureField(S.t("API 열쇠 (키체인에 저장)", "API key (saved in the Keychain)"), text: $m.brainKey,
                                    prompt: Text(SettingsModel.keyHint(m.brainProvider).isEmpty ? S.t("붙여 넣기", "paste it here") : S.t("저장됨 ", "saved ") + SettingsModel.keyHint(m.brainProvider)))
                    }
                    Text(S.t("어떤 두뇌든 손(누르기·입력·열기)은 같은 안전 장치를 지납니다. 셸·파일은 없습니다.",
                             "Whatever brain you pick, the hands go through the same safety checks. There's no shell or file access."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(S.t("설정 폴더 열기", "Open folder")) { NSWorkspace.shared.open(Paths.home) }
                Spacer()
                Button(S.t("저장하고 다시 켜기", "Save & restart")) { m.save(); onSave() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 760)
        .padding(.bottom, 8)
    }
}

enum SettingsWindow {
    static var window: NSWindow?
    static func show(cfg: Config) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let S = Strings(ko: cfg.ko, name: cfg.assistantName)
        let view = SettingsView(m: SettingsModel(cfg), S: S) { relaunch() }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Mac Butler — " + S.t("설정", "Settings")
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    /// Under launchd (installed with scripts/install.sh) a non-zero exit makes launchd start us again.
    /// Otherwise start a fresh copy, then quit.
    static func relaunch() {
        (NSApp.delegate as? AppDelegate)?.butler?.shutdown()
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]?.contains(Bundle.main.bundleIdentifier ?? "-") == true { exit(3) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-n", Bundle.main.bundlePath]
        try? p.run()
        exit(0)
    }
}
