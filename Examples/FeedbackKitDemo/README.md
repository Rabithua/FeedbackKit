# FeedbackKit Demo

Open `FeedbackKitDemo.xcodeproj` and run the `FeedbackKitDemo` scheme on iOS 18 or later. The project
uses a local package reference to the repository root.

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

The Demo scheme also contains a UI test that taps both visible outer corners of the shared
full-width action label and waits for Fixture bootstrap to complete:

```bash
xcodebuild -project FeedbackKitDemo.xcodeproj -scheme FeedbackKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' test
```
