import Foundation
import Synchronization

/// Zero network, enforced. Every request through the URL loading system fails and is
/// recorded, and so is every request without a fixture. The CLI exits on the first
/// record, so a test fails even when the app caught the error and recovered.
nonisolated final class NetworkGuard: URLProtocol {
    private static let entries = Mutex<[String]>([])

    static var violations: [String] { entries.withLock { $0 } }
    static func record(_ entry: String) { entries.withLock { $0.append(entry) } }
    static func reset() { entries.withLock { $0.removeAll() } }

    // ponytail: covers URLSession.shared and the global protocol registry; a session built from
    // its own URLSessionConfiguration needs NetworkGuard in its protocolClasses.
    static func install() { URLProtocol.registerClass(NetworkGuard.self) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record("\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
