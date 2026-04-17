import AppKit
import SwiftUI

@main
struct CHDMANApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppViewModel()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Window("CHDMAN", id: "main") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}
// MARK: - App Delegate (sets dock icon on launch)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = Self.makeIcon()
    }

    static func makeIcon() -> NSImage {
        let size: CGFloat = 512
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // Background — rounded rect with dark gradient
            let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 90, yRadius: 90)
            NSGradient(colors: [
                NSColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 1.0),
                NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
            ])?.draw(in: bg, angle: -90)

            // Rainbow stripes (retro Apple homage)
            let colors: [(CGFloat, CGFloat, CGFloat)] = [
                (0.20, 0.60, 0.86), // blue
                (0.61, 0.32, 0.71), // purple
                (0.91, 0.30, 0.24), // red
                (0.98, 0.56, 0.20), // orange
                (1.00, 0.82, 0.21), // yellow
                (0.38, 0.73, 0.33), // green
            ]
            let stripeH: CGFloat = 6
            let stripeY = size * 0.58
            for (i, c) in colors.enumerated() {
                NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1).setFill()
                NSBezierPath(rect: NSRect(x: 60, y: stripeY + CGFloat(i) * stripeH, width: size - 120, height: stripeH)).fill()
            }

            // Disc circle (drawn with Core Graphics, no SF Symbols)
            let discCenter = NSPoint(x: size / 2, y: size / 2 + 10)
            let outerR: CGFloat = 130
            let innerR: CGFloat = 30

            // Outer disc
            let outerPath = NSBezierPath(ovalIn: NSRect(
                x: discCenter.x - outerR, y: discCenter.y - outerR,
                width: outerR * 2, height: outerR * 2
            ))
            NSColor.white.withAlphaComponent(0.15).setFill()
            outerPath.fill()
            NSColor.white.withAlphaComponent(0.5).setStroke()
            outerPath.lineWidth = 2
            outerPath.stroke()

            // Inner hole
            let innerPath = NSBezierPath(ovalIn: NSRect(
                x: discCenter.x - innerR, y: discCenter.y - innerR,
                width: innerR * 2, height: innerR * 2
            ))
            NSColor.white.withAlphaComponent(0.3).setFill()
            innerPath.fill()
            NSColor.white.withAlphaComponent(0.5).setStroke()
            innerPath.lineWidth = 1.5
            innerPath.stroke()

            // "CHD" text below disc
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let text = "CHD" as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (size - textSize.width) / 2, y: 55), withAttributes: attrs)

            return true
        }
    }
}

