// jax — press buttons / links / text fields of the frontmost app by name, without moving the mouse (Accessibility).
//   jax list [filter]            list pressable things (role | name)
//   jax tap "name" [n]           press the n-th (default 1) element whose name contains the text
//   jax field "field name" "text"  focus a text field and type into it (visibly, via My Jarvis)
import AppKit
import ApplicationServices

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
let clickable: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXTab", "AXRadioButton", "AXCheckBox", "AXPopUpButton", "AXCell", "AXRow", "AXMenuButton", "AXDisclosureTriangle"]
let fields: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

guard let front = NSWorkspace.shared.frontmostApplication else { print("no frontmost app"); exit(1) }
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
case "tap":
    guard a.count >= 2 else { print("jax tap \"name\" [n]"); exit(1) }
    let pool = items.filter { clickable.contains($0.1) }
    guard let hit = pick(a[1], a.count >= 3 ? Int(a[2]) ?? 1 : 1, pool) else { print("not found: \(a[1]) (\(pool.count) candidates — try jax list)"); exit(2) }
    _ = press(hit.0, hit.3)
    print("pressed: \(hit.1) \"\(hit.2.prefix(60))\"")
case "field":
    guard a.count >= 3 else { print("jax field \"field name\" \"text\""); exit(1) }
    let pool = items.filter { fields.contains($0.1) }
    let hit = a[1].isEmpty ? pool.first : (pick(a[1], 1, pool) ?? pool.first)
    guard let hit else { print("no text field"); exit(2) }
    AXUIElementSetAttributeValue(hit.0, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    usleep(150_000)
    let text = a[2]
    DistributedNotificationCenter.default().postNotificationName(.init("com.myjarvis.type"), object: text, userInfo: nil, deliverImmediately: true)
    usleep(useconds_t(min(Double(text.count) * 0.03 + 0.3, 6) * 1_000_000))
    print("typed \(text.count) chars into \"\(hit.2.prefix(40))\"")
default:
    let f = a.count >= 2 ? norm(a[1]) : ""
    let shown = items.filter { f.isEmpty || norm($0.2).contains(f) }.prefix(150)
    print("\(front.localizedName ?? "") · \(items.count) elements (showing \(shown.count))")
    for (i, it) in shown.enumerated() { print("\(i + 1). \(it.1.replacingOccurrences(of: "AX", with: "")) | \(it.2.prefix(70))") }
}
