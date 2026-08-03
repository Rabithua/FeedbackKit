import SwiftUI

struct FeedbackSkeletonView: View {
    enum Layout {
        case hub
        case list
        case detail
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
                    HStack(spacing: 10) {
                        Circle()
                            .stroke(lineWidth: style.borderWidth)
                            .frame(width: 34, height: 34)
                        Text("Feedback center").font(.title2.bold())
                        Spacer(minLength: 8)
                        Circle()
                            .stroke(lineWidth: style.borderWidth)
                            .frame(width: 34, height: 34)
                    }
                    .padding(.horizontal, style.pagePadding)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

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
            case .detail:
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Feedback title placeholder").font(.title3)
                        Text("Feedback content placeholder that fills the available width.")
                        Text("Additional feedback context placeholder.")
                        Divider()
                        Text("Reply content placeholder").font(.body)
                        Text("Reply metadata").font(.caption)
                        Divider()
                        Text("Another response placeholder").font(.body)
                        Text("Response metadata").font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, style.pagePadding)
                    .padding(.bottom, 24)
                }
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
