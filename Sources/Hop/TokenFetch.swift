import AppKit
import SwiftUI
import SwitcherCore

/// One "Get token" run for one account: drives `claude setup-token` and hands the token straight to
/// `onToken`. There is no confirm step: the user chose the account and signed in to it.
/// (Hop can't ask Anthropic which login a setup-token is for: its account lookup refuses these tokens.)
@MainActor
final class TokenFetchModel: ObservableObject, Identifiable {
    enum Phase {
        case waiting(browser: String?, signedInBefore: Bool)
        case failed(String)
    }

    let id = UUID()
    let account: Account
    @Published private(set) var phase: Phase = .waiting(browser: nil, signedInBefore: false)
    var onToken: ((String) -> Void)?
    private var runner: SetupTokenRunner?

    init(account: Account) {
        self.account = account
    }

    func start() {
        runner?.cancel()
        let runner = SetupTokenRunner(
            profileDirectory: BrowserProfileFile.url(for: account.id),
            onToken: { [weak self] token in self?.onToken?(token) },
            onFailure: { [weak self] failure in self?.phase = .failed(failure.localizedDescription) })
        self.runner = runner
        phase = .waiting(browser: runner.browser?.name, signedInBefore: runner.hasSignedInBefore)
        runner.start()
    }

    func cancel() {
        runner?.cancel()
        runner = nil
    }
}

/// The sheet shown while Hop gets a token. It closes on its own once the token is saved.
struct TokenFetchSheet: View {
    @ObservedObject var fetch: TokenFetchModel
    /// Saves the token on the account.
    let save: (String) -> Void
    let pasteInstead: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup-token for \u{201c}\(fetch.account.name)\u{201d}").font(.headline)
            content
        }
        .padding(16)
        .frame(width: 400)
        .onAppear {
            fetch.onToken = { token in
                save(token)
                dismiss()
            }
            fetch.start()
        }
        .onDisappear { fetch.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch fetch.phase {
        case .waiting(let browser, let signedInBefore):
            HStack(alignment: .top, spacing: 10) {
                ProgressView().controlSize(.small)
                Text(waitingText(browser, signedInBefore: signedInBefore)).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            buttons {
                Button("Paste a token instead\u{2026}", action: pasteInstead)
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
            }
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            buttons {
                Button("Paste a token instead\u{2026}", action: pasteInstead)
                Spacer()
                Button("Close", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Try Again") { fetch.start() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func waitingText(_ browser: String?, signedInBefore: Bool) -> String {
        let name = "\u{201c}\(fetch.account.name)\u{201d}"
        if let browser, signedInBefore {
            return "Click Authorize in the \(browser) window. (If it asks you to sign in, use \(name).) "
                + "Hop closes the window when it has the token."
        }
        if let browser {
            return "Sign in as \(name) in the new \(browser) window, then click Authorize. This window is only for \(name), "
                + "and it remembers the sign-in, so next time it's just Authorize. Hop closes it when it has the token."
        }
        return "Your browser opened claude.ai. Make sure you're signed in as \(name), then click Authorize."
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }.padding(.top, 4)
    }
}

/// Runs Get token in its own small window, for the menu's "Add a setup-token…": the browser opens at once,
/// without going through Edit accounts.
@MainActor
final class TokenFetchWindow {
    private let model: AppModel
    private let tokenStore: TokenStore
    private var window: NSWindow?

    init(model: AppModel, tokenStore: TokenStore = KeychainTokenStore()) {
        self.model = model
        self.tokenStore = tokenStore
    }

    func show(for account: Account) {
        close()
        NSApp.activate()
        let fetch = TokenFetchModel(account: account)
        let sheet = TokenFetchSheet(fetch: fetch) { [weak self] token in
            self?.store(token, for: account)
        } pasteInstead: { [weak self] in
            self?.close()
            DispatchQueue.main.async { self?.paste(for: account) }
        } dismiss: { [weak self] in
            self?.close()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: sheet))
        window.title = "Get setup-token"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func close() {
        // Deferred so the window isn't freed while one of its own buttons is still running.
        let window = self.window
        self.window = nil
        DispatchQueue.main.async { window?.close() }
    }

    private func paste(for account: Account) {
        guard let raw = TokenPrompt.paste(accountName: account.name) else { return }
        store(raw, for: account)
    }

    private func store(_ raw: String, for account: Account) {
        do {
            try model.storeToken(raw, for: account.id, in: tokenStore)
        } catch {
            Alerts.show("Couldn't save the setup-token", error.localizedDescription)
        }
    }
}
