import SwiftUI

struct DemoFullWidthButtonLabel: View {
    let title: String
    let systemImage: String
    var showsProgress = false

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if showsProgress {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
