import AppKit
import CoreServices

/// Brings one specific Claude instance to the front.
///
/// macOS 14+ uses cooperative activation: `activate()` from a background app returns
/// true but does nothing. So we take activation first (we're handling the user's click
/// or hotkey) and hand it over, then fall back to System Events if it didn't take.
@MainActor
enum Focuser {
    static func bringToFront(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        NSApp.activate()
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [.activateAllWindows])
        if !hasOnScreenWindow(pid) { sendReopen(to: pid) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else { return }
            NSLog("Hop: cooperative activation didn't take for pid %d; using System Events", pid)
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to set frontmost of (first process whose unix id is \(pid)) to true")?
                .executeAndReturnError(&error)
        }
    }

    private static func hasOnScreenWindow(_ pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }

    /// Same event as clicking the Dock icon: Electron shows its window again.
    private static func sendReopen(to pid: pid_t) {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        _ = try? event.sendEvent(options: [.noReply], timeout: 1)
    }
}
