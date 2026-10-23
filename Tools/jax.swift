// jax — press buttons / links / text fields of the frontmost app by name, without moving the mouse (Accessibility).
//   jax list [filter]            list pressable things (role | name)
//   jax tap "name" [n]           press the n-th (default 1) element whose name contains the text
//   jax field "field name" "text"  focus a text field and type into it (visibly, via Mac Butler)
//   jax key cmd+t | enter | esc …  press a key / shortcut
//   jax front                      frontmost app, window title, and (browsers) the address bar
//   jax volume 0-100               set the output volume
//   jax open-app "Name"            open an app            jax open-url https://…   open a web page
//   jax screenshot                 → /tmp/macbutler/screen.png (1280 px wide) for the assistant to look at
//   jax click X Y                  press whatever is at that point (pointer snaps back)
// With MACBUTLER_SAFE=1 (set by Mac Butler's brain in safe mode) nothing is pressed, typed or opened in
// protected apps: terminals, code editors, Claude, System Settings, Keychain, password managers, permission prompts.
import AppKit
import ApplicationServices

/// Sends "<cmd>\n<text>" to the running Mac Butler over its private socket (~/.macbutler/butler.sock).
func butlerSend(_ cmd: String, _ text: String) -> Bool {
    let home = ProcessInfo.processInfo.environment["MACBUTLER_HOME"].map { ($0 as NSString).expandingTildeInPath } ?? (NSHomeDirectory() + "/.macbutler")
    let p = home + "/butler.sock"
    let s = socket(AF_UNIX, SOCK_STREAM, 0)
    guard s >= 0 else { return false }
    defer { close(s) }
    var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(p.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in for (i, b) in bytes.enumerated() { raw[i] = b }; raw[bytes.count] = 0 }
    let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard ok == 0 else { return false }
    let msg = Array((cmd + "\n" + text).utf8)
    _ = msg.withUnsafeBytes { write(s, $0.baseAddress, msg.count) }
    shutdown(s, SHUT_WR)
    var b = [UInt8](repeating: 0, count: 8); _ = read(s, &b, 8)
    return true
}

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func frame(_ e: AXUIElement) -> CGRect? {
    var p = CGPoint.zero, s = CGSize.zero
    guard let pv = attr(e, "AXPosition"), let sv = attr(e, "AXSize") else { return nil }
    AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func label(_ e: AXUIElement) -> String {
    for k in ["AXTitle", "AXDescription", "AXValue", "AXPlaceholderValue", "AXHelp"] {
        if let s = attr(e, k) as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    // text inside a link
    var out = ""
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] {
        if let s = attr(c, "AXValue") as? String ?? attr(c, "AXTitle") as? String { out += s + " " }
        if out.count > 80 { break }
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}
let safe = ProcessInfo.processInfo.environment["MACBUTLER_SAFE"] == "1"
let protectedApps: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
    "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
    "com.apple.ScriptEditor2", "com.apple.Automator", "com.apple.shortcuts", "com.apple.systempreferences",
    "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.SecurityAgent", "com.apple.UserNotificationCenter",
    "com.apple.coreservices.uiagent", "com.apple.installer", "com.apple.dt.Xcode", "com.apple.Console",
    "com.anthropic.claudefordesktop", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    "com.1password.1password", "com.bitwarden.desktop"]
func guardApp(_ bundle: String?, _ name: String?) {
    let own = ProcessInfo.processInfo.environment["MACBUTLER_BUNDLE"]
    if safe, let b = bundle, protectedApps.contains(b) || b == own {
        print("blocked: \(name ?? b) is protected in safe mode — ask the user to do this, or delegate to a Claude session"); exit(3)
    }
}
func appBundle(pid: pid_t) -> (String?, String?) { let a = NSRunningApplication(processIdentifier: pid); return (a?.bundleIdentifier, a?.localizedName) }

let clickable: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXTab", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXCell", "AXRow", "AXMenuButton", "AXDisclosureTriangle"]
let fields: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

