// Settings window (menu → Settings…). Edits ~/.macbutler/config.json and restarts the app.
import AppKit
import SwiftUI

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
    let inputs = AudioDevices.inputs(), outputs = AudioDevices.outputs()
    private var cfg: Config

    init(_ c: Config) {
        cfg = c
        language = c.lang; activation = c.activation; userName = c.userName; assistantName = c.assistantName
        wakeWords = c.wakeWords.joined(separator: ", "); greetingText = c.greetingText
        hotkey = c.hotkey; tts = c.tts; sayVoice = c.sayVoice
        elevenVoiceId = c.elevenLabs.voiceId; elevenKeyFile = c.elevenLabs.apiKeyFile; claudeModel = c.claudeModel
        inputDevice = c.inputDevice; outputDevice = c.outputDevice; bargeIn = c.bargeIn
    }

    /// Writes only the keys this window manages; everything else in config.json is kept as is.
    func save() {
        let url = Paths.home.appendingPathComponent("config.json")
        var obj = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        obj["language"] = language; obj["activation"] = activation; obj["userName"] = userName; obj["assistantName"] = assistantName
        obj["wakeWords"] = wakeWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        obj["greetingText"] = greetingText; obj["hotkey"] = hotkey; obj["tts"] = tts; obj["sayVoice"] = sayVoice
        obj["claudeModel"] = claudeModel; obj["inputDevice"] = inputDevice; obj["outputDevice"] = outputDevice; obj["bargeIn"] = bargeIn
        var el = obj["elevenLabs"] as? [String: Any] ?? [:]
        el["voiceId"] = elevenVoiceId; el["apiKeyFile"] = elevenKeyFile
        obj["elevenLabs"] = el
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: url)
            log("settings saved")
        }
    }

    static func sayVoices(lang: String) -> [String] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = ["-v", "?"]
        let out = Pipe(); p.standardOutput = out
        try? p.run(); p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let want = (Config.languages.first { $0.code == lang }?.locale ?? "en-US").replacingOccurrences(of: "-", with: "_").prefix(3)
        return text.split(separator: "\n").compactMap { line in
            guard line.contains(String(want)), let r = line.range(of: #"\s{2,}[a-z]{2}_[A-Z]{2}"#, options: .regularExpression) else { return nil }
            return String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
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
                Picker(S.t("읽어 주는 엔진", "Speech engine"), selection: $m.tts) { Text("macOS say").tag("say"); Text("ElevenLabs").tag("elevenlabs") }
                if m.tts == "say" {
                    Picker(S.t("맥 목소리", "macOS voice"), selection: $m.sayVoice) {
                        Text(S.t("시스템 기본", "System default")).tag("")
                        ForEach(SettingsModel.sayVoices(lang: m.language), id: \.self) { Text($0).tag($0) }
                    }
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
