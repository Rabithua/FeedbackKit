@testable import FeedbackKitCore
import Foundation
import Testing

struct FeedbackSecureTransportURLTests {
    @Test func httpsURLIsSecure() {
        #expect(URL(string: "https://api.example.com/v1")!.isFeedbackSecureTransportURL)
    }

    @Test func httpLocalhostIsSecure() {
        #expect(URL(string: "http://localhost/test")!.isFeedbackSecureTransportURL)
    }

    @Test func httpRemoteIsNotSecure() {
        #expect(URL(string: "http://api.example.com/v1")!.isFeedbackSecureTransportURL == false)
    }

    @Test func urlWithCredentialsIsNotSecure() {
        #expect(URL(string: "https://user:pass@api.example.com")!.isFeedbackSecureTransportURL == false)
        #expect(URL(string: "https://user@api.example.com")!.isFeedbackSecureTransportURL == false)
    }
}

struct FeedbackSecureRedirectDelegateTests {
    private let delegate = FeedbackSecureRedirectDelegate()

    @Test func allowsSameOriginSecureRedirect() {
        let original = URLRequest(url: URL(string: "https://api.example.com/v1/a")!)
        let redirect = URLRequest(url: URL(string: "https://api.example.com/v1/b")!)

        #expect(delegate.approvedRedirectRequest(redirect, originalRequest: original) != nil)
    }

    @Test func blocksCrossOriginRedirect() {
        let original = URLRequest(url: URL(string: "https://api.example.com/v1/a")!)
        let redirect = URLRequest(url: URL(string: "https://evil.example.com/v1/b")!)

        #expect(delegate.approvedRedirectRequest(redirect, originalRequest: original) == nil)
    }

    @Test func blocksCrossPortRedirect() {
        let original = URLRequest(url: URL(string: "https://api.example.com/v1/a")!)
        let redirect = URLRequest(url: URL(string: "https://api.example.com:9999/v1/b")!)

        #expect(delegate.approvedRedirectRequest(redirect, originalRequest: original) == nil)
    }

    @Test func blocksDowngradeToInsecureRedirect() {
        let original = URLRequest(url: URL(string: "https://api.example.com/v1/a")!)
        let redirect = URLRequest(url: URL(string: "http://api.example.com/v1/b")!)

        #expect(delegate.approvedRedirectRequest(redirect, originalRequest: original) == nil)
    }

    @Test func blocksRedirectWithCredentials() {
        let original = URLRequest(url: URL(string: "https://api.example.com/v1/a")!)
        let redirect = URLRequest(url: URL(string: "https://user:pass@api.example.com/v1/b")!)

        #expect(delegate.approvedRedirectRequest(redirect, originalRequest: original) == nil)
    }
}
