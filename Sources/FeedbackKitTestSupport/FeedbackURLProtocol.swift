import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class FeedbackURLProtocol: URLProtocol, @unchecked Sendable {
    public typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storedHandler: Handler?

    public static func install(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        storedHandler = handler
    }

    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        storedHandler = nil
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    public override func startLoading() {
        Self.lock.lock(); let handler = Self.storedHandler; Self.lock.unlock()
        guard let handler else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    public override func stopLoading() {}
}
