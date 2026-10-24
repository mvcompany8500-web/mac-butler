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
    @Published var brainEffort: String
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
        brainProvider = c.brainProvider; brainModel = c.brainModel; brainBaseURL = c.brainBaseURL; brainEffort = c.brainEffort
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
        obj["brainProvider"] = brainProvider; obj["brainModel"] = brainModel; obj["brainBaseURL"] = brainBaseURL; obj["brainEffort"] = brainEffort
        obj["ttsVoice"] = ttsVoice; obj["ttsRegion"] = ttsRegion; obj["ttsURL"] = ttsURL
        let bk = brainKey.trimmingCharacters(in: .whitespacesAndNewlines), vk = voiceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bk.isEmpty, !["claude-code", "codex", "aside", "ollama", "lmstudio"].contains(brainProvider) { Keys.set(brainProvider, bk); log("saved a key for \(brainProvider)") }
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
    var height: CGFloat = 760
    var onSave: () -> Void
    var body: some View {
        Form {
            Section(S.t("기본", "Basics")) {
                Picker(S.t("언어", "Language"), selection: $m.language) { ForEach(Config.languages, id: \.code) { Text($0.name).tag($0.code) } }
                Picker(S.t("부르는 방식", "How to call it"), selection: $m.activation) {
                    Text(S.t("부르는 말 (+ 단축키)", "Wake word (+ hotkey)")).tag("voice")
                    Text(S.t("단축키만", "Hotkey only")).tag("hold")
                }
                Note(S.t("부르는 말은 늘 귀를 열어 두고, 단축키만은 누를 때만 듣습니다.", "The wake word keeps listening; hotkey only listens while you press it."))
                TextField(S.t("나를 부르는 호칭", "What it calls you"), text: $m.userName, prompt: Text(S.t("예: 대표님", "e.g. Tony")))
                TextField(S.t("비서 이름", "Assistant name"), text: $m.assistantName)
                TextField(S.t("부르는 말", "Wake words"), text: $m.wakeWords, prompt: Text(S.t("쉼표로 여러 개 · 비우면 기본값", "comma-separated · empty = default")))
                TextField(S.t("인사말", "Greeting"), text: $m.greetingText, prompt: Text(S.t("어서 오십시오, {user}", "Welcome home, {user}.")))
                Picker(S.t("단축키로 부르기", "Wake hotkey"), selection: $m.hotkey) {
                    Text(S.t("오른쪽 ⌥ (기본)", "Right ⌥ (default)")).tag("rightOption"); Text(S.t("오른쪽 ⌘", "Right ⌘")).tag("rightCommand"); Text(S.t("끔", "Off")).tag("none")
                }
                Note(S.t("한 번 톡 누르면 부르기, 누른 채 말하면 그동안만 듣습니다.", "Tap once to wake it; hold it and talk to be heard only while held."))
                Picker(S.t("실행 방식", "How it acts"), selection: $m.confirmDelegate) {
                    Text(S.t("바로 실행 (기본)", "Right away (default)")).tag("never")
                    Text(S.t("클로드에 넘길 때만 묻기", "Ask before handing to Claude")).tag("brain")
                    Text(S.t("물어보고 실행", "Ask first")).tag("always")
                }
                Note(S.t("바로 실행은 묻지 않고 합니다. 어느 방식이든 보내기·결제·삭제처럼 되돌릴 수 없는 일은 한 번 묻습니다.",
                         "Right away just does it. In every mode it asks once before anything irreversible (sending, paying, deleting)."))
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
                    Text(S.t("자동 (기본)", "Auto (default)")).tag("auto")
                    Text(S.t("아무 말로나", "Any speech")).tag("any")
                    Text(S.t("부르는 말·「멈춰」로만", "Wake word or “stop” only")).tag("wake")
                }
                Note(S.t("자동은 이어폰이면 아무 말로, 스피커면 부르는 말·「멈춰」로만 끊습니다. 스피커 소리를 제 말로 착각하지 않게요.",
                         "Auto: with headphones any speech interrupts; on speakers only the wake word or “stop” — so it doesn't mistake its own voice for you."))
            }
            Section(S.t("목소리", "Voice")) {
                LabeledContent(S.t("읽어 주는 엔진", "Speech engine")) {
                    EngineMenu(selection: $m.tts, localTitle: S.t("이 맥에서", "On this Mac"), local: [
                        Choice("say", S.t("맥 목소리 — 무료 (기본)", "macOS voice — free (default)")),
                        Choice("http", S.t("내 음성 서버 — 주소로 연결", "My voice server — by URL"))
                    ], apiTitle: S.t("API 키 연결", "API key"), api: [
                        Choice("elevenlabs", "ElevenLabs"),
                        Choice("openai", S.t("OpenAI 목소리", "OpenAI voice")),
                        Choice("azure", S.t("Azure 음성 — 매달 무료 한도", "Azure Speech — monthly free tier"))
                    ])
                }
                if m.tts == "say" {
                    Picker(S.t("맥 목소리", "macOS voice"), selection: $m.sayVoice) {
                        Text(S.t("자동 — 가장 자연스러운 목소리", "Auto — the most natural one")).tag("")
                        ForEach(SettingsModel.sayVoices(lang: m.language), id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Text(S.t("더 자연스러운 목소리(무료): 시스템 설정 → 손쉬운 사용 → 읽기 및 말하기 → 시스템 목소리 → 목소리 관리… → Premium 받기",
                             "More natural voices (free): System Settings → Accessibility → Spoken Content → System voice → Manage Voices… → download a Premium voice"))
                        .font(.caption).foregroundStyle(.secondary)
                } else if m.tts == "elevenlabs" {
                    TextField("ElevenLabs voice ID", text: $m.elevenVoiceId)
                    TextField(S.t("API 키가 든 .env 파일 (또는 아래 칸)", ".env file with ELEVENLABS_API_KEY (or the box below)"), text: $m.elevenKeyFile)
                } else {
                    TextField(S.t("목소리 이름", "Voice"), text: $m.ttsVoice,
                              prompt: Text(m.tts == "azure" ? "ko-KR-SunHiNeural" : m.tts == "openai" ? "alloy" : S.t("서버가 아는 이름", "a name your server knows")))
                    if m.tts == "azure" { TextField(S.t("지역", "Region"), text: $m.ttsRegion, prompt: Text("koreacentral")) }
                    if m.tts == "http" { TextField(S.t("서버 주소", "Server URL"), text: $m.ttsURL, prompt: Text("http://127.0.0.1:5002/tts")) }
                }
                if m.tts != "say" {
                    SecureField(S.t("API 키 (맥 키체인에만 저장)", "API key (kept in the macOS Keychain only)"), text: $m.voiceKey,
                                prompt: Text(SettingsModel.keyHint(m.voiceAccount).isEmpty ? S.t(m.tts == "http" ? "필요할 때만" : "붙여 넣기", m.tts == "http" ? "only if needed" : "paste it here") : S.t("저장됨 ", "saved ") + SettingsModel.keyHint(m.voiceAccount)))
                    Text(S.t("안 되면 늘 무료 맥 목소리로 대신 읽습니다.", "If it fails, the free macOS voice reads instead.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent(S.t("생각하는 AI", "Who does the thinking")) {
                    EngineMenu(selection: $m.brainProvider, localTitle: S.t("로컬 연결 — 이 맥에 로그인된 AI", "Local — AI signed in on this Mac"), local: [
                        Choice("claude-code", S.t("Claude Code — Claude 구독 (기본)", "Claude Code — your Claude plan (default)")),
                        Choice("codex", S.t("Codex — ChatGPT 구독 (GPT)", "Codex — your ChatGPT plan (GPT)")),
                        Choice("ollama", S.t("Ollama — 이 맥에서 무료", "Ollama — free on this Mac")),
                        Choice("lmstudio", S.t("LM Studio — 이 맥에서 무료", "LM Studio — free on this Mac")),
                        Choice("aside", S.t("Aside — Aside 브라우저", "Aside — the Aside browser"))
                    ], apiTitle: S.t("API 키 연결", "API key"), api: [
                        Choice("anthropic", "Claude (Anthropic)"),
                        Choice("openai", "GPT (OpenAI)"),
                        Choice("gemini", "Gemini (Google)"),
                        Choice("openrouter", S.t("OpenRouter — 여러 회사 모델", "OpenRouter — many models")),
                        Choice("groq", "Groq"),
                        Choice("openai-compatible", S.t("OpenAI 호환 서버 — 주소로 연결", "OpenAI-compatible server — by URL"))
                    ])
                }
                switch m.brainProvider {
                case "claude-code":
                    Picker(S.t("모델", "Model"), selection: $m.claudeModel) { Text("Sonnet").tag("sonnet"); Text("Haiku").tag("haiku"); Text("Opus").tag("opus") }
                        .pickerStyle(.segmented)
                    Note(S.t("보통은 Sonnet. Haiku는 더 빠르고, Opus는 더 깊게 생각합니다.", "Sonnet for most things. Haiku is faster, Opus thinks deeper."))
                case "codex":
                    Picker(S.t("생각 깊이", "Thinking"), selection: $m.brainEffort) {
                        Text(S.t("빠르게", "Fast")).tag("low"); Text(S.t("보통", "Normal")).tag("medium"); Text(S.t("깊게", "Deep")).tag("high")
                    }.pickerStyle(.segmented)
                    Picker(S.t("모델", "Model"), selection: $m.brainModel) {
                        Text(S.t("기본 — Codex가 고름 (권장)", "Default — Codex picks (recommended)")).tag("")
                        ForEach(CodexBrain.listedModels(), id: \.self) { Text($0).tag($0) }
                    }
                    Note(CodexBrain.binary == nil
                         ? S.t("이 맥에 Codex가 없습니다. Codex 명령줄 도구를 설치하고 터미널에서 codex login 을 한 번 해 주세요.",
                               "Codex isn't on this Mac. Install the Codex CLI and run codex login once in Terminal.")
                         : S.t("이 맥에 로그인된 Codex로 생각합니다. 빠르게가 음성 비서에 맞고, 목록 모델이 안 되면 기본으로 돌리세요.",
                               "Thinks with the Codex you're signed in to. Fast suits a voice assistant; if a listed model fails, go back to Default."))
                case "aside":
                    Note(AsideBrain.binary == nil
                         ? S.t("Aside 명령줄 도구가 아직 없습니다. Aside 설정 → 개발자에서 설치하고, 터미널에서 aside login 을 한 번 해 주세요.",
                               "The Aside CLI isn't installed yet. Install it in Aside → Settings → Developer, then run aside login once in Terminal.")
                         : S.t("소리·앱 열기·타이머 같은 빠른 명령은 자비스가 하고, 나머지는 Aside 브라우저가 합니다. 결제·보내기·지우기 직전에는 멈추고 묻게 합니다.",
                               "Quick commands (volume, apps, timers) stay in Mac Butler; the rest goes to Aside's browser, told to stop and ask before paying, sending or deleting."))
                case "ollama", "lmstudio":
                    TextField(S.t("모델", "Model"), text: $m.brainModel, prompt: Text(m.brainProvider == "ollama" ? S.t("비우면 설치된 첫 모델", "empty = first installed") : S.t("비우면 불러온 첫 모델", "empty = first loaded")))
                    Note(S.t("이 맥 안에서만 생각합니다. 인터넷으로 나가는 것이 없습니다.", "Thinks entirely on this Mac. Nothing leaves it."))
                default:
                    TextField(S.t("모델", "Model"), text: $m.brainModel,
                              prompt: Text(["anthropic": "claude-sonnet-5-5"][m.brainProvider] ?? S.t("그 회사 모델 목록의 이름", "a name from their model list")))
                    if m.brainProvider == "openai-compatible" {
                        TextField(S.t("서버 주소", "Server URL"), text: $m.brainBaseURL, prompt: Text("https://…/v1"))
                    }
                    SecureField(S.t("API 키", "API key"), text: $m.brainKey,
                                prompt: Text(SettingsModel.keyHint(m.brainProvider).isEmpty ? S.t("붙여 넣기", "paste it here") : S.t("저장됨 ", "saved ") + SettingsModel.keyHint(m.brainProvider)))
                    Note(S.t("API 키는 맥 키체인에만 저장되고, 쓴 만큼 그 회사에 요금이 나갑니다.", "The key is kept in the macOS Keychain only; that company bills you for what you use."))
                }
            } header: { Text(S.t("두뇌", "Brain")) } footer: {
                Text(S.t("어떤 두뇌든 손(누르기·입력·열기)은 같은 안전 장치를 지납니다. 셸·파일은 없습니다.",
                         "Whatever brain you pick, the hands go through the same safety checks. There's no shell or file access."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(S.t("설정 폴더 열기", "Open folder")) { NSWorkspace.shared.open(Paths.home) }
                Spacer()
                Button(S.t("저장하고 다시 켜기", "Save & restart")) { m.save(); onSave() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: height)
        .padding(.bottom, 8)
    }
}

enum SettingsWindow {
    static var window: NSWindow?
    /// The whole settings form drawn off screen into a PNG (design check, `--settings-shot`).
    static func shot(_ path: String) {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let cfg = Config.load(), S = Strings(ko: cfg.ko, name: cfg.assistantName)
        let host = NSHostingController(rootView: SettingsView(m: SettingsModel(cfg), S: S, height: 2400) {})
        let w = NSWindow(contentViewController: host)
        w.setFrame(NSRect(x: -4000, y: 0, width: 580, height: 2400), display: true)
        w.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let v = host.view
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
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


/// One choice in an engine menu: what's saved (tag) and what's shown.
struct Choice: Identifiable { let id: String; let label: String; init(_ id: String, _ label: String) { self.id = id; self.label = label } }

/// Engine chooser (Handy-style settings, 2026-10-24): local choices first; API-key services sit in a submenu that opens
/// sideways on hover, so the main list stays short.
struct EngineMenu: View {
    @Binding var selection: String
    let localTitle: String
    let local: [Choice]
    let apiTitle: String
    let api: [Choice]
    var body: some View {
        Menu {
            Section(localTitle) {
                Picker("", selection: $selection) { ForEach(local) { Text($0.label).tag($0.id) } }.pickerStyle(.inline).labelsHidden()
            }
            Divider()
            Menu(apiTitle) {
                Picker("", selection: $selection) { ForEach(api) { Text($0.label).tag($0.id) } }.pickerStyle(.inline).labelsHidden()
            }
        } label: { Text(current) }
        .fixedSize()
    }
    private var current: String {
        if let c = local.first(where: { $0.id == selection }) { return c.label }
        if let c = api.first(where: { $0.id == selection }) { return apiTitle + " · " + c.label }
        return selection
    }
}

/// The one-line explanation under a setting.
struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
