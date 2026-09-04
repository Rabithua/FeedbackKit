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

    @Test func attachmentRemoveTargetDoesNotOverlapTheNextTile() throws {
        var firstRemovalCount = 0
        var secondRemovalCount = 0
        let spacing: CGFloat = 10
        let width = FeedbackAttachmentTile.layoutWidth * 2 + spacing
        let height = FeedbackAttachmentTile.layoutHeight
        let host = NSHostingView(
            rootView: HStack(alignment: .bottom, spacing: spacing) {
                FeedbackAttachmentTile(
                    filename: "First",
                    removeLabel: "Remove first",
                    style: .default,
                    remove: { firstRemovalCount += 1 }
                )
                FeedbackAttachmentTile(
                    filename: "Second",
                    removeLabel: "Remove second",
                    style: .default,
                    remove: { secondRemovalCount += 1 }
                )
            }
            .frame(width: width, height: height, alignment: .topLeading)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        let secondTileLeft = FeedbackAttachmentTile.layoutWidth + spacing
        try click(
            window: window,
            at: NSPoint(
                x: secondTileLeft + 2,
                y: height - FeedbackAttachmentTile.controlRadius - 2
            )
        )
        #expect(firstRemovalCount == 0)
        #expect(secondRemovalCount == 0)

        let secondButtonLeft = secondTileLeft
            + FeedbackStyle.attachmentTileSize
            - FeedbackAttachmentTile.controlRadius
        for point in [
            NSPoint(x: secondButtonLeft + 2, y: height - 2),
            NSPoint(
                x: secondButtonLeft + FeedbackAttachmentTile.controlSize - 2,
                y: height - FeedbackAttachmentTile.controlSize + 2
            ),
        ] {
            try click(window: window, at: point)
        }

        #expect(firstRemovalCount == 0)
        #expect(secondRemovalCount == 2)
    }

    @Test func campaignNavigationVisibleCornersTriggerTheirActions() throws {
        var backCount = 0
        var primaryCount = 0
        let width: CGFloat = 320
        let height: CGFloat = 54
        let host = NSHostingView(
            rootView: FeedbackCampaignNavigationBar(
                isFirstPage: false,
                isLastPage: true,
                isSubmitting: false,
                style: .default,
                back: { backCount += 1 },
                primary: { primaryCount += 1 }
            )
            .frame(width: width, height: height)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        for point in [NSPoint(x: 2, y: 6), NSPoint(x: 318, y: 6)] {
            try click(window: window, at: point)
        }

        #expect(backCount == 1)
        #expect(primaryCount == 1)
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
