# FeedbackKit

FeedbackKit is an iOS and iPadOS 18+ Swift package for integrating a complete feedback center with FeedbackServer. It includes anonymous visitor identity, public activity, owned feedback conversations, attachments, voting, a version-and-body changelog, user-controlled private diagnostics, and a default SwiftUI interface.

## Products

- `FeedbackKitCore`: FeedbackServer DTOs, client transport, visitor credentials, drafts, uploads, voting, and inbox APIs.
- `FeedbackKitDiagnostics`: structured logs, breadcrumbs, MetricKit crash summaries, redaction, retention, and private diagnostic snapshots.
- `FeedbackKitUI`: the localized SwiftUI feedback center.
- `FeedbackKitTestSupport`: fixture transport, `URLProtocol`, fixed clocks, and metadata providers.

## Add the package

In Xcode, add `https://github.com/Rabithua/FeedbackKit.git` with the **Up to Next
Minor Version** rule starting at `0.1.31`. Link these products to the app target:

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

let client = FeedbackClient(
    configuration: .init(
        baseURL: URL(string: "https://api.feedkit.cn/v1/api")!,
        productKey: "<publishable-product-key>",
        keychainService: "com.example.MyApp.feedback.visitor"
    )
)

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

Keep one client instance for the lifetime of the app. The server URL must include `/v1/api`, and
the Keychain service must be stable and unique to the host app.

The package never uploads diagnostics automatically. New feedback always starts with diagnostic
sharing disabled. A private snapshot is generated only after the server and host both support the
feature and the user explicitly enables the switch for that submission.

When diagnostics are enabled, keep one collector alongside the client:

```swift
import FeedbackKitCore
import FeedbackKitDiagnostics
import Foundation

let configuration = FeedbackConfiguration(
    baseURL: URL(string: "https://api.feedkit.cn/v1/api")!,
    productKey: "<publishable-product-key>"
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
seeding, and acceptance checks. The package also compiles a minimal host example as part of its
test target: [FeedbackKitIntegrationExample.swift](Tests/FeedbackKitUITests/FeedbackKitIntegrationExample.swift).

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

Server-side availability restrictions remain available to custom integrations as
`FeedbackClientError.server(statusCode: 503, code:)`. The packaged UI intentionally presents a
localized generic temporary-unavailability message for these codes and preserves the in-progress
body, attachments, and draft after a failed submission.

## Validation

```bash
swift test
xcodebuild -scheme FeedbackKit-Package -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
