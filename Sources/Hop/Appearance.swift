import AppKit
import SwitcherCore

extension AccountColor {
    var nsColor: NSColor {
        switch self {
        case .purple: .systemPurple
        case .teal: .systemTeal
        case .coral: .systemOrange
        case .pink: .systemPink
        case .blue: .systemBlue
        case .green: .systemGreen
        case .amber: .systemYellow
        case .red: .systemRed
        case .gray: .systemGray
        }
    }

    var label: String { rawValue.capitalized }
}

enum Dot {
    /// 10pt color dot: filled when running, ring when closed.
    static func image(color: NSColor, filled: Bool) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if filled {
                color.setFill()
                path.fill()
            } else {
                color.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
    }
}
