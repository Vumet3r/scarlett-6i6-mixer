import Foundation

/// Owns the scarlett-daemon process: spawns it when the socket is dead and
/// respawns it if it crashes (bounded so we never enter a spawn storm).
@MainActor
final class DaemonManager {
    static let shared = DaemonManager()

    private var process: Process?
    private var spawnedAt: Date?
    private var respawnCount = 0
    private var everSpawned = false
    private let maxRespawns = 3
    private let logPath = "/tmp/scarlett-daemon.log"

    var isProcessRunning: Bool { process?.isRunning == true }

    /// True when the process is alive, or when we spawned one before and it
    /// died (used to distinguish "binary missing" from "keeps crashing").
    var hasOwnedProcess: Bool { everSpawned && (process == nil || process?.isRunning == true) }

    /// Known places to find the daemon binary, in priority order.
    static var candidates: [URL] {
        var list: [URL] = []
        if let env = ProcessInfo.processInfo.environment["SCARLETT_DAEMON"] {
            list.append(URL(fileURLWithPath: env))
        }
        // Dev build: executable lives in <proj>/fase-2-gui/scarlett-app/.build/...
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        list.append(exeDir.appendingPathComponent("../../../../../fase-1-daemon/build/scarlett-daemon"))
        // Properly packaged .app
        if let res = Bundle.main.resourceURL {
            list.append(res.appendingPathComponent("scarlett-daemon"))
        }
        // User-installed copy
        list.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".scarlett/scarlett-daemon"))
        return list
    }

    /// Spawn the daemon unless our own instance is already alive.
    @discardableResult
    func ensureRunning() -> Bool {
        if isProcessRunning { return true }
        if let p = process {
            // Previous instance died; back off before respawning.
            guard respawnCount < maxRespawns,
                  Date().timeIntervalSince(spawnedAt ?? .distantPast) > 2 else { return false }
        }
        for url in Self.candidates {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            spawn(url)
            if isProcessRunning { return true }
        }
        return false
    }

    /// Stop the daemon we own when the app quits.
    func shutdown() {
        if let p = process {
            process = nil
            if p.isRunning { p.terminate() }
        }
    }

    private func spawn(_ url: URL) {
        let p = Process()
        p.executableURL = url
        if let handle = logFileHandle() {
            p.standardOutput = handle
            p.standardError = handle
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.process = nil }
        }
        do {
            try p.run()
            process = p
            everSpawned = true
            respawnCount += 1
            spawnedAt = Date()
            fputs("daemon: spawned \(url.path)\n", stderr)
        } catch {
            fputs("daemon: spawn failed \(error)\n", stderr)
            process = nil
        }
    }

    private func logFileHandle() -> FileHandle? {
        FileManager.default.createFile(atPath: logPath, contents: nil)
        guard let handle = FileHandle(forUpdatingAtPath: logPath) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }
}