guard let front = NSWorkspace.shared.frontmostApplication else { print("no frontmost app"); exit(1) }

// Commands that don't need the element tree
let args0 = Array(CommandLine.arguments.dropFirst())
if args0.first == "open-url", args0.count >= 2 {
    guard let u = URL(string: args0[1]), ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { print("only http(s) URLs"); exit(2) }
    NSWorkspace.shared.open(u); print("opened \(u.absoluteString)"); exit(0)
}
if args0.first == "open-app", args0.count >= 2 {
    let want = args0.dropFirst().joined(separator: " ").lowercased().replacingOccurrences(of: ".app", with: "")
    var found: URL?
    for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".app") {
            let u = URL(fileURLWithPath: dir).appendingPathComponent(f)
            let names = [String(f.dropLast(4)), FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")].map { $0.lowercased() }
            if names.contains(want) { found = u; break }
        }
        if found != nil { break }
    }
    guard let app = found else { print("app not found: \(want)"); exit(2) }
    guardApp(Bundle(url: app)?.bundleIdentifier, app.lastPathComponent)
    let sem = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in sem.signal() }
    _ = sem.wait(timeout: .now() + 5); print("opened \(app.lastPathComponent)"); exit(0)
}
if args0.first == "screenshot" {
    let dir = "/tmp/macbutler"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let f = dir + "/screen.png"
    for (tool, args) in [("/usr/sbin/screencapture", ["-x", f]), ("/usr/bin/sips", ["-Z", "1280", f])] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; try? p.run(); p.waitUntilExit()
    }
    let w = NSScreen.main?.frame.width ?? 1280
    print("\(f)  (1 px = \(String(format: "%.2f", w / 1280)) pt; multiply image x/y by that for jax click)"); exit(0)
}
if args0.first == "click", args0.count >= 3, let x = Double(args0[1]), let y = Double(args0[2]) {
    var el: AXUIElement?
    AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(x), Float(y), &el)
    var pid: pid_t = 0
    if let el { AXUIElementGetPid(el, &pid) }
    let (b, n) = appBundle(pid: pid); guardApp(b, n)
    if let el, AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { print("pressed at \(Int(x)),\(Int(y)) in \(n ?? "?")"); exit(0) }
    let c = Process(); c.executableURL = URL(fileURLWithPath: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/cliclick") ? "/opt/homebrew/bin/cliclick" : "/usr/local/bin/cliclick")
    c.arguments = ["-r", "c:\(Int(x)),\(Int(y))"]; try? c.run(); c.waitUntilExit(); print("clicked \(Int(x)),\(Int(y)) in \(n ?? "?")"); exit(0)
}
if args0.first == "key", args0.count >= 2 {
    let fa = NSWorkspace.shared.frontmostApplication; guardApp(fa?.bundleIdentifier, fa?.localizedName)
    let names: [String: CGKeyCode] = ["enter": 36, "return": 36, "tab": 48, "space": 49, "delete": 51, "esc": 53, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126, "pageup": 116, "pagedown": 121, "home": 115, "end": 119,
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, ",": 43, ".": 47, "/": 44, "[": 33, "]": 30, "=": 24, "-": 27]
    var flags: CGEventFlags = []; var code: CGKeyCode?
    for part in args0[1].lowercased().split(separator: "+").map(String.init) {
        switch part {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: code = names[part]
        }
    }
    guard let code else { print("unknown key: \(args0[1])"); exit(2) }
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] { let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down); e?.flags = flags; e?.post(tap: .cghidEventTap) }
    print("pressed \(args0[1])"); exit(0)
}
if args0.first == "volume", args0.count >= 2, let v = Int(args0[1]), (0...100).contains(v) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", "set volume output volume \(v)"]
    try? p.run(); p.waitUntilExit(); print("volume \(v)"); exit(0)
}
let app = AXUIElementCreateApplication(front.processIdentifier)
AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
usleep(120_000)
guard let w = attr(app, "AXFocusedWindow") ?? (attr(app, "AXWindows") as? [AXUIElement])?.first as AnyObject? else { print("no window"); exit(1) }
let win = w as! AXUIElement

