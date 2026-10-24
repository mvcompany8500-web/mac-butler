// butler-mcp — Sasarisa's hands as an MCP server (stdio, JSON-RPC 2.0, one message per line).
// Every brain gets the same tool box: Claude Code and other agent CLIs load it as an MCP server, and the
// app's own API brains (OpenAI, Anthropic, OpenAI-compatible) talk to it the same way. There is no shell here:
// each tool runs one bundled tool (`jax`, `butler`) with a fixed argument list, so the safe-mode guards in
// those tools (protected apps, send/pay confirmation, password fields) hold whatever brain is calling.
import Foundation

let binDir = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()

struct Tool { let name: String; let desc: String; let props: [String: [String: Any]]; let required: [String] }
func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
func i(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
let tools: [Tool] = [
    Tool(name: "list", desc: "List pressable buttons, links and text fields of the frontmost app (role | name). Use before screenshot.", props: ["filter": s("only names containing this text")], required: []),
    Tool(name: "tap", desc: "Press the n-th (default 1) button/link/menu item whose name contains `name`, without moving the mouse.", props: ["name": s("part of the element's name"), "n": i("which match, 1-based")], required: ["name"]),
    Tool(name: "field", desc: "Focus a text field (by part of its name; empty = first field) and type text into it, visibly.", props: ["field": s("part of the field's name, or empty"), "text": s("what to type")], required: ["field", "text"]),
    Tool(name: "type", desc: "Type text into whatever field is focused now, character by character (Hangul OK).", props: ["text": s("what to type")], required: ["text"]),
    Tool(name: "key", desc: "Press a key or shortcut: enter, esc, tab, up, cmd+t, cmd+shift+n …", props: ["keys": s("e.g. cmd+t")], required: ["keys"]),
    Tool(name: "front", desc: "Frontmost app, window title and (browsers) the address bar.", props: [:], required: []),
    Tool(name: "volume", desc: "Set the output volume 0–100.", props: ["level": i("0–100")], required: ["level"]),
    Tool(name: "open_app", desc: "Open an app by name.", props: ["name": s("app name, e.g. Safari")], required: ["name"]),
    Tool(name: "open_url", desc: "Open an http(s) web page in the browser.", props: ["url": s("https://…")], required: ["url"]),
    Tool(name: "screenshot", desc: "Look at the screen (last resort — try list first). Returns the image and the scale for click.", props: [:], required: []),
    Tool(name: "click", desc: "Press whatever is at screen point x,y in points (pointer snaps back). Only when list/tap can't find it.", props: ["x": i("points"), "y": i("points")], required: ["x", "y"]),
    Tool(name: "delegate", desc: "Hand a task to a Claude Code session in the Claude app. session: its name, \".\" = the one in front, empty = a new session.", props: ["session": s("session name, \".\" or empty"), "task": s("the full instruction")], required: ["session", "task"]),
    Tool(name: "switch_session", desc: "Switch the Claude app to a session by name (navigation only, nothing typed).", props: ["name": s("session name")], required: ["name"]),
    Tool(name: "now", desc: "The current date and time.", props: [:], required: []),
]

/// Runs one bundled tool with a fixed argument list (no shell) and returns (exit code, output).
func run(_ tool: String, _ args: [String], timeout: TimeInterval = 25) -> (Int32, String) {
    let p = Process()
    p.executableURL = tool.hasPrefix("/") ? URL(fileURLWithPath: tool) : binDir.appendingPathComponent(tool)
    p.arguments = args
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    do { try p.run() } catch { return (127, "could not start \(tool): \(error.localizedDescription)") }
    let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit(); killer.cancel()
    return (p.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
}

func str(_ a: [String: Any], _ k: String) -> String? {
    if let v = a[k] as? String { return v }
    if let v = a[k] as? NSNumber { return v.stringValue }
    return nil
}

/// One tool call → MCP content blocks.
func call(_ name: String, _ a: [String: Any]) -> (content: [[String: Any]], isError: Bool) {
    func text(_ r: (Int32, String)) -> ([[String: Any]], Bool) { ([["type": "text", "text": r.1.isEmpty ? (r.0 == 0 ? "ok" : "failed") : r.1]], r.0 != 0) }
    func need(_ k: String) -> String? { str(a, k).flatMap { $0.isEmpty ? nil : $0 } }
    switch name {
    case "list": return text(run("jax", ["list"] + (need("filter").map { [$0] } ?? [])))
    case "tap":
        guard let n = need("name") else { return text((2, "name is required")) }
        return text(run("jax", ["tap", n] + (need("n").map { [$0] } ?? [])))
    case "field":
        guard let t = str(a, "text") else { return text((2, "text is required")) }
        return text(run("jax", ["field", str(a, "field") ?? "", t]))
    case "type":
        guard let t = str(a, "text"), !t.isEmpty else { return text((2, "text is required")) }
        let r = run("butler", ["type", t])
        if r.0 == 0 { Thread.sleep(forTimeInterval: min(Double(t.count) * 0.03 + 0.3, 6)) }
        return text(r.0 == 0 && r.1.isEmpty ? (0, "typed \(t.count) chars") : r)
    case "key":
        guard let k = need("keys") else { return text((2, "keys is required")) }
        return text(run("jax", ["key", k]))
    case "front": return text(run("jax", ["front"]))
    case "volume":
        guard let v = need("level") else { return text((2, "level is required")) }
        return text(run("jax", ["volume", v]))
    case "open_app":
        guard let n = need("name") else { return text((2, "name is required")) }
        return text(run("jax", ["open-app", n]))
    case "open_url":
        guard let u = need("url") else { return text((2, "url is required")) }
        return text(run("jax", ["open-url", u]))
    case "click":
        guard let x = need("x"), let y = need("y") else { return text((2, "x and y are required")) }
        return text(run("jax", ["click", x, y]))
    case "screenshot":
        let r = run("jax", ["screenshot"])
        let path = String(r.1.split(separator: " ").first ?? "")
        guard r.0 == 0, path.hasPrefix("/"), let png = FileManager.default.contents(atPath: path) else { return text(r) }
        let note = r.1.dropFirst(path.count).trimmingCharacters(in: .whitespaces)
        return ([["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"], ["type": "text", "text": "screen \(note)"]], false)
    case "delegate":
        guard let t = need("task") else { return text((2, "task is required")) }
        let session = (str(a, "session") ?? "").replacingOccurrences(of: "|", with: " ")
        return text(run("butler", ["delegate", session + "|" + t]))
    case "switch_session":
        guard let n = need("name") else { return text((2, "name is required")) }
        return text(run("butler", ["session", n]))
    case "now": return text(run("/bin/date", []))
    default: return text((2, "unknown tool: \(name)"))
    }
}

func reply(_ id: Any, result: Any? = nil, error: (Int, String)? = nil) {
    var msg: [String: Any] = ["jsonrpc": "2.0", "id": id]
    if let error { msg["error"] = ["code": error.0, "message": error.1] } else { msg["result"] = result ?? [:] }
    guard var d = try? JSONSerialization.data(withJSONObject: msg) else { return }
    d.append(0x0A)
    FileHandle.standardOutput.write(d)
}

let version = ProcessInfo.processInfo.environment["MACBUTLER_VERSION"] ?? "0"
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
    let method = obj["method"] as? String ?? ""
    guard let id = obj["id"] else { continue }          // notifications (initialized, cancelled) need no answer
    let params = obj["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        reply(id, result: ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                           "capabilities": ["tools": [:]], "serverInfo": ["name": "butler", "version": version]])
    case "ping": reply(id)
    case "tools/list":
        reply(id, result: ["tools": tools.map { t in
            ["name": t.name, "description": t.desc,
             "inputSchema": ["type": "object", "properties": t.props, "required": t.required] as [String: Any]] as [String: Any]
        }])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        let r = call(name, params["arguments"] as? [String: Any] ?? [:])
        reply(id, result: ["content": r.content, "isError": r.isError])
    default: reply(id, error: (-32601, "method not found: \(method)"))
    }
}
