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
    func applicationDidFinishLaunching(_ n: Notification) {
        cfg = Config.load()
        let cfg = self.cfg
        let S = Strings(ko: cfg.ko, name: cfg.assistantName)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◉" + String(cfg.assistantName.prefix(1)).uppercased()
        let menu = NSMenu()
        menu.addItem(withTitle: S.menuToggle(), action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: S.menuGreet(), action: #selector(greet), keyEquivalent: "")
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
    var hotkeyDown = false
    func installHotkey() {
        let code: UInt16 = cfg.hotkey == "rightCommand" ? 54 : 61
        guard cfg.hotkey != "none" else { return }
        let handler: (NSEvent) -> Void = { [weak self] e in
            guard let self, e.keyCode == code else { return }
            let flag: NSEvent.ModifierFlags = code == 54 ? .command : .option
            if e.modifierFlags.contains(flag) { self.hotkeyDown = true }
            else if self.hotkeyDown { self.hotkeyDown = false; DispatchQueue.main.async { self.butler?.manualWake() } }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in self?.hotkeyDown = false }   // ⌥+key combos don't count
    }

    @objc func toggle() {
        guard let j = butler else { return }
        j.enabled.toggle()
        let ch = String(cfg.assistantName.prefix(1)).uppercased(); item.button?.title = (j.enabled ? "◉" : "○") + ch
        if !j.enabled { j.goIdle() }
    }
    @objc func greet() { butler?.greet() }
    @objc func openFolder() { NSWorkspace.shared.open(Paths.home) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ n: Notification) { butler?.shutdown() }
}

// `MacButler --selftest` checks the command grammar without a microphone.
if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run() ? 0 : 1) }

let delegate = AppDelegate()
signal(SIGTERM, SIG_IGN)   // stop Whisper / Claude children when launchd stops us
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler { delegate.butler?.shutdown(); exit(0) }
termSource.resume()

let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
