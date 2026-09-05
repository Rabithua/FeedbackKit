# Migrating to FeedbackKit 2.1

FeedbackKit 2.1 adds the visitor campaign API and typed, display-ready campaign form models. Update
the package dependency to a minimum of `2.1.0`. In Xcode, use **Up to Next Major Version** starting
at `2.1.0`. In a package manifest, use:

```swift
.package(
    url: "https://github.com/Rabithua/FeedbackKit.git",
    from: "2.1.0"
)
```

Keep the existing Product Key, Keychain service, and long-lived `FeedbackClient`. No Product or
visitor migration is needed.

## Source compatibility

Campaign responses are private feedback records with the server type `survey`. `FeedbackKind`
remains the same four-case ordinary submission enum, so existing exhaustive switches continue to
compile. `OwnedFeedbackSummary` and `FeedbackDetail` now expose the exact server value through the
extensible `recordKind` property:

```swift
switch feedback.recordKind {
case .survey:
    showCampaignResponse(feedback)
case .bug, .suggestion, .praise, .conversation:
    showOrdinaryFeedback(feedback)
default:
    showOrdinaryFeedback(feedback)
}
```

The existing `type: FeedbackKind` property remains available as a compatibility projection and
returns `.conversation` for campaign or future non-submittable record kinds. Use `recordKind` for
display and branching when the campaign distinction matters. `FeedbackKind.submittableCases`
contains the four kinds accepted by `createFeedback` and `submitFeedback`; a survey can be created
only through `submitCampaignResponse`.

## Campaign API

- `campaigns()` lists up to the 20 newest campaigns currently collecting responses.
- `campaign(id:)` loads one complete campaign.
- `campaignPrompt()` returns one lightweight invitation candidate. It applies read/response
  history for an existing FeedbackKit visitor and otherwise uses a no-write public fallback.
- `markCampaignRead(id:)` explicitly consumes an invitation and may create the anonymous visitor
  identity. `FeedbackCampaignSheet` also calls it once after Campaign content becomes displayable.
- `FeedbackCampaignAnswerSchema` exposes the bounded server schema as typed string, number,
  integer, boolean, and array cases.
- `FeedbackCampaign.form` splits flat campaign elements into identified pages and removes the
  page-break markers.
- `submitCampaignResponse` accepts typed natural-JSON answers, optional comments and attachments,
  and the same explicit diagnostics choice as ordinary feedback.
- `FeedbackCampaignSheet` is an opt-in SwiftUI renderer. It never presents itself or creates a
  homepage invitation. Campaign actions in developer posts can open it from `FeedbackCenterView`.
- `FeedbackDeveloperPostAction.Kind.campaign` decodes `campaignId`; `campaignID` exposes the typed
  projection while the existing `target` projection remains available.

FeedbackServer no longer accepts regular-expression `pattern` constraints on newly created
campaigns. FeedbackKit continues decoding that field for campaigns published by an older server,
but new form renderers should rely on the current bounded schema fields instead.

See the campaign example in the repository [README](../README.md#campaign-forms) for the complete
read, render, and submit flow.

## Upgrade checklist

- Move the package requirement and resolved pin to `2.1.0` or newer.
- Use `recordKind` where owned-feedback or detail UIs should distinguish campaign responses.
- Keep `FeedbackKind` or `FeedbackKind.submittableCases` for ordinary submission UIs.
- Re-run the host app's build and feedback integration tests.
