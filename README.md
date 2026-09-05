# FeedbackKit

FeedbackKit 2.1 is an iOS and iPadOS 18+ Swift package for integrating a complete feedback center
with FeedbackServer. It includes anonymous visitor identity, public activity, owned feedback
conversations, attachments, voting, a version-and-body changelog, user-controlled private
diagnostics, typed campaign forms, opt-in Journey analytics, and a default SwiftUI interface.

## Products

- `FeedbackKitCore`: FeedbackServer DTOs, client transport, visitor credentials, drafts, uploads, voting, campaign forms, and inbox APIs.
- `FeedbackKitDiagnostics`: structured logs, breadcrumbs, MetricKit crash summaries, redaction, retention, and private diagnostic snapshots.
- `FeedbackKitJourney`: opt-in user journey sessions and events, recorded in memory and submitted on session end for product analytics.
- `FeedbackKitUI`: the localized SwiftUI feedback center and opt-in campaign sheet.
- `FeedbackKitTestSupport`: fixture transport, `URLProtocol`, fixed clocks, and metadata providers.

## Add the package

In Xcode, add `https://github.com/Rabithua/FeedbackKit.git` with the **Up to Next
Major Version** rule starting at `2.1.0`. Link these products to the app target:

- `FeedbackKitCore`
- `FeedbackKitUI`
- `FeedbackKitDiagnostics` only when the app offers diagnostic upload
- `FeedbackKitJourney` only when the app records opt-in journey analytics

`FeedbackKitTestSupport` is intended for test targets only.
`FeedbackKitUI` depends only on `FeedbackKitCore`; adding the default interface does not link the
diagnostic collector or Journey analytics unless the app selects those products.

Existing integrations should update the package requirement to a minimum of `2.1.0`; see
[Migrating to 2.1](Documentation/MigratingTo2.1.md) for the campaign APIs and source-compatibility
details.

## Minimal integration

```swift
import FeedbackKitCore
import FeedbackKitUI

let configuration = try FeedbackConfiguration(
    productKey: "<publishable-product-key>",
    bundle: .main
)
let client = FeedbackClient(configuration: configuration)

FeedbackCenterView(client: client)
```

## Campaign forms

Published campaigns are available through `FeedbackKitCore`. Their bounded answer schemas decode
into typed Swift cases, and `campaign.form` converts the server's flat elements into pages with
stable integer IDs and no page-break markers.

`FeedbackKitUI` can render and submit the complete form. Campaign presentation stays host-owned:
the SDK does not poll, show a homepage invitation, or present a Campaign automatically. A host can
ask for one lightweight invitation candidate without creating a visitor identity:

```swift
if let prompt = try await client.campaignPrompt() {
    showCampaignInvitation(
        preview: prompt.preview,
        accept: { presentCampaign(id: prompt.id) },
        decline: {
            Task { try? await client.markCampaignRead(id: prompt.id) }
        }
    )
}
```

`campaignPrompt()` returns `.existingVisitor` when server-side read and response history was
available, or `.untracked` when it used the Product-keyed public fallback. Keychain inspection
failures are surfaced; they are never treated as a new user. Rejecting the invitation is host-owned,
so call `markCampaignRead(id:)` when a rejection should suppress it next time.

Present `FeedbackCampaignSheet(campaignID:client:)` after acceptance. Once the full Campaign is
displayable, the sheet marks it read once; that best-effort acknowledgement never blocks the form.
The alternate `campaign:` initializer behaves the same way. Both support the existing
`FeedbackStyle`, haptics, language policy, and submission callback. An answered Campaign renders a
completion state, and a removed or invalidated Campaign opened from an old link renders an ended
state. A Campaign action on a developer post opens this same sheet inside `FeedbackCenterView`.

For a fully custom campaign interface, render the typed form directly:

```swift
let campaigns = try await client.campaigns()
guard let summary = campaigns.first else { return }

let campaign = try await client.campaign(id: summary.id)
let form = campaign.form

for page in form.pages {
    for element in page.elements {
        switch element.content {
        case let .notice(text):
            showNotice(text)
        case let .question(question):
            switch question.answer {
            case let .string(schema):
                showTextOrSingleChoice(question, allowedValues: schema.allowedValues)
            case let .number(schema):
                showNumber(question, minimum: schema.minimum, maximum: schema.maximum)
            case let .integer(schema):
                showInteger(question, minimum: schema.minimum, maximum: schema.maximum)
            case let .boolean(schema):
                showToggle(question, constant: schema.constant)
            case let .array(schema):
                showMultipleChoice(question, schema: schema)
            }
        }
    }
}
```

