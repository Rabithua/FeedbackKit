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

## Required source change

Campaign responses are private feedback records with the server type `survey`. `FeedbackKind` now
includes `.survey` so owned-feedback and detail responses decode without losing that distinction.
If the app switches exhaustively over `FeedbackKind`, add the new case:

```swift
switch feedback.type {
case .bug, .suggestion, .praise, .conversation:
    showOrdinaryFeedback(feedback)
case .survey:
    showCampaignResponse(feedback)
}
```

Use `FeedbackKind.submittableCases` for an ordinary feedback picker. It contains the four kinds
accepted by `createFeedback` and `submitFeedback`; `.survey` can be created only through
`submitCampaignResponse`.

## Campaign API

- `campaigns()` lists campaigns currently collecting responses.
- `campaign(id:)` loads one complete campaign.
- `FeedbackCampaignAnswerSchema` exposes the bounded server schema as typed string, number,
  integer, boolean, and array cases.
- `FeedbackCampaign.form` splits flat campaign elements into identified pages and removes the
  page-break markers.
- `submitCampaignResponse` accepts typed natural-JSON answers, optional comments and attachments,
  and the same explicit diagnostics choice as ordinary feedback.

See the campaign example in the repository [README](../README.md#campaign-forms) for the complete
read, render, and submit flow.

## Upgrade checklist

- Move the package requirement and resolved pin to `2.1.0` or newer.
- Add `.survey` to exhaustive `FeedbackKind` switches.
- Replace `FeedbackKind.allCases` with `FeedbackKind.submittableCases` in ordinary submission UIs.
- Re-run the host app's build and feedback integration tests.
