import Foundation
import SwiftUI
import AppKit

/// Redirect stderr to a file for crash diagnostics.
func setupCrashLog() {
    let logPath = "/tmp/scarlett-app-crash.log"
    if let f = fopen(logPath, "w") {
        dup2(fileno(f), STDERR_FILENO)
    }
    // Try to not die on SIGPIPE if stdout/stderr is a closed pipe
    signal(SIGPIPE, SIG_IGN)
}

final class ScarlettAppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    /// Launching a bare executable without Info.plist can default to the
    /// `.accessory` activation policy: the window accepts mouse clicks but
    /// never becomes key, so text fields can't be typed in.  Force regular.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            fputs("keyEvent chars=\(event.charactersIgnoringModifiers ?? "-")\n", stderr)
            return event
        }
    }

    /// Clean up the daemon we spawned on quit (Cmd+Q / last window closed).
    func applicationWillTerminate(_ notification: Notification) {
        DaemonManager.shared.shutdown()
    }

    /// Closing the window quits the app so the daemon never gets orphaned.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ScarlettApp: App {
    @NSApplicationDelegateAdaptor(ScarlettAppDelegate.self) private var appDelegate
    @StateObject private var vm = ScarlettViewModel()

    init() {
        setupCrashLog()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .task { await vm.connect() }
                .onDisappear { vm.disconnect() }
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowResizability(.contentSize)
    }
}
