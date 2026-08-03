import SwiftUI

struct FeedbackReleaseBodyText: View {
    let text: String

    private var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    var body: some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.isEmpty {
                        Color.clear
                            .frame(height: 4)
                            .accessibilityHidden(true)
                    } else {
                        Text(verbatim: String(line))
                            .font(.body)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("developerCommunity.release.body")
        }
    }
}