Build an answer dictionary with the public scalar and array initializers, then submit it. Client
context is prepared automatically; attachment IDs and an explicitly authorized diagnostic snapshot
use the same rules as ordinary feedback:

```swift
let response = try await client.submitCampaignResponse(
    campaignID: campaign.id,
    answers: [
        "satisfaction": FeedbackCampaignAnswer(4),
        "features": FeedbackCampaignAnswer(["sync", "share"]),
        "recommend": FeedbackCampaignAnswer(true),
    ],
    comment: "Keep it up!",
    locale: .current,
    includeDiagnostics: false,
    idempotencyKey: UUID().uuidString
)
```

Campaign responses expose `recordKind == .survey` in owned-feedback and detail results.
`FeedbackKind` remains the four-case ordinary submission enum, so existing exhaustive switches keep
compiling. Its compatibility `type` projection returns `.conversation` for a campaign response;
use `recordKind` whenever the exact server-side distinction matters.

## Show new replies on foreground

`FeedbackKitUI` provides an opt-in controller and a ready-made conversation sheet. The host keeps
ownership of app lifecycle handling; FeedbackKit does not install a global `scenePhase` observer or
create a visitor identity just to look for replies.

```swift
import FeedbackKitCore
import FeedbackKitUI
import SwiftUI

@MainActor
struct AppRootView: View {
    let client: FeedbackClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var replyInbox: FeedbackReplyInboxController

    init(client: FeedbackClient) {
        self.client = client
        _replyInbox = State(initialValue: FeedbackReplyInboxController(client: client))
    }

    var body: some View {
        AppContent()
            .task(id: scenePhase) {
                if scenePhase == .active {
                    await replyInbox.beginForegroundCycle()
                } else if scenePhase == .background {
                    replyInbox.endForegroundCycle()
                }
            }
            .sheet(item: $replyInbox.pendingPresentation) { presentation in
                FeedbackConversationSheet(
                    presentation: presentation,
                    controller: replyInbox
                )
            }
    }
}
```

Call `endForegroundCycle()` only for `.background`. A temporary `.inactive` transition belongs to
the same foreground cycle, so repeated `.active` notifications still produce only one check. The
controller scans every unread inbox page, loads the full conversation, and prepares only the latest
administrator reply. The sheet acknowledges that reply when it appears; discovery failures,
cancellation, and inboxes without a reply do not advance the read cursor.

For a completely custom interface, use `FeedbackKitCore` directly. The read-only entry point
`existingVisitorInbox(after:)` returns `nil` without creating a Keychain identity or making a
network request when the user has never used FeedbackKit. Omit `after` on the first page and pass
each page's `nextCursor` only while `hasMore` is true.

The default language policy follows the host app's effective SwiftUI locale. A single-language app
can keep the feedback UI and server-authored content on that language even when the device uses a
different language:

```swift
FeedbackCenterView(
    client: client,
    languagePolicy: .fixed(Locale(identifier: "zh-Hans"))
)
```

Keep one client instance for the lifetime of the app. FeedbackKit always connects to
`https://api.feedkit.cn/v1/api`; hosts configure only the Product Key. Unless an explicit service is
provided, the Keychain service is derived as `<bundle-id>.feedbackkit.visitor` and must remain
stable after release.

For Info.plist-based configuration, add only `FeedbackProductKey` and then use:

```swift
let client = FeedbackClient(
    configuration: try FeedbackConfiguration(bundle: .main)
)
```

Before exposing the feedback center, an integration or debug screen can explicitly verify
Keychain access, networking, Product binding, and diagnostics readiness:

```swift
let summary = try await client.verifyIntegration(locale: .current)
print(summary.product.name, summary.diagnostics)
```

This preflight uses the normal bootstrap flow and may create the anonymous visitor identity. It is
never run automatically.

The default UI includes a centered `Powered by FeedKit.cn` attribution at the end of the main hub.
It opens `https://feedkit.cn/` only after the user activates it.

The package never uploads diagnostics automatically. New feedback always starts with diagnostic
sharing disabled. A private snapshot is generated only after the server and host both support the
feature and the user explicitly enables the switch for that submission.

When diagnostics are enabled, keep one collector alongside the client:

