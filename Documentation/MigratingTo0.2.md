# Migrating to FeedbackKit 0.2

FeedbackKit 0.2 removes server-address configuration, makes invalid host configuration explicit,
and adds opt-in integration verification and structured developer observability.

## Remove the server URL

Delete the `baseURL` argument, `FeedbackServerBaseURL` Info.plist key, and any corresponding xcconfig
setting. FeedbackKit now always connects to `https://api.feedkit.cn/v1/api`.

Before:

```swift
let configuration = FeedbackConfiguration(
    baseURL: feedbackServerURL,
    productKey: productKey,
    keychainService: "com.example.MyApp.feedback.visitor"
)
```

After:

```swift
let configuration = try FeedbackConfiguration(
    productKey: productKey,
    keychainService: "com.example.MyApp.feedback.visitor"
)
```

Configuration initializers now throw `FeedbackConfigurationError` for a missing or empty Product
Key, missing Bundle ID, or empty Keychain service. Initialization validates only local values and
does not access the network or Keychain.

For new apps, `try FeedbackConfiguration(productKey: productKey, bundle: .main)` derives the service
as `<bundle-id>.feedbackkit.visitor`. `try FeedbackConfiguration(bundle: .main)` additionally reads
`FeedbackProductKey` and the optional `FeedbackKeychainService` from Info.plist.

## Preserve the existing anonymous identity

An already released app must keep using exactly the same Keychain service. If the app previously
relied on FeedbackKit's old default value, pass it explicitly:

```swift
let configuration = try FeedbackConfiguration(
    productKey: productKey,
    keychainService: "ink.rote.FeedbackKit.visitor"
)
```

Changing the service creates a new anonymous identity on that device, which loses access to the
previous identity's private feedback history.

## Update error matching

`FeedbackClientError` is now a structure with a stable `kind` and a sanitized
`FeedbackFailureContext`. Replace enum-pattern matching with `error.kind`:

```swift
do {
    try await submitFeedback()
} catch let error as FeedbackClientError {
    switch error.kind {
    case .rateLimited:
        scheduleRetry(after: error.context.retryAfter)
    case .unauthorized:
        resetFeedbackPresentation()
    default:
        report(error.context.requestID)
    }
}
```

The context can contain the operation, HTTP status, server code, `X-Request-ID`, retry-after value,
and a sanitized debug description. Decoding failures expose only the target type and coding path,
never the response body. Cancellation still throws `CancellationError`.

## Add preflight only where intentional

`try await client.verifyIntegration(locale:)` runs the normal bootstrap flow and returns the bound
Product plus `FeedbackDiagnosticsReadiness`: `disabled`, `providerMissing`, `unsupportedSchema`, or
`ready`. It may create the anonymous visitor credential and is never called automatically.

## Add an observer only when needed

The client remains silent by default. Pass `FeedbackClientObserver.osLog(subsystem:)` or a custom
closure observer to receive sanitized completion events for requests and upload stages. Observer
events never include Product Keys, authorization values, bodies, query parameters, resource IDs,
or presigned URLs, and observer handling never changes the request result.

Developer observation is separate from FeedbackKit diagnostics: diagnostic snapshots are still
created and uploaded only when both the Product and host support them and the user explicitly opts
in for that submission.
