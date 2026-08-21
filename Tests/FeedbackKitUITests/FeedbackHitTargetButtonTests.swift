#if os(macOS)
import AppKit
@testable import FeedbackKitUI
import SwiftUI
import Testing

@MainActor
struct FeedbackHitTargetButtonTests {
    @Test func visibleOuterCornersTriggerTheButtonAction() throws {
        var tapCount = 0
        let host = NSHostingView(
            rootView: FeedbackHitTargetButton {
                tapCount += 1
            } label: {
                Image(systemName: "info.circle")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 44, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        for point in [NSPoint(x: 2, y: 2), NSPoint(x: 42, y: 42)] {
            try click(window: window, at: point)
        }

        #expect(tapCount == 2)
    }

    private func click(window: NSWindow, at point: NSPoint) throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: point,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        let up = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: point,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 0
            )
        )
        window.sendEvent(down)
        window.sendEvent(up)
    }
}
#endif
