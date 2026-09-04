# Integrating FeedbackKit in a new app

FeedbackKit uses one FeedbackServer Product per app. Complete the server setup first, then add the
Swift package and verify the full feedback loop before shipping.

## 1. Create the Product

Connect the FeedbackServer management agent using the administrator that should own the new app,
then create a Product with an explicit name and slug. Use these defaults unless the product has a
reviewed reason to differ:

- Feedback visibility: `private`
- Diagnostics: disabled
- Default locale: the app's source locale
- Attachment limits: keep the server defaults initially

Save the returned publishable Product key in the app's environment-specific build configuration.
The key identifies the Product but is not an administrator credential. Product ownership is
isolated by administrator and cannot currently be shared or transferred, so choose the owner before
creating it.

Optionally configure an App Store binding for changelog import and a Product-specific Bark channel.
Neither is required for client bootstrap or feedback submission.

## 2. Add the Swift package

Add `https://github.com/Rabithua/FeedbackKit.git` in Xcode with **Up to Next Major Version**, starting
at `2.0.0`. Existing 0.2 integrations can update their package requirement without changing source;
see [Migrating to FeedbackKit 2.0](MigratingTo2.0.md).

Link `FeedbackKitCore` and `FeedbackKitUI` to the app target. Link `FeedbackKitDiagnostics` only when
the app will offer opt-in diagnostic upload, and link `FeedbackKitJourney` only when the app will
record opt-in journey analytics. Add `FeedbackKitTestSupport` only to test targets.

FeedbackKit 2.0 requires iOS 18 or macOS 15 and Swift 6 language mode.

## 3. Configure each build environment

Define the publishable Product Key in a host-owned xcconfig file:

```text
FEEDBACK_PRODUCT_KEY = pk_example
```

Expose it through the app's Info.plist:

```xml
<key>FeedbackProductKey</key>
<string>$(FEEDBACK_PRODUCT_KEY)</string>
```

FeedbackKit always uses `https://api.feedkit.cn/v1/api`; the host does not configure a server or API
path. By default, the Keychain service is derived as `<bundle-id>.feedbackkit.visitor`. To override
it, add the optional `FeedbackKeychainService` Info.plist key. Changing the service after release
creates a new anonymous identity on that device and loses access to the previous identity's private
feedback history.

## 4. Own one client for the app lifetime

Create the client once in the app's dependency container or runtime object:

```swift
import FeedbackKitCore
import Foundation

@MainActor
final class AppFeedbackRuntime {
    let client: FeedbackClient

    init(bundle: Bundle = .main) throws {
        client = FeedbackClient(
            configuration: try FeedbackConfiguration(bundle: bundle)
        )
    }
}
```

Configuration initialization is throwing and side-effect free. In production code, surface a
`FeedbackConfigurationError` in the app's integration or diagnostics screen when build settings
may be absent. Present `FeedbackCenterView(client: runtime.client)` from a sheet or full-screen
cover. `FeedbackCenterToolbarButton` provides a ready-made 44-point toolbar entry.

### Optionally present administrator replies on foreground

Create one `FeedbackReplyInboxController` beside the long-lived client. When the host scene becomes
active, call `beginForegroundCycle()` in a task. When it reaches `.background`, call
`endForegroundCycle()`. Do not end the cycle for `.inactive`; interruptions and system overlays may
move a scene between `.active` and `.inactive` several times in one foreground session.

Drive `FeedbackConversationSheet` with `.sheet(item: $controller.pendingPresentation)`. It opens the
already-loaded conversation and acknowledges the selected reply on appearance. FeedbackKit checks
only once per cycle, scans all inbox pages, and chooses the highest-sequence administrator reply.
It does not acknowledge status-only events, failed detail loads, or cancelled checks. If no
credential already exists, the check creates no identity and performs no request.

Apps supplying their own feedback UI can use `FeedbackKitCore` without `FeedbackKitUI`: call
`existingVisitorInbox()` for the first page, continue with `existingVisitorInbox(after:)`, load the
chosen conversation with the normal client API, and call `acknowledgeInbox(cursor:)` only when the
host considers that reply displayed.

The main hub ends with a centered `Powered by FeedKit.cn` attribution. Activating it opens
`https://feedkit.cn/`; displaying the attribution does not make an additional network request.

### Choose the feedback language policy

FeedbackKit follows the host view's effective SwiftUI locale by default. This keeps the package UI
and localized server content aligned with an app that supports normal per-app language selection.

For a single-language app, declare that language in the app target and fix FeedbackKit to the same
locale. For example, a Simplified Chinese-only app should use `zh-Hans` as its development region,
list only `zh-Hans` in `CFBundleLocalizations`, and present:

```swift
FeedbackCenterView(
    client: runtime.client,
    languagePolicy: .fixed(Locale(identifier: "zh-Hans"))
)
```

Do not use the FeedbackServer Product default locale as an automatic UI override. That value is the
server's deterministic content fallback, while the language policy represents the language the user
should see. FeedbackKit applies the resolved policy consistently to package strings, content loads,
submissions, and refreshes.

