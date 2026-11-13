import Foundation

/// A failure while switching accounts. The pointer-based switch only ever fails at the file write,
/// surfaced with a human-readable message.
public enum SwitchError: Error, Equatable, LocalizedError {
    case store(String)
    public var errorDescription: String? {
        switch self {
        case .store(let message): return message
        }
    }
}
