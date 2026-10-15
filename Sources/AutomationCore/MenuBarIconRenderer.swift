import AppKit

/// Draws the non-template menu-bar icon: a base glyph plus an optional coloured badge.
public enum MenuBarIconRenderer {
    // AppKit image coordinates are unflipped: high y means TOP. Explicit top-left badge.
    public static let badgeRect = NSRect(x: 0, y: 10, width: 10, height: 10)

    public static func image(symbol: String, dark: Bool, badge: (symbol: String, color: NSColor)?) -> NSImage {
        NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            func drawSymbol(_ name: String, rect: NSRect, color: NSColor, operation: NSCompositingOperation = .sourceOver) {
                guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
                let tinted = NSImage(size: rect.size)
                tinted.lockFocus()
                glyph.draw(in: NSRect(origin: .zero, size: rect.size))
                color.setFill()
                NSRect(origin: .zero, size: rect.size).fill(using: .sourceIn)
                tinted.unlockFocus()
                tinted.draw(in: rect, from: .zero, operation: operation, fraction: 1)
            }
            drawSymbol(symbol, rect: NSRect(x: 4, y: 1, width: 18, height: 16), color: dark ? .white : .black)
            if let badge {
                // The menu bar is translucent: never paint an opaque backdrop. Punch a slightly
                // larger badge silhouette out of the base glyph so a transparent gap separates them.
                drawSymbol(badge.symbol, rect: badgeRect.insetBy(dx: -1.5, dy: -1.5), color: .black, operation: .destinationOut)
                drawSymbol(badge.symbol, rect: badgeRect, color: badge.color)
            }
            return true
        }
    }
}
