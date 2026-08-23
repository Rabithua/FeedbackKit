# FeedbackKit

FeedbackKit is an iOS and iPadOS 18+ Swift package for integrating a complete feedback center with FeedbackServer. It includes anonymous visitor identity, public activity, owned feedback conversations, attachments, voting, a version-and-body changelog, user-controlled private diagnostics, and a default SwiftUI interface.

## Products

- `FeedbackKitCore`: FeedbackServer DTOs, client transport, visitor credentials, drafts, uploads, voting, and inbox APIs.
- `FeedbackKitDiagnostics`: structured logs, breadcrumbs, MetricKit crash summaries, redaction, retention, and private diagnostic snapshots.
- `FeedbackKitUI`: the localized SwiftUI feedback center.
- `FeedbackKitTestSupport`: fixture transport, `URLProtocol`, fixed clocks, and metadata providers.

## Add the package

In Xcode, add `https://github.com/Rabithua/FeedbackKit.git` with the **Up to Next
Minor Version** rule starting at `0.2.0`. Link these products to the app target:

- `FeedbackKitCore`
- `FeedbackKitUI`
- `FeedbackKitDiagnostics` only when the app offers diagnostic upload

`FeedbackKitTestSupport` is intended for test targets only.
`FeedbackKitUI` depends only on `FeedbackKitCore`; adding the default interface does not link the
diagnostic collector unless the app selects that product.

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
seeding, and acceptance checks. For upgrades, read [Migrating to 0.2](Documentation/MigratingTo0.2.md).
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