var items: [(AXUIElement, String, String, CGRect)] = []
var n = 0
func walk(_ e: AXUIElement, _ d: Int) {
    n += 1
    if d > 60 || n > 15000 { return }
    let role = attr(e, "AXRole") as? String ?? ""
    if clickable.contains(role) || fields.contains(role), let f = frame(e), f.width > 2, f.height > 2 {
        let l = label(e)
        if !l.isEmpty || fields.contains(role) { items.append((e, role, l, f)) }
    }
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(c, d + 1) }
}
walk(win, 0)

func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
func pick(_ q: String, _ idx: Int, _ pool: [(AXUIElement, String, String, CGRect)]) -> (AXUIElement, String, String, CGRect)? {
    let w = norm(q)
    let exact = pool.filter { norm($0.2) == w }
    let pre = pool.filter { norm($0.2).hasPrefix(w) && norm($0.2) != w }
    let has = pool.filter { norm($0.2).contains(w) && !norm($0.2).hasPrefix(w) }
    let all = exact + pre + has
    return idx - 1 < all.count ? all[idx - 1] : nil
}
func press(_ e: AXUIElement, _ f: CGRect) -> Bool {
    if AXUIElementPerformAction(e, kAXPressAction as CFString) == .success { return true }
    // Only if AXPress is unsupported: click and put the pointer straight back (barely visible)
    let c = Process(); c.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/cliclick")
    c.arguments = ["-r", "c:\(Int(f.midX)),\(Int(f.midY))"]; try? c.run(); c.waitUntilExit()
    return true
}

let a = Array(CommandLine.arguments.dropFirst())
switch a.first ?? "list" {
case "front":
    let title = attr(win, "AXTitle") as? String ?? ""
    let url = items.first { fields.contains($0.1) && ($0.2.lowercased().contains("address") || $0.2.contains("주소") || $0.2.contains("검색")) }
    print("app: \(front.localizedName ?? "")\nwindow: \(title)" + (url.map { "\naddress: " + ((attr($0.0, "AXValue") as? String) ?? "") } ?? ""))
case "tap":
    guardApp(front.bundleIdentifier, front.localizedName)
    guard a.count >= 2 else { print("jax tap \"name\" [n]"); exit(1) }
    let pool = items.filter { clickable.contains($0.1) }
    guard let hit = pick(a[1], a.count >= 3 ? Int(a[2]) ?? 1 : 1, pool) else { print("not found: \(a[1]) (\(pool.count) candidates — try jax list)"); exit(2) }
    _ = press(hit.0, hit.3)
    print("pressed: \(hit.1) \"\(hit.2.prefix(60))\"")
case "field":
    guardApp(front.bundleIdentifier, front.localizedName)
    guard a.count >= 3 else { print("jax field \"field name\" \"text\""); exit(1) }
    let pool = items.filter { fields.contains($0.1) }
    let hit = a[1].isEmpty ? pool.first : (pick(a[1], 1, pool) ?? pool.first)
    guard let hit else { print("no text field"); exit(2) }
    AXUIElementSetAttributeValue(hit.0, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    usleep(150_000)
    let text = a[2]
    _ = butlerSend("type", text)
    usleep(useconds_t(min(Double(text.count) * 0.03 + 0.3, 6) * 1_000_000))
    print("typed \(text.count) chars into \"\(hit.2.prefix(40))\"")
default:
    let f = a.count >= 2 ? norm(a[1]) : ""
    let shown = items.filter { f.isEmpty || norm($0.2).contains(f) }.prefix(150)
    print("\(front.localizedName ?? "") · \(items.count) elements (showing \(shown.count))")
    for (i, it) in shown.enumerated() { print("\(i + 1). \(it.1.replacingOccurrences(of: "AX", with: "")) | \(it.2.prefix(70))") }
}
