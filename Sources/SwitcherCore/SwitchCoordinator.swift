import Foundation

public protocol LoginStore {
    /// Claude Code's own item; nil when it doesn't exist.
    func readLive() throws -> Data?
    func writeLive(_ value: Data) throws
    /// Removes Claude Code's item; used only to undo a write Hop just made.
    func deleteLive() throws
    func readSaved(_ accountID: UUID) throws -> Data?
    func writeSaved(_ value: Data, for accountID: UUID) throws
    func deleteSaved(_ accountID: UUID) throws
}

public protocol IdentityDocumentStore {
    /// `~/.claude.json`; nil when the file doesn't exist.
    func read() throws -> Data?
    func write(_ document: Data) throws
}

public enum UnknownLoginChoice: Equatable {
    case attach(UUID)
    case create
}

public enum SwitchError: Error, Equatable, LocalizedError {
    case unrecognizedLogin(String)
    case targetHasNoLogin(String)
    case targetLoginExpired(name: String, on: Date)
    case alreadyActive(String)
    case cancelled(email: String)
    case store(String)
    case rolledBack(String)

    public var errorDescription: String? {
        switch self {
        case .unrecognizedLogin(let why): "Claude Code's login format changed (\(why)). Hop won't touch it."
        case .targetHasNoLogin(let name): "\(name) has no saved terminal login yet. Log in as it once, then switch to any other account so Hop can save it."
        case .targetLoginExpired(let name, let on):
            "\(name)'s saved login expired on \(on.formatted(date: .abbreviated, time: .omitted)). Log in as it once in Terminal."
        case .alreadyActive(let name): "\(name) is already the active account."
        case .cancelled(let email): "The current login (\(email)) isn't saved. Save it first, or the switch would lose it."
        case .store(let why): why
        case .rolledBack(let why): "Couldn't finish the switch (\(why)). The previous login was restored."
        }
    }
}

public struct SwitchResult: Equatable {
    public let from: UUID?
    public let to: UUID
    public let accounts: [Account]
    public let state: HopState
}

/// The switch procedure from the spec. Pure apart from the two stores it is given.
public struct SwitchCoordinator {
    private let logins: LoginStore
    private let identityDocument: IdentityDocumentStore
    private let home: String
    private let now: () -> Date

    public init(logins: LoginStore, identityDocument: IdentityDocumentStore, home: String, now: @escaping () -> Date = Date.init) {
        self.logins = logins
        self.identityDocument = identityDocument
        self.home = home
        self.now = now
    }

    public func switchTo(_ targetID: UUID, accounts: [Account], state: HopState,
                         resolveUnknown: (String) -> UnknownLoginChoice?) throws -> SwitchResult {
        guard let target = accounts.first(where: { $0.id == targetID }) else { throw SwitchError.store("unknown account") }
        // 1. Read everything before writing anything.
        let liveValue = try logins.readLive()
        let document = try identityDocument.read()
        let live = LiveLogin.parse(keychainValue: liveValue, identityDocument: document)
        if case .unrecognized(let why) = live { throw SwitchError.unrecognizedLogin(why) }

        // 3 (early). The target must be usable, so a refused switch never captures anything either.
        guard let savedData = try logins.readSaved(targetID) else { throw SwitchError.targetHasNoLogin(target.name) }
        let saved = try SavedLogin.decode(savedData)
        guard let refreshExpiry = saved.refreshTokenExpiresAt else { throw SwitchError.unrecognizedLogin("saved login has no expiry") }
        if refreshExpiry <= now().addingTimeInterval(60) { throw SwitchError.targetLoginExpired(name: target.name, on: refreshExpiry) }

        // 2. Attribute and save the outgoing login.
        var accounts = accounts
        var from: UUID?
        if case .loggedIn(let summary) = live, let liveValue, let document {
            let (outgoingID, updated) = try captureLive(summary: summary, liveValue: liveValue, document: document,
                                                        accounts: accounts, state: state, resolveUnknown: resolveUnknown)
            accounts = updated
            from = outgoingID
            if outgoingID == targetID { throw SwitchError.alreadyActive(target.name) }
        }

        // 4. Write: Keychain, then identity; undo the Keychain if the identity write fails.
        let newLive = try LiveLogin.replacingLoginSection(in: liveValue, with: saved.loginSection)
        let newDocument = try IdentityDocument.replacingIdentity(in: document, with: saved.identity)
        try logins.writeLive(newLive)
        do {
            try identityDocument.write(newDocument)
        } catch {
            if let liveValue { try? logins.writeLive(liveValue) } else { try? logins.deleteLive() }
            throw SwitchError.rolledBack(error.localizedDescription)
        }
        let newState = HopState(activeAccountID: targetID, writtenRefreshTokenSHA256: saved.refreshTokenSHA256)
        return SwitchResult(from: from, to: targetID, accounts: accounts, state: newState)
    }

