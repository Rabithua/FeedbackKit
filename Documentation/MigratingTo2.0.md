# Migrating to FeedbackKit 2.0

FeedbackKit 2.0 is the product-suite release of the Swift SDK. It keeps the existing Swift API and
FeedbackServer route contract compatible with 0.2.2, so an existing integration does not require
source changes.

The required migration is to update the package dependency to a minimum of `2.0.0`. In Xcode, use
**Up to Next Major Version** starting at `2.0.0`. In a package manifest, use:

```swift
.package(
    url: "https://github.com/Rabithua/FeedbackKit.git",
    from: "2.0.0"
)
```

Keep the existing Product Key, `FeedbackKeychainService`, and long-lived `FeedbackClient`. Changing
the Keychain service would create a new anonymous visitor identity and lose access to the previous
identity's private feedback history.

## What changed since 0.2.2

### Opt-in Journey analytics

The new `FeedbackKitJourney` library records bounded user journey sessions in memory and submits
them through the existing `FeedbackClient` transport. Add this product only to targets that use
journey analytics; existing targets do not link it automatically.

- Sessions can use the reserved default kind or an app-defined lowercase taxonomy key.
- Events support free-form nonblank names, typed JSON payload values, and routing to all sessions,
  selected kinds, hashed object identifiers, composed targets, or a custom predicate.
- Raw object identifiers are hashed before storage and submission and are preserved across event
  rewrites without becoming public API.
- Sessions are thread-safe, extensible through `accepts`, `prepare`, and `sessionDidEnd`, and enforce
  the server's duration, event-count, payload-size, depth, key, and string bounds before submission.
- `shutdown()` ends registered sessions before draining them. Permanent validation failures are
  isolated so later valid sessions can still submit; transient failures remain queued for retry.

```swift
import FeedbackKitJourney

let journeys = UserJourneyManager(client: client)
let checkout = UserJourneySession(
    kind: UserJourneySessionKind(rawValue: "checkout"),
    objectID: orderID
)

await journeys.register(checkout)
await journeys.record(
    UserJourneyEvent(
        target: .objectID(orderID),
        name: "Payment sheet opened",
        payload: ["source": .string("cart")]
    )
)
try await journeys.shutdown()
```

Journey analytics is opt-in. Apps remain responsible for deciding when to record these events and
for keeping user content and secrets out of event names and payloads.

### Foreground reply presentation

`FeedbackKitUI` now includes `FeedbackReplyInboxController` and `FeedbackConversationSheet` for
showing the latest administrator reply once per foreground cycle. The controller:

- checks only when the host explicitly calls `beginForegroundCycle()`;
- does not create an anonymous identity for an app that has never used FeedbackKit;
- scans all unread inbox pages and loads the selected owned conversation;
- acknowledges a reply only after its sheet appears; and
- keeps cancellation, request failures, and status-only events from advancing the read cursor.

Custom interfaces can use `existingVisitorInbox(after:)`. Custom credential providers may implement
the new read-only `existingCredential(for:)` requirement to participate; its default implementation
returns `nil`, preserving source compatibility for existing conformers.

### Accessibility improvements

The feedback detail sheet now offers medium and large detents, uses Dynamic Type-aware vote text,
and exposes the vote action and current count to assistive technologies. These changes improve large
text and VoiceOver use without changing host integration code.

### Internal transport organization

The client networking and diagnostic upload implementation was split into focused source files and
shares a package-internal JSON transport entry point with Journey submissions. Public client calls,
request routes, Product Key handling, visitor authorization, and response models remain compatible.

## Upgrade checklist

- Change the package requirement from `0.2.x` to a minimum of `2.0.0`.
- Keep the existing Product Key and Keychain service.
- Continue linking `FeedbackKitCore`, `FeedbackKitUI`, and optionally `FeedbackKitDiagnostics` as
  before.
- Add `FeedbackKitJourney` only if the app will explicitly record journey analytics.
- Optionally adopt `FeedbackReplyInboxController` for foreground reply presentation.
- Re-run the package, generic iOS, and fixture demo validations from the repository README.

No public API migration is required.
