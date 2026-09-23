import Foundation

public enum OpenAction: Equatable {
    case focusRunning, focusPending, wait, launch
}

public enum OpenDecision {
    /// running: the tracker maps this account to a live instance.
    /// launching: an openApplication call for it hasn't completed yet.
    /// pendingAlive: it was launched and the returned app hasn't terminated, but the tracker doesn't list it yet.
    public static func decide(running: Bool, launching: Bool, pendingAlive: Bool) -> OpenAction {
        if running { return .focusRunning }
        if launching { return .wait }
        if pendingAlive { return .focusPending }
        return .launch
    }
}