    /// Menu action "Save current login as…": capture without switching.
    public func saveCurrentLogin(accounts: [Account], state: HopState, choice: UnknownLoginChoice) throws -> (accounts: [Account], state: HopState) {
        let liveValue = try logins.readLive()
        let document = try identityDocument.read()
        guard case .loggedIn(let summary) = LiveLogin.parse(keychainValue: liveValue, identityDocument: document),
              let liveValue, let document else {
            throw SwitchError.unrecognizedLogin("nothing is logged in")
        }
        let (id, updated) = try captureLive(summary: summary, liveValue: liveValue, document: document,
                                            accounts: accounts, state: state, resolveUnknown: { _ in choice })
        return (updated, HopState(activeAccountID: id, writtenRefreshTokenSHA256: summary.refreshTokenSHA256))
    }

    public func savedLoginExpiry(for accounts: [Account]) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for account in accounts {
            if let data = try? logins.readSaved(account.id), let saved = try? SavedLogin.decode(data), let expiry = saved.refreshTokenExpiresAt {
                result[account.id] = expiry
            }
        }
        return result
    }

    public static func newAccount(email: String, accounts: [Account], home: String) -> Account {
        let used = Set(accounts.map(\.color))
        let color = AccountColor.allCases.first { !used.contains($0) } ?? .gray
        let folder = NewAccountFolder.candidate(forName: email, accounts: accounts, home: home)
        return Account(name: email, color: color, folder: folder, email: email)
    }

    // MARK: - capture

    /// Saves the live login under the account it belongs to, creating or attaching when unknown.
    /// Returns that account's id and the (possibly extended) account list.
    private func captureLive(summary: LoginSummary, liveValue: Data, document: Data, accounts: [Account], state: HopState,
                             resolveUnknown: (String) -> UnknownLoginChoice?) throws -> (UUID, [Account]) {
        var accounts = accounts
        let section = try LiveLogin.loginSection(of: liveValue)
        var identity = try IdentityDocument.identity(of: document) ?? Data("{}".utf8)
        let outgoingID: UUID
        switch LoginAttribution.attribute(summary, accounts: accounts, state: state) {
        case .hopWrote(let id):
            outgoingID = id
            // A stale session may have rewritten the identity file; prefer the identity we saved for this account.
            if let data = try logins.readSaved(id), let previous = try? SavedLogin.decode(data),
               previous.email?.lowercased() != summary.email.lowercased() {
                identity = previous.identity
            }
        case .emailMatch(let id):
            outgoingID = id
        case .unknown(let email):
            switch resolveUnknown(email) {
            case .attach(let id)?:
                guard let index = accounts.firstIndex(where: { $0.id == id }) else { throw SwitchError.store("unknown account") }
                accounts[index].email = email
                outgoingID = id
            case .create?:
                let created = Self.newAccount(email: email, accounts: accounts, home: home)
                accounts.append(created)
                outgoingID = created.id
            case nil:
                throw SwitchError.cancelled(email: email)
            }
        }
        if let index = accounts.firstIndex(where: { $0.id == outgoingID }), accounts[index].email == nil {
            accounts[index].email = summary.email
        }
        let saved = SavedLogin(loginSection: section, identity: identity, capturedAt: now())
        try logins.writeSaved(try saved.encoded(), for: outgoingID)
        return (outgoingID, accounts)
    }
}
