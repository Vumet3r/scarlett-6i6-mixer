import Foundation

enum ScarlettError: Error, LocalizedError {
    case notConnected
    case commandFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to daemon"
        case .commandFailed(let s): return s
        case .parseError(let s): return s
        }
    }
}

final class ScarlettClient: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "com.scarlett.client", qos: .userInitiated)

    init(path: String = "/tmp/scarlett-6i6.sock") {
        self.path = path
    }

    /// Open a new connection, send command, read response, close.
    private func sendInner(_ cmd: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ScarlettError.notConnected }

        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        path.withCString { src in
            withUnsafeMutableBytes(of: &addr.sun_path) { dst in
                _ = strncpy(dst.baseAddress!.assumingMemoryBound(to: CChar.self), src,
                        min(path.utf8.count, dst.count - 1))
            }
        }

        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { throw ScarlettError.notConnected }

        let cmdBytes = Array((cmd + "\n").utf8)
        let sent = cmdBytes.withUnsafeBytes { buf in
            Darwin.send(fd, buf.baseAddress, buf.count, 0)
        }
        guard sent == cmdBytes.count else {
            throw ScarlettError.commandFailed("write failed")
        }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBytes { bufPtr in
            Darwin.read(fd, bufPtr.baseAddress, bufPtr.count - 1)
        }
        guard n > 0 else {
            throw ScarlettError.commandFailed("read failed")
        }
        buf[n] = 0
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sync API

    func send(_ cmd: String) throws -> String {
        try queue.sync { try sendInner(cmd) }
    }

    func get(_ key: String) throws -> String {
        let resp = try send("GET \(key)")
        guard resp.hasPrefix("OK ") else {
            throw ScarlettError.commandFailed(resp)
        }
        return String(resp.dropFirst(3))
    }

    func set(_ key: String, _ value: String) throws {
        let resp = try send("SET \(key) \(value)")
        guard resp.hasPrefix("OK") else {
            throw ScarlettError.commandFailed(resp)
        }
    }

    func dump() throws -> [(String, String)] {
        let resp = try send("DUMP")
        guard resp.hasPrefix("OK") else {
            throw ScarlettError.commandFailed(resp)
        }
        let parts = resp.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return parts.split(separator: " ").compactMap { token in
            let kv = token.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            return (String(kv[0]), String(kv[1]))
        }
    }

    func getMeters() throws -> [UInt8] {
        let resp = try get("meters")
        return resp.split(separator: " ").compactMap { UInt8($0) }
    }

    /// Persist current settings to the device flash. Command is exactly
    /// "SET save" (no value argument), so it bypasses `set(_:_:)`.
    func saveToHardware() throws -> String {
        try send("SET save")
    }

    func saveToHardwareAsync() async throws -> String {
        try await sendAsync("SET save")
    }

    // MARK: - Async API

    func sendAsync(_ cmd: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                do { let resp = try self.sendInner(cmd); cont.resume(returning: resp) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}
