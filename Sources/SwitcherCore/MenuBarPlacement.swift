import CoreGraphics
import Foundation

public enum MenuBarPlacement {
    /// Whether macOS has hidden a status item behind a display notch.
    ///
    /// On a notched screen, status items are laid out right of the notch; when that side is full,
    /// AppKit still places new items, but at x positions inside or left of the notch, where nothing
    /// is drawn. `safeTopRight` is the screen's `auxiliaryTopRightArea`: the strip of menu bar to
    /// the right of the notch, or `nil` on screens without one, where items are never hidden this way.
    public static func isHiddenByNotch(itemFrame: CGRect, safeTopRight: CGRect?) -> Bool {
        guard let safeTopRight else { return false }
        return itemFrame.minX < safeTopRight.minX
    }
}
