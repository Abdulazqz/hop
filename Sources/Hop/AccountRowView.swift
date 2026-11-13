import AppKit

/// One account row in the status menu, drawn as a view so it can carry its own buttons. Clicking the row runs
/// its main action (switch to the account, or get its setup-token); the icons on the right open Terminal on the
/// account and open its Claude app (⌥-click to quit it), with no submenu to hover through first.
@MainActor
final class AccountRowView: NSView {
    struct Content {
        var name: String
        var color: NSColor
        var desktopRunning: Bool
        var isActive: Bool
        /// "⌃⌥3", shown right-aligned like a key equivalent.
        var hint: String?
        var help: String
        /// The terminal button's tooltip; nil when the account has no setup-token, which dims the button.
        var terminalHelp: String?
        /// The Claude app's icon; nil when the app isn't installed, which leaves the button out.
        var appIcon: NSImage?
        var appHelp: String
    }

    var onRow: () -> Void = {}
    var onTerminal: () -> Void = {}
    /// Called with true for ⌥-click (quit) and false for a plain click (open or bring to front).
    var onApp: (_ quit: Bool) -> Void = { _ in }

    private let check = NSImageView()
    private let dot = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let terminal = NSButton()
    private let app = NSButton()
    private let hasApp: Bool

    /// Matches the system menu: taller rows and rounder highlights from macOS 26 on.
    private enum Metrics {
        static let modern = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
        static let height: CGFloat = modern ? 24 : 22
        static let highlightInset: CGFloat = 5
        static let highlightRadius: CGFloat = modern ? 6 : 4
        static let checkX: CGFloat = 9
        static let dotX: CGFloat = 22
        static let nameX: CGFloat = 38
        static let button: CGFloat = 20
        static let buttonGap: CGFloat = 4
        static let hintGap: CGFloat = 14
        static let trailing: CGFloat = 12
    }

    init(_ content: Content) {
        hasApp = content.appIcon != nil
        super.init(frame: .zero)

        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        check.isHidden = !content.isActive

        let image = Dot.image(color: content.color, filled: content.desktopRunning)
        image.accessibilityDescription = content.desktopRunning ? "Claude app running" : "Claude app closed"
        dot.image = image

        let font = NSFont.menuFont(ofSize: 0)
        name.stringValue = content.name
        name.font = font
        name.lineBreakMode = .byTruncatingTail
        hint.stringValue = content.hint ?? ""
        hint.font = font
        hint.alignment = .right
        hint.isHidden = content.hint == nil

        configure(terminal,
                  image: NSImage(systemSymbolName: "terminal", accessibilityDescription: "Open Terminal")?
                    .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)),
                  help: content.terminalHelp ?? "Add a setup-token first: click the row",
                  action: #selector(terminalClicked))
        terminal.isEnabled = content.terminalHelp != nil
        configure(app, image: content.appIcon, help: content.appHelp, action: #selector(appClicked))
        app.isHidden = !hasApp

        [check, dot, name, hint, terminal, app].forEach(addSubview)
        toolTip = content.help
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(content.name + (content.isActive ? ", active" : ""))

        frame = NSRect(x: 0, y: 0, width: naturalWidth, height: Metrics.height)
        autoresizingMask = [.width]   // stretch to the menu's width, so the hint and icons sit at the right edge
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func configure(_ button: NSButton, image: NSImage?, help: String, action: Selector) {
        button.image = image
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.target = self
        button.action = action
    }

    private var buttonsWidth: CGFloat {
        Metrics.button + (hasApp ? Metrics.buttonGap + Metrics.button : 0)
    }

    private var naturalWidth: CGFloat {
        let hintWidth = hint.isHidden ? 0 : hint.intrinsicContentSize.width + Metrics.hintGap
        return Metrics.nameX + name.intrinsicContentSize.width + Metrics.hintGap + hintWidth + buttonsWidth + Metrics.trailing
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        func centered(_ size: NSSize, x: CGFloat) -> NSRect {
            NSRect(x: x, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
        }
        check.frame = centered(NSSize(width: 12, height: 12), x: Metrics.checkX)
        dot.frame = centered(NSSize(width: 10, height: 10), x: Metrics.dotX)

        var right = bounds.width - Metrics.trailing
        if hasApp {
            app.frame = centered(NSSize(width: Metrics.button, height: Metrics.button), x: right - Metrics.button)
            right -= Metrics.button + Metrics.buttonGap
        }
        terminal.frame = centered(NSSize(width: Metrics.button, height: Metrics.button), x: right - Metrics.button)
        right -= Metrics.button + Metrics.hintGap

        let labelHeight = name.intrinsicContentSize.height
        if !hint.isHidden {
            let width = hint.intrinsicContentSize.width
            hint.frame = centered(NSSize(width: width, height: labelHeight), x: right - width)
            right -= width + Metrics.hintGap
        }
        name.frame = centered(NSSize(width: max(0, right - Metrics.nameX), height: labelHeight), x: Metrics.nameX)
    }

    private var isHighlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    /// Text and icons switch to the selected-item colors while the row is highlighted, like a native item.
    override func viewWillDraw() {
        let lit = isHighlighted
        let text: NSColor = lit ? .selectedMenuItemTextColor : .labelColor
        name.textColor = text
        check.contentTintColor = text
        hint.textColor = lit ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.7) : .secondaryLabelColor
        terminal.contentTintColor = lit ? .selectedMenuItemTextColor : .secondaryLabelColor
        terminal.alphaValue = terminal.isEnabled ? 1 : 0.35
        super.viewWillDraw()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Metrics.highlightInset, dy: 0),
                     xRadius: Metrics.highlightRadius, yRadius: Metrics.highlightRadius).fill()
    }

    /// A click anywhere on the row but its buttons (they take their own clicks).
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        closeMenu(then: onRow)
    }

    @objc private func terminalClicked() { closeMenu(then: onTerminal) }

    @objc private func appClicked() {
        let quit = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        let onApp = self.onApp
        closeMenu { onApp(quit) }
    }

    /// Closes the menu first, then acts, so a dialog or new window doesn't open under a still-open menu.
    private func closeMenu(then action: @escaping () -> Void) {
        enclosingMenuItem?.menu?.cancelTracking()
        Task { @MainActor in action() }
    }
}
