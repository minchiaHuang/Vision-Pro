import Foundation

/// Test-only `URLProtocol` that serves scripted responses, routing by request URL.
/// Inject the session it backs via `StubURLProtocol.session()` and set `route` before
/// exercising the code under test.
///
/// `route` is process-global, so any suite using this MUST be `@Suite(.serialized)`.
final class StubURLProtocol: URLProtocol {

    /// Maps a request URL to an HTTP status + body. Set by each test.
    static var route: ((URL) -> (status: Int, body: Data))?

    /// A `URLSession` whose requests are intercepted by this protocol.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let (status, body) = Self.route?(url) ?? (500, Data())
        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
