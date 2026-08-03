# FeedbackKit

FeedbackKit is an iOS and iPadOS 18+ Swift package for integrating a complete feedback center with FeedbackServer. It includes anonymous visitor identity, public activity, owned feedback conversations, attachments, voting, roadmap, changelog, user-controlled private diagnostics, and a default SwiftUI interface.

## Products

- `FeedbackKitCore`: FeedbackServer DTOs, client transport, visitor credentials, drafts, uploads, voting, and inbox APIs.
- `FeedbackKitDiagnostics`: structured logs, breadcrumbs, MetricKit crash summaries, redaction, retention, and private diagnostic snapshots.
- `FeedbackKitUI`: the localized SwiftUI feedback center.
- `FeedbackKitTestSupport`: fixture transport, `URLProtocol`, fixed clocks, and metadata providers.

## Integration

```swift
import FeedbackKitCore
import FeedbackKitDiagnostics
import FeedbackKitUI

let diagnostics = FeedbackDiagnostics(
    configuration: .init(
        retentionDays: 7,
        maximumEventCount: 500,
        maximumDiskBytes: 2 * 1024 * 1024
    )
)

let client = FeedbackClient(
    configuration: .init(
        baseURL: URL(string: "https://feedback.example.com/v1/api")!,
        productKey: "<publishable-product-key>"
    ),
    diagnostics: diagnostics
)

FeedbackCenterView(client: client, routeHandler: routeHandler)
```

The package never uploads diagnostics automatically. A diagnostic snapshot is generated and uploaded only after the user enables the submission switch and sends that specific feedback. FeedbackServer keeps diagnostic artifacts private even when the related feedback is public.

## Host extension points

- Implement `FeedbackRouteHandler` for allow-listed host `app_route` actions.
- Implement `FeedbackDiagnosticSource` to add an existing log source. FeedbackKit redacts and size-limits all source output again.
- Implement `FeedbackAppMetadataProvider` for deterministic tests or custom device context.
- Use `FeedbackStyle` for the intentionally small set of spacing, radius, and border adjustments.

The package ships English, Simplified Chinese, Traditional Chinese, Japanese, and Korean localizations and follows the host app's system background and tint.

## Validation

```bash
swift test
xcodebuild -scheme FeedbackKit-Package -destination 'generic/platform=iOS' build
```
