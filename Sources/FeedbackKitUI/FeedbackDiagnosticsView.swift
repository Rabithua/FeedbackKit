import FeedbackKitDiagnostics
import Observation
import SwiftUI

@MainActor @Observable
private final class FeedbackDiagnosticsModel {
    enum Filter: String, CaseIterable, Identifiable { case all; case warning; case error; case critical; var id: Self { self } }
    var events: [FeedbackDiagnosticEvent] = []
    var filter: Filter = .all
    var exportText = ""
    var isLoading = false
    var error: Error?
    let diagnostics: FeedbackDiagnostics
    init(diagnostics: FeedbackDiagnostics) { self.diagnostics = diagnostics }

    var filtered: [FeedbackDiagnosticEvent] {
        switch filter {
        case .all: events
        case .warning: events.filter { $0.level == .warning }
        case .error: events.filter { $0.level == .error }
        case .critical: events.filter { $0.level == .critical }
        }
    }
    func load() async { isLoading = true; defer { isLoading = false }; do { events = try await diagnostics.events().sorted { $0.timestamp > $1.timestamp }; exportText = try await diagnostics.exportText(); error = nil } catch { self.error = error } }
    func clear() async { do { try await diagnostics.clear(); await load() } catch { self.error = error } }
}

struct FeedbackDiagnosticsView: View {
    @State private var model: FeedbackDiagnosticsModel
    @State private var confirmClear = false
    @State private var finalClear = false
    let style: FeedbackStyle
    init(diagnostics: FeedbackDiagnostics, style: FeedbackStyle) { _model = State(initialValue: FeedbackDiagnosticsModel(diagnostics: diagnostics)); self.style = style }

    var body: some View {
        Group {
            if model.events.isEmpty, model.isLoading { FeedbackSkeletonView(layout: .list, style: style) }
            else if model.events.isEmpty, let error = model.error { FeedbackErrorView(error: error) { Task { await model.load() } } }
            else if model.events.isEmpty { ContentUnavailableView(FK.text("feedbackkit.diagnostics.empty"), systemImage: "doc.text.magnifyingglass") }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Picker(FK.text("feedbackkit.diagnostics.filter"), selection: $model.filter) {
                            ForEach(FeedbackDiagnosticsModel.Filter.allCases) { filter in Text(label(filter)).tag(filter) }
                        }.pickerStyle(.segmented)
                        ForEach(model.filtered) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(event.level.rawValue.uppercased()).font(.caption.bold()); Text(event.category).font(.caption); Spacer(); Text(event.timestamp.feedbackRelativeText).font(.caption2).foregroundStyle(.secondary) }
                                Text(event.message).font(.callout.monospaced()).textSelection(.enabled)
                            }.padding(12).feedbackBorder(style)
                        }
                    }.padding(style.pagePadding)
                }.refreshable { await model.load() }
            }
        }
        .background(FeedbackSystemBackground())
        .navigationTitle(FK.text("feedbackkit.diagnostics.title"))
        .feedbackInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { copy(model.exportText) } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel(FK.text("feedbackkit.copy"))
                ShareLink(item: model.exportText) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel(FK.text("feedbackkit.export"))
                Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }.accessibilityLabel(FK.text("feedbackkit.clear"))
            }
        }
        .task { await model.load() }
        .alert(FK.text("feedbackkit.diagnostics.clear.title"), isPresented: $confirmClear) { Button(FK.text("feedbackkit.continue"), role: .destructive) { finalClear = true }; Button(FK.text("feedbackkit.cancel"), role: .cancel) {} }
        .alert(FK.text("feedbackkit.diagnostics.clear.final"), isPresented: $finalClear) { Button(FK.text("feedbackkit.clear"), role: .destructive) { Task { await model.clear() } }; Button(FK.text("feedbackkit.cancel"), role: .cancel) {} }
    }

    private func label(_ filter: FeedbackDiagnosticsModel.Filter) -> String {
        switch filter { case .all: FK.text("feedbackkit.filter.all"); case .warning: FK.text("feedbackkit.filter.warning"); case .error: FK.text("feedbackkit.filter.error"); case .critical: FK.text("feedbackkit.filter.critical") }
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
