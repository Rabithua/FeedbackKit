import AppKit
@testable import FeedbackKitCore
@testable import FeedbackKitUI
import SwiftUI
import Testing

struct FeedbackReleaseRenderingTests {
    @MainActor
    @Test func releaseTimelineRendersCompleteBody() throws {
        let json = #"{"id":"66666666-6666-4666-8666-666666666666","version":"2.0.7","releasedAt":"2026-08-01T08:00:00Z","title":"2.0.7","body":"让大型笔记列表更流畅，并提升加载恢复和编辑可靠性。\n\n• 大型笔记列表的加载与滚动更高效，浏览时减少不必要的刷新。\n• 重试个人主页、公开笔记、分享链接和启动恢复时，保留有用内容并展示进度与结果。\n• 在新版 iOS 上，输入区域不再被遮挡。\n• 本地附件目录尚未创建时，正确保存附件。","locale":"zh-Hans","items":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(FeedbackRelease.self, from: Data(json.utf8))
        let content = LazyVStack(alignment: .leading, spacing: 30) {
            FeedbackReleaseTimelineRow(release: release, isCurrent: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 36)
        .overlay(alignment: .leading) {
            FeedbackReleaseRail()
                .frame(width: 28)
        }
        .padding(16)
        .background(Color.white)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 472, height: nil)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == 472)
        #expect(image.size.height > 180)
    }
}
