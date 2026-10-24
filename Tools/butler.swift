// Talk to the running Mac Butler.   butler <say|type|delegate|settings> [text]
//   say       "open chrome"            — run a command as if spoken
//   type      "hello"                  — type into the focused field, character by character
//   delegate  "session name|task"      — hand a task to Claude (empty session name = new session)
//   settings  [close]                  — open (or close) the settings window
//   session   "name"                   — switch the Claude app to that session (no typing)
// Uses a private Unix socket (owner-only); other users and sandboxed apps can't send commands.
import Foundation

/// Sends "<cmd>\n<text>" to the running Mac Butler over its private socket (~/.macbutler/butler.sock).
func butlerSend(_ cmd: String, _ text: String) -> String? {
    let home = ProcessInfo.processInfo.environment["MACBUTLER_HOME"].map { ($0 as NSString).expandingTildeInPath } ?? (NSHomeDirectory() + "/.macbutler")
    let p = home + "/butler.sock"
    let s = socket(AF_UNIX, SOCK_STREAM, 0)
    guard s >= 0 else { return nil }
    defer { close(s) }
    var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(p.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in for (i, b) in bytes.enumerated() { raw[i] = b }; raw[bytes.count] = 0 }
    let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard ok == 0 else { return nil }
    let msg = Array((cmd + "\n" + text).utf8)
    _ = msg.withUnsafeBytes { write(s, $0.baseAddress, msg.count) }
    shutdown(s, SHUT_WR)
    var b = [UInt8](repeating: 0, count: 64); let n = read(s, &b, 64)
    return n > 0 ? String(decoding: b[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
}

let a = CommandLine.arguments
guard a.count >= 2, ["say", "type", "delegate", "settings", "session", "setup"].contains(a[1]) else { print("usage: butler <say|type|delegate|settings|session|setup> [text]"); exit(1) }
guard let answer = butlerSend(a[1], a.dropFirst(2).joined(separator: " ")) else { print("Mac Butler is not running"); exit(2) }
_ = answer
if a[1] == "delegate", answer == "sent" { print("sent — free mode: Mac Butler typed the task into the Claude session. Say briefly that it was handed over."); exit(0) }
if a[1] == "delegate" { print("pending — Mac Butler holds the task until the user says yes. In your answer, ASK whether to hand it over; do not say it was done.") }
