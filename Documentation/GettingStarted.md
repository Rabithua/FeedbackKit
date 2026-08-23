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

Add `https://github.com/Rabithua/FeedbackKit.git` in Xcode with **Up to Next Minor Version**, starting
at `0.1.31`.

Link `FeedbackKitCore` and `FeedbackKitUI` to the app target. Link `FeedbackKitDiagnostics` only when
the app will offer opt-in diagnostic upload. Add `FeedbackKitTestSupport` only to test targets.

FeedbackKit requires iOS 18 or macOS 15 and Swift 6 language mode.

## 3. Configure each build environment

Define host-owned build settings in an xcconfig file. In xcconfig syntax, `$()` prevents the `//` in
the URL from being parsed as a comment:

```text
FEEDBACK_SERVER_BASE_URL = https:/$()/api.feedkit.cn/v1/api
FEEDBACK_PRODUCT_KEY = pk_example
```

Expose them through the app's Info.plist:

```xml
<key>FeedbackServerBaseURL</key>
<string>$(FEEDBACK_SERVER_BASE_URL)</string>
<key>FeedbackProductKey</key>
<string>$(FEEDBACK_PRODUCT_KEY)</string>
```

The base URL must end in `/v1/api`. Use a stable, app-specific Keychain service such as
`com.example.MyApp.feedback.visitor`. Changing it after release creates a new anonymous identity on
that device, which loses access to the previous identity's private feedback history.

## 4. Own one client for the app lifetime

Create the client once in the app's dependency container or runtime singleton:

```swift
import FeedbackKitCore

enum AppFeedbackRuntime {
    static let client: FeedbackClient = {
        guard
            let rawURL = Bundle.main.object(
                forInfoDictionaryKey: "FeedbackServerBaseURL"
            ) as? String,
            let baseURL = URL(string: rawURL),
            let productKey = Bundle.main.object(
                forInfoDictionaryKey: "FeedbackProductKey"
            ) as? String,
            productKey.isEmpty == false
        else {
            preconditionFailure("FeedbackServer build settings are missing")
        }

        return FeedbackClient(
            configuration: .init(
                baseURL: baseURL,
                productKey: productKey,
                keychainService: "com.example.MyApp.feedback.visitor"
            )
        )
    }()
}
```

Present `FeedbackCenterView(client: AppFeedbackRuntime.client)` from a sheet or full-screen cover.
`FeedbackCenterToolbarButton` provides a ready-made 44-point toolbar entry.

### Choose the feedback language policy

FeedbackKit follows the host view's effective SwiftUI locale by default. This keeps the package UI
and localized server content aligned with an app that supports normal per-app language selection.

For a single-language app, declare that language in the app target and fix FeedbackKit to the same
locale. For example, a Simplified Chinese-only app should use `zh-Hans` as its development region,
list only `zh-Hans` in `CFBundleLocalizations`, and present:

```swift
FeedbackCenterView(
    client: AppFeedbackRuntime.client,
    languagePolicy: .fixed(Locale(identifier: "zh-Hans"))
)
```

Do not use the FeedbackServer Product default locale as an automatic UI override. That value is the
server's deterministic content fallback, while the language policy represents the language the user
should see. FeedbackKit applies the resolved policy consistently to package strings, content loads,
submissions, and refreshes.

## 5. Add only the host integrations you need

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

enum AppFeedbackRuntime {
    static let diagnostics = FeedbackDiagnostics()

    static func makeClient(configuration: FeedbackConfiguration) -> FeedbackClient {
        FeedbackClient(
            configuration: configuration,
            diagnostics: diagnostics
        )
    }
}
```

Keep the collector alive with the client. When implementing a custom source, override
`diagnosticSnapshotData(maxBytes:)` and stop reading once that byte budget is reached. FeedbackKit
shares the Product's current server limit across custom snapshot reads, validates the final payload
again, and uses the same resolved locale for diagnostic metadata as for the feedback submission.
Keep custom event and breadcrumb arrays small because their source APIs are compatibility-oriented
and do not accept a byte budget.

Diagnostics are always private on FeedbackServer. The composer starts with the switch off for every
feedback kind, and uploads only after the user turns it on for that submission.

## 6. Seed optional hub content

An empty Product can submit and display private feedback immediately. The other sections remain
empty until the administrator publishes matching content:

- Activity: public Feedback or a published Developer Post
- Roadmap: an Item with a public Product association and roadmap stage
- Changelog: a published Release with a translation for the requested locale

Prepare at least one supported translation for each user-facing catalog entry. App Store changelog
import creates a draft and does not publish automatically.

## 7. Acceptance checklist

- Install a fresh build and open the feedback center without an existing visitor credential.
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
