// Local control channel for the bundled tools (`butler`, `jax field`).
// A Unix socket at ~/.macbutler/butler.sock, mode 0600, and every connection must come from the
// same user (getpeereid). Sandboxed apps can't reach it; other users can't connect.
// Wire format: "<command>\n<text>" — commands: say, type, delegate, settings.
import Foundation

final class ControlSocket {
    static var path: String { Paths.home.appendingPathComponent("butler.sock").path }
    private var fd: Int32 = -1
    private let handler: (String, String) -> Void

    init(handler: @escaping (String, String) -> Void) { self.handler = handler }

    func start() {
        let p = ControlSocket.path
        unlink(p)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { log("control socket: socket() failed"); return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(p.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { log("control socket: path too long"); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        let old = umask(0o177)                     // socket file created as 0600
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        umask(old)
        guard ok == 0, listen(fd, 8) == 0 else { log("control socket: bind/listen failed"); close(fd); return }
        chmod(p, 0o600)
        let me = getuid()
        Thread.detachNewThread { [weak self] in
            while let self, self.fd >= 0 {
                let c = accept(self.fd, nil, nil)
                if c < 0 { continue }
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(c, &uid, &gid) == 0, uid == me else { log("control socket: rejected uid \(uid)"); close(c); continue }
                var tv = timeval(tv_sec: 2, tv_usec: 0)
                setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var data = Data(), buf = [UInt8](repeating: 0, count: 4096)
                while data.count < 65_536 {
                    let n = read(c, &buf, buf.count)
                    if n <= 0 { break }
                    data.append(contentsOf: buf[0..<n])
                }
                write(c, "ok\n", 3)
                close(c)
                guard let s = String(data: data, encoding: .utf8) else { continue }
                let parts = s.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let cmd = String(parts.first ?? ""), text = parts.count > 1 ? String(parts[1]) : ""
                guard ["say", "type", "delegate", "settings", "session", "setup"].contains(cmd) else { continue }
                DispatchQueue.main.async { self.handler(cmd, text) }
            }
        }
        log("control socket ready")
    }

    func stop() { if fd >= 0 { close(fd); fd = -1 }; unlink(ControlSocket.path) }
}
