import Foundation
@testable import SwitcherCore

final class FakeTokenStore: TokenStore {
    var tokens: [UUID: String] = [:]
    func readToken(_ id: UUID) throws -> String? { tokens[id] }
    func writeToken(_ token: String, for id: UUID) throws { tokens[id] = token }
    func deleteToken(_ id: UUID) throws { tokens[id] = nil }
}
