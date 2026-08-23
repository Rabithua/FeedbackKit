import FeedbackKitCore
import SwiftUI

struct FeedbackDiagnosticsView: View {
    @State private var model: FeedbackDiagnosticsModel
    @State private var confirmClear = false
    @State private var finalClear = false
    let style: FeedbackStyle
    @Environment(\.feedbackHaptics) private var haptics
    @Environment(\.locale) private var locale
    @Environment(\.feedbackLocalization) private var localization
    init(diagnostics: any FeedbackDiagnosticsInspecting, style: FeedbackStyle) {
        _model = State(initialValue: FeedbackDiagnosticsModel(diagnostics: diagnostics))
        self.style = style
    }

    var body: some View {
        Group {
            if model.events.isEmpty, model.isLoading { FeedbackSkeletonView(layout: .list, style: style) }
            else if model.events.isEmpty, let error = model.error { FeedbackErrorView(error: error) { Task { await model.load() } } }
            else if model.events.isEmpty { ContentUnavailableView(localization.text("feedbackkit.diagnostics.empty"), systemImage: "doc.text.magnifyingglass") }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Picker(localization.text("feedbackkit.diagnostics.filter"), selection: filterBinding) {
                            ForEach(FeedbackDiagnosticsModel.Filter.allCases) { filter in Text(label(filter)).tag(filter) }
                        }.pickerStyle(.segmented)
                        ForEach(model.filtered) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(event.level.rawValue.uppercased()).font(.caption.bold()); Text(event.category).font(.caption); Spacer(); Text(event.timestamp.feedbackRelativeText(locale: locale)).font(.caption2).foregroundStyle(.secondary) }
                                Text(event.message).font(.callout.monospaced()).textSelection(.enabled)
                            }.padding(12).feedbackBorder(style)
                        }
                    }.padding(style.pagePadding)
                }.refreshable { await model.load() }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(localization.text("feedbackkit.diagnostics.title"))
        .feedbackInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    copy(model.exportText)
                    haptics.trigger(.success)
                } label: { Image(systemName: "doc.on.doc") }
                .accessibilityLabel(localization.text("feedbackkit.copy"))
                ShareLink(item: model.exportText) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(localization.text("feedbackkit.export"))
                    .simultaneousGesture(TapGesture().onEnded { haptics.trigger(.action) })
                Button(role: .destructive) {
                    haptics.trigger(.warning)
                    confirmClear = true
                } label: { Image(systemName: "trash") }
                .accessibilityLabel(localization.text("feedbackkit.clear"))
            }
        }
        .task { await model.load() }
        .alert(localization.text("feedbackkit.diagnostics.clear.title"), isPresented: $confirmClear) { Button(localization.text("feedbackkit.continue"), role: .destructive) { finalClear = true }; Button(localization.text("feedbackkit.cancel"), role: .cancel) {} }
        .alert(localization.text("feedbackkit.diagnostics.clear.final"), isPresented: $finalClear) {
            Button(localization.text("feedbackkit.clear"), role: .destructive) {
                Task {
                    let didClear = await model.clear()
                    haptics.trigger(didClear ? .success : .error)
                }
            }
            Button(localization.text("feedbackkit.cancel"), role: .cancel) {}
        }
    }

    private func label(_ filter: FeedbackDiagnosticsModel.Filter) -> String {
        switch filter { case .all: localization.text("feedbackkit.filter.all"); case .warning: localization.text("feedbackkit.filter.warning"); case .error: localization.text("feedbackkit.filter.error"); case .critical: localization.text("feedbackkit.filter.critical") }
    }

    private var filterBinding: Binding<FeedbackDiagnosticsModel.Filter> {
        Binding(
            get: { model.filter },
            set: {
                model.filter = $0
                haptics.trigger(.selection)
            }
        )
    }
    private func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}

#if os(iOS)
import UIKit
#else
import AppKit
#endif
