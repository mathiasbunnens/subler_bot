import AppKit
import XCTest
@testable import AutomationCore

final class MenuBarIconRendererTests: XCTestCase {
    private func bitmap(_ image: NSImage) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 40, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Pixel at image point (x, y), AppKit unflipped coordinates (high y = top).
    private func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> NSColor {
        rep.colorAt(x: Int(x * 2), y: rep.pixelsHigh - 1 - Int(y * 2))!.usingColorSpace(.deviceRGB)!
    }

    private func isOpaqueDarkOrLight(_ color: NSColor) -> Bool {
        let gray = max(color.redComponent, color.greenComponent, color.blueComponent)
        let spread = gray - min(color.redComponent, color.greenComponent, color.blueComponent)
        return color.alphaComponent > 0.5 && spread < 0.1 && (gray < 0.15 || gray > 0.9)
    }

    func testBadgeHasNoOpaqueBackdropInEitherAppearance() {
        let badges: [(String, NSColor)] = [("exclamationmark.triangle.fill", .systemOrange), ("checkmark.circle.fill", .systemGreen)]
        for dark in [true, false] {
            for (symbol, color) in badges {
                let rep = bitmap(MenuBarIconRenderer.image(symbol: "film", dark: dark, badge: (symbol, color)))
                let rect = MenuBarIconRenderer.badgeRect
                // Badge corners lie outside the triangle/circle glyph: a filled backdrop made them opaque.
                for (x, y) in [(rect.minX + 1.25, rect.maxY - 1.25), (rect.maxX - 1.25, rect.maxY - 1.25), (rect.minX + 0.25, rect.minY + 0.25)] {
                    XCTAssertLessThan(pixel(rep, x, y).alphaComponent, 0.1, "\(symbol) dark=\(dark) corner (\(x), \(y)) must be transparent")
                }
                var badgePixels = 0
                for px in stride(from: rect.minX, to: rect.maxX, by: 0.5) {
                    for py in stride(from: rect.minY, to: rect.maxY, by: 0.5) {
                        let c = pixel(rep, px, py)
                        XCTAssertFalse(isOpaqueDarkOrLight(c) && (dark ? c.redComponent < 0.15 : c.redComponent > 0.9),
                            "\(symbol) dark=\(dark): no black/white backdrop pixel at (\(px), \(py))")
                        if c.alphaComponent > 0.5 && c.saturationComponent > 0.5 { badgePixels += 1 }
                    }
                }
                XCTAssertGreaterThan(badgePixels, 20, "\(symbol) must still be drawn in colour")
            }
        }
    }

    func testBaseGlyphIsClearedAroundTheBadgeButKeptElsewhere() {
        let plain = bitmap(MenuBarIconRenderer.image(symbol: "film", dark: true, badge: nil))
        let badged = bitmap(MenuBarIconRenderer.image(symbol: "film", dark: true, badge: ("exclamationmark.triangle.fill", .systemOrange)))
        var cleared = 0, kept = 0
        for px in stride(from: 0, to: 22, by: 0.5) {
            for py in stride(from: 0, to: 20, by: 0.5) {
                let before = pixel(plain, px, py), after = pixel(badged, px, py)
                if before.alphaComponent > 0.5 && after.alphaComponent < 0.1 { cleared += 1 }
                if px > 12 || py < 8 { if before.alphaComponent > 0.5 { XCTAssertGreaterThan(after.alphaComponent, 0.5); kept += 1 } }
            }
        }
        XCTAssertGreaterThan(cleared, 0, "a transparent gap separates the badge from the base glyph")
        XCTAssertGreaterThan(kept, 20)
    }
}