## 5. Verify the integration explicitly

Use the normal feedback UI directly in production. During development, or before enabling a live
entry point, call the opt-in preflight:

```swift
do {
    let summary = try await runtime.client.verifyIntegration(locale: .current)
    print(summary.product.name)
    print(summary.diagnostics)
} catch let error as FeedbackClientError {
    print(error.kind, error.context.requestID as Any)
}
```

The call verifies Keychain access, networking, Product binding, and diagnostics readiness using the
normal bootstrap path. It creates or reuses the anonymous visitor identity, so call it only from an
explicit user or developer action. Constructing the client does not perform this request.

## 6. Add only the host integrations you need

For server-authored `app_route` actions, implement `FeedbackRouteHandler` with an allow-list. Return
`false` for every unrecognized value; never execute arbitrary URLs or reflected route strings.

```swift
import FeedbackKitUI

struct AppFeedbackRoutes: FeedbackRouteHandler {
    @MainActor
    func openFeedbackAppRoute(_ route: String) -> Bool {
        switch route {
        case "settings":
            AppRouter.shared.openSettings()
            return true
        default:
            return false
        }
    }
}
```

Pass the host's existing haptic adapter with `FeedbackHaptics`; `.none` is the safe default.

To offer diagnostics, enable the Product capability only after completing the privacy review, create
a `FeedbackDiagnostics` instance, and pass it to `FeedbackClient`. Existing log systems can be
registered through `FeedbackDiagnosticSource`. FeedbackKit redacts and size-limits collected data,
but the host remains responsible for its App Store privacy answers and for avoiding secrets or user
content in logs. The package privacy manifest does not replace those disclosures.

```swift
import FeedbackKitCore
import FeedbackKitDiagnostics

let diagnostics = FeedbackDiagnostics()
let configuration = try FeedbackConfiguration(bundle: .main)
let client = FeedbackClient(
    configuration: configuration,
    diagnostics: diagnostics
)
```

Keep the collector alive with the client. When implementing a custom source, override
`diagnosticSnapshotData(maxBytes:)` and stop reading once that byte budget is reached. FeedbackKit
shares the Product's current server limit across custom snapshot reads, validates the final payload
again, and uses the same resolved locale for diagnostic metadata as for the feedback submission.
Keep custom event and breadcrumb arrays small because their source APIs are compatibility-oriented
and do not accept a byte budget.

Diagnostics are always private on FeedbackServer. The composer starts with the switch off for every
feedback kind, and uploads only after the user turns it on for that submission.

### Add developer telemetry only when needed

`FeedbackClient` is silent by default. To observe sanitized operation completions, pass an explicit
observer:

```swift
let client = FeedbackClient(
    configuration: try FeedbackConfiguration(bundle: .main),
    observer: .osLog(subsystem: "com.example.MyApp")
)
```

This observer is independent from user-authorized diagnostics and does not collect request bodies,
credentials, URLs, query parameters, resource IDs, or presigned upload URLs. A custom synchronous
`FeedbackClientObserver` handler should return promptly and must not alter request behavior.

## 7. Seed optional hub content

An empty Product can submit and display private feedback immediately. The other sections remain
empty until the administrator publishes matching content:

- Activity: public Feedback or a published Developer Post
- Roadmap: an Item with a public Product association and roadmap stage
- Changelog: a published Release with a translation for the requested locale

Prepare at least one supported translation for each user-facing catalog entry. App Store changelog
import creates a draft and does not publish automatically.

## 8. Acceptance checklist

- Install a fresh build and open the feedback center without an existing visitor credential.
- Trigger `verifyIntegration` and confirm the expected Product and diagnostics readiness are shown.
- With a fixed language policy, test on a device whose preferred language differs and confirm the
  feedback UI, server-authored content, and submitted diagnostic locale remain in the fixed
  language.
- Confirm Activity, My Feedback, Roadmap, and Changelog load without errors when empty.
- Confirm the entire hub card surface is tappable, not only its text.
- With VoiceOver, confirm feedback-kind descriptions, vote counts, unread counts, and developer
  post actions are announced, and verify the layout at an accessibility Dynamic Type size.
- Submit one private feedback item and verify it appears under My Feedback.
- Reply as the administrator, refresh the app, and verify the unread badge increases.
- Open that feedback detail, return to the hub, and verify the badge is acknowledged immediately.
- Relaunch and verify the same anonymous identity retains its private conversation.
- If diagnostics are enabled, confirm the switch starts off, no diagnostic endpoints are called
  while off, and an explicitly enabled submission creates a private diagnostic artifact.
- Verify unknown `app_route` values are rejected and valid allow-listed routes open correctly.

For deterministic client tests, inject `FeedbackFixtureTransport`, a test credential provider, and a
fixed metadata provider from `FeedbackKitTestSupport`. Do not use live FeedbackServer networking in
unit tests.
