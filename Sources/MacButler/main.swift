// Mac Butler — an always-listening voice assistant for macOS, powered by Claude Code.
// The assistant answers to "Jarvis" by default (configurable: assistantName / wakeWords).
// Say the wake word, then talk. It types, clicks, opens things, and hands bigger jobs to Claude.
import AppKit
import AVFoundation
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var butler: Butler?
    var item: NSStatusItem!
    var cfg = Config()
    var statusItems: [NSMenuItem] = []
    var usageItem: NSMenuItem?
    func applicationDidFinishLaunching(_ n: Notification) {
        cfg = Config.load()
        let cfg = self.cfg
        let S = Strings(ko: cfg.ko, name: cfg.assistantName)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◉" + String(cfg.assistantName.prefix(1)).uppercased()
        let menu = NSMenu()
        menu.addItem(withTitle: S.menuToggle(), action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: S.menuGreet(), action: #selector(greet), keyEquivalent: "")
        menu.addItem(withTitle: S.t("설정…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: S.t("준비 화면…", "Setup…"), action: #selector(openSetup), keyEquivalent: "")
        menu.addItem(withTitle: S.menuFolder(), action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(.separator())
        let head = NSMenuItem(title: S.menuStatus, action: nil, keyEquivalent: ""); head.isEnabled = false
        menu.addItem(head)
        for (i, _) in AppDelegate.checks.enumerated() {
            let it = NSMenuItem(title: "", action: #selector(fixPermission(_:)), keyEquivalent: ""); it.tag = i; it.target = self
            menu.addItem(it); statusItems.append(it)
        }
        if cfg.hotkey != "none" {
            let hk = NSMenuItem(title: S.hotkeyHint(cfg.hotkey == "rightCommand" ? "오른쪽 ⌘ / right ⌘" : "오른쪽 ⌥ / right ⌥"), action: nil, keyEquivalent: ""); hk.isEnabled = false
            menu.addItem(hk)
        }
        menu.addItem(.separator())
        let ui = NSMenuItem(title: "", action: nil, keyEquivalent: ""); ui.isEnabled = false; menu.addItem(ui); usageItem = ui
        menu.addItem(withTitle: S.t("배운 명령 모두 지우기", "Forget learned commands"), action: #selector(forgetLearned), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: S.menuQuit(), action: #selector(quit), keyEquivalent: "q")
        for i in menu.items where i.action != nil { i.target = self }
        menu.delegate = self
        item.menu = menu
        installHotkey()

        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            SFSpeechRecognizer.requestAuthorization { st in
                DispatchQueue.main.async {
                    log("permissions: mic=\(ok) speech=\(st.rawValue) accessibility=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")
                    let j = Butler(cfg: cfg)
                    self.butler = j
                    j.start()
                    SetupWindow.showIfNeeded(cfg: cfg)
                }
            }
        }
    }
    // MARK: status checklist (refreshed every time the menu opens)

    static let checks: [(key: String, pane: String)] = [
        ("mic", "Privacy_Microphone"), ("speech", "Privacy_SpeechRecognition"), ("ax", "Privacy_Accessibility"),
        ("screen", "Privacy_ScreenCapture"), ("claude", ""), ("whisper", "")]
    func menuWillOpen(_ menu: NSMenu) {
        let S = Strings(ko: cfg.ko, name: cfg.assistantName)
        let ok: [Bool] = [
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            SFSpeechRecognizer.authorizationStatus() == .authorized,
            AXIsProcessTrusted(), CGPreflightScreenCaptureAccess(),
            cfg.claudeBinary != nil,
            FileManager.default.fileExists(atPath: cfg.whisperModelPath) && cfg.whisperBinary != nil]
        let names = [S.permMic, S.permSpeech, S.permAX, S.permScreen, S.depClaude, S.depWhisper]
        for (i, it) in statusItems.enumerated() { it.title = (ok[i] ? "✓  " : "✗  ") + names[i] }
        let u = Usage.today()
        usageItem?.title = S.t("오늘 클로드 \(u["calls"] ?? 0)번 · 토큰 \(((u["input"] ?? 0) + (u["cacheRead"] ?? 0) + (u["cacheWrite"] ?? 0) + (u["output"] ?? 0)) / 1000)천 · 배운 명령 \(Learning.store.count)개",
                               "Today: \(u["calls"] ?? 0) Claude calls · \(((u["input"] ?? 0) + (u["cacheRead"] ?? 0) + (u["cacheWrite"] ?? 0) + (u["output"] ?? 0)) / 1000)k tokens · \(Learning.store.count) learned")
    }
    @objc func fixPermission(_ sender: NSMenuItem) {
        let c = AppDelegate.checks[sender.tag]
        let url: String
        switch c.key {
        case "claude": url = "https://docs.claude.com/en/docs/claude-code/setup"
        case "whisper": NSWorkspace.shared.open(Paths.home.appendingPathComponent("models")); return
        default: url = "x-apple.systempreferences:com.apple.preference.security?" + c.pane
        }
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    /// Tap the right Option (or right Command) key alone to wake — for noisy rooms and meetings.
    /// Right ⌥ (or ⌘): tap = wake (like saying the name) · hold = push-to-talk like Handy (release runs it).
    var hotkeyDown: Date?
    var holdTimer: Timer?
    var holding = false
    func installHotkey() {
        let code: UInt16 = cfg.hotkey == "rightCommand" ? 54 : 61
        guard cfg.hotkey != "none" else { return }
        let handler: (NSEvent) -> Void = { [weak self] e in
            guard let self, e.keyCode == code else { return }
            let flag: NSEvent.ModifierFlags = code == 54 ? .command : .option
            DispatchQueue.main.async {
                if e.modifierFlags.contains(flag) {
                    self.hotkeyDown = Date()
                    self.holdTimer?.invalidate()
                    self.holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                        guard self.hotkeyDown != nil else { return }
                        self.holding = true; self.butler?.holdBegan()
                    }
                } else if self.hotkeyDown != nil {
                    self.hotkeyDown = nil; self.holdTimer?.invalidate()
                    if self.holding { self.holding = false; self.butler?.holdEnded() } else { self.butler?.manualWake() }
                }
            }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in   // ⌥+key combos don't count
            DispatchQueue.main.async {
                guard let self, self.hotkeyDown != nil else { return }
                self.hotkeyDown = nil; self.holdTimer?.invalidate()
                if self.holding { self.holding = false; self.butler?.holdCancelled() }
            }
        }
    }

    @objc func toggle() {
        guard let j = butler else { return }
        j.enabled.toggle()
        let ch = String(cfg.assistantName.prefix(1)).uppercased(); item.button?.title = (j.enabled ? "◉" : "○") + ch
        if !j.enabled { j.goIdle() }
    }
    @objc func greet() { butler?.greet() }
    @objc func forgetLearned() { Learning.store = [:]; Learning.save(); log("learned commands cleared") }
    @objc func openSetup() { SetupWindow.show(cfg: cfg) }
    @objc func openSettings() { SettingsWindow.show(cfg: cfg) }
    @objc func openFolder() { NSWorkspace.shared.open(Paths.home) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ n: Notification) { butler?.shutdown() }
}

// `MacButler --selftest` checks the command grammar without a microphone.
if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run() ? 0 : 1) }
// `MacButler --devices` lists microphones and speakers (UIDs go into inputDevice / outputDevice).
if CommandLine.arguments.contains("--devices") {
    for d in AudioDevices.all() { print("\(d.input ? "🎤" : "  ")\(d.output ? "🔈" : "  ") \(d.name)  —  \(d.uid)") }
    exit(0)
}

let delegate = AppDelegate()
signal(SIGTERM, SIG_IGN)   // stop Whisper / Claude children when launchd stops us
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler { delegate.butler?.shutdown(); exit(0) }
termSource.resume()

let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