```swift
import FeedbackKitCore
import FeedbackKitDiagnostics
import Foundation

let configuration = try FeedbackConfiguration(
    productKey: "<publishable-product-key>",
    bundle: .main
)
let diagnostics = FeedbackDiagnostics()
let client = FeedbackClient(
    configuration: configuration,
    diagnostics: diagnostics
)
```

The server's current `maxBytes` capability and the resolved feedback locale are passed into
snapshot generation. Custom sources should override
`diagnosticSnapshotData(maxBytes:)` and stop reading at that limit; the compatibility
implementation clips legacy `diagnosticSnapshotData()` results.

Follow the complete [new app onboarding guide](Documentation/GettingStarted.md) for Product setup,
xcconfig/Info.plist configuration, diagnostics and privacy decisions, route handling, catalog
seeding, and acceptance checks. For upgrades, read [Migrating to 2.1](Documentation/MigratingTo2.1.md).
The earlier [2.0](Documentation/MigratingTo2.0.md) and
[0.2](Documentation/MigratingTo0.2.md) migration guides remain available for historical integrations.
The runnable [FeedbackKit Demo](Examples/FeedbackKitDemo/README.md) starts in Fixture mode with no
configuration and also offers an explicitly verified Live mode.

## Observe client operations

The client is silent by default. Apps that want structured developer telemetry can supply an
observer without enabling or collecting user diagnostics:

```swift
let observer = FeedbackClientObserver.osLog(
    subsystem: Bundle.main.bundleIdentifier ?? "FeedbackKitHost"
)
let client = FeedbackClient(
    configuration: configuration,
    observer: observer
)
```

Events contain only operation, outcome, duration, HTTP status, server code, request ID,
retry-after, and failure kind. They never contain Product Keys, authorization values, payloads,
query parameters, resource IDs, or presigned URLs. Use `FeedbackClientObserver { event in ... }`
to bridge the same safe event model into another telemetry system.

## Host extension points

- Implement `FeedbackRouteHandler` for allow-listed host `app_route` actions.
- Implement `FeedbackDiagnosticSource` to add an existing log source. Prefer the byte-limited
  snapshot API so each custom snapshot read shares a bounded collection budget; FeedbackKit also
  bounds the final encoded snapshot. Event and breadcrumb arrays returned by custom sources remain
  host-controlled and should be kept small.
- Implement `FeedbackAppMetadataProvider` for deterministic tests or custom device context.
- Custom `FeedbackVisitorCredentialProviding` implementations should implement
  `existingCredential(for:)` as a strictly read-only lookup to enable foreground reply checks. The
  default implementation returns `nil` so existing conformers remain source compatible.
- Use `FeedbackStyle` for the intentionally small set of spacing, radius, and border adjustments.

For custom attachment workflows, `FeedbackAttachmentSource(fileURL:)` keeps uploads file-backed.
The caller owns that file and must keep it available until `uploadAttachments` returns. Use
`loadData()` only when explicit materialization is required.

The package ships English, Simplified Chinese, Traditional Chinese, Japanese, and Korean
localizations. Its UI strings, localized FeedbackServer content, submissions, and refreshes all use
the same effective language. It also follows the host app's system background and tint.

Custom integrations can switch on `FeedbackClientError.kind` and inspect structured context such as
`statusCode`, `serverCode`, `requestID`, and `retryAfter`. The packaged UI intentionally preserves
generic localized user messages and keeps in-progress body, attachments, and drafts after a failed
submission.

## Validation

```bash
swift test
xcodebuild -scheme FeedbackKit-Package -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Examples/FeedbackKitDemo/FeedbackKitDemo.xcodeproj -scheme FeedbackKitDemo -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Normal package tests are deterministic and offline. The FeedbackServer v2 contract is opt-in and is
reported as skipped unless both variables are present. `FEEDBACKKIT_TEST_BASE_URL` must be the full
API base URL through `/v1/api`; `FEEDBACKKIT_TEST_PRODUCT_KEY` must be a publishable key for a test
Product whose temporary visitor and feedback data may be deleted:

```bash
FEEDBACKKIT_TEST_BASE_URL='https://api.feedkit.cn/v1/api' \
FEEDBACKKIT_TEST_PRODUCT_KEY='<publishable-product-key>' \
swift test --filter FeedbackServerV2ContractTests
```

The live test never prints the Product Key. It creates an isolated visitor, conditionally uploads a
tiny image when the Product allows attachments, exercises the v2 SDK routes, and deletes the visitor
at the end.
