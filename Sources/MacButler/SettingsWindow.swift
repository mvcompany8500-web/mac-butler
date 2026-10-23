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
    let inputs = AudioDevices.inputs(), outputs = AudioDevices.outputs()
    private var cfg: Config

    init(_ c: Config) {
        cfg = c
        language = c.lang; activation = c.activation; userName = c.userName; assistantName = c.assistantName
        wakeWords = c.wakeWords.joined(separator: ", "); greetingText = c.greetingText
        hotkey = c.hotkey; tts = c.tts; sayVoice = c.sayVoice
        elevenVoiceId = c.elevenLabs.voiceId; elevenKeyFile = c.elevenLabs.apiKeyFile; claudeModel = c.claudeModel
        inputDevice = c.inputDevice; outputDevice = c.outputDevice; bargeIn = c.bargeIn; hudPosition = c.hudPosition; confirmDelegate = c.confirmDelegate
    }

    /// Writes only the keys this window manages; everything else in config.json is kept as is.
    func save() {
        let url = Paths.home.appendingPathComponent("config.json")
        var obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        obj["language"] = language; obj["activation"] = activation; obj["userName"] = userName; obj["assistantName"] = assistantName
        obj["wakeWords"] = wakeWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        obj["greetingText"] = greetingText; obj["hotkey"] = hotkey; obj["tts"] = tts; obj["sayVoice"] = sayVoice
        obj["claudeModel"] = claudeModel; obj["inputDevice"] = inputDevice; obj["outputDevice"] = outputDevice; obj["bargeIn"] = bargeIn; obj["hudPosition"] = hudPosition; obj["confirmDelegate"] = confirmDelegate
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
                Picker(S.t("읽어 주는 엔진", "Speech engine"), selection: $m.tts) { Text(S.t("맥 목소리 (무료·기본)", "macOS voice (free, default)")).tag("say"); Text(S.t("ElevenLabs (유료·내 열쇠)", "ElevenLabs (paid, your key)")).tag("elevenlabs") }
                if m.tts == "say" {
                    Picker(S.t("맥 목소리", "macOS voice"), selection: $m.sayVoice) {
                        Text(S.t("자동 (설치된 것 중 가장 자연스러운 목소리)", "Automatic (the most natural voice installed)")).tag("")
                        ForEach(SettingsModel.sayVoices(lang: m.language), id: \.id) { Text($0.label).tag($0.id) }
                    }
                    Text(S.t("더 자연스러운 목소리(무료): 시스템 설정 → 손쉬운 사용 → 읽기 및 말하기 → 시스템 목소리 → 목소리 관리… → Premium 받기",
                             "More natural voices (free): System Settings → Accessibility → Spoken Content → System voice → Manage Voices… → download a Premium voice"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("ElevenLabs voice ID", text: $m.elevenVoiceId)
                    TextField(S.t("API 열쇠가 든 .env 파일 경로", "Path to a .env with ELEVENLABS_API_KEY"), text: $m.elevenKeyFile)
                }
            }
            Section(S.t("두뇌", "Brain")) {
                Picker(S.t("Claude 모델", "Claude model"), selection: $m.claudeModel) { Text("Sonnet").tag("sonnet"); Text("Haiku").tag("haiku"); Text("Opus").tag("opus") }
            }
            HStack {
                Button(S.t("설정 폴더 열기", "Open folder")) { NSWorkspace.shared.open(Paths.home) }
                Spacer()
                Button(S.t("저장하고 다시 켜기", "Save & restart")) { m.save(); onSave() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 700)
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
