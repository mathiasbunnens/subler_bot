import AppKit
import SwiftUI
import AutomationCore

enum MenuBarStatusImage {
    static func isFinished(jobs: [MovieJob], currentJob: MovieJob?, message: String?, hasCompletedThisSession: Bool = false) -> Bool {
        hasCompletedThisSession && currentJob == nil && message == nil && !jobs.isEmpty && jobs.allSatisfy {
            $0.status == .completed && $0.error == nil && !$0.needsSelection
        }
    }

    // AppKit image coordinates are unflipped: high y means TOP. Explicit top-left badge.
    static let badgeRect = NSRect(x: 0, y: 10, width: 10, height: 10)

    static func image(symbol: String, finished: Bool, dark: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 20)
        let image = NSImage(size: size, flipped: false) { _ in
            func drawSymbol(_ name: String, rect: NSRect, color: NSColor) {
                guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
                let tinted = NSImage(size: rect.size)
                tinted.lockFocus()
                glyph.draw(in: NSRect(origin: .zero, size: rect.size))
                color.setFill()
                NSRect(origin: .zero, size: rect.size).fill(using: .sourceIn)
                tinted.unlockFocus()
                tinted.draw(in: rect)
            }
            drawSymbol(symbol, rect: NSRect(x: 4, y: 1, width: 18, height: 16), color: dark ? .white : .black)
            if finished {
                (dark ? NSColor.black : NSColor.white).setFill()
                NSBezierPath(ovalIn: badgeRect.insetBy(dx: 1, dy: 1)).fill()
                drawSymbol("checkmark.circle.fill", rect: badgeRect, color: NSColor.systemGreen)
            }
            return true
        }
        // A template image would erase the green when MenuBarExtra applies its tint.
        image.isTemplate = false
        image.accessibilityDescription = finished ? "Tous les films sont terminés" : "Subler Automation"
        return image
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var queue: JobQueueService
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Image(nsImage: MenuBarStatusImage.image(symbol: queue.symbol,
            finished: MenuBarStatusImage.isFinished(jobs: queue.jobs, currentJob: queue.currentJob, message: queue.message, hasCompletedThisSession: queue.hasCompletedThisSession),
            dark: colorScheme == .dark))
    }
}
