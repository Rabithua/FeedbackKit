import SwiftUI

struct FeedbackSkeletonView: View {
    enum Layout {
        case hub
        case list
        case feedbackDetail
        case developerPostDetail
        case releases
    }

    let layout: Layout
    let style: FeedbackStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        Group {
            switch layout {
            case .hub:
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: style.sectionSpacing) {
                            HStack(spacing: 12) {
                                Color.clear
                                    .feedbackBorder(style)
                                    .aspectRatio(1, contentMode: .fit)
                                VStack(spacing: 12) {
                                    Color.clear
                                        .feedbackBorder(style)
                                        .frame(minHeight: 72)
                                    Color.clear
                                        .feedbackBorder(style)
                                        .frame(minHeight: 72)
                                }
                            }
                            Text("Recent activity").font(.headline)
                            FeedbackSkeletonRows(style: style, count: 3)
                        }
                        .padding(.horizontal, style.pagePadding)
                        .padding(.bottom, 20)
                    }
                }
            case .list:
                ScrollView {
                    FeedbackSkeletonRows(style: style, count: 5)
                        .padding(style.pagePadding)
                }
            case .feedbackDetail:
                FeedbackDetailSkeletonView(style: style)
            case .developerPostDetail:
                FeedbackDeveloperPostSkeletonView(style: style)
            case .releases:
                ScrollView {
                    HStack(alignment: .top, spacing: 14) {
                        Capsule().frame(width: 6)
                        VStack(alignment: .leading, spacing: 30) {
                            ForEach(0 ..< 3, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("v0.0.0").font(.title2.bold())
                                    Text("Release title placeholder").font(.headline)
                                    Text("Release notes placeholder that fills the available width.")
                                    Text("Release date").font(.caption).frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                    }
                    .padding(style.pagePadding)
                }
            }
        }
        .foregroundStyle(.secondary.opacity(0.28))
        .redacted(reason: .placeholder)
        .opacity(isDimmed ? 0.45 : 0.85)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
            value: isDimmed
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FK.text("feedbackkit.loading"))
        .onAppear { isDimmed = reduceMotion == false }
        .onChange(of: reduceMotion) { _, shouldReduce in
            isDimmed = shouldReduce == false
        }
    }
}
