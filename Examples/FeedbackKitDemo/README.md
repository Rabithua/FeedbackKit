# FeedbackKit Demo

Open `FeedbackKitDemo.xcodeproj` from FeedbackKit `2.1.0` or newer and run the `FeedbackKitDemo`
scheme on iOS 18 or later. The project uses a local package reference to the repository root, so no
separate package version selection is required.

Fixture mode is selected by default and requires no configuration. It exercises healthy and empty
products, offline transport, validation errors, rate limiting, temporary unavailability,
submission, voting, attachments, and private diagnostics with the production SDK surface.

To use Live mode:

1. Copy `Configuration/Config.local.example.xcconfig` to
   `Configuration/Config.local.xcconfig`.
2. Set `FEEDBACK_PRODUCT_KEY` in the local file. Set `FEEDBACK_KEYCHAIN_SERVICE` only when an
   existing app must preserve a previously released service.
3. Run the app, choose Live, and tap **Verify integration**. The feedback center becomes available
   only after the preflight succeeds.

The local configuration file is ignored by Git. Without a Product Key, Live mode shows the repair
instructions instead of crashing.

Use normal Xcode simulator signing when running the app. `CODE_SIGNING_ALLOWED=NO` is only suitable
for non-running generic CI builds; an unsigned simulator app cannot exercise the Keychain-backed
visitor identity required by Live mode.

The Demo scheme contains UI tests for the shared full-width action hit area, the centered FeedKit
attribution, and Live verification. The Live test is skipped when the local Product Key is absent;
when configured, it performs the same integration preflight as the button without submitting
feedback:

```bash
xcodebuild -project FeedbackKitDemo.xcodeproj -scheme FeedbackKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' test
```
