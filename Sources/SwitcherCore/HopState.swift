import Foundation

/// What Hop last did to the shared login. Lets Hop recognize its own write later without storing the token.
public struct HopState: Codable, Equatable {
    public var version: Int = 1
    public var activeAccountID: UUID?
    public var writtenRefreshTokenSHA256: String?

    public init(activeAccountID: UUID? = nil, writtenRefreshTokenSHA256: String? = nil) {
        self.activeAccountID = activeAccountID
        self.writtenRefreshTokenSHA256 = writtenRefreshTokenSHA256
    }

    public static let empty = HopState()

    /// Missing or unreadable state means "Hop hasn't switched yet".
    public static func load(from url: URL) -> HopState {
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(HopState.self, from: data) else {
            return .empty
        }
        return state
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
