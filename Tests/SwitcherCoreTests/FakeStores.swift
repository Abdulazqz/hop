import Foundation
@testable import SwitcherCore

final class FakeLoginStore: LoginStore {
    var live: Data?
    var saved: [UUID: Data] = [:]
    var liveWrites: [Data] = []
    var failLiveWrite = false
    func readLive() throws -> Data? { live }
    func writeLive(_ value: Data) throws {
        if failLiveWrite { throw SwitchError.store("keychain write failed") }
        live = value; liveWrites.append(value)
    }
    func readSaved(_ accountID: UUID) throws -> Data? { saved[accountID] }
    func writeSaved(_ value: Data, for accountID: UUID) throws { saved[accountID] = value }
    func deleteSaved(_ accountID: UUID) throws { saved[accountID] = nil }
}

final class FakeIdentityStore: IdentityDocumentStore {
    var document: Data?
    var failWrite = false
    var writes = 0
    func read() throws -> Data? { document }
    func write(_ document: Data) throws {
        if failWrite { throw SwitchError.store("disk full") }
        self.document = document; writes += 1
    }
}